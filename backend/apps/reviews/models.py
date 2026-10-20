from django.conf import settings
from django.db import models
from django.db.models import Q


class Review(models.Model):
    ROLE_HOUSEHOLD = "household"
    ROLE_WORKER = "worker"
    AUTHOR_ROLE_CHOICES = [
        (ROLE_HOUSEHOLD, "Household"),
        (ROLE_WORKER, "Worker"),
    ]

    # SET_NULL, not CASCADE: deleting the account that *wrote* a review must
    # never rewrite the reputation of the person it was about. The username is
    # snapshotted so a review whose author is gone can still be attributed.
    # target stays CASCADE -- a review about a deleted account has no subject.
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="authored_reviews",
        null=True,
        blank=True,
    )
    author_username = models.CharField(max_length=150, blank=True, default="")
    target = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="received_reviews")
    author_role = models.CharField(max_length=20, choices=AUTHOR_ROLE_CHOICES)
    target_role = models.CharField(max_length=20, choices=AUTHOR_ROLE_CHOICES)
    job = models.ForeignKey("jobs.JobPosting", on_delete=models.SET_NULL, related_name="reviews", null=True, blank=True)
    job_title = models.CharField(max_length=255, blank=True, default="")
    rating = models.DecimalField(max_digits=2, decimal_places=1, null=True, blank=True)
    feedback = models.TextField(blank=True, default="")
    quality_of_work = models.IntegerField(null=True, blank=True, choices=[(i, str(i)) for i in range(1, 6)])
    punctuality = models.IntegerField(null=True, blank=True, choices=[(i, str(i)) for i in range(1, 6)])
    communication = models.IntegerField(null=True, blank=True, choices=[(i, str(i)) for i in range(1, 6)])
    professionalism = models.IntegerField(null=True, blank=True, choices=[(i, str(i)) for i in range(1, 6)])
    created_at = models.DateTimeField(auto_now_add=True)
    # True only for the automatic 3.5-star placeholder assigned when a
    # household never reviews within the window (see reviews/services.py).
    # A real review submitted later replaces it in place instead of being
    # rejected as a duplicate of a rating the reviewer never actually gave.
    is_system_generated = models.BooleanField(default=False)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["job", "author", "target"],
                condition=Q(author_role="household", target_role="worker", job__isnull=False),
                name="unique_household_worker_review_per_job",
            ),
            models.UniqueConstraint(
                fields=["job", "author", "target"],
                condition=Q(author_role="worker", target_role="household", job__isnull=False),
                name="unique_worker_household_review_per_job",
            )
        ]

    def save(self, *args, **kwargs):
        if self.author_id and not self.author_username:
            self.author_username = self.author.username
            update_fields = kwargs.get("update_fields")
            if update_fields is not None:
                kwargs["update_fields"] = list(update_fields) + ["author_username"]
        super().save(*args, **kwargs)

    @property
    def author_label(self) -> str:
        return self.author.username if self.author_id else (self.author_username or "Deleted account")

    def __str__(self) -> str:
        return f"{self.author_label} -> {self.target.username}"
