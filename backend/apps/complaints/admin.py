from django.contrib import admin

from apps.complaints.models import Complaint


@admin.register(Complaint)
class ComplaintAdmin(admin.ModelAdmin):
    list_display = ("id", "complainant", "respondent", "complaint_type", "status", "job", "created_at")
    list_filter = ("status", "complaint_type", "created_at")
    search_fields = ("complainant__username", "respondent__username", "description")
    readonly_fields = ("created_at", "updated_at")
    fieldsets = (
        ("Complaint Info", {"fields": ("complainant", "respondent", "job", "complaint_type", "description")}),
        ("Status & Resolution", {"fields": ("status", "resolution", "admin_notes")}),
        ("Timestamps", {"fields": ("created_at", "updated_at")}),
    )
