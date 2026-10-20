from decimal import Decimal
from datetime import timedelta

from django.core.cache import cache
from django.db import IntegrityError
from django.db.models import Exists, OuterRef, Q
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.jobs.models import JobApplication, JobPosting
from apps.reviews.models import Review

DEFAULT_NO_FEEDBACK_RATING = Decimal("3.5")
DEFAULT_NO_FEEDBACK_AFTER_HOURS = 72


def effective_review_rating(review) -> Decimal:
    """The rating a review actually contributes to averages/trends.

    Mirrors ReviewSerializer.get_overall_rating(): when the four detailed
    metrics (quality_of_work, punctuality, communication, professionalism)
    are present, the review's effective rating is their average rather than
    the plain star-picker value, so a household's per-metric scores are what
    actually move a worker's aggregate rating.
    """
    metrics = [review.quality_of_work, review.punctuality, review.communication, review.professionalism]
    valid_metrics = [m for m in metrics if m is not None]
    if not valid_metrics:
        return review.rating
    return Decimal(sum(valid_metrics)) / Decimal(len(valid_metrics))


def recalculate_user_rating(user) -> None:
    profile = getattr(user, "profile", None)
    if not profile or profile.role not in {UserProfile.ROLE_WORKER, UserProfile.ROLE_HOUSEHOLD}:
        return

    # A review scored on the four metrics but with no overall star value
    # still has a real effective_review_rating (their average) -- filtering
    # on rating__isnull=False alone silently dropped those from the worker's
    # average entirely.
    ratings = Review.objects.filter(
        Q(rating__isnull=False)
        | Q(quality_of_work__isnull=False)
        | Q(punctuality__isnull=False)
        | Q(communication__isnull=False)
        | Q(professionalism__isnull=False),
        target=user,
    )
    effective_ratings = [effective_review_rating(review) for review in ratings]
    effective_ratings = [rating for rating in effective_ratings if rating is not None]
    rating_count = len(effective_ratings)
    if rating_count == 0:
        profile.average_rating = None
        profile.rating_count = 0
    else:
        total_rating = sum(effective_ratings, Decimal("0.0"))
        profile.average_rating = total_rating / rating_count
        profile.rating_count = rating_count
    profile.save(update_fields=["average_rating", "rating_count"])


def recalculate_worker_rating(worker_user) -> None:
    recalculate_user_rating(worker_user)


def assign_default_worker_ratings(after_hours: int = DEFAULT_NO_FEEDBACK_AFTER_HOURS, dry_run: bool = False) -> int:
    cutoff = timezone.now() - timezone.timedelta(hours=after_hours)
    # Any household review of that worker on that job -- a real one, one
    # scored only on the four metrics, or the 3.5 placeholder itself -- means
    # there is nothing to assign. Excluding placeholders here used to retry
    # (and fail) the same insert on every sweep, forever; checking in one
    # query instead of one EXISTS per row keeps the sweep cheap as history
    # grows.
    household_review = Review.objects.filter(
        job=OuterRef("job"),
        author=OuterRef("job__household"),
        target=OuterRef("worker"),
        author_role=Review.ROLE_HOUSEHOLD,
        target_role=Review.ROLE_WORKER,
    )
    applications = (
        JobApplication.objects.select_related("job", "job__household", "worker")
        .filter(
            status=JobApplication.STATUS_COMPLETED,
            job__status=JobPosting.STATUS_COMPLETED,
            job__completed_at__isnull=False,
            job__completed_at__lte=cutoff,
        )
        .annotate(already_rated=Exists(household_review))
        .filter(already_rated=False)
    )

    created_count = 0
    for application in applications:
        job = application.job
        if dry_run:
            created_count += 1
            continue

        try:
            Review.objects.create(
                author=job.household,
                target=application.worker,
                author_role=Review.ROLE_HOUSEHOLD,
                target_role=Review.ROLE_WORKER,
                job=job,
                job_title=job.title,
                rating=DEFAULT_NO_FEEDBACK_RATING,
                feedback="Default 3.5-star rating assigned because no household feedback was submitted after job completion.",
                is_system_generated=True,
            )
            created_count += 1
        except IntegrityError:
            continue

    return created_count


