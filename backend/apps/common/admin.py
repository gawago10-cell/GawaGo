from django.contrib import admin

from apps.common.models import VerificationRequest


@admin.register(VerificationRequest)
class VerificationRequestAdmin(admin.ModelAdmin):
    list_display = ("worker", "status", "submitted_at", "reviewed_at")
    list_filter = ("status", "submitted_at", "reviewed_at")
    search_fields = ("worker__username", "primary_id_name", "secondary_doc_name")
    readonly_fields = ("submitted_at", "reviewed_at")
