from rest_framework import serializers
from django.urls import reverse
from pathlib import Path

from apps.common.models import VerificationRequest


ALLOWED_VERIFICATION_DOCUMENT_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".heic",
    ".heif",
    ".pdf",
}


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
    primary_id_preview = serializers.SerializerMethodField()
    secondary_doc_preview = serializers.SerializerMethodField()

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
            "primary_id_name",
            "secondary_doc_name",
            "primary_id_preview",
            "secondary_doc_preview",
            "notes",
            "status",
            "submitted_at",
            "reviewed_at",
            "review_note",
        ]
        read_only_fields = ["id", "status", "submitted_at", "reviewed_at", "review_note"]

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
    primary_id_name = serializers.CharField()
    secondary_doc_name = serializers.CharField()
    primary_id_file = serializers.FileField(required=True)
    secondary_doc_file = serializers.FileField(required=True)
    notes = serializers.CharField(required=False, allow_blank=True)
    worker_username = serializers.CharField(required=False, allow_blank=True)

    def validate_primary_id_file(self, value):
        return self.validate_document_file(value)

    def validate_secondary_doc_file(self, value):
        return self.validate_document_file(value)

    @staticmethod
    def validate_document_file(value):
        if Path(value.name).suffix.lower() not in ALLOWED_VERIFICATION_DOCUMENT_EXTENSIONS:
            raise serializers.ValidationError("Choose an image or PDF document.")
        return value
