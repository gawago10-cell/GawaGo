import json
from decimal import Decimal
from pathlib import Path

from django.contrib.auth.models import User
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers

from apps.common.fields import RoundedCoordinateField
from apps.accounts.models import (
    PasswordResetRequest,
    SignupVerificationRequest,
    UserProfile,
    WorkerAvailability,
    WorkerPortfolio,
    WorkerSkill,
    WorkerCertification,
    WorkerPortfolioItem,
    SkillRating,
    VerificationDocument,
)
from apps.common.serializers import VerificationRequestSerializer


def validate_tayabas_coordinates(attrs):
    latitude = attrs.get("latitude")
    longitude = attrs.get("longitude")
    if (latitude is None) != (longitude is None):
        raise serializers.ValidationError(
            {"location": "Latitude and longitude must be provided together."}
        )
    if latitude is None or longitude is None:
        return attrs
    return attrs


MAX_WORKER_SKILLS = 4


def validate_worker_profile_requirements(attrs, *, role, profile=None):
    attrs = validate_tayabas_coordinates(attrs)
    if role != UserProfile.ROLE_WORKER:
        return attrs

    skills = attrs.get("skills")
    if skills is not None and len(skills) > MAX_WORKER_SKILLS:
        raise serializers.ValidationError(
            {"skills": f"Workers can list at most {MAX_WORKER_SKILLS} skills."}
        )

    hourly_rate = attrs.get("hourly_rate", getattr(profile, "hourly_rate", None))
    daily_rate = attrs.get("daily_rate", getattr(profile, "daily_rate", None))
    if not any(
        rate is not None and Decimal(str(rate)) > 0
        for rate in (hourly_rate, daily_rate)
    ):
        raise serializers.ValidationError(
            {"service_rate": "Workers must provide a positive hourly or daily service rate."}
        )

    latitude = attrs.get("latitude", getattr(profile, "latitude", None))
    longitude = attrs.get("longitude", getattr(profile, "longitude", None))
    location_label = attrs.get(
        "location_label",
        getattr(profile, "location_label", ""),
    )
    if latitude is None or longitude is None or not str(location_label or "").strip():
        raise serializers.ValidationError(
            {"location": "Workers must provide a location and exact map coordinates."}
        )

    validate_tayabas_coordinates(
        {
            "latitude": latitude,
            "longitude": longitude,
        }
    )
    return attrs


class FlexibleStringListField(serializers.ListField):
    child = serializers.CharField()

    def to_internal_value(self, data):
        if isinstance(data, str):
            try:
                parsed = json.loads(data)
            except json.JSONDecodeError:
                parsed = [item.strip() for item in data.split(",") if item.strip()]
            data = parsed
        return super().to_internal_value(data)


class UserProfileSerializer(serializers.ModelSerializer):
    user_id = serializers.IntegerField(source="user.id", read_only=True)
    username = serializers.CharField(source="user.username", read_only=True)
    email = serializers.EmailField(source="user.email", read_only=True)
    full_name = serializers.SerializerMethodField()
    user_type = serializers.CharField(source="role", read_only=True)
    verification_request = serializers.SerializerMethodField()
    profile_photo_url = serializers.SerializerMethodField()
    availability_windows = serializers.SerializerMethodField()
    date_joined = serializers.DateTimeField(source="user.date_joined", read_only=True)
    # Account-suspension state -- admin-only (see PublicUserProfileSerializer,
    # which strips these), surfaced for the User Management screen.
    is_blocked = serializers.SerializerMethodField()
    blocked_until = serializers.DateTimeField(read_only=True)
    blocked_reason = serializers.CharField(read_only=True)
    # Lets User Management exclude admin/superadmin accounts from the
    # household/worker directory -- an admin's own UserProfile.role is
    # usually just "worker" by default, so role alone can't tell them apart.
    is_staff = serializers.BooleanField(source="user.is_staff", read_only=True)

    class Meta:
        model = UserProfile
        fields = [
            "id",
            "user_id",
            "username",
            "email",
            "full_name",
            "user_type",
            "role",
            "phone",
            "bio",
            "years_experience",
            "skills",
            "hourly_rate",
            "daily_rate",
            "verification_status",
            "location_label",
            "latitude",
            "longitude",
            "profile_photo",
            "profile_photo_url",
            "average_rating",
            "rating_count",
            "display_rating",
            "reputation_tier",
            "rating_trend",
            "verification_request",
            "availability_windows",
            "date_joined",
            "is_blocked",
            "blocked_until",
            "blocked_reason",
            "is_staff",
        ]

    def get_is_blocked(self, obj):
        # refresh_block_status() lazily lifts an expired timed suspension, so
        # this reads the account's real current state rather than a possibly
        # stale flag.
        return obj.refresh_block_status()
        read_only_fields = ["display_rating"]

    def get_full_name(self, obj):
        return obj.user.get_full_name().strip() or obj.user.username

    def get_verification_request(self, obj):
        request_obj = obj.user.verification_requests.order_by("-submitted_at").first()
        if not request_obj:
            return None
        return VerificationRequestSerializer(request_obj, context=self.context).data

    def get_profile_photo_url(self, obj):
        if not obj.profile_photo:
            return ""
        request = self.context.get("request")
        url = obj.profile_photo.url
        return request.build_absolute_uri(url) if request else url

    def get_availability_windows(self, obj):
        if obj.role != UserProfile.ROLE_WORKER:
            return []
        windows = obj.user.availability_windows.filter(is_available=True).order_by("date", "start_time")
        return WorkerAvailabilitySerializer(windows, many=True).data


