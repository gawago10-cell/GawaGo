from django.contrib.auth.models import User
from django.db import models
from django.utils import timezone
from django.contrib.auth.hashers import make_password, check_password
import secrets
from datetime import timedelta


def profile_photo_path(instance, filename):
    return f"profiles/{instance.user_id}/{filename}"


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

    def __str__(self) -> str:
        return f"{self.user.username} ({self.role})"

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


class VerificationDocument(models.Model):
    ID_TYPE_NATIONAL = "national_id"
    ID_TYPE_PASSPORT = "passport"
    ID_TYPE_DRIVERS = "drivers_license"
    ID_TYPE_VOTER = "voter_id"
    ID_TYPE_TIN = "tin"
    ID_TYPE_UMID = "umid"
    ID_TYPE_POSTAL = "postal_id"
    ID_TYPE_OTHER = "other"

    ID_TYPE_CHOICES = [
        (ID_TYPE_NATIONAL, "National ID (UMID/GSIS/SSS)"),
        (ID_TYPE_PASSPORT, "Passport"),
        (ID_TYPE_DRIVERS, "Driver's License"),
        (ID_TYPE_VOTER, "Voter ID"),
        (ID_TYPE_TIN, "TIN ID"),
        (ID_TYPE_UMID, "UMID"),
        (ID_TYPE_POSTAL, "Postal ID"),
        (ID_TYPE_OTHER, "Other Government ID"),
    ]

    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_REJECTED = "rejected"
    STATUS_CHOICES = [
        (STATUS_PENDING, "Pending Review"),
        (STATUS_APPROVED, "Approved"),
        (STATUS_REJECTED, "Rejected"),
    ]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="verification_documents")
    id_type = models.CharField(max_length=50, choices=ID_TYPE_CHOICES, default=ID_TYPE_NATIONAL)
    id_number = models.CharField(max_length=255, blank=True, default="")
    document_file = models.FileField(upload_to="verification_documents/%Y/%m/%d/")
    is_primary = models.BooleanField(default=True)
    verification_status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING)
    verified_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name="verified_documents")
    verification_notes = models.TextField(blank=True, default="")
    verified_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return f"{self.user.username} - {self.get_id_type_display()}"


def portfolio_item_path(instance, filename):
    return f"portfolios/{instance.worker_id}/{filename}"


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
    proficiency = models.CharField(max_length=20, choices=PROFICIENCY_CHOICES, default="beginner")
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
    certificate_file = models.FileField(upload_to=portfolio_item_path, blank=True, null=True)
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
