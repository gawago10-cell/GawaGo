from django.db import models

from apps.accounts.models import UserProfile
from apps.jobs.models import JobPosting


class RouteDistanceCache(models.Model):
    job = models.ForeignKey(JobPosting, on_delete=models.CASCADE, related_name="route_distance_cache")
    worker_profile = models.ForeignKey(UserProfile, on_delete=models.CASCADE, related_name="route_distance_cache")
    job_latitude = models.DecimalField(max_digits=10, decimal_places=7)
    job_longitude = models.DecimalField(max_digits=10, decimal_places=7)
    worker_latitude = models.DecimalField(max_digits=10, decimal_places=7)
    worker_longitude = models.DecimalField(max_digits=10, decimal_places=7)
    distance_km = models.DecimalField(max_digits=10, decimal_places=3)
    route_points = models.JSONField(default=list, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["job", "worker_profile"], name="unique_route_distance_cache_pair"),
        ]

    def __str__(self) -> str:
        return f"{self.job_id} to {self.worker_profile_id}: {self.distance_km} km"
