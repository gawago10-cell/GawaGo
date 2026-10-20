import uuid
from pathlib import Path

from django.conf import settings
from django.db import models

from apps.complaints.storage import PrivateMediaStorage
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

    # SET_NULL for the same reason the job link below is: deleting an account
    # must never erase a report, least of all one filed against that account.
    # Both usernames are snapshotted so a report stays attributable afterwards.
    complainant = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="complaints_filed",
        null=True,
        blank=True,
    )
    complainant_username = models.CharField(max_length=150, blank=True, default="")
    respondent = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="complaints_against",
        null=True,
        blank=True,
    )
    respondent_username = models.CharField(max_length=150, blank=True, default="")
    # SET_NULL: deleting a job must never erase a report filed about it.
    job = models.ForeignKey(JobPosting, on_delete=models.SET_NULL, related_name="complaints", null=True, blank=True)
    complaint_type = models.CharField(max_length=50, choices=TYPE_CHOICES)
    description = models.TextField()
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_SUBMITTED)
    resolution = models.TextField(blank=True, null=True)
    admin_notes = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def save(self, *args, **kwargs):
        snapshots = []
        if self.complainant_id and not self.complainant_username:
            self.complainant_username = self.complainant.username
            snapshots.append("complainant_username")
        if self.respondent_id and not self.respondent_username:
            self.respondent_username = self.respondent.username
            snapshots.append("respondent_username")
        update_fields = kwargs.get("update_fields")
        if update_fields is not None and snapshots:
            kwargs["update_fields"] = list(update_fields) + snapshots
        super().save(*args, **kwargs)

    @property
    def complainant_label(self) -> str:
        if self.complainant_id:
            return self.complainant.username
        return self.complainant_username or "Deleted account"

    @property
    def respondent_label(self) -> str:
        if self.respondent_id:
            return self.respondent.username
        return self.respondent_username or "Deleted account"

    def __str__(self) -> str:
        return f"Complaint #{self.id}: {self.get_complaint_type_display()} by {self.complainant_label}"


def complaint_evidence_path(instance, filename):
    # Random name: the original filename (often IMG_1234.jpg) is guessable and
    # can itself identify the person who took the photo.
    return f"complaint_evidence/{instance.complaint_id}/{uuid.uuid4().hex}{Path(filename).suffix.lower()}"


class ComplaintEvidence(models.Model):
    """A photo attached to a report so an admin can see what happened rather
    than judging from the description alone. Stored privately and served only
    by ComplaintEvidenceView, never from /media/."""

    complaint = models.ForeignKey(Complaint, on_delete=models.CASCADE, related_name="evidence")
    image = models.ImageField(upload_to=complaint_evidence_path, storage=PrivateMediaStorage())
    uploaded_at = models.DateTimeField(auto_now_add=True)
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["order", "uploaded_at"]

    def __str__(self) -> str:
        return f"Evidence for complaint #{self.complaint_id}"
