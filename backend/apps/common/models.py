from django.conf import settings
from django.db import models


def verification_document_path(instance, filename):
    return f"verification_documents/{instance.worker_id}/{filename}"


class VerificationRequest(models.Model):
    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_REJECTED = "rejected"
    STATUS_CHOICES = [
        (STATUS_PENDING, "Pending"),
        (STATUS_APPROVED, "Approved"),
        (STATUS_REJECTED, "Rejected"),
    ]

    worker = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="verification_requests")
    primary_id_name = models.CharField(max_length=255)
    secondary_doc_name = models.CharField(max_length=255)
    primary_id_file = models.FileField(upload_to=verification_document_path, blank=True, null=True)
    secondary_doc_file = models.FileField(upload_to=verification_document_path, blank=True, null=True)
    notes = models.TextField(blank=True, default="")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING)
    submitted_at = models.DateTimeField(auto_now_add=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    review_note = models.TextField(blank=True, default="")


class RevokedToken(models.Model):
    """A JWT explicitly invalidated before its natural expiry (e.g. on logout).

    Rows are only meaningful until `expires_at`, matching the token's own
    exp claim -- after that the token would be rejected on expiry alone, so
    stale rows are opportunistically deleted whenever a new one is inserted.
    """

    jti = models.CharField(max_length=64, unique=True, db_index=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="revoked_tokens")
    expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(auto_now_add=True)
