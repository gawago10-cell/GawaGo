import logging
from datetime import timedelta

from django.utils import timezone
from rest_framework import serializers

from apps.accounts.models import SkillRating
from apps.accounts.serializers import validate_tayabas_coordinates
from apps.common.fields import RoundedCoordinateField
from apps.common.sanitize import sanitize_text
from apps.common.skills import is_other_placeholder
from apps.jobs.models import JobApplication, JobImage, JobPosting
from apps.jobs.privacy import (
    approximate_coordinate,
    distance_label,
    hire_reveals_contact,
    masked_location_label,
    rounded_distance_km,
    viewer_can_see_locations,
)
from apps.matching.recommendations import score_pair_with_distance
from apps.matching.services import get_cached_road_route, get_road_route_for_match, smart_match_sort_key
from apps.jobs.services import (
    UNDERWAY_JOB_STATUSES,
    can_back_out_of_hire,
    can_withdraw_application,
    full_time_started,
    hired_jobs_under_way,
    hold_apply_message,
    hold_ends_on,
    hold_on,
    hold_title,
    job_days,
    job_has_lapsed,
    job_not_started_message,
    lapsed_note,
)
from apps.jobs.statuses import get_application_stage, get_job_stage, get_stage_label


def route_lookup(context):
    """Resolving a route live costs an outbound HTTP request, so collection
    endpoints (which serialize an unbounded number of rows) opt into a
    cache-only lookup via context. Detail responses, where the set is bounded
    and the distance is the point of the screen, still resolve live.
    """
    if context.get("route_lookup") == "cache_only":
        return get_cached_road_route
    return get_road_route_for_match
from apps.reviews.models import Review


INACTIVE_APPLICATION_STATUSES = {
    JobApplication.STATUS_REJECTED,
    JobApplication.STATUS_CLOSED,
    JobApplication.STATUS_WITHDRAWN,
}


def applicant_sort_key(application, distance_km):
    """How a household's applicant list is ordered, everywhere it is served:
    live applications first, then Smart Matching's rule order (AGENTS.md
    I.B) within each group, rather than by who applied last."""
    inactive = 1 if application.status in INACTIVE_APPLICATION_STATUSES else 0
    profile = getattr(application.worker, "profile", None)
    if profile is None:
        return (inactive, 1)
    return (inactive, 0, smart_match_sort_key(application.job, profile, distance_km))

logger = logging.getLogger(__name__)

# How soon after an application is created a household request counts as
# the invitation that created it (see get_invited).
INVITE_WINDOW = timedelta(minutes=1)

def validate_offered_rate(value):
    """A job pays something: PHP 0.00 or PHP 0.11 posts made the agreed rate
    meaningless (spec II.B; system scan, 2026-11-01)."""
    if value is not None and value < 1:
        raise serializers.ValidationError("Enter a rate of at least PHP 1.00.")
    return value


def _reject_past_dates(attrs):
    """A job can't be scheduled, started or ended in the past -- on create or
    on edit (only the dates actually being set are checked)."""
    today = timezone.localdate()
    for field in ("job_start_date", "job_end_date"):
        if attrs.get(field) and attrs[field] < today:
            raise serializers.ValidationError({field: "Choose today or a later date."})


# Household jobs in one city; also keeps values inside the integer columns.
MAX_WORKER_SLOTS = 50
MAX_ESTIMATED_WORKING_DAYS = 366

# What both clients send for "unlimited"; the real bypass is
# geographic_boundary == "unlimited" (apps.matching.services), but the pair
# has to stay inside a sane range rather than accepting any float.
UNLIMITED_DISTANCE_KM = 999999.0
BOUNDARY_TO_KM = {
    "1km": 1.0,
    "2km": 2.0,
    "5km": 5.0,
    "10km": 10.0,
    "unlimited": UNLIMITED_DISTANCE_KM,
}


def _validate_job_dates(attrs, instance=None):
    start = attrs.get("job_start_date", getattr(instance, "job_start_date", None))
    end = attrs.get("job_end_date", getattr(instance, "job_end_date", None))
    if start and end:
        # A one-day job ends on the day it starts, so only an end *before* the
        # start is wrong.
        if end < start:
            raise serializers.ValidationError(
                {"job_end_date": "End date must be on or after the start date."}
            )
        working_days = attrs.get(
            "estimated_working_days", getattr(instance, "estimated_working_days", None)
        )
        span = (end - start).days + 1
        if working_days and working_days > span:
            raise serializers.ValidationError(
                {
                    "estimated_working_days": (
                        f"That is more working days than the {span}-day schedule allows."
                    )
                }
            )


