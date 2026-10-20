from django.conf import settings
from django.db import models


class Notification(models.Model):
    ACTION_NONE = ""
    ACTION_HIRE_REQUEST = "hire_request"
    ACTION_JOB_DETAIL = "job_detail"
    ACTION_REVIEW = "review"
    ACTION_CHOICES = [
        (ACTION_NONE, "No action"),
        (ACTION_HIRE_REQUEST, "Hire request"),
        (ACTION_JOB_DETAIL, "Job detail"),
        (ACTION_REVIEW, "Review"),
    ]

    TYPE_APPLICATION = "application"
    TYPE_ACCOUNT_ACTIVITY = "account_activity"
    TYPE_ACCEPTED = "accepted"
    TYPE_HIRING = "hiring"
    TYPE_REJECTION = "rejection"
    TYPE_VERIFICATION = "verification"
    TYPE_ANALYTICS = "analytics"
    TYPE_COMPLETION = "completion"
    TYPE_REVIEW_REMINDER = "review_reminder"
    TYPE_JOB_MATCH = "job_match"
    TYPE_REVIEW = "review"
    TYPE_ADMIN_ALERT = "admin_alert"
    TYPE_CHOICES = [
        (TYPE_APPLICATION, "Application"),
        (TYPE_ACCOUNT_ACTIVITY, "Account Activity"),
        (TYPE_ACCEPTED, "Accepted"),
        (TYPE_HIRING, "Hiring"),
        (TYPE_REJECTION, "Rejection"),
        (TYPE_VERIFICATION, "Verification"),
        (TYPE_ANALYTICS, "Analytics"),
        (TYPE_COMPLETION, "Completion"),
        (TYPE_REVIEW_REMINDER, "Review Reminder"),
        (TYPE_JOB_MATCH, "Job Match"),
        (TYPE_REVIEW, "Review"),
        (TYPE_ADMIN_ALERT, "Admin Alert"),
    ]

    recipient = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications")
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="triggered_notifications",
        null=True,
        blank=True,
    )
    notification_type = models.CharField(max_length=30, choices=TYPE_CHOICES)
    title = models.CharField(max_length=255)
    message = models.TextField()
    related_job_id = models.PositiveIntegerField(null=True, blank=True)
    related_application_id = models.PositiveIntegerField(null=True, blank=True)
    action_type = models.CharField(max_length=40, choices=ACTION_CHOICES, blank=True, default=ACTION_NONE)
    action_url = models.CharField(max_length=255, blank=True, default="")
    requires_action = models.BooleanField(default=False)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            # The background job-match pass may run more than once for a job
            # (retry, duplicate enqueue); a worker is told about a job once.
            models.UniqueConstraint(
                fields=["recipient", "related_job_id"],
                condition=models.Q(notification_type="job_match"),
                name="unique_job_match_notification_per_job",
            )
        ]

    def __str__(self) -> str:
        return f"{self.recipient.username}: {self.title}"
