from django.contrib.auth.models import User
from django.db import models
from django.utils import timezone
from django.contrib.auth.hashers import make_password, check_password
import secrets
import uuid
from datetime import timedelta
from pathlib import Path

from apps.complaints.storage import PrivateMediaStorage


def profile_photo_path(instance, filename):
    # Random name: the original filename (often the person's own name, e.g.
    # Juan_Dela_Cruz_selfie.png) must not persist in a public /media/ URL.
    return f"profiles/{instance.user_id}/{uuid.uuid4().hex}{Path(filename).suffix.lower()}"


# The model that used this is gone (verification now runs through
# common.VerificationRequest), but migration 0016 still imports it by path,
# so removing it would break `migrate` on a fresh database.
def id_document_path(instance, filename):
    return f"verification_documents/{instance.user_id}/{uuid.uuid4().hex}{Path(filename).suffix.lower()}"


def currently_suspended_q(prefix=""):
    """Matches accounts suspended *right now*, optionally across a relation
    (e.g. currently_suspended_q("household__profile__")).

    A plain is_blocked=True test would also catch an account whose timed
    suspension already ran out but hasn't been lazily cleared by
    refresh_block_status() yet.
    """
    return models.Q(**{f"{prefix}is_blocked": True}) & (
        models.Q(**{f"{prefix}blocked_until__isnull": True})
        | models.Q(**{f"{prefix}blocked_until__gt": timezone.now()})
    )


class UserProfileQuerySet(models.QuerySet):
    def not_suspended(self):
        return self.exclude(currently_suspended_q())


class UserProfile(models.Model):
    ROLE_HOUSEHOLD = "household"
    ROLE_WORKER = "worker"
    ROLE_CHOICES = [
        (ROLE_HOUSEHOLD, "Household"),
        (ROLE_WORKER, "Worker"),
    ]

    TIER_NEW = "new"
    TIER_ESTABLISHED = "established"
    TIER_TRUSTED = "trusted"
    TIER_ELITE = "elite"
    TIER_CHOICES = [
        (TIER_NEW, "New Worker"),
        (TIER_ESTABLISHED, "Established"),
        (TIER_TRUSTED, "Trusted"),
        (TIER_ELITE, "Elite"),
    ]

    objects = UserProfileQuerySet.as_manager()

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="profile")
    role = models.CharField(max_length=20, choices=ROLE_CHOICES, default=ROLE_WORKER)
    phone = models.CharField(max_length=30, blank=True, default="")
    bio = models.TextField(blank=True, default="")
    years_experience = models.PositiveIntegerField(default=0)
    skills = models.JSONField(default=list, blank=True)
    hourly_rate = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    daily_rate = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    verification_status = models.CharField(max_length=20, default="pending")
    primary_id_type = models.CharField(max_length=50, choices=[
        ("national_id", "National ID (UMID/GSIS/SSS)"),
        ("passport", "Passport"),
        ("drivers_license", "Driver's License"),
        ("voter_id", "Voter ID"),
        ("tin", "TIN ID"),
        ("umid", "UMID"),
        ("postal_id", "Postal ID"),
        ("other", "Other Government ID"),
    ], default="national_id")
    location_label = models.CharField(max_length=255, blank=True, default="")
    latitude = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    longitude = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    profile_photo = models.ImageField(upload_to=profile_photo_path, blank=True, null=True)
    average_rating = models.DecimalField(max_digits=3, decimal_places=2, null=True, blank=True)
    rating_count = models.PositiveIntegerField(default=0)
    reputation_tier = models.CharField(max_length=20, choices=TIER_CHOICES, default=TIER_NEW)
    rating_trend = models.CharField(max_length=20, default="neutral", choices=[
        ("improving", "Improving"),
        ("declining", "Declining"),
        ("neutral", "Neutral"),
    ])
    # Bumped whenever this user's credentials change (e.g. password reset) so
    # every previously issued JWT -- which carries an iat claim -- can be
    # rejected at once, without needing a per-token revocation entry for each.
    credentials_updated_at = models.DateTimeField(null=True, blank=True)
    # Admin suspension. Separate from User.is_active because a block carries a
    # reason and an optional end date that the user is shown at login.
    is_blocked = models.BooleanField(default=False)
    blocked_at = models.DateTimeField(null=True, blank=True)
    blocked_reason = models.TextField(blank=True, default="")
    # Null means the block is permanent (or the account isn't blocked at all).
    # A future datetime means a timed suspension that should lift on its own.
    blocked_until = models.DateTimeField(null=True, blank=True)

    def __str__(self) -> str:
        return f"{self.user.username} ({self.role})"

    def refresh_block_status(self) -> bool:
        """Returns whether the account is currently blocked right now, lazily
        lifting an expired timed suspension along the way (no cron needed --
        this is called from every login/authenticated-request/admin-read
        path, so an expired suspension self-heals on the next touch)."""
        if not self.is_blocked:
            return False
        if self.blocked_until and timezone.now() >= self.blocked_until:
            self.is_blocked = False
            self.blocked_at = None
            self.blocked_reason = ""
            self.blocked_until = None
            self.save(update_fields=["is_blocked", "blocked_at", "blocked_reason", "blocked_until"])
            # The suspension notice promised the account would be restored on
            # a date, and nothing said when it had been. Imported here because
            # notifications import accounts.
            from apps.notifications.services import create_notification
            from apps.notifications.models import Notification

            create_notification(
                recipient=self.user,
                notification_type=Notification.TYPE_ACCOUNT_ACTIVITY,
                title="Account restored",
                message="Your suspension has ended. You can sign in and use GawaGo again.",
            )
            return False
        return True

    @property
    def block_message(self) -> str:
        # Shown at login and when an open session is ended. AGENTS.md II.D:
        # the user is told the superadmin's reason, not only that they are
        # suspended.
        reason = (self.blocked_reason or "").strip()
        if reason and reason[-1] not in ".!?":
            reason += "."
        reason = f" Reason: {reason}" if reason else ""
        if self.blocked_until:
            until = timezone.localtime(self.blocked_until).strftime("%Y-%m-%d %H:%M")
            return f"This account is suspended until {until}.{reason} Contact support for assistance."
        return f"This account has been blocked.{reason} Contact support for assistance."

    @property
    def has_location(self) -> bool:
        return self.latitude is not None and self.longitude is not None

    @property
    def display_rating(self) -> str:
        if not self.rating_count or self.average_rating is None:
            return "No ratings yet"
        return f"{self.average_rating:.2f}"