class WorkerAvailabilitySerializer(serializers.ModelSerializer):
    class Meta:
        model = WorkerAvailability
        fields = ["id", "date", "start_time", "end_time", "is_available"]
        read_only_fields = ["id"]

    def validate(self, attrs):
        start_time = attrs.get("start_time") or getattr(self.instance, "start_time", None)
        end_time = attrs.get("end_time") or getattr(self.instance, "end_time", None)
        if start_time and end_time and start_time == end_time:
            raise serializers.ValidationError({"end_time": "End time must be different from start time."})
        return attrs


class WorkerAvailabilityBulkSerializer(serializers.Serializer):
    availability_windows = WorkerAvailabilitySerializer(many=True)




class PublicUserProfileSerializer(UserProfileSerializer):
    class Meta(UserProfileSerializer.Meta):
        fields = [
            field
            for field in UserProfileSerializer.Meta.fields
            if field not in {
                "email",
                "phone",
                "verification_request",
                "latitude",
                "longitude",
                "availability_windows",
                "is_blocked",
                "blocked_until",
                "blocked_reason",
                "is_staff",
            }
        ]


class RegisterSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150)
    email = serializers.EmailField()
    password = serializers.CharField(min_length=8, write_only=True)
    first_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    last_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    role = serializers.ChoiceField(choices=UserProfile.ROLE_CHOICES, default=UserProfile.ROLE_WORKER)
    phone = serializers.CharField(max_length=30, required=False, allow_blank=True)
    bio = serializers.CharField(required=False, allow_blank=True)
    years_experience = serializers.IntegerField(required=False, min_value=0)
    skills = FlexibleStringListField(required=False)
    hourly_rate = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True, min_value=Decimal("0.00")
    )
    daily_rate = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True, min_value=Decimal("0.00")
    )
    location_label = serializers.CharField(required=False, allow_blank=True)
    latitude = RoundedCoordinateField(max_digits=10, decimal_places=7, required=False, allow_null=True)
    longitude = RoundedCoordinateField(max_digits=10, decimal_places=7, required=False, allow_null=True)

    def validate_password(self, value):
        try:
            validate_password(value)
        except DjangoValidationError as exc:
            raise serializers.ValidationError(list(exc.messages))
        return value


    def validate(self, attrs):
        return validate_worker_profile_requirements(
            attrs,
            role=attrs.get("role", UserProfile.ROLE_WORKER),
        )


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField()