def assign_due_default_worker_ratings() -> int:
    return assign_default_worker_ratings(after_hours=DEFAULT_NO_FEEDBACK_AFTER_HOURS)


# Reads that self-trigger the sweep (reviews, profiles, the admin dashboard)
# share one cooldown: cache.add() succeeds for one caller per window, so a
# looped request drives at most one sweep per window instead of one each.
ASSIGN_DEFAULT_RATINGS_COOLDOWN_SECONDS = 300
ASSIGN_DEFAULT_RATINGS_LOCK_KEY = "reviews:assign_due_default_ratings_lock"


def assign_due_default_worker_ratings_on_read() -> int:
    if not cache.add(ASSIGN_DEFAULT_RATINGS_LOCK_KEY, True, ASSIGN_DEFAULT_RATINGS_COOLDOWN_SECONDS):
        return 0
    return assign_due_default_worker_ratings()


def calculate_reputation_tier(user) -> str:
    """AGENTS.md II.A: every tier above New needs 5+ reviews -- Elite 4.5+,
    Trusted 4.0+, Established 3.5+. A couple of early 5-star reviews must not
    outrank a worker with a long record."""
    profile = getattr(user, "profile", None)
    if not profile:
        return UserProfile.TIER_NEW

    rating = profile.average_rating
    if profile.rating_count < 5 or rating is None:
        return UserProfile.TIER_NEW
    if rating >= Decimal("4.5"):
        return UserProfile.TIER_ELITE
    if rating >= Decimal("4.0"):
        return UserProfile.TIER_TRUSTED
    if rating >= Decimal("3.5"):
        return UserProfile.TIER_ESTABLISHED
    return UserProfile.TIER_NEW


# Below this many reviews in a window, one outlier score swings the window's
# average enough to flip the trend on essentially no evidence.
RATING_TREND_MIN_SAMPLES_PER_WINDOW = 2


def calculate_rating_trend(user) -> str:
    """
    Calculate rating trend by comparing recent ratings to older ratings.
    Weights recent ratings (last 30 days) higher.
    Returns: 'improving', 'declining', or 'neutral'
    """
    profile = getattr(user, "profile", None)
    if not profile or not profile.rating_count:
        return "neutral"

    thirty_days_ago = timezone.now() - timedelta(days=30)

    # Get recent ratings
    recent_reviews = Review.objects.filter(
        target=user, rating__isnull=False, created_at__gte=thirty_days_ago
    ).order_by("-created_at")[:10]

    # Get older ratings
    old_reviews = Review.objects.filter(
        target=user, rating__isnull=False, created_at__lt=thirty_days_ago
    ).order_by("-created_at")[:10]

    if (
        len(recent_reviews) < RATING_TREND_MIN_SAMPLES_PER_WINDOW
        or len(old_reviews) < RATING_TREND_MIN_SAMPLES_PER_WINDOW
    ):
        return "neutral"

    recent_avg = sum(
        float(effective_review_rating(r) or 0) for r in recent_reviews
    ) / len(recent_reviews)
    old_avg = sum(
        float(effective_review_rating(r) or 0) for r in old_reviews
    ) / len(old_reviews)

    # Calculate trend
    if recent_avg > old_avg + 0.5:
        return "improving"
    elif recent_avg < old_avg - 0.5:
        return "declining"
    else:
        return "neutral"


def update_worker_reputation(user) -> None:
    """Update both reputation tier and rating trend for a worker."""
    profile = getattr(user, "profile", None)
    if not profile:
        return
    # The rating average is recalculated by a signal on a different User
    # instance, so the profile cached on this one can still hold the old
    # average; the tier must come from the stored value.
    profile.refresh_from_db(fields=["average_rating", "rating_count"])

    profile.reputation_tier = calculate_reputation_tier(user)
    profile.rating_trend = calculate_rating_trend(user)
    profile.save(update_fields=["reputation_tier", "rating_trend"])
