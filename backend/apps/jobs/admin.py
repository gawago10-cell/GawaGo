from django.contrib import admin
from django.db import transaction

from apps.jobs.models import JobApplication, JobImage, JobPosting
from apps.jobs.services import reopen_if_nobody_hired


@admin.register(JobPosting)
class JobPostingAdmin(admin.ModelAdmin):
    list_display = ("title", "household", "job_type", "required_skill", "worker_slots", "status", "created_at")
    list_filter = ("job_type", "status", "created_at")
    search_fields = ("title", "household__username", "required_skill")


@admin.register(JobImage)
class JobImageAdmin(admin.ModelAdmin):
    list_display = ("job", "uploaded_at", "order")
    list_filter = ("uploaded_at",)
    search_fields = ("job__title",)


@admin.register(JobApplication)
class JobApplicationAdmin(admin.ModelAdmin):
    list_display = ("job", "worker", "status", "applied_at", "updated_at")
    list_filter = ("status", "applied_at")
    search_fields = ("job__title", "worker__username")

    def save_model(self, request, obj, form, change):
        """Taking a hire away here used to leave its job "in progress" with
        nobody hired; the job opens again instead."""
        super().save_model(request, obj, form, change)
        if change and obj.status != JobApplication.STATUS_HIRED:
            job_id = obj.job_id
            transaction.on_commit(
                lambda: reopen_if_nobody_hired(job_id, note="Reopened: the hire was changed in the admin.")
            )