class ProfileUpdateSerializer(serializers.Serializer):
    first_name = serializers.CharField(required=False, allow_blank=True)
    last_name = serializers.CharField(required=False, allow_blank=True)
    email = serializers.EmailField(required=False)
    phone = serializers.CharField(max_length=30, required=False, allow_blank=True)
    bio = serializers.CharField(required=False, allow_blank=True)
    years_experience = serializers.IntegerField(required=False, min_value=0)
    skills = FlexibleStringListField(required=False)
    hourly_rate = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True, min_value=Decimal("0.00")
    )
    daily_rate = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True, min_value=Decimal("0.00")
    )
    location_label = serializers.CharField(required=False, allow_blank=True)
    latitude = RoundedCoordinateField(max_digits=10, decimal_places=7, required=False, allow_null=True)
    longitude = RoundedCoordinateField(max_digits=10, decimal_places=7, required=False, allow_null=True)
    profile_photo = serializers.FileField(required=False, allow_null=True)

    def validate_profile_photo(self, value):
        if value is None:
            return value
        allowed_extensions = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif"}
        if Path(value.name).suffix.lower() not in allowed_extensions:
            raise serializers.ValidationError("Choose an image file for the profile photo.")
        return value


    def validate(self, attrs):
        profile = self.context.get("profile")
        return validate_worker_profile_requirements(
            attrs,
            role=getattr(profile, "role", None),
            profile=profile,
        )


class ForgotPasswordRequestSerializer(serializers.Serializer):
    email = serializers.EmailField()


class VerifyResetTokenSerializer(serializers.Serializer):
    email = serializers.EmailField()
    token = serializers.CharField(min_length=6, max_length=12)


class ResetPasswordSerializer(serializers.Serializer):
    email = serializers.EmailField()
    token = serializers.CharField(min_length=6, max_length=12)
    new_password = serializers.CharField(min_length=8)


class VerifySignupSerializer(serializers.Serializer):
    email = serializers.EmailField()
    token = serializers.CharField(min_length=6, max_length=12)


class PasswordResetRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = PasswordResetRequest
        fields = ["id", "email", "created_at", "expires_at", "used_at", "attempts"]


class SignupVerificationRequestSerializer(serializers.ModelSerializer):
    class Meta:
        model = SignupVerificationRequest
        fields = ["id", "email", "created_at", "expires_at", "verified_at"]


class WorkerSkillSerializer(serializers.ModelSerializer):
    class Meta:
        model = WorkerSkill
        fields = ["id", "skill_name", "proficiency", "average_rating", "rating_count", "created_at"]
        read_only_fields = ["id", "average_rating", "rating_count", "created_at"]


class WorkerCertificationSerializer(serializers.ModelSerializer):
    certificate_file_url = serializers.SerializerMethodField()
    verified_by_username = serializers.CharField(source="verified_by.username", read_only=True, allow_null=True)
    # The admin review queue lists certificates across all workers, so it
    # needs to say whose each one is -- and enough about them (name,
    # location, tenure) to render the review card without a second request.
    worker_username = serializers.CharField(source="worker.username", read_only=True)
    worker_name = serializers.SerializerMethodField()
    worker_location_label = serializers.CharField(source="worker.profile.location_label", read_only=True, default="")
    worker_member_since = serializers.DateTimeField(source="worker.date_joined", read_only=True)
    certificate_type_label = serializers.CharField(source="get_certificate_type_display", read_only=True)

    class Meta:
        model = WorkerCertification
        fields = [
            "id", "worker_username", "worker_name", "worker_location_label", "worker_member_since",
            "certificate_type", "certificate_type_label", "certificate_name", "issuer", "issue_date", "expiry_date",
            "certificate_file", "certificate_file_url", "is_verified", "verification_status",
            "verified_by", "verified_by_username", "verification_notes", "verified_at", "created_at"
        ]
        read_only_fields = ["id", "worker_username", "worker_name", "worker_location_label", "worker_member_since",
                           "certificate_type_label", "is_verified", "verification_status", "verified_by",
                           "verified_by_username", "verification_notes", "verified_at", "created_at"]

    def get_worker_name(self, obj):
        return obj.worker.get_full_name().strip() or obj.worker.username

    def get_certificate_file_url(self, obj):
        if not obj.certificate_file:
            return None
        request = self.context.get("request")
        url = obj.certificate_file.url
        return request.build_absolute_uri(url) if request else url


class WorkerPortfolioItemSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()
    before_image_url = serializers.SerializerMethodField()
    after_image_url = serializers.SerializerMethodField()

    class Meta:
        model = WorkerPortfolioItem
        fields = ["id", "title", "description", "image", "image_url",
                  "before_image", "before_image_url", "after_image", "after_image_url", "created_at"]
        read_only_fields = ["id", "created_at"]

    def get_image_url(self, obj):
        if not obj.image:
            return None
        request = self.context.get("request")
        url = obj.image.url
        return request.build_absolute_uri(url) if request else url

    def get_before_image_url(self, obj):
        if not obj.before_image:
            return None
        request = self.context.get("request")
        url = obj.before_image.url
        return request.build_absolute_uri(url) if request else url

    def get_after_image_url(self, obj):
        if not obj.after_image:
            return None
        request = self.context.get("request")
        url = obj.after_image.url
        return request.build_absolute_uri(url) if request else url


