from rest_framework import serializers
from django.urls import reverse

from apps.accounts.banned import banned_match, normalize_id_number
from apps.accounts.models import BannedCredential
from apps.common.models import AdminActionLog, VerificationRequest
from apps.common.permissions import is_platform_admin
from apps.common.uploads import UploadRejected, validate_document_upload


class AdminActionLogSerializer(serializers.ModelSerializer):
    action_label = serializers.CharField(source="get_action_display", read_only=True)

    class Meta:
        model = AdminActionLog
        fields = [
            "id", "actor_username", "action", "action_label",
            "target_label", "target_type", "target_id", "detail", "created_at",
        ]
        read_only_fields = fields


class VerificationRequestSerializer(serializers.ModelSerializer):
    account_role = serializers.SerializerMethodField()
    worker_username = serializers.CharField(source="worker.username", read_only=True)
    worker_name = serializers.SerializerMethodField()
    worker_email = serializers.EmailField(source="worker.email", read_only=True)
    worker_phone = serializers.SerializerMethodField()
    worker_location_label = serializers.SerializerMethodField()
    worker_skills = serializers.SerializerMethodField()
    worker_hourly_rate = serializers.SerializerMethodField()
    worker_daily_rate = serializers.SerializerMethodField()
    worker_years_experience = serializers.SerializerMethodField()
    worker_profile_photo = serializers.SerializerMethodField()
    primary_id_type_label = serializers.CharField(source="get_primary_id_type_display", read_only=True)
    primary_id_preview = serializers.SerializerMethodField()
    secondary_doc_preview = serializers.SerializerMethodField()
    ban_check = serializers.SerializerMethodField()

    class Meta:
        model = VerificationRequest
        fields = [
            "id",
            "worker",
            "account_role",
            "worker_username",
            "worker_name",
            "worker_email",
            "worker_phone",
            "worker_location_label",
            "worker_skills",
            "worker_hourly_rate",
            "worker_daily_rate",
            "worker_years_experience",
            "worker_profile_photo",
            "primary_id_type",
            "primary_id_type_label",
            "primary_id_name",
            "primary_id_number",
            "secondary_doc_name",
            "primary_id_preview",
            "secondary_doc_preview",
            "notes",
            "status",
            "submitted_at",
            "reviewed_at",
            "review_note",
            "ban_check",
        ]
        read_only_fields = ["id", "status", "submitted_at", "reviewed_at", "review_note", "ban_check"]

    def get_ban_check(self, obj):
        """For admins only: whether this request's ID number or the
        applicant's full name belongs to a permanently blocked account
        (AGENTS.md II.D). The applicant's own copy of the request gets None,
        so they never learn why an ID was turned down."""
        request = self.context.get("request")
        if not request or not is_platform_admin(getattr(request, "user", None)):
            return None
        id_match = obj.banned_match_username
        if not id_match and obj.primary_id_number:
            row = banned_match(BannedCredential.KIND_ID_NUMBER, obj.primary_id_number, exclude_user=obj.worker)
            id_match = row.username if row else ""
        name_row = banned_match(BannedCredential.KIND_NAME, obj.worker.get_full_name(), exclude_user=obj.worker)
        return {
            "id_number_match": id_match,
            "name_match": name_row.username if name_row else "",
        }

    def get_worker_name(self, obj):
        full_name = obj.worker.get_full_name().strip()
        return full_name or obj.worker.username

    def get_account_role(self, obj):
        profile = self.get_worker_profile(obj)
        return profile.role if profile else ""

    def get_worker_profile(self, obj):
        return getattr(obj.worker, "profile", None)

    def get_worker_phone(self, obj):
        profile = self.get_worker_profile(obj)
        return profile.phone if profile else ""

    def get_worker_location_label(self, obj):
        profile = self.get_worker_profile(obj)
        return profile.location_label if profile else ""

    def get_worker_skills(self, obj):
        profile = self.get_worker_profile(obj)
        return profile.skills if profile else []

    def get_worker_hourly_rate(self, obj):
        profile = self.get_worker_profile(obj)
        return profile.hourly_rate if profile else None

    def get_worker_daily_rate(self, obj):
        profile = self.get_worker_profile(obj)
        return profile.daily_rate if profile else None

    def get_worker_years_experience(self, obj):
        profile = self.get_worker_profile(obj)
        return profile.years_experience if profile else 0

    def get_worker_profile_photo(self, obj):
        profile = self.get_worker_profile(obj)
        if not profile or not profile.profile_photo:
            return ""
        request = self.context.get("request")
        url = profile.profile_photo.url
        return request.build_absolute_uri(url) if request else url

    def get_primary_id_preview(self, obj):
        return self.get_document_url(obj, "primary") if obj.primary_id_file else ""

    def get_secondary_doc_preview(self, obj):
        return self.get_document_url(obj, "secondary") if obj.secondary_doc_file else ""

    def get_document_url(self, obj, document_type):
        request = self.context.get("request")
        path = reverse("verification-request-document", args=[obj.id, document_type])
        return request.build_absolute_uri(path) if request else path


class VerificationRequestCreateSerializer(serializers.Serializer):
    primary_id_type = serializers.ChoiceField(
        choices=VerificationRequest.ID_TYPE_CHOICES,
        default=VerificationRequest.ID_TYPE_OTHER,
    )
    # Only meaningful for "other"; for every listed type the label is taken
    # from the choice itself, so the two can never disagree.
    primary_id_name = serializers.CharField(required=False, allow_blank=True, max_length=255)
    # Required for every new request: it is what stops a permanently blocked
    # person from getting verified again under a new account.
    primary_id_number = serializers.CharField(max_length=64)
    secondary_doc_name = serializers.CharField(max_length=255)
    primary_id_file = serializers.FileField(required=True)
    secondary_doc_file = serializers.FileField(required=True)
    notes = serializers.CharField(required=False, allow_blank=True)
    worker_username = serializers.CharField(required=False, allow_blank=True)

    def validate_primary_id_number(self, value):
        typed = " ".join(str(value or "").split())
        if not 4 <= len(normalize_id_number(typed)) <= 30:
            raise serializers.ValidationError("Enter the ID number exactly as it is printed on your ID.")
        return typed

    def validate(self, attrs):
        id_type = attrs.get("primary_id_type", VerificationRequest.ID_TYPE_OTHER)
        typed_name = (attrs.get("primary_id_name") or "").strip()
        if id_type == VerificationRequest.ID_TYPE_OTHER:
            if not typed_name:
                raise serializers.ValidationError(
                    {"primary_id_name": "Name the ID you are uploading."}
                )
            attrs["primary_id_name"] = typed_name
        else:
            attrs["primary_id_name"] = dict(VerificationRequest.ID_TYPE_CHOICES)[id_type]
        return attrs

    def validate_primary_id_file(self, value):
        return self.validate_document_file(value)

    def validate_secondary_doc_file(self, value):
        return self.validate_document_file(value)

    @staticmethod
    def validate_document_file(value):
        try:
            return validate_document_upload(value)
        except UploadRejected as rejected:
            raise serializers.ValidationError(str(rejected)) from rejected
