from rest_framework import serializers

from apps.complaints.models import Complaint


class ComplaintSerializer(serializers.ModelSerializer):
    complainant_username = serializers.CharField(source="complainant.username", read_only=True)
    respondent_username = serializers.CharField(source="respondent.username", read_only=True, allow_null=True)
    job_service_type = serializers.CharField(source="job.serviceType", read_only=True, allow_null=True)
    job_title = serializers.SerializerMethodField()

    class Meta:
        model = Complaint
        fields = [
            "id",
            "complainant",
            "complainant_username",
            "respondent",
            "respondent_username",
            "job",
            "job_title",
            "job_service_type",
            "complaint_type",
            "description",
            "status",
            "resolution",
            "admin_notes",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "complainant_username",
            "respondent_username",
            "job_title",
            "job_service_type",
            "status",
            "resolution",
            "admin_notes",
            "created_at",
            "updated_at",
        ]

    def get_job_title(self, obj):
        if obj.job:
            return f"{obj.job.serviceType} at {obj.job.barangay}"
        return None