class SkillRatingSerializer(serializers.ModelSerializer):
    skill = serializers.PrimaryKeyRelatedField(queryset=WorkerSkill.objects.all(), required=False)
    # Ratings feed WorkerSkill.average_rating, so an out-of-range value would
    # skew a worker's displayed score. Matches ReviewCreateSerializer's 1-5.
    rating = serializers.DecimalField(max_digits=2, decimal_places=1, min_value=1, max_value=5)
    # Lets a household rate a skill the worker performed but never added to
    # their portfolio (e.g. hired as a plumber, also fixed a light fixture).
    # The view resolves this into a real WorkerSkill, creating one if needed.
    skill_name = serializers.CharField(write_only=True, required=False, max_length=120)

    class Meta:
        model = SkillRating
        fields = ["id", "job", "worker", "skill", "skill_name", "rating", "feedback", "created_at"]
        # job comes from the URL and worker from the rated skill, so neither
        # is accepted from the request body -- a household must not be able
        # to attribute a rating to an unrelated job or worker.
        read_only_fields = ["id", "job", "worker", "created_at"]

    def validate(self, attrs):
        if not attrs.get("skill") and not (attrs.get("skill_name") or "").strip():
            raise serializers.ValidationError({"skill": "Provide an existing skill id or a skill_name."})
        return attrs


class VerificationDocumentSerializer(serializers.ModelSerializer):
    # Both clients already limit the picker to these types and the ID photos
    # are small, but that is client-side only: the API accepted any file of
    # any size until this ran server-side too.
    ALLOWED_DOCUMENT_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".pdf"}
    MAX_DOCUMENT_BYTES = 10 * 1024 * 1024

    verified_by_username = serializers.CharField(source="verified_by.username", read_only=True, allow_null=True)

    def validate_document_file(self, value):
        if value is None:
            return value
        if Path(value.name).suffix.lower() not in self.ALLOWED_DOCUMENT_EXTENSIONS:
            raise serializers.ValidationError(
                "Upload an image (JPG, PNG, WEBP, HEIC) or a PDF for your ID document."
            )
        if value.size > self.MAX_DOCUMENT_BYTES:
            raise serializers.ValidationError("Keep the document under 10 MB.")
        return value
    # The admin review queue lists documents across all users -- and enough
    # about each one (name, location, tenure) to render the review card
    # without a second request.
    user_username = serializers.CharField(source="user.username", read_only=True)
    user_name = serializers.SerializerMethodField()
    user_location_label = serializers.CharField(source="user.profile.location_label", read_only=True, default="")
    user_member_since = serializers.DateTimeField(source="user.date_joined", read_only=True)
    id_type_label = serializers.CharField(source="get_id_type_display", read_only=True)

    class Meta:
        model = VerificationDocument
        fields = [
            "id", "user", "user_username", "user_name", "user_location_label", "user_member_since",
            "id_type", "id_type_label", "id_number",
            "document_file", "is_primary",
            "verification_status", "verified_by", "verified_by_username",
            "verification_notes", "verified_at", "created_at", "updated_at"
        ]
        read_only_fields = ["id", "user", "user_username", "user_name", "user_location_label",
                           "user_member_since", "id_type_label", "verification_status", "verified_by",
                           "verified_by_username", "verification_notes", "verified_at", "created_at", "updated_at"]

    def get_user_name(self, obj):
        return obj.user.get_full_name().strip() or obj.user.username


class WorkerPortfolioSerializer(serializers.ModelSerializer):
    skills = WorkerSkillSerializer(source="worker.portfolio_skills", many=True, read_only=True)
    certifications = WorkerCertificationSerializer(source="worker.portfolio_certifications", many=True, read_only=True)
    portfolio_items = WorkerPortfolioItemSerializer(source="worker.portfolio_items", many=True, read_only=True)

    class Meta:
        model = WorkerPortfolio
        fields = ["id", "bio", "years_experience", "skills", "certifications",
                  "portfolio_items", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]
