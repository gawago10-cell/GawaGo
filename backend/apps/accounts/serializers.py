import json
from decimal import Decimal
from pathlib import Path

from django.contrib.auth.models import User
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.urls import reverse
from rest_framework import serializers

from apps.common.fields import RoundedCoordinateField
from apps.common.sanitize import sanitize_text
from apps.common.uploads import (
    DOCUMENT_EXTENSIONS,
    MAX_DOCUMENT_BYTES as MAX_DOCUMENT_UPLOAD_BYTES,
    UploadRejected,
    validate_document_upload,
    validate_image_upload,
)
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
)
from apps.common.serializers import VerificationRequestSerializer


# Both clients already limit the picker to these types, but that is
# client-side only -- apps.common.uploads enforces the real rules (contents,
# not just the extension) for every upload path.
ALLOWED_DOCUMENT_EXTENSIONS = DOCUMENT_EXTENSIONS
MAX_DOCUMENT_BYTES = MAX_DOCUMENT_UPLOAD_BYTES


# Tayabas City sits at roughly 13.93-14.12 N, 121.50-121.75 E. The box is
# padded well past the city limits so a pin dropped just outside a barangay
# boundary still saves, while coordinates from another province -- or the
# 0,0 and 999,999 that a malformed client sends -- are refused. The platform
# serves one city (AGENTS.md V), so a job in New York is bad data, not an
# edge case.
TAYABAS_LATITUDE_RANGE = (13.80, 14.25)
TAYABAS_LONGITUDE_RANGE = (121.35, 121.90)


def validate_tayabas_coordinates(attrs):
    latitude = attrs.get("latitude")
    longitude = attrs.get("longitude")
    if (latitude is None) != (longitude is None):
        raise serializers.ValidationError(
            {"location": "Latitude and longitude must be provided together."}
        )
    if latitude is None or longitude is None:
        return attrs
    latitude = float(latitude)
    longitude = float(longitude)
    within_latitude = TAYABAS_LATITUDE_RANGE[0] <= latitude <= TAYABAS_LATITUDE_RANGE[1]
    within_longitude = TAYABAS_LONGITUDE_RANGE[0] <= longitude <= TAYABAS_LONGITUDE_RANGE[1]
    if not (within_latitude and within_longitude):
        raise serializers.ValidationError(
            {"location": "Pick a location inside Tayabas City and its barangays."}
        )
    return attrs


MAX_WORKER_SKILLS = 3
# WorkerSkill.skill_name's column size; every profile skill gets a WorkerSkill row.
SKILL_NAME_MAX_LENGTH = 120


def viewer_may_see_credential_review(request, worker_id):
    """Admin review notes and the reviewing admin's identity belong to staff
    and to the credential's owner."""
    user = getattr(request, "user", None)
    if user is None or not user.is_authenticated:
        return False
    return user.is_staff or user.id == worker_id


def validate_worker_profile_requirements(attrs, *, role, profile=None):
    attrs = validate_tayabas_coordinates(attrs)
    if role != UserProfile.ROLE_WORKER:
        return attrs

    skills = attrs.get("skills")
    if skills is not None:
        # "Cooking", "cooking" and "COOKING" are one skill, and a worker with
        # none cannot be matched to anything, so an empty list is not a valid
        # saved state.
        # Same notion of "one skill" as the portfolio sync (skill_key):
        # case and repeated spaces don't make a different skill.
        deduplicated = []
        seen = set()
        for skill in skills:
            name = " ".join(str(skill).split())
            if not name or name.casefold() in seen:
                continue
            seen.add(name.casefold())
            deduplicated.append(name)
        if not deduplicated:
            raise serializers.ValidationError({"skills": "List at least one skill."})
        if len(deduplicated) > MAX_WORKER_SKILLS:
            raise serializers.ValidationError(
                {"skills": f"Workers can list at most {MAX_WORKER_SKILLS} skills."}
            )
        attrs["skills"] = deduplicated

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

    def get_value(self, dictionary):
        value = super().get_value(dictionary)
        # Multipart and form-encoded bodies arrive as a one-item list holding
        # the whole serialized list, so unwrap it here or the string parsing
        # in to_internal_value never runs and the list is stored as one
        # mangled string.
        if (
            isinstance(value, list)
            and len(value) == 1
            and isinstance(value[0], str)
            and self._looks_serialized(value[0])
        ):
            return value[0]
        return value

    @staticmethod
    def _looks_serialized(raw):
        text = raw.strip()
        return (text.startswith("[") and text.endswith("]")) or "," in text

    def to_internal_value(self, data):
        if isinstance(data, str):
            data = self._parse_text(data)
        return super().to_internal_value(data)

    @staticmethod
    def _parse_text(raw):
        text = raw.strip()
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            parsed = None
        if isinstance(parsed, list):
            return [str(item).strip() for item in parsed if str(item).strip()]
        if isinstance(parsed, str):
            return [parsed.strip()] if parsed.strip() else []
        if text.startswith("[") and text.endswith("]"):
            text = text[1:-1]
        return [item.strip() for item in text.split(",") if item.strip()]


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
    # The web client restores a signed-in session from this endpoint on page
    # load, and a superadmin has to come back as a superadmin: role alone
    # cannot tell the two admin levels apart.
    is_superuser = serializers.BooleanField(source="user.is_superuser", read_only=True)

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
            "is_superuser",
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
                "is_superuser",
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
    skills = FlexibleStringListField(child=serializers.CharField(max_length=SKILL_NAME_MAX_LENGTH), required=False)
    hourly_rate = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True, min_value=Decimal("0.00")
    )
    daily_rate = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True, min_value=Decimal("0.00")
    )
    location_label = serializers.CharField(required=False, allow_blank=True, max_length=255)
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