class WorkerAvailability(models.Model):
    worker = models.ForeignKey(User, on_delete=models.CASCADE, related_name="availability_windows")
    date = models.DateField()
    start_time = models.TimeField()
    end_time = models.TimeField()
    is_available = models.BooleanField(default=True)

    class Meta:
        ordering = ["date", "start_time"]
        constraints = [
            models.UniqueConstraint(
                fields=["worker", "date", "start_time", "end_time"],
                name="unique_worker_availability_window",
            )
        ]

    def __str__(self) -> str:
        return f"{self.worker.username} available {self.date} {self.start_time}-{self.end_time}"


class PasswordResetRequest(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="password_reset_requests")
    email = models.EmailField()
    token_hash = models.CharField(max_length=128)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    attempts = models.PositiveIntegerField(default=0)

    class Meta:
        indexes = [models.Index(fields=["email", "created_at"])]

    @property
    def is_expired(self) -> bool:
        return timezone.now() >= self.expires_at

    @property
    def is_used(self) -> bool:
        return self.used_at is not None

    @classmethod
    def create_request(cls, user: User, token: str, ttl_minutes: int = 10) -> "PasswordResetRequest":
        return cls.objects.create(
            user=user,
            email=user.email,
            token_hash=make_password(token),
            expires_at=timezone.now() + timedelta(minutes=ttl_minutes),
        )

    def verify_token(self, token: str) -> bool:
        if self.is_expired or self.is_used:
            return False
        return check_password(token, self.token_hash)


class SignupVerificationRequest(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="verification_request")
    email = models.EmailField()
    token_hash = models.CharField(max_length=128)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    verified_at = models.DateTimeField(null=True, blank=True)

    @property
    def is_expired(self) -> bool:
        return timezone.now() >= self.expires_at

    @classmethod
    def create_request(cls, user: User, token: str, ttl_minutes: int = 10) -> "SignupVerificationRequest":
        return cls.objects.create(
            user=user,
            email=user.email,
            token_hash=make_password(token),
            expires_at=timezone.now() + timedelta(minutes=ttl_minutes),
        )

    def verify_token(self, token: str) -> bool:
        if self.is_expired or self.verified_at is not None:
            return False
        return check_password(token, self.token_hash)


def portfolio_item_path(instance, filename):
    return f"portfolios/{instance.worker_id}/{uuid.uuid4().hex}{Path(filename).suffix.lower()}"