class JobApplicationSerializer(serializers.ModelSerializer):
    job_id = serializers.IntegerField(source="job.id", read_only=True)
    job_title = serializers.CharField(source="job.title", read_only=True)
    job_type = serializers.CharField(source="job.job_type", read_only=True)
    job_status = serializers.CharField(source="job.status", read_only=True)
    job_schedule = serializers.CharField(source="job.schedule", read_only=True)
    job_schedule_type = serializers.CharField(source="job.schedule_type", read_only=True)
    job_start_date = serializers.DateField(source="job.job_start_date", read_only=True)
    job_end_date = serializers.DateField(source="job.job_end_date", read_only=True)
    job_estimated_working_days = serializers.IntegerField(source="job.estimated_working_days", read_only=True)
    job_description = serializers.CharField(source="job.description", read_only=True)
    household_username = serializers.CharField(source="job.household.username", read_only=True)
    household_name = serializers.SerializerMethodField()
    household_phone = serializers.SerializerMethodField()
    household_email = serializers.SerializerMethodField()
    location_label = serializers.SerializerMethodField()
    service_rate = serializers.DecimalField(source="job.service_rate", max_digits=10, decimal_places=2, read_only=True)
    job_rate_type = serializers.CharField(source="job.rate_type", read_only=True)
    job_rate_type_label = serializers.CharField(source="job.get_rate_type_display", read_only=True)
    worker_username = serializers.CharField(source="worker.username", read_only=True)
    worker_name = serializers.SerializerMethodField()
    worker_location_label = serializers.CharField(source="worker.profile.location_label", read_only=True)
    worker_latitude = serializers.SerializerMethodField()
    worker_longitude = serializers.SerializerMethodField()
    worker_verification_status = serializers.CharField(source="worker.profile.verification_status", read_only=True)
    worker_available = serializers.SerializerMethodField()
    worker_rating_label = serializers.CharField(source="worker.profile.display_rating", read_only=True)
    worker_rating_count = serializers.IntegerField(source="worker.profile.rating_count", read_only=True)
    worker_completed_jobs = serializers.SerializerMethodField()
    worker_match_score = serializers.SerializerMethodField()
    worker_bio = serializers.CharField(source="worker.profile.bio", read_only=True)
    worker_years_experience = serializers.IntegerField(source="worker.profile.years_experience", read_only=True)
    worker_profile_photo_url = serializers.SerializerMethodField()
    worker_skills = serializers.ListField(source="worker.profile.skills", child=serializers.CharField(), read_only=True)
    worker_hourly_rate = serializers.DecimalField(source="worker.profile.hourly_rate", max_digits=10, decimal_places=2, read_only=True)
    worker_daily_rate = serializers.DecimalField(source="worker.profile.daily_rate", max_digits=10, decimal_places=2, read_only=True)
    route_distance_km = serializers.SerializerMethodField()
    distance_label = serializers.SerializerMethodField()
    route_points = serializers.SerializerMethodField()
    can_accept_hire_request = serializers.SerializerMethodField()
    can_request_completion = serializers.SerializerMethodField()
    can_withdraw = serializers.SerializerMethodField()
    can_back_out = serializers.SerializerMethodField()
    can_review = serializers.SerializerMethodField()
    household_can_review = serializers.SerializerMethodField()
    status_stage = serializers.SerializerMethodField()
    status_label = serializers.SerializerMethodField()
    invited = serializers.SerializerMethodField()
    hold_free_from = serializers.SerializerMethodField()

    def get_hold_free_from(self, obj):
        """For a hired worker on a full-time job past its last day: the day
        they may take other jobs again even if the household never marks it
        done (worker_hold). None otherwise: a one-time or part-time job only
        holds its own days, which have passed."""
        if obj.status != JobApplication.STATUS_HIRED or obj.job.status != JobPosting.STATUS_ASSIGNED:
            return None
        days = job_days(obj.job)
        if not days or not job_has_lapsed(obj.job) or not full_time_started(obj.job.schedule_type, days):
            return None
        return (hold_ends_on(days) + timedelta(days=1)).isoformat()

    def get_status_stage(self, obj):
        return get_application_stage(obj.status, obj.job.status, job=obj.job)

    def get_invited(self, obj):
        """True when the household invited this worker instead of the worker
        applying. The invite view creates the application and moves it to
        hire_requested at once, logging that first change as the household's;
        applying logs nothing, and a later invite of an applicant comes long
        after the application, so those read as applied."""
        first = obj.status_events.order_by("created_at", "id").first()
        return bool(
            first
            and first.to_status == JobApplication.STATUS_HIRE_REQUESTED
            and first.actor_id == obj.job.household_id
            and first.created_at - obj.applied_at <= INVITE_WINDOW
        )

    def get_household_can_review(self, obj):
        """Whether the job's household can still review *this* worker. The
        job-level can_review only says some worker is left, so on a job with
        several workers the clients need this to offer the right one."""
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated or obj.job.household_id != user.id:
            return False
        if obj.status != JobApplication.STATUS_COMPLETED or obj.job.status != JobPosting.STATUS_COMPLETED:
            return False
        # The automatic 3.5 placeholder doesn't count: a real review replaces it.
        return not Review.objects.filter(
            job=obj.job,
            author=user,
            target_id=obj.worker_id,
            author_role=Review.ROLE_HOUSEHOLD,
            target_role=Review.ROLE_WORKER,
            is_system_generated=False,
        ).exists()

    def get_status_label(self, obj):
        return get_stage_label(self.get_status_stage(obj))

    class Meta:
        model = JobApplication
        fields = [
            "id",
            "status_stage",
            "status_label",
            "invited",
            "hold_free_from",
            "job_id",
            "job_title",
            "job_type",
            "job_status",
            "job_schedule",
            "job_schedule_type",
            "job_start_date",
            "job_end_date",
            "job_estimated_working_days",
            "job_description",
            "household_username",
            "household_name",
            "household_phone",
            "household_email",
            "location_label",
            "service_rate",
            "job_rate_type",
            "job_rate_type_label",
            "worker",
            "worker_username",
            "worker_name",
            "worker_location_label",
            "worker_latitude",
            "worker_longitude",
            "worker_verification_status",
            "worker_available",
            "worker_rating_label",
            "worker_rating_count",
            "worker_completed_jobs",
            "worker_match_score",
            "worker_bio",
            "worker_years_experience",
            "worker_profile_photo_url",
            "worker_skills",
            "worker_hourly_rate",
            "worker_daily_rate",
            "route_distance_km",
            "distance_label",
            "route_points",
            "can_accept_hire_request",
            "can_request_completion",
            "can_withdraw",
            "can_back_out",
            "can_review",
            "household_can_review",
            "status",
            "applied_at",
            "updated_at",
            "note",
        ]
        read_only_fields = ["id", "worker_username", "applied_at", "updated_at"]

    def get_worker_available(self, obj):
        """False while the worker's account is suspended, so the household
        sees "Not available right now" instead of an Accept that fails. The
        reason stays confidential (AGENTS.md II.D)."""
        profile = getattr(obj.worker, "profile", None)
        if not profile or not profile.is_blocked:
            return True
        return bool(profile.blocked_until and profile.blocked_until <= timezone.now())

    def get_worker_name(self, obj):
        return obj.worker.get_full_name().strip() or obj.worker.username

    def get_household_name(self, obj):
        return obj.job.household.get_full_name().strip() or obj.job.household.username

    def _hire_reveals_contact(self, obj):
        """The household's phone and email are only earned once hired -- one
        shared rule (apps.jobs.privacy), so this and the worker-facing side
        can't drift apart. Enforced here rather than trusting the client to
        hide data it was never supposed to receive.

        Locations are deliberately *not* gated this way; see
        `_can_see_locations`."""
        request = self.context.get("request")
        return hire_reveals_contact(obj, getattr(request, "user", None))

    def _can_see_locations(self, obj):
        # Applications are only ever listed to that job's household, the
        # worker themselves, or staff, so authentication is the whole test
        # here -- there is no anonymous reader to withhold anything from.
        request = self.context.get("request")
        return viewer_can_see_locations(getattr(request, "user", None))

    def get_location_label(self, obj):
        if self._can_see_locations(obj):
            return obj.job.location_label
        return masked_location_label(obj.job.location_label)

    def get_household_phone(self, obj):
        if not self._hire_reveals_contact(obj):
            return ""
        return getattr(obj.job.household.profile, "phone", "") or ""

    def get_household_email(self, obj):
        if not self._hire_reveals_contact(obj):
            return ""
        return obj.job.household.email or ""

    def _worker_coordinate(self, obj, field):
        value = getattr(getattr(obj.worker, "profile", None), field, None)
        if value is None or not self._can_see_locations(obj):
            return None
        return float(value)

    def get_worker_latitude(self, obj):
        return self._worker_coordinate(obj, "latitude")

    def get_worker_longitude(self, obj):
        return self._worker_coordinate(obj, "longitude")

    def get_worker_profile_photo_url(self, obj):
        photo = getattr(obj.worker.profile, "profile_photo", None)
        if not photo:
            return ""
        request = self.context.get("request")
        url = photo.url
        return request.build_absolute_uri(url) if request else url

    def _viewer_owns_job(self, obj):
        """The two fields below only feed the household's applicant cards, so
        a worker listing their own applications doesn't pay for a per-row
        count query and scoring pass that nothing on their side renders."""
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated:
            return False
        return user.is_staff or obj.job.household_id == user.id

    def get_worker_completed_jobs(self, obj):
        if not self._viewer_owns_job(obj):
            return 0
        return JobApplication.objects.filter(
            worker_id=obj.worker_id, status=JobApplication.STATUS_COMPLETED
        ).count()

    def get_worker_match_score(self, obj):
        """0-1 content-based fit, the same number the AI match cards show, so
        an applicant and a recommended worker are comparable on one scale."""
        if not self._viewer_owns_job(obj):
            return None
        try:
            result = score_pair_with_distance(
                obj.job,
                getattr(obj.worker, "profile", None),
                self.get_worker_route(obj).get("distance_km"),
            )
        except Exception:
            # This score is extra context on an applicant card, so a scorer
            # that cannot run (a missing/blocked scikit-learn, say) must not
            # take down the job and application lists with it.
            logger.exception("Match score unavailable for application %s", obj.pk)
            return None
        # Two decimals, like the recommended-workers breakdown: at full
        # precision the proximity term would give back the exact distance.
        return round(result["ai_score"], 2) if result else None

    def get_worker_route(self, obj):
        cache_key = f"application_route:{obj.job_id}:{obj.worker_id}"
        if not hasattr(self, "_worker_route_cache"):
            self._worker_route_cache = {}
        if cache_key not in self._worker_route_cache:
            self._worker_route_cache[cache_key] = route_lookup(self.context)(obj.job, obj.worker.profile)
        return self._worker_route_cache[cache_key]

    def get_route_distance_km(self, obj):
        return rounded_distance_km(self.get_worker_route(obj).get("distance_km"))

    def get_distance_label(self, obj):
        return distance_label(self.get_worker_route(obj).get("distance_km"))

    def get_route_points(self, obj):
        # The route's far end is the worker's home (and its near end the job
        # site), so it is gated exactly like the coordinates.
        if not self._can_see_locations(obj):
            return []
        return self.get_worker_route(obj).get("route_points") or []

    def get_can_accept_hire_request(self, obj):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated or obj.worker_id != user.id:
            return False
        if obj.status != JobApplication.STATUS_HIRE_REQUESTED:
            return False
        return obj.job.status not in [JobPosting.STATUS_COMPLETED, JobPosting.STATUS_CANCELLED]

    def get_can_request_completion(self, obj):
        # The household marks a job done, not the worker (AGENTS.md I.A). The
        # field stays, always false, so app builds already on phones hide
        # their old "Mark as done" button instead of offering a refused call.
        return False

    def _viewer_is_worker(self, obj):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        return bool(user and user.is_authenticated and obj.worker_id == user.id)

    def get_can_withdraw(self, obj):
        """The worker can take back an application still waiting on the
        household (fourth scan, 2026-11-01)."""
        return self._viewer_is_worker(obj) and can_withdraw_application(obj)

    def get_can_back_out(self, obj):
        """The hired worker can give the job up, with a reason, until its
        first day (fourth scan, 2026-11-01)."""
        return self._viewer_is_worker(obj) and can_back_out_of_hire(obj)

    def get_can_review(self, obj):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated or obj.worker_id != user.id:
            return False
        if obj.status != JobApplication.STATUS_COMPLETED or obj.job.status != JobPosting.STATUS_COMPLETED:
            return False
        return not Review.objects.filter(
            job=obj.job,
            author=user,
            target=obj.job.household,
            author_role=Review.ROLE_WORKER,
            target_role=Review.ROLE_HOUSEHOLD,
        ).exists()


class JobImageSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = JobImage
        fields = ["id", "image", "image_url", "uploaded_at", "order"]
        read_only_fields = ["id", "uploaded_at"]

    def get_image_url(self, obj):
        if not obj.image:
            return ""
        request = self.context.get("request")
        url = obj.image.url
        return request.build_absolute_uri(url) if request else url


class JobPostingSerializer(serializers.ModelSerializer):
    household_username = serializers.CharField(source="household.username", read_only=True)
    household_name = serializers.SerializerMethodField()
    household_verification_status = serializers.SerializerMethodField()
    applications = serializers.SerializerMethodField()
    current_worker_application = serializers.SerializerMethodField()
    hired_count = serializers.SerializerMethodField()
    workers_needed = serializers.IntegerField(source="worker_slots", read_only=True)
    can_apply = serializers.SerializerMethodField()
    apply_blocked_reason = serializers.SerializerMethodField()
    apply_blocked_title = serializers.SerializerMethodField()
    accepting_applications = serializers.SerializerMethodField()
    expired_note = serializers.SerializerMethodField()
    can_accept_hire_request = serializers.SerializerMethodField()
    can_request_completion = serializers.SerializerMethodField()
    can_mark_done = serializers.SerializerMethodField()
    mark_done_note = serializers.SerializerMethodField()
    can_cancel = serializers.SerializerMethodField()
    cancel_needs_reason = serializers.SerializerMethodField()
    can_review = serializers.SerializerMethodField()
    images = JobImageSerializer(many=True, read_only=True)
    location_label = serializers.SerializerMethodField()
    latitude = serializers.SerializerMethodField()
    longitude = serializers.SerializerMethodField()
    approximate_latitude = serializers.SerializerMethodField()
    approximate_longitude = serializers.SerializerMethodField()
    route_distance_km = serializers.SerializerMethodField()
    route_points = serializers.SerializerMethodField()
    status_stage = serializers.SerializerMethodField()
    status_label = serializers.SerializerMethodField()
    distance_label = serializers.SerializerMethodField()
    rate_type_label = serializers.CharField(source="get_rate_type_display", read_only=True)
    skill_ratings = serializers.SerializerMethodField()
    household_rating = serializers.SerializerMethodField()

    @staticmethod
    def _history_worker_id(serializer):
        params = getattr(serializer.context.get("request"), "query_params", None) or {}
        worker_id = params.get("worker")
        return int(worker_id) if worker_id and str(worker_id).isdigit() else None

    def get_household_rating(self, obj):
        """The overall rating the household gave this worker for this job --
        the same review that feeds the worker's reputation and that the
        household sees on its own My Jobs -- so the employment history can't
        show "No ratings yet" for a job the household rated. Only filled for
        a worker's history (?worker=<id>). The four metrics come along when
        the household gave them; is_default marks the automatic 3.5."""
        worker_id = self._history_worker_id(self)
        if worker_id is None:
            return None
        review = (
            Review.objects.filter(job=obj, target_id=worker_id, author_role="household", target_role="worker")
            .order_by("-created_at")
            .first()
        )
        if review is None or review.rating is None:
            return None
        metrics = [
            {"label": label, "value": value}
            for label, value in (
                ("Quality of work", review.quality_of_work),
                ("Punctuality", review.punctuality),
                ("Communication", review.communication),
                ("Professionalism", review.professionalism),
            )
            if value is not None
        ]
        return {"rating": float(review.rating), "is_default": review.is_system_generated, "metrics": metrics}

    def get_skill_ratings(self, obj):
        """The per-skill ratings one worker received on this job, for their
        employment history (AGENTS.md II.C). Only filled when the list is a
        worker's history (?worker=<id>), since a job may have several workers."""
        params = getattr(self.context.get("request"), "query_params", None) or {}
        worker_id = params.get("worker")
        if not worker_id or not str(worker_id).isdigit():
            return []
        ratings = (
            SkillRating.objects.filter(job=obj, worker_id=int(worker_id))
            .select_related("skill")
            .order_by("skill__skill_name")
        )
        return [{"skill_name": rating.skill.skill_name, "rating": float(rating.rating)} for rating in ratings]

    def get_status_stage(self, obj):
        return get_job_stage(obj.status)

    def get_status_label(self, obj):
        return get_stage_label(self.get_status_stage(obj))

    def get_distance_label(self, obj):
        # The backend's own wording ("Within 1 km") rather than each client
        # computing its own phrasing, which used to read "480 meters away" on
        # web and "0.48 km away" on mobile for the same job.
        return distance_label(self.get_route_distance_km(obj))

    class Meta:
        model = JobPosting
        fields = [
            "id",
            "status_stage",
            "status_label",
            "household_username",
            "household_name",
            "household_verification_status",
            "title",
            "job_type",
            "required_skill",
            "schedule",
            "schedule_type",
            "description",
            "location_label",
            "latitude",
            "longitude",
            "approximate_latitude",
            "approximate_longitude",
            "service_rate",
            "rate_type",
            "rate_type_label",
            "worker_slots",
            "status",
            "hired_count",
            "workers_needed",
            "can_apply",
            "apply_blocked_reason",
            "apply_blocked_title",
            "accepting_applications",
            "expired_note",
            "can_accept_hire_request",
            "can_request_completion",
            "can_mark_done",
            "mark_done_note",
            "can_cancel",
            "cancel_needs_reason",
            "can_review",
            "job_start_date",
            "job_end_date",
            "estimated_working_days",
            "max_distance_km",
            "geographic_boundary",
            "created_at",
            "completed_at",
            "applications",
            "current_worker_application",
            "images",
            "route_distance_km",
            "route_points",
            "distance_label",
            "skill_ratings",
            "household_rating",
        ]
        read_only_fields = [
            "id",
            "household_username",
            "household_name",
            "created_at",
            "completed_at",
            "applications",
            "current_worker_application",
            "images",
            "route_distance_km",
            "route_points",
            "distance_label",
            "skill_ratings",
            "household_rating",
        ]

    def validate_service_rate(self, value):
        return validate_offered_rate(value)

    def validate_worker_slots(self, value):
        if value < 1:
            raise serializers.ValidationError("Ensure this value is greater than or equal to 1.")
        if value > MAX_WORKER_SLOTS:
            raise serializers.ValidationError(f"Ensure this value is less than or equal to {MAX_WORKER_SLOTS}.")
        return value

    def validate_max_distance_km(self, value):
        if value < 0.1:
            raise serializers.ValidationError("Ensure this value is greater than or equal to 0.1.")
        return value

    def validate_estimated_working_days(self, value):
        if value is not None and value < 1:
            raise serializers.ValidationError("Ensure this value is greater than or equal to 1.")
        if value is not None and value > MAX_ESTIMATED_WORKING_DAYS:
            raise serializers.ValidationError(f"Ensure this value is less than or equal to {MAX_ESTIMATED_WORKING_DAYS}.")
        return value

    def validate(self, attrs):
        instance = self.instance
        if instance is None:
            return attrs
        # latitude/longitude are SerializerMethodFields (read-only), so a
        # PATCH sending them used to just drop them with a 200 and no
        # explanation. Reject instead of silently no-op-ing (F11); a wrong
        # pin should be fixed by cancelling and reposting, not edited here.
        if "required_skill" in attrs and is_other_placeholder(attrs["required_skill"]):
            raise serializers.ValidationError(
                {"required_skill": "Type the service you need instead of \"Other\"."}
            )
        location_keys = {"latitude", "longitude"} & set((self.initial_data or {}).keys())
        if location_keys:
            raise serializers.ValidationError(
                {key: "Job location can't be changed after posting." for key in location_keys}
            )
        # The worker agreed to these terms when hired, so only the status may
        # move once the job has left "open" (AGENTS.md II.B price transparency).
        if instance.status != JobPosting.STATUS_OPEN:
            changed = [
                field for field, value in attrs.items()
                if field != "status" and getattr(instance, field) != value
            ]
            if changed:
                raise serializers.ValidationError(
                    {field: "Job details can't be changed once a worker has been hired." for field in changed}
                )
        # Same rule as posting: the kilometres follow the chosen radius, so an
        # edit can't leave a job labelled "10km" while matching still uses
        # 1 km, and a bare kilometre value can't be set on its own.
        if "geographic_boundary" in attrs:
            attrs["max_distance_km"] = BOUNDARY_TO_KM[attrs["geographic_boundary"]]
        elif "max_distance_km" in attrs:
            raise serializers.ValidationError(
                {"max_distance_km": "Change the search radius with geographic_boundary (1km, 2km, 5km, 10km or unlimited)."}
            )
        if "job_start_date" in attrs and not attrs["job_start_date"]:
            raise serializers.ValidationError({"job_start_date": "Choose the day the job starts."})
        _reject_past_dates(attrs)
        _validate_job_dates(attrs, instance)
        # Posting writes the schedule as "<type> starting <date>"; an edit
        # that moves the start date would otherwise leave the old date there.
        new_start = attrs.get("job_start_date")
        if "schedule" not in attrs and new_start and instance.job_start_date and new_start != instance.job_start_date:
            old_suffix = f"starting {instance.job_start_date.isoformat()}"
            if (instance.schedule or "").endswith(old_suffix):
                attrs["schedule"] = instance.schedule[: -len(old_suffix)] + f"starting {new_start.isoformat()}"
        for field in ("title", "job_type", "required_skill", "schedule", "description"):
            if field in attrs:
                attrs[field] = sanitize_text(attrs[field])
        return attrs

    def get_household_name(self, obj):
        return obj.household.get_full_name().strip() or obj.household.username

    def get_household_verification_status(self, obj):
        """Workers decide partly on whether the poster is a verified
        household, so the job card needs the status without a second
        request per row."""
        return getattr(
            getattr(obj.household, "profile", None), "verification_status", ""
        ) or ""

    def can_view_exact_location(self, obj):
        # Any signed-in user. A worker needs the job's real location on the
        # map to decide whether it is worth travelling to, which is before
        # applying, not after being hired. Signed-out visitors still get the
        # approximate point and barangay label, because job list and detail
        # are readable without an account (apps.jobs.privacy).
        request = self.context.get("request")
        return viewer_can_see_locations(getattr(request, "user", None))

    def get_location_label(self, obj):
        if self.can_view_exact_location(obj):
            return obj.location_label
        return masked_location_label(obj.location_label)

    def get_latitude(self, obj):
        return obj.latitude if self.can_view_exact_location(obj) else None

    def get_longitude(self, obj):
        return obj.longitude if self.can_view_exact_location(obj) else None

    def get_approximate_latitude(self, obj):
        return approximate_coordinate(obj.latitude)

    def get_approximate_longitude(self, obj):
        return approximate_coordinate(obj.longitude)

    def get_applications(self, obj):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated:
            return []
        applications = obj.applications.all()
        if user.is_staff or obj.household_id == user.id:
            # The household reviews applicants in Smart Matching's rule order
            # (AGENTS.md I.B), not by who applied last. Sorting reuses the
            # route each row already resolved while serializing.
            visible_applications = list(applications)
            serializer = JobApplicationSerializer(visible_applications, many=True, context=self.context)
            rows = serializer.data
            child = serializer.child

            def sort_key(pair):
                application, _row = pair
                return applicant_sort_key(application, child.get_worker_route(application).get("distance_km"))

            return [row for _application, row in sorted(zip(visible_applications, rows), key=sort_key)]
        profile = getattr(user, "profile", None)
        if not profile or profile.role != "worker":
            return []
        visible_applications = applications.filter(worker=user)
        return JobApplicationSerializer(visible_applications, many=True, context=self.context).data

    def get_current_worker_application(self, obj):
        application = self.get_current_worker_application_obj(obj)
        if not application:
            return None
        return JobApplicationSerializer(application, context=self.context).data

    def get_current_worker_application_obj(self, obj):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        profile = getattr(user, "profile", None)
        if not user or not user.is_authenticated or not profile or profile.role != "worker":
            return None
        cache_key = f"current_worker_application:{obj.pk}:{user.pk}"
        if not hasattr(self, "_current_worker_application_cache"):
            self._current_worker_application_cache = {}
        if cache_key not in self._current_worker_application_cache:
            self._current_worker_application_cache[cache_key] = obj.applications.filter(worker=user).first()
        return self._current_worker_application_cache[cache_key]

    def get_hired_count(self, obj):
        return obj.applications.filter(status__in=[JobApplication.STATUS_HIRED, JobApplication.STATUS_COMPLETED]).count()

    def is_authenticated_worker(self):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        profile = getattr(user, "profile", None)
        if not user or not user.is_authenticated or not profile or profile.role != "worker":
            return False, None, None
        return True, user, profile

    def _worker_hold(self, obj):
        """The requesting worker's hired job that keeps them from this one (a
        full-time job under way, or one on the same days), or None. Their
        hired jobs are looked up once per request: a list serializes many."""
        is_worker, user, _profile = self.is_authenticated_worker()
        if not is_worker:
            return None
        cache = self.context.setdefault("_hired_jobs_under_way", {})
        if user.id not in cache:
            cache[user.id] = hired_jobs_under_way(user)
        return hold_on(obj, cache[user.id])

    def get_accepting_applications(self, obj):
        """Still in the market: open, or under way with openings left.
        Mirrors JobApplicationView -- a multi-worker job keeps taking
        applicants after its first hire, until every opening is filled."""
        if job_has_lapsed(obj):
            return False
        if obj.status == JobPosting.STATUS_OPEN:
            return True
        return obj.status == JobPosting.STATUS_ASSIGNED and self.get_hired_count(obj) < obj.worker_slots

    def get_expired_note(self, obj):
        """For the household: its open job's day passed with nobody hired."""
        request = self.context.get("request")
        user = getattr(request, "user", None)
        is_owner = bool(user and user.is_authenticated and (user.id == obj.household_id or user.is_staff))
        if not is_owner or obj.status != JobPosting.STATUS_OPEN or not job_has_lapsed(obj):
            return ""
        return lapsed_note(obj)

    def _could_apply(self, obj, user, profile):
        if profile.verification_status != "verified" or not self.get_accepting_applications(obj):
            return False
        # A worker who withdrew, or was closed out when the job filled, may
        # apply again (fourth scan, 2026-11-01; flow audit, 2026-11-04).
        return not obj.applications.filter(worker=user).exclude(
            status__in=[JobApplication.STATUS_WITHDRAWN, JobApplication.STATUS_CLOSED]
        ).exists()

    def get_can_apply(self, obj):
        is_worker, user, profile = self.is_authenticated_worker()
        if not is_worker or self._worker_hold(obj):
            return False
        return self._could_apply(obj, user, profile)

    def _blocking_hold(self, obj):
        """The hold, but only on a job the worker could otherwise apply to."""
        is_worker, user, profile = self.is_authenticated_worker()
        hold = self._worker_hold(obj) if is_worker else None
        return hold if hold and self._could_apply(obj, user, profile) else None

    def get_apply_blocked_reason(self, obj):
        """Why a job the worker could otherwise apply to is closed to them
        (another job of theirs holds them), or ""."""
        hold = self._blocking_hold(obj)
        return hold_apply_message(hold) if hold else ""

    def get_apply_blocked_title(self, obj):
        """The short lead shown before apply_blocked_reason, or ""."""
        hold = self._blocking_hold(obj)
        return hold_title(hold) if hold else ""

    def get_can_accept_hire_request(self, obj):
        application = self.get_current_worker_application_obj(obj)
        if not application or application.status != JobApplication.STATUS_HIRE_REQUESTED:
            return False
        if obj.status in [JobPosting.STATUS_COMPLETED, JobPosting.STATUS_CANCELLED]:
            return False
        if self._worker_hold(obj):
            return False
        return self.get_hired_count(obj) < obj.worker_slots

    def get_can_request_completion(self, obj):
        # See JobApplicationSerializer.get_can_request_completion.
        return False

    def _household_can_finish(self, obj):
        """The requesting household owns this job and it is in progress with
        a hired worker -- the state where "Mark as done" belongs, whether or
        not the start date has come yet."""
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated or obj.household_id != user.id:
            return False
        if obj.status not in {JobPosting.STATUS_ASSIGNED, JobPosting.STATUS_COMPLETION_REQUESTED}:
            return False
        return self.get_hired_count(obj) > 0

    def get_can_mark_done(self, obj):
        if not self._household_can_finish(obj):
            return False
        profile = getattr(obj.household, "profile", None)
        if not profile or profile.verification_status != "verified":
            return False
        return not job_not_started_message(obj)

    def get_mark_done_note(self, obj):
        """Why "Mark as done" is not available yet, for the household to read
        beside the disabled button; "" when it is available or not theirs."""
        if not self._household_can_finish(obj):
            return ""
        profile = getattr(obj.household, "profile", None)
        if not profile or profile.verification_status != "verified":
            return "Your household account must be verified before you can complete a job."
        return job_not_started_message(obj)

    def get_can_cancel(self, obj):
        """The household can call its job off until it is done, hired worker
        or not: a worker who never showed up used to leave "Mark as done" as
        the only way out (fourth scan, 2026-11-01)."""
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated or obj.household_id != user.id:
            return False
        return obj.status == JobPosting.STATUS_OPEN or obj.status in UNDERWAY_JOB_STATUSES

    def get_cancel_needs_reason(self, obj):
        """Cancelling owes the hired worker a reason (third scan, 2026-11-01)."""
        if not self.get_can_cancel(obj):
            return False
        return any(application.status == JobApplication.STATUS_HIRED for application in obj.applications.all())

    def get_can_review(self, obj):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        profile = getattr(user, "profile", None)
        if not user or not user.is_authenticated or obj.status != JobPosting.STATUS_COMPLETED:
            return False
        if user.is_staff:
            return False
        if obj.household_id == user.id:
            completed_applications = obj.applications.filter(
                status=JobApplication.STATUS_COMPLETED,
            )
            completed_worker_ids = completed_applications.values_list("worker_id", flat=True)
            # The automatic 3.5-star placeholder does not count as the
            # household having reviewed: a real review replaces it in place,
            # but both clients hide the form while can_review is false, so the
            # placeholder used to lock the household out of reviewing at all.
            reviewed_worker_ids = Review.objects.filter(
                job=obj,
                author=user,
                target_id__in=completed_worker_ids,
                author_role=Review.ROLE_HOUSEHOLD,
                target_role=Review.ROLE_WORKER,
                is_system_generated=False,
            ).values_list("target_id", flat=True)
            return completed_applications.exclude(worker_id__in=reviewed_worker_ids).exists()
        if not profile or profile.role != "worker":
            return False
        application = self.get_current_worker_application_obj(obj)
        if not application or application.status != JobApplication.STATUS_COMPLETED:
            return False
        return not Review.objects.filter(
            job=obj,
            author=user,
            target=obj.household,
            author_role=Review.ROLE_WORKER,
            target_role=Review.ROLE_HOUSEHOLD,
        ).exists()

    def get_worker_route(self, obj):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        profile = getattr(user, "profile", None)
        if not user or not user.is_authenticated or not profile or profile.role != "worker":
            return None
        cache_key = f"worker_route:{obj.pk}:{profile.pk}"
        if not hasattr(self, "_worker_route_cache"):
            self._worker_route_cache = {}
        if cache_key not in self._worker_route_cache:
            self._worker_route_cache[cache_key] = route_lookup(self.context)(obj, profile)
        return self._worker_route_cache[cache_key]

    def get_route_distance_km(self, obj):
        route = self.get_worker_route(obj)
        distance_km = route.get("distance_km") if route else None
        return round(distance_km, 3) if distance_km is not None else None

    def get_route_points(self, obj):
        if not self.can_view_exact_location(obj):
            return []
        route = self.get_worker_route(obj)
        return route.get("route_points") if route else []