class AdminAccountSerializer(serializers.Serializer):
    """One staff account as the superadmin Admin Management table shows it."""

    id = serializers.IntegerField(read_only=True)
    username = serializers.CharField(read_only=True)
    email = serializers.EmailField(read_only=True)
    full_name = serializers.SerializerMethodField()
    is_active = serializers.BooleanField(read_only=True)
    is_superuser = serializers.BooleanField(read_only=True)
    date_joined = serializers.DateTimeField(read_only=True)
    last_login = serializers.DateTimeField(read_only=True)
    role_label = serializers.SerializerMethodField()

    def get_full_name(self, obj):
        return obj.get_full_name() or obj.username

    def get_role_label(self, obj):
        return "Full System Control" if obj.is_superuser else "Admin"


class AdminAccountCreateSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150)
    email = serializers.EmailField()
    password = serializers.CharField(min_length=8, write_only=True)
    first_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    last_name = serializers.CharField(max_length=150, required=False, allow_blank=True)

    def validate_username(self, value):
        username = value.strip()
        if not username:
            raise serializers.ValidationError("Username is required.")
        if User.objects.filter(username__iexact=username).exists():
            raise serializers.ValidationError("That username is already taken.")
        return username

    def validate_email(self, value):
        email = value.strip().lower()
        if User.objects.filter(email__iexact=email).exists():
            raise serializers.ValidationError("That email is already in use.")
        return email

    def validate_password(self, value):
        try:
            validate_password(value)
        except DjangoValidationError as exc:
            raise serializers.ValidationError(list(exc.messages))
        return value


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField()


