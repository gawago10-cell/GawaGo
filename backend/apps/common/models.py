import uuid
from pathlib import Path

from django.conf import settings
from django.db import models

from apps.complaints.storage import PrivateMediaStorage


def verification_document_path(instance, filename):
    # Random name: the original filename (often the person's name) must not
    # end up in a path someone could guess.
    return f"verification_documents/{instance.worker_id}/{uuid.uuid4().hex}{Path(filename).suffix.lower()}"


class VerificationRequest(models.Model):
    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_REJECTED = "rejected"
    STATUS_CHOICES = [
        (STATUS_PENDING, "Pending"),
        (STATUS_APPROVED, "Approved"),
        (STATUS_REJECTED, "Rejected"),
    ]

    # The government IDs accepted as a primary ID. A controlled vocabulary
    # rather than free text, so the admin queue and the reports can group by
    # ID type -- and so "supports these ID types" is a claim the data backs.
    ID_TYPE_NATIONAL = "national_id"
    ID_TYPE_PASSPORT = "passport"
    ID_TYPE_DRIVERS = "drivers_license"
    ID_TYPE_VOTER = "voter_id"
    ID_TYPE_TIN = "tin"
    ID_TYPE_UMID = "umid"
    ID_TYPE_POSTAL = "postal_id"
    ID_TYPE_OTHER = "other"
    ID_TYPE_CHOICES = [
        (ID_TYPE_NATIONAL, "National ID (PhilSys)"),
        (ID_TYPE_PASSPORT, "Passport"),
        (ID_TYPE_DRIVERS, "Driver's License"),
        (ID_TYPE_VOTER, "Voter ID"),
        (ID_TYPE_TIN, "TIN ID"),
        (ID_TYPE_UMID, "UMID"),
        (ID_TYPE_POSTAL, "Postal ID"),
        (ID_TYPE_OTHER, "Other Government ID"),
    ]

    worker = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="verification_requests")
    # Rows created before the ID types existed carry only a free-text name,
    # so they default to "other" rather than claiming a type nobody chose.
    primary_id_type = models.CharField(max_length=50, choices=ID_TYPE_CHOICES, default=ID_TYPE_OTHER)
    # The human label. Taken from primary_id_type's display name, except for
    # "other", where it is what the submitter typed.
    primary_id_name = models.CharField(max_length=255)
    secondary_doc_name = models.CharField(max_length=255)
    # Government IDs: private storage, readable only through
    # VerificationRequestDocumentView's permission check.
    primary_id_file = models.FileField(
        upload_to=verification_document_path, storage=PrivateMediaStorage(), blank=True, null=True
    )
    secondary_doc_file = models.FileField(
        upload_to=verification_document_path, storage=PrivateMediaStorage(), blank=True, null=True
    )
    notes = models.TextField(blank=True, default="")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING)
    submitted_at = models.DateTimeField(auto_now_add=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    review_note = models.TextField(blank=True, default="")


class AdminActionLog(models.Model):
    """One row per admin action, for the superadmin Audit Logs screen.

    actor is SET_NULL (not CASCADE) with actor_username snapshotted, so the
    log survives even if the admin account that did something is later
    removed -- an audit trail that disappears when the account does would
    defeat its own purpose.
    """

    ACTION_USER_SUSPENDED = "user_suspended"
    ACTION_USER_RESTORED = "user_restored"
    ACTION_COMPLAINT_STATUS_CHANGED = "complaint_status_changed"
    ACTION_COMPLAINT_RESPONDENT_BLOCKED = "complaint_respondent_blocked"
    ACTION_VERIFICATION_APPROVED = "verification_approved"
    ACTION_VERIFICATION_REJECTED = "verification_rejected"
    ACTION_CERTIFICATE_APPROVED = "certificate_approved"
    ACTION_CERTIFICATE_REJECTED = "certificate_rejected"
    ACTION_JOB_UPDATED = "job_updated"
    ACTION_JOB_DELETED = "job_deleted"
    ACTION_ADMIN_CREATED = "admin_created"
    ACTION_ADMIN_DEACTIVATED = "admin_deactivated"
    ACTION_ADMIN_REACTIVATED = "admin_reactivated"
    ACTION_CHOICES = [
        (ACTION_USER_SUSPENDED, "Suspended a user"),
        (ACTION_USER_RESTORED, "Restored a user"),
        (ACTION_COMPLAINT_STATUS_CHANGED, "Changed a complaint's status"),
        (ACTION_COMPLAINT_RESPONDENT_BLOCKED, "Blocked a complaint's respondent"),
        (ACTION_VERIFICATION_APPROVED, "Approved a verification request"),
        (ACTION_VERIFICATION_REJECTED, "Rejected a verification request"),
        (ACTION_CERTIFICATE_APPROVED, "Approved a certificate"),
        (ACTION_CERTIFICATE_REJECTED, "Rejected a certificate"),
        (ACTION_JOB_UPDATED, "Updated a household's job"),
        (ACTION_JOB_DELETED, "Deleted a household's job"),
        (ACTION_ADMIN_CREATED, "Created an admin account"),
        (ACTION_ADMIN_DEACTIVATED, "Deactivated an admin account"),
        (ACTION_ADMIN_REACTIVATED, "Reactivated an admin account"),
    ]

    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name="admin_action_logs"
    )
    actor_username = models.CharField(max_length=150)
    action = models.CharField(max_length=40, choices=ACTION_CHOICES)
    # A human-readable description of what was acted on (a username, a job
    # title, a complaint's parties) -- snapshotted the same way, so the log
    # entry still reads sensibly after the target itself is gone.
    target_label = models.CharField(max_length=255, blank=True, default="")
    target_type = models.CharField(max_length=40, blank=True, default="")
    target_id = models.PositiveIntegerField(null=True, blank=True)
    detail = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"{self.actor_username}: {self.action} -> {self.target_label}"


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
