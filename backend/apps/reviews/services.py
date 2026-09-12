from decimal import Decimal
from datetime import timedelta

from django.db import IntegrityError
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

    ratings = Review.objects.filter(
        target=user,
        rating__isnull=False,
    )
    rating_count = ratings.count()
    if rating_count == 0:
        profile.average_rating = None
        profile.rating_count = 0
    else:
        total_rating = sum((effective_review_rating(review) for review in ratings), Decimal("0.0"))
        profile.average_rating = total_rating / rating_count
        profile.rating_count = rating_count
    profile.save(update_fields=["average_rating", "rating_count"])


def recalculate_worker_rating(worker_user) -> None:
    recalculate_user_rating(worker_user)


def assign_default_worker_ratings(after_hours: int = DEFAULT_NO_FEEDBACK_AFTER_HOURS, dry_run: bool = False) -> int:
    cutoff = timezone.now() - timezone.timedelta(hours=after_hours)
    applications = JobApplication.objects.select_related("job", "job__household", "worker").filter(
        status=JobApplication.STATUS_COMPLETED,
        job__status=JobPosting.STATUS_COMPLETED,
        job__completed_at__isnull=False,
        job__completed_at__lte=cutoff,
    )

    created_count = 0
    for application in applications:
        job = application.job
        already_rated = Review.objects.filter(
            job=job,
            author=job.household,
            target=application.worker,
            author_role=Review.ROLE_HOUSEHOLD,
            target_role=Review.ROLE_WORKER,
            rating__isnull=False,
        ).exists()
        if already_rated:
            continue

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
            )
            created_count += 1
        except IntegrityError:
            continue

    return created_count


def assign_due_default_worker_ratings() -> int:
    return assign_default_worker_ratings(after_hours=DEFAULT_NO_FEEDBACK_AFTER_HOURS)


def calculate_reputation_tier(user) -> str:
    """
    Calculate reputation tier based on:
    - Average rating (4.5+ = Elite, 4.0+ = Trusted, 3.5+ = Established, < 3.5 = New)
    - Number of ratings (minimum 5 ratings required for Elite/Trusted)
    """
    profile = getattr(user, "profile", None)
    if not profile:
        return UserProfile.TIER_NEW

    rating = profile.average_rating
    count = profile.rating_count

    # Not enough ratings yet
    if count < 2:
        return UserProfile.TIER_NEW

    if count >= 5 and rating is not None:
        if rating >= Decimal("4.5"):
            return UserProfile.TIER_ELITE
        elif rating >= Decimal("4.0"):
            return UserProfile.TIER_TRUSTED
        elif rating >= Decimal("3.5"):
            return UserProfile.TIER_ESTABLISHED

    # With fewer ratings, use lower thresholds
    if rating is not None:
        if rating >= Decimal("4.5"):
            return UserProfile.TIER_TRUSTED
        elif rating >= Decimal("3.8"):
            return UserProfile.TIER_ESTABLISHED

    return UserProfile.TIER_NEW


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

    if not recent_reviews or not old_reviews:
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

    profile.reputation_tier = calculate_reputation_tier(user)
    profile.rating_trend = calculate_rating_trend(user)
    profile.save(update_fields=["reputation_tier", "rating_trend"])
