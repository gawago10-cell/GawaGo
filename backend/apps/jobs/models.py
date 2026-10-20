import uuid
from pathlib import Path

from django.conf import settings
from django.db import models
from django.utils import timezone


def job_image_path(instance, filename):
    # Random name: the original filename is guessable and the public /media/
    # URL otherwise serves it back verbatim forever.
    dated_path = timezone.now().strftime("jobs/%Y/%m/%d")
    return f"{dated_path}/{uuid.uuid4().hex}{Path(filename).suffix.lower()}"


class JobPosting(models.Model):
    STATUS_OPEN = "open"
    STATUS_ASSIGNED = "assigned"
    STATUS_COMPLETION_REQUESTED = "completion_requested"
    STATUS_COMPLETED = "completed"
    STATUS_CANCELLED = "cancelled"
    STATUS_CHOICES = [
        (STATUS_OPEN, "Open"),
        (STATUS_ASSIGNED, "Assigned"),
        (STATUS_COMPLETION_REQUESTED, "Completion Requested"),
        (STATUS_COMPLETED, "Completed"),
        (STATUS_CANCELLED, "Cancelled"),
    ]

    DISTANCE_CHOICES = [
        ('1km', '1 Kilometer'),
        ('2km', '2 Kilometers'),
        ('5km', '5 Kilometers'),
        ('10km', '10 Kilometers'),
        ('unlimited', 'Unlimited'),
    ]

    household = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="job_postings")
    title = models.CharField(max_length=255)
    job_type = models.CharField(max_length=120)
    required_skill = models.CharField(max_length=120)
    schedule = models.CharField(max_length=255)
    schedule_type = models.CharField(max_length=80, blank=True, default="")
    description = models.TextField(blank=True, default="")
    location_label = models.CharField(max_length=255)
    latitude = models.DecimalField(max_digits=10, decimal_places=7)
    longitude = models.DecimalField(max_digits=10, decimal_places=7)
    service_rate = models.DecimalField(max_digits=10, decimal_places=2)
    # What service_rate is per. Both clients always asked for it, but it had
    # nowhere to be stored, so every rate displayed as "per day".
    RATE_PER_DAY = "per_day"
    RATE_PER_HOUR = "per_hour"
    RATE_FIXED = "fixed"
    RATE_TYPE_CHOICES = [
        (RATE_PER_DAY, "Per Day"),
        (RATE_PER_HOUR, "Per Hour"),
        (RATE_FIXED, "Fixed Rate"),
    ]
    rate_type = models.CharField(max_length=20, choices=RATE_TYPE_CHOICES, default=RATE_PER_DAY)
    worker_slots = models.PositiveIntegerField(default=1)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_OPEN)

    job_start_date = models.DateField(null=True, blank=True)
    job_end_date = models.DateField(null=True, blank=True)
    estimated_working_days = models.IntegerField(null=True, blank=True)
    max_distance_km = models.FloatField(default=1.0)
    geographic_boundary = models.CharField(max_length=20, choices=DISTANCE_CHOICES, default='1km')

    created_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    def __str__(self) -> str:
        return self.title


class JobImage(models.Model):
    job = models.ForeignKey(JobPosting, on_delete=models.CASCADE, related_name="images")
    image = models.ImageField(upload_to=job_image_path)
    uploaded_at = models.DateTimeField(auto_now_add=True)
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["order", "uploaded_at"]

    def __str__(self) -> str:
        return f"Image for {self.job.title}"


class JobApplication(models.Model):
    STATUS_PENDING = "pending"
    STATUS_HIRE_REQUESTED = "hire_requested"
    STATUS_HIRED = "hired"
    STATUS_REJECTED = "rejected"
    STATUS_CLOSED = "closed"
    STATUS_COMPLETED = "completed"
    STATUS_CHOICES = [
        (STATUS_PENDING, "Pending"),
        (STATUS_HIRE_REQUESTED, "Hire Requested"),
        (STATUS_HIRED, "Hired"),
        (STATUS_REJECTED, "Rejected"),
        (STATUS_CLOSED, "Closed"),
        (STATUS_COMPLETED, "Completed"),
    ]

    job = models.ForeignKey(JobPosting, on_delete=models.CASCADE, related_name="applications")
    worker = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="job_applications")
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING)
    applied_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    note = models.TextField(blank=True, default="")

    class Meta:
        unique_together = ("job", "worker")
        ordering = ["-applied_at"]

    def __str__(self) -> str:
        return f"{self.worker.username} -> {self.job.title}"


class JobStatusEvent(models.Model):
    ENTITY_JOB = "job"
    ENTITY_APPLICATION = "application"
    ENTITY_CHOICES = [
        (ENTITY_JOB, "Job"),
        (ENTITY_APPLICATION, "Application"),
    ]

    job = models.ForeignKey(JobPosting, on_delete=models.CASCADE, related_name="status_events")
    application = models.ForeignKey(
        JobApplication,
        on_delete=models.CASCADE,
        related_name="status_events",
        null=True,
        blank=True,
    )
    entity = models.CharField(max_length=20, choices=ENTITY_CHOICES)
    from_status = models.CharField(max_length=20, blank=True, default="")
    to_status = models.CharField(max_length=20)
    # Null when a transition is not attributable to a signed-in user, such as
    # the scheduled task that closes out unreviewed jobs.
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="job_status_events",
        null=True,
        blank=True,
    )
    note = models.CharField(max_length=255, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at", "id"]
        indexes = [
            models.Index(fields=["job", "created_at"]),
        ]

    def __str__(self) -> str:
        return f"{self.entity} {self.from_status or '-'} -> {self.to_status}"
