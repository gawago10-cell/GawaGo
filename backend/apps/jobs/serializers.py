from rest_framework import serializers

from apps.common.fields import RoundedCoordinateField
from apps.jobs.models import JobApplication, JobImage, JobPosting
from apps.matching.services import get_road_route_for_match
from apps.reviews.models import Review


class JobApplicationSerializer(serializers.ModelSerializer):
    job_id = serializers.IntegerField(source="job.id", read_only=True)
    job_title = serializers.CharField(source="job.title", read_only=True)
    job_type = serializers.CharField(source="job.job_type", read_only=True)
    job_status = serializers.CharField(source="job.status", read_only=True)
    job_schedule = serializers.CharField(source="job.schedule", read_only=True)
    job_schedule_type = serializers.CharField(source="job.schedule_type", read_only=True)
    job_preferred_date = serializers.DateField(source="job.preferred_date", read_only=True)
    job_preferred_time = serializers.TimeField(source="job.preferred_time", read_only=True)
    job_description = serializers.CharField(source="job.description", read_only=True)
    household_username = serializers.CharField(source="job.household.username", read_only=True)
    household_name = serializers.SerializerMethodField()
    location_label = serializers.CharField(source="job.location_label", read_only=True)
    service_rate = serializers.DecimalField(source="job.service_rate", max_digits=10, decimal_places=2, read_only=True)
    worker_username = serializers.CharField(source="worker.username", read_only=True)
    worker_name = serializers.SerializerMethodField()
    worker_location_label = serializers.CharField(source="worker.profile.location_label", read_only=True)
    worker_latitude = serializers.FloatField(source="worker.profile.latitude", read_only=True)
    worker_longitude = serializers.FloatField(source="worker.profile.longitude", read_only=True)
    worker_verification_status = serializers.CharField(source="worker.profile.verification_status", read_only=True)
    worker_rating_label = serializers.CharField(source="worker.profile.display_rating", read_only=True)
    worker_bio = serializers.CharField(source="worker.profile.bio", read_only=True)
    worker_years_experience = serializers.IntegerField(source="worker.profile.years_experience", read_only=True)
    worker_profile_photo_url = serializers.SerializerMethodField()
    worker_skills = serializers.ListField(source="worker.profile.skills", child=serializers.CharField(), read_only=True)
    worker_hourly_rate = serializers.DecimalField(source="worker.profile.hourly_rate", max_digits=10, decimal_places=2, read_only=True)
    worker_daily_rate = serializers.DecimalField(source="worker.profile.daily_rate", max_digits=10, decimal_places=2, read_only=True)
    route_distance_km = serializers.SerializerMethodField()
    route_points = serializers.SerializerMethodField()
    can_accept_hire_request = serializers.SerializerMethodField()
    can_request_completion = serializers.SerializerMethodField()
    can_review = serializers.SerializerMethodField()

    class Meta:
        model = JobApplication
        fields = [
            "id",
            "job_id",
            "job_title",
            "job_type",
            "job_status",
            "job_schedule",
            "job_schedule_type",
            "job_preferred_date",
            "job_preferred_time",
            "job_description",
            "household_username",
            "household_name",
            "location_label",
            "service_rate",
            "worker",
            "worker_username",
            "worker_name",
            "worker_location_label",
            "worker_latitude",
            "worker_longitude",
            "worker_verification_status",
            "worker_rating_label",
            "worker_bio",
            "worker_years_experience",
            "worker_profile_photo_url",
            "worker_skills",
            "worker_hourly_rate",
            "worker_daily_rate",
            "route_distance_km",
            "route_points",
            "can_accept_hire_request",
            "can_request_completion",
            "can_review",
            "status",
            "applied_at",
            "updated_at",
            "note",
        ]
        read_only_fields = ["id", "worker_username", "applied_at", "updated_at"]

    def get_worker_name(self, obj):
        return obj.worker.get_full_name().strip() or obj.worker.username

    def get_household_name(self, obj):
        return obj.job.household.get_full_name().strip() or obj.job.household.username

    def get_worker_profile_photo_url(self, obj):
        photo = getattr(obj.worker.profile, "profile_photo", None)
        if not photo:
            return ""
        request = self.context.get("request")
        url = photo.url
        return request.build_absolute_uri(url) if request else url

    def get_worker_route(self, obj):
        cache_key = f"application_route:{obj.job_id}:{obj.worker_id}"
        if not hasattr(self, "_worker_route_cache"):
            self._worker_route_cache = {}
        if cache_key not in self._worker_route_cache:
            self._worker_route_cache[cache_key] = get_road_route_for_match(obj.job, obj.worker.profile)
        return self._worker_route_cache[cache_key]

    def get_route_distance_km(self, obj):
        distance_km = self.get_worker_route(obj).get("distance_km")
        return round(distance_km, 3) if distance_km is not None else None

    def get_route_points(self, obj):
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
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated or obj.worker_id != user.id:
            return False
        return obj.status == JobApplication.STATUS_HIRED and obj.job.status == JobPosting.STATUS_ASSIGNED

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
    applications = serializers.SerializerMethodField()
    current_worker_application = serializers.SerializerMethodField()
    hired_count = serializers.SerializerMethodField()
    workers_needed = serializers.IntegerField(source="worker_slots", read_only=True)
    can_apply = serializers.SerializerMethodField()
    can_accept_hire_request = serializers.SerializerMethodField()
    can_request_completion = serializers.SerializerMethodField()
    can_review = serializers.SerializerMethodField()
    images = JobImageSerializer(many=True, read_only=True)
    latitude = serializers.SerializerMethodField()
    longitude = serializers.SerializerMethodField()
    route_distance_km = serializers.SerializerMethodField()
    route_points = serializers.SerializerMethodField()

    class Meta:
        model = JobPosting
        fields = [
            "id",
            "household_username",
            "household_name",
            "title",
            "job_type",
            "required_skill",
            "schedule",
            "schedule_type",
            "preferred_date",
            "preferred_time",
            "description",
            "location_label",
            "latitude",
            "longitude",
            "service_rate",
            "worker_slots",
            "status",
            "hired_count",
            "workers_needed",
            "can_apply",
            "can_accept_hire_request",
            "can_request_completion",
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
        ]

    def get_household_name(self, obj):
        return obj.household.get_full_name().strip() or obj.household.username

    def can_view_exact_location(self, obj):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated:
            return False
        if user.is_staff or obj.household_id == user.id:
            return True
        profile = getattr(user, "profile", None)
        if not profile or profile.role != "worker":
            return False
        return obj.applications.filter(
            worker=user,
            status__in=[
                JobApplication.STATUS_HIRE_REQUESTED,
                JobApplication.STATUS_HIRED,
                JobApplication.STATUS_COMPLETED,
            ],
        ).exists()

    def get_latitude(self, obj):
        return obj.latitude if self.can_view_exact_location(obj) else None

    def get_longitude(self, obj):
        return obj.longitude if self.can_view_exact_location(obj) else None

    def get_applications(self, obj):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if not user or not user.is_authenticated:
            return []
        applications = obj.applications.all()
        if user.is_staff or obj.household_id == user.id:
            visible_applications = applications
        else:
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

    def get_can_apply(self, obj):
        is_worker, user, profile = self.is_authenticated_worker()
        if not is_worker:
            return False
        if profile.verification_status != "verified":
            return False
        if obj.status != JobPosting.STATUS_OPEN:
            return False
        if self.get_hired_count(obj) >= obj.worker_slots:
            return False
        return not obj.applications.filter(worker=user).exists()

    def get_can_accept_hire_request(self, obj):
        application = self.get_current_worker_application_obj(obj)
        if not application or application.status != JobApplication.STATUS_HIRE_REQUESTED:
            return False
        if obj.status in [JobPosting.STATUS_COMPLETED, JobPosting.STATUS_CANCELLED]:
            return False
        return self.get_hired_count(obj) < obj.worker_slots

    def get_can_request_completion(self, obj):
        application = self.get_current_worker_application_obj(obj)
        if not application or application.status != JobApplication.STATUS_HIRED:
            return False
        return obj.status == JobPosting.STATUS_ASSIGNED

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
            reviewed_worker_ids = Review.objects.filter(
                job=obj,
                author=user,
                target_id__in=completed_worker_ids,
                author_role=Review.ROLE_HOUSEHOLD,
                target_role=Review.ROLE_WORKER,
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
            self._worker_route_cache[cache_key] = get_road_route_for_match(obj, profile)
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
    preferred_date = serializers.DateField(required=False, allow_null=True)
    preferred_time = serializers.TimeField(required=False, allow_null=True)
    description = serializers.CharField(required=False, allow_blank=True, default="")
    location_label = serializers.CharField(max_length=255)
    latitude = RoundedCoordinateField(max_digits=10, decimal_places=7)
    longitude = RoundedCoordinateField(max_digits=10, decimal_places=7)
    service_rate = serializers.DecimalField(max_digits=10, decimal_places=2)
    worker_slots = serializers.IntegerField(min_value=1, default=1)
    status = serializers.ChoiceField(choices=JobPosting.STATUS_CHOICES, required=False)
    job_start_date = serializers.DateField(required=False, allow_null=True)
    job_end_date = serializers.DateField(required=False, allow_null=True)
    estimated_working_days = serializers.IntegerField(required=False, allow_null=True)
    max_distance_km = serializers.FloatField(required=False, default=1.0)
    geographic_boundary = serializers.ChoiceField(choices=JobPosting.DISTANCE_CHOICES, required=False, default='1km')

    def validate(self, attrs):
        if not attrs.get("schedule") and not (attrs.get("preferred_date") and attrs.get("preferred_time")):
            raise serializers.ValidationError({"schedule": "Schedule text or preferred date and time are required."})
        if attrs.get("job_start_date") and attrs.get("job_end_date"):
            if attrs["job_end_date"] <= attrs["job_start_date"]:
                raise serializers.ValidationError({"job_end_date": "End date must be after start date."})
        return attrs


class JobApplicationCreateSerializer(serializers.Serializer):
    worker_username = serializers.CharField(required=False)
    note = serializers.CharField(required=False, allow_blank=True, default="")


class JobApplicationStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=JobApplication.STATUS_CHOICES)
    job_id = serializers.IntegerField(required=False)
    worker_username = serializers.CharField(required=False, allow_blank=True)