def certificate_file_path(instance, filename):
    # Credential files (TESDA certs, licenses) often carry the worker's full
    # legal name and ID numbers, so unlike a work-sample photo these live in
    # PRIVATE_MEDIA_ROOT and are only ever returned by a permission-checked
    # view (WorkerCertificationFileView), never a public /media/ URL.
    return f"certifications/{instance.worker_id}/{uuid.uuid4().hex}{Path(filename).suffix.lower()}"


class WorkerPortfolio(models.Model):
    worker = models.OneToOneField(User, on_delete=models.CASCADE, related_name="portfolio")
    bio = models.TextField(blank=True, default="")
    years_experience = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"Portfolio: {self.worker.username}"


class WorkerSkill(models.Model):
    PROFICIENCY_CHOICES = [
        ("beginner", "Beginner"),
        ("intermediate", "Intermediate"),
        ("expert", "Expert"),
    ]

    worker = models.ForeignKey(User, on_delete=models.CASCADE, related_name="portfolio_skills")
    skill_name = models.CharField(max_length=120)
    # Blank when the entry was created from the profile's skill list rather
    # than by the worker on their portfolio: no proficiency was ever claimed.
    proficiency = models.CharField(max_length=20, choices=PROFICIENCY_CHOICES, default="beginner", blank=True)
    average_rating = models.DecimalField(max_digits=3, decimal_places=2, null=True, blank=True)
    rating_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ("worker", "skill_name")
        ordering = ["-average_rating", "skill_name"]

    def __str__(self) -> str:
        return f"{self.worker.username} - {self.skill_name} ({self.proficiency})"


class WorkerCertification(models.Model):
    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_REJECTED = "rejected"
    STATUS_CHOICES = [
        (STATUS_PENDING, "Pending Review"),
        (STATUS_APPROVED, "Approved"),
        (STATUS_REJECTED, "Rejected"),
    ]

    TYPE_TESDA = "tesda"
    TYPE_LICENSE = "license"
    TYPE_CREDENTIAL = "credential"
    TYPE_CERTIFICATION = "certification"
    TYPE_OTHER = "other"
    TYPE_CHOICES = [
        (TYPE_TESDA, "TESDA Certificate"),
        (TYPE_LICENSE, "Professional License"),
        (TYPE_CREDENTIAL, "Professional Credential"),
        (TYPE_CERTIFICATION, "Professional Certification"),
        (TYPE_OTHER, "Other"),
    ]

    worker = models.ForeignKey(User, on_delete=models.CASCADE, related_name="portfolio_certifications")
    certificate_type = models.CharField(max_length=50, choices=TYPE_CHOICES, default=TYPE_CERTIFICATION)
    certificate_name = models.CharField(max_length=255)
    issuer = models.CharField(max_length=255, blank=True, default="")
    issue_date = models.DateField(null=True, blank=True)
    expiry_date = models.DateField(null=True, blank=True)
    certificate_file = models.FileField(
        upload_to=certificate_file_path, storage=PrivateMediaStorage(), blank=True, null=True
    )
    is_verified = models.BooleanField(default=False)
    verification_status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING)
    verified_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name="verified_certifications")
    verification_notes = models.TextField(blank=True, default="")
    verified_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-issue_date"]

    def __str__(self) -> str:
        return f"{self.worker.username} - {self.certificate_name}"


class WorkerPortfolioItem(models.Model):
    worker = models.ForeignKey(User, on_delete=models.CASCADE, related_name="portfolio_items")
    title = models.CharField(max_length=255, blank=True, default="")
    description = models.TextField(blank=True, default="")
    image = models.ImageField(upload_to=portfolio_item_path)
    before_image = models.ImageField(upload_to=portfolio_item_path, blank=True, null=True)
    after_image = models.ImageField(upload_to=portfolio_item_path, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"Portfolio item: {self.worker.username} - {self.title}"


class SkillRating(models.Model):
    job = models.ForeignKey("jobs.JobPosting", on_delete=models.CASCADE, related_name="skill_ratings")
    household = models.ForeignKey(User, on_delete=models.CASCADE, related_name="given_skill_ratings")
    worker = models.ForeignKey(User, on_delete=models.CASCADE, related_name="received_skill_ratings")
    skill = models.ForeignKey(WorkerSkill, on_delete=models.CASCADE, related_name="skill_ratings")
    rating = models.DecimalField(max_digits=2, decimal_places=1)
    feedback = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ("job", "household", "worker", "skill")
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"{self.household.username} rated {self.worker.username} - {self.skill.skill_name}: {self.rating}"
