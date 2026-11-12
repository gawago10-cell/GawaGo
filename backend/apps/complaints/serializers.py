from django.urls import reverse
from rest_framework import serializers

from apps.accounts.banned import latest_id_number
from apps.common.sanitize import sanitize_text
from apps.complaints.models import Complaint, ComplaintEvidence
from apps.common.barangays import barangay_from_location_label
from apps.jobs.privacy import masked_location_label


class ComplaintEvidenceSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = ComplaintEvidence
        fields = ["id", "image_url", "uploaded_at", "order"]

    def get_image_url(self, obj):
        # Points at the permission-checked view, not the file itself: clients
        # must fetch it with their bearer token.
        if not obj.image:
            return ""
        request = self.context.get("request")
        url = reverse("complaint-evidence", args=[obj.complaint_id, obj.id])
        return request.build_absolute_uri(url) if request else url


def _party_detail(user):
    """Everything the admin review UI shows about one side of a report.
    Only used by ComplaintAdminSerializer -- phone/email are exposed to
    admins reviewing a report, never to the other party via the regular
    household/worker ComplaintSerializer.
    """
    if not user:
        return None
    profile = getattr(user, "profile", None)
    display_name = " ".join(part for part in [user.first_name, user.last_name] if part).strip()
    id_number, id_type_label = latest_id_number(user)
    return {
        "username": user.username,
        "display_name": display_name or user.username,
        "role": getattr(profile, "role", ""),
        "average_rating": profile.average_rating if profile else None,
        "rating_count": profile.rating_count if profile else 0,
        "location_label": profile.location_label if profile else "",
        "member_since": user.date_joined.date().isoformat() if user.date_joined else None,
        "phone": profile.phone if profile else "",
        "email": user.email,
        # What a permanent block would also bar from a new account
        # (AGENTS.md II.D), shown in the Block Permanently dialog.
        "id_number": id_number,
        "id_type_label": id_type_label,
    }


class ComplaintSerializer(serializers.ModelSerializer):
    """What the complainant sees about their own report. Never used for the
    respondent (who must not learn a report exists) and never carries the
    internal admin_notes -- see ComplaintAdminSerializer for those."""

    complainant_username = serializers.CharField(source="complainant_label", read_only=True)
    respondent_username = serializers.CharField(source="respondent_label", read_only=True)
    # The person's name, as the rest of the app shows people; the filer saw
    # only a username. Nothing else about them (contact, ID) is added here.
    respondent_name = serializers.SerializerMethodField()
    job_service_type = serializers.CharField(source="job.job_type", read_only=True, allow_null=True)
    job_status = serializers.CharField(source="job.status", read_only=True, allow_null=True)
    job_title = serializers.SerializerMethodField()
    evidence = ComplaintEvidenceSerializer(many=True, read_only=True)

    class Meta:
        model = Complaint
        fields = [
            "id",
            "complainant",
            "complainant_username",
            "respondent",
            "respondent_username",
            "respondent_name",
            "job",
            "job_title",
            "job_service_type",
            "job_status",
            "complaint_type",
            "description",
            "evidence",
            "status",
            "resolution",
            "created_at",
            "updated_at",
        ]
        # complainant and respondent are derived by the view from the job's
        # real household/applicant relationship, never taken from the
        # request body -- a filer must not be able to name an unrelated
        # respondent or impersonate another complainant.
        read_only_fields = [
            "id",
            "complainant",
            "complainant_username",
            "respondent",
            "respondent_username",
            "respondent_name",
            "job_title",
            "job_service_type",
            "job_status",
            "evidence",
            "status",
            "resolution",
            "created_at",
            "updated_at",
        ]

    def validate_description(self, value):
        return sanitize_text(value)

    def get_respondent_name(self, obj):
        if obj.respondent is None:
            return obj.respondent_label
        return obj.respondent.get_full_name().strip() or obj.respondent.username

    def get_job_title(self, obj):
        if obj.job:
            # Barangay, not the street: a report is filed by people who may
            # never have been hired for this job. The barangay alone, as the
            # other screens show it; the city and province added nothing.
            barangay = barangay_from_location_label(obj.job.location_label)
            return f"{obj.job.title} at {barangay}" if barangay else obj.job.title
        return None


class ComplaintAdminSerializer(ComplaintSerializer):
    """Adds internal admin_notes and the account detail the admin review
    queue shows for each party. Only used by the superadmin-only views in
    views.py -- never for household/worker-facing responses.

    Whether the reported account is currently suspended lives here rather
    than on the filer's own view: the status flow tells a filer how their
    report is progressing, not what action was taken against the person.
    """

    job_name = serializers.SerializerMethodField()
    job_barangay = serializers.SerializerMethodField()
    complainant_detail = serializers.SerializerMethodField()
    respondent_detail = serializers.SerializerMethodField()
    respondent_is_blocked = serializers.SerializerMethodField()
    respondent_blocked_until = serializers.SerializerMethodField()

    class Meta(ComplaintSerializer.Meta):
        fields = ComplaintSerializer.Meta.fields + [
            "admin_notes",
            "job_name",
            "job_barangay",
            "complainant_detail",
            "respondent_detail",
            "respondent_is_blocked",
            "respondent_blocked_until",
        ]
        read_only_fields = ComplaintSerializer.Meta.read_only_fields + [
            "admin_notes",
            "job_name",
            "job_barangay",
            "complainant_detail",
            "respondent_detail",
            "respondent_is_blocked",
            "respondent_blocked_until",
        ]

    def get_respondent_is_blocked(self, obj):
        profile = getattr(obj.respondent, "profile", None)
        if profile is None:
            return False
        return profile.refresh_block_status()

    def get_respondent_blocked_until(self, obj):
        profile = getattr(obj.respondent, "profile", None)
        if profile is None or not profile.refresh_block_status() or not profile.blocked_until:
            return None
        return profile.blocked_until.isoformat()

    def get_job_name(self, obj):
        return obj.job.title if obj.job else None

    def get_job_barangay(self, obj):
        return obj.job.location_label if obj.job else ""

    def get_complainant_detail(self, obj):
        return _party_detail(obj.complainant)

    def get_respondent_detail(self, obj):
        return _party_detail(obj.respondent)