class ProfileUpdateSerializer(serializers.Serializer):
    # Explicit max_length: a plain Serializer doesn't inherit column widths,
    # so an oversized value would reach the database and 500.
    first_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    last_name = serializers.CharField(required=False, allow_blank=True, max_length=150)
    email = serializers.EmailField(required=False)
    phone = serializers.CharField(max_length=30, required=False, allow_blank=True)
    bio = serializers.CharField(required=False, allow_blank=True)
    years_experience = serializers.IntegerField(required=False, min_value=0)
    skills = FlexibleStringListField(child=serializers.CharField(max_length=SKILL_NAME_MAX_LENGTH), required=False)
    hourly_rate = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True, min_value=Decimal("0.00")
    )
    daily_rate = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False, allow_null=True, min_value=Decimal("0.00")
    )
    location_label = serializers.CharField(required=False, allow_blank=True, max_length=255)
    latitude = RoundedCoordinateField(max_digits=10, decimal_places=7, required=False, allow_null=True)
    longitude = RoundedCoordinateField(max_digits=10, decimal_places=7, required=False, allow_null=True)
    profile_photo = serializers.FileField(required=False, allow_null=True)
    # Email changes are re-auth-gated below: a hijacked access token (valid
    # up to an hour, see common/authentication.py) must not be able to turn
    # itself into a permanent takeover by silently moving the account to an
    # attacker-controlled email, since password resets are then mailed there.
    current_password = serializers.CharField(required=False, write_only=True)

    def validate_profile_photo(self, value):
        if value is None:
            return value
        try:
            return validate_image_upload(value)
        except UploadRejected as rejected:
            raise serializers.ValidationError(str(rejected)) from rejected

    def validate_bio(self, value):
        return sanitize_text(value)

    def validate_email(self, value):
        # Login and password reset both look accounts up by email, so two
        # accounts sharing one would make either pick an arbitrary account.
        email = value.strip().lower()
        profile = self.context.get("profile")
        others = User.objects.filter(email__iexact=email)
        if profile is not None:
            others = others.exclude(pk=profile.user_id)
        if others.exists():
            raise serializers.ValidationError("Email already exists.")
        return email


    def validate(self, attrs):
        user = self.context.get("user")
        new_email = attrs.get("email")
        if new_email and user is not None and new_email != (user.email or "").strip().lower():
            if not attrs.get("current_password") or not user.check_password(attrs["current_password"]):
                raise serializers.ValidationError(
                    {"current_password": "Enter your current password to change your email."}
                )
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
    # certificate_file lives in private storage (no public .url), so the
    # model field itself is write-only for uploads; certificate_file_url
    # below is the only read representation, pointing at the
    # permission-checked serving view.
    certificate_file = serializers.FileField(write_only=True, required=False)
    certificate_file_url = serializers.SerializerMethodField()
    certificate_file_type = serializers.SerializerMethodField()
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
            "certificate_file", "certificate_file_url", "certificate_file_type", "is_verified", "verification_status",
            "verified_by", "verified_by_username", "verification_notes", "verified_at", "created_at"
        ]
        read_only_fields = ["id", "worker_username", "worker_name", "worker_location_label", "worker_member_since",
                           "certificate_type_label", "is_verified", "verification_status", "verified_by",
                           "verified_by_username", "verification_notes", "verified_at", "created_at"]

    # Who reviewed a credential and what they wrote about it is for the admin
    # queue and the worker themselves, never for whoever is reading the
    # public portfolio.
    REVIEWER_FIELDS = ("verified_by", "verified_by_username", "verification_notes", "verified_at")

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not viewer_may_see_credential_review(self.context.get("request"), instance.worker_id):
            for field in self.REVIEWER_FIELDS:
                data.pop(field, None)
        return data

    def validate_certificate_file(self, value):
        # Anything other than a real image or PDF (an .html file, say) would
        # otherwise be stored and served back as a live page.
        if value is None:
            return value
        try:
            return validate_document_upload(value)
        except UploadRejected as rejected:
            raise serializers.ValidationError(str(rejected)) from rejected

    def validate_certificate_name(self, value):
        return sanitize_text(value)

    def validate_issuer(self, value):
        return sanitize_text(value)

    def get_worker_name(self, obj):
        return obj.worker.get_full_name().strip() or obj.worker.username

    def get_certificate_file_type(self, obj):
        """"image" or "pdf" (or "" with no file). The file URL is the
        permission-checked serving view, which has no extension, so clients
        can't tell from the URL whether to show a thumbnail."""
        if not obj.certificate_file:
            return ""
        name = obj.certificate_file.name.lower()
        if name.endswith(".pdf"):
            return "pdf"
        if name.endswith((".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".heif")):
            return "image"
        return "file"

    def get_certificate_file_url(self, obj):
        if not obj.certificate_file:
            return None
        # certificate_file lives in private storage (no public .url), so this
        # always points at the permission-checked serving view (F16).
        path = f"/api/accounts/portfolio/certifications/{obj.id}/file/"
        request = self.context.get("request")
        return request.build_absolute_uri(path) if request else path


def _validated_portfolio_image(value):
    if value is None:
        return value
    try:
        return validate_image_upload(value)
    except UploadRejected as rejected:
        raise serializers.ValidationError(str(rejected)) from rejected


class WorkerPortfolioItemSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()
    before_image_url = serializers.SerializerMethodField()
    after_image_url = serializers.SerializerMethodField()

    class Meta:
        model = WorkerPortfolioItem
        fields = ["id", "title", "description", "image", "image_url",
                  "before_image", "before_image_url", "after_image", "after_image_url", "created_at"]
        read_only_fields = ["id", "created_at"]

    def validate_image(self, value):
        return _validated_portfolio_image(value)

    def validate_before_image(self, value):
        return _validated_portfolio_image(value)

    def validate_after_image(self, value):
        return _validated_portfolio_image(value)

    def validate_title(self, value):
        return sanitize_text(value)

    def validate_description(self, value):
        return sanitize_text(value)

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


class WorkerPortfolioSerializer(serializers.ModelSerializer):
    skills = serializers.SerializerMethodField()
    certifications = serializers.SerializerMethodField()

    def get_skills(self, obj):
        from apps.accounts.services import listed_portfolio_skills

        return WorkerSkillSerializer(listed_portfolio_skills(obj.worker), many=True).data
    portfolio_items = WorkerPortfolioItemSerializer(source="worker.portfolio_items", many=True, read_only=True)

    def get_certifications(self, obj):
        certifications = obj.worker.portfolio_certifications.all()
        if not viewer_may_see_credential_review(self.context.get("request"), obj.worker_id):
            # A pending credential is an unverified claim and a rejected one
            # was turned down, so neither belongs on a public portfolio.
            certifications = certifications.filter(
                verification_status=WorkerCertification.STATUS_APPROVED
            )
        return WorkerCertificationSerializer(certifications, many=True, context=self.context).data

    class Meta:
        model = WorkerPortfolio
        fields = ["id", "bio", "years_experience", "skills", "certifications",
                  "portfolio_items", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]
