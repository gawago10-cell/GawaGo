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

    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="authored_reviews")
    target = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="received_reviews")
    author_role = models.CharField(max_length=20, choices=AUTHOR_ROLE_CHOICES)
    target_role = models.CharField(max_length=20, choices=AUTHOR_ROLE_CHOICES)
    job = models.ForeignKey("jobs.JobPosting", on_delete=models.CASCADE, related_name="reviews", null=True, blank=True)
    job_title = models.CharField(max_length=255, blank=True, default="")
    rating = models.DecimalField(max_digits=2, decimal_places=1, null=True, blank=True)
    feedback = models.TextField(blank=True, default="")
    quality_of_work = models.IntegerField(null=True, blank=True, choices=[(i, str(i)) for i in range(1, 6)])
    punctuality = models.IntegerField(null=True, blank=True, choices=[(i, str(i)) for i in range(1, 6)])
    communication = models.IntegerField(null=True, blank=True, choices=[(i, str(i)) for i in range(1, 6)])
    professionalism = models.IntegerField(null=True, blank=True, choices=[(i, str(i)) for i in range(1, 6)])
    created_at = models.DateTimeField(auto_now_add=True)

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

    def __str__(self) -> str:
        return f"{self.author.username} -> {self.target.username}"
