from django.conf import settings
from django.db import models

from apps.jobs.models import JobPosting


class Complaint(models.Model):
    STATUS_SUBMITTED = "submitted"
    STATUS_UNDER_REVIEW = "under_review"
    STATUS_RESOLVED = "resolved"
    STATUS_CLOSED = "closed"
    STATUS_CHOICES = [
        (STATUS_SUBMITTED, "Submitted"),
        (STATUS_UNDER_REVIEW, "Under Review"),
        (STATUS_RESOLVED, "Resolved"),
        (STATUS_CLOSED, "Closed"),
    ]

    TYPE_PAYMENT_ISSUE = "payment_issue"
    TYPE_QUALITY_OF_WORK = "quality_of_work"
    TYPE_NO_SHOW = "no_show"
    TYPE_SAFETY_CONCERN = "safety_concern"
    TYPE_BEHAVIOR = "behavior"
    TYPE_OTHER = "other"
    TYPE_CHOICES = [
        (TYPE_PAYMENT_ISSUE, "Payment Issue"),
        (TYPE_QUALITY_OF_WORK, "Quality of Work"),
        (TYPE_NO_SHOW, "No Show"),
        (TYPE_SAFETY_CONCERN, "Safety Concern"),
        (TYPE_BEHAVIOR, "Inappropriate Behavior"),
        (TYPE_OTHER, "Other"),
    ]

    complainant = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="complaints_filed"
    )
    respondent = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="complaints_against",
        null=True,
        blank=True,
    )
    job = models.ForeignKey(JobPosting, on_delete=models.CASCADE, related_name="complaints", null=True, blank=True)
    complaint_type = models.CharField(max_length=50, choices=TYPE_CHOICES)
    description = models.TextField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_SUBMITTED)
    resolution = models.TextField(blank=True, null=True)
    admin_notes = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"Complaint #{self.id}: {self.get_complaint_type_display()} by {self.complainant.username}"


def complaint_evidence_path(instance, filename):
    return f"complaint_evidence/{instance.complaint_id}/{filename}"


class ComplaintEvidence(models.Model):
    """A photo attached to a report so an admin can see what happened rather
    than judging from the description alone."""

    complaint = models.ForeignKey(Complaint, on_delete=models.CASCADE, related_name="evidence")
    image = models.ImageField(upload_to=complaint_evidence_path)
    uploaded_at = models.DateTimeField(auto_now_add=True)
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["order", "uploaded_at"]

    def __str__(self) -> str:
        return f"Evidence for complaint #{self.complaint_id}"