class JobCreateSerializer(serializers.Serializer):
    # Plain Serializer, so these do not inherit the model's column widths.
    # Without an explicit max_length an oversized value reaches the database
    # and surfaces as a 500 instead of a field validation error.
    household_username = serializers.CharField(required=False, allow_blank=True, max_length=150)
    title = serializers.CharField(max_length=255)
    job_type = serializers.CharField(max_length=120)
    required_skill = serializers.CharField(max_length=120)
    schedule = serializers.CharField(required=False, allow_blank=True, max_length=255)
    schedule_type = serializers.CharField(required=False, allow_blank=True, default="", max_length=80)
    description = serializers.CharField(required=False, allow_blank=True, default="")
    location_label = serializers.CharField(max_length=255)
    latitude = RoundedCoordinateField(max_digits=10, decimal_places=7)
    longitude = RoundedCoordinateField(max_digits=10, decimal_places=7)
    service_rate = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=0)
    rate_type = serializers.ChoiceField(choices=JobPosting.RATE_TYPE_CHOICES, required=False, default=JobPosting.RATE_PER_DAY)
    worker_slots = serializers.IntegerField(min_value=1, max_value=MAX_WORKER_SLOTS, default=1)
    status = serializers.ChoiceField(choices=JobPosting.STATUS_CHOICES, required=False)
    job_start_date = serializers.DateField(required=False, allow_null=True)
    job_end_date = serializers.DateField(required=False, allow_null=True)
    estimated_working_days = serializers.IntegerField(
        required=False, allow_null=True, min_value=1, max_value=MAX_ESTIMATED_WORKING_DAYS
    )
    max_distance_km = serializers.FloatField(
        required=False, default=1.0, min_value=0.1, max_value=UNLIMITED_DISTANCE_KM
    )
    geographic_boundary = serializers.ChoiceField(choices=JobPosting.DISTANCE_CHOICES, required=False, default='1km')

    def validate_service_rate(self, value):
        return validate_offered_rate(value)

    def validate(self, attrs):
        # Every rule that keeps a job honest runs off its dates: it lapses,
        # holds its worker, blocks the next post until it is marked done, and
        # can't be finished before it starts. Both clients always send a start
        # date; the API now insists too (flow audit, 2026-11-04).
        if not attrs.get("job_start_date"):
            raise serializers.ValidationError({"job_start_date": "Choose the day the job starts."})
        # "Other" is the clients' choice for typing a service outside the
        # catalog; a job "needing Other" can't be matched to any worker.
        if is_other_placeholder(attrs.get("required_skill")):
            raise serializers.ValidationError(
                {"required_skill": "Type the service you need instead of \"Other\"."}
            )
        _reject_past_dates(attrs)
        validate_tayabas_coordinates(attrs)
        _validate_job_dates(attrs)
        # Derive the kilometres from the chosen radius so the stored pair can
        # never disagree -- a job used to be able to say "10km" while matching
        # actually used 1 km.
        boundary = (self.initial_data or {}).get("geographic_boundary")
        if boundary in BOUNDARY_TO_KM:
            attrs["max_distance_km"] = BOUNDARY_TO_KM[boundary]
        for field in ("title", "job_type", "required_skill", "schedule", "description"):
            if field in attrs:
                attrs[field] = sanitize_text(attrs[field])
        return attrs


class JobApplicationCreateSerializer(serializers.Serializer):
    worker_username = serializers.CharField(required=False)
    note = serializers.CharField(required=False, allow_blank=True, default="")


class JobApplicationStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=JobApplication.STATUS_CHOICES)
    job_id = serializers.IntegerField(required=False)
    worker_username = serializers.CharField(required=False, allow_blank=True)
