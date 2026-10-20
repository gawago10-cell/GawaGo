from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ("accounts", "0006_workeravailability"),
        ("jobs", "0009_jobposting_completion_requested_status"),
    ]

    operations = [
        migrations.CreateModel(
            name="RouteDistanceCache",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("job_latitude", models.DecimalField(decimal_places=7, max_digits=10)),
                ("job_longitude", models.DecimalField(decimal_places=7, max_digits=10)),
                ("worker_latitude", models.DecimalField(decimal_places=7, max_digits=10)),
                ("worker_longitude", models.DecimalField(decimal_places=7, max_digits=10)),
                ("distance_km", models.DecimalField(decimal_places=3, max_digits=10)),
                ("route_points", models.JSONField(blank=True, default=list)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "job",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="route_distance_cache",
                        to="jobs.jobposting",
                    ),
                ),
                (
                    "worker_profile",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="route_distance_cache",
                        to="accounts.userprofile",
                    ),
                ),
            ],
        ),
        migrations.AddConstraint(
            model_name="routedistancecache",
            constraint=models.UniqueConstraint(
                fields=("job", "worker_profile"),
                name="unique_route_distance_cache_pair",
            ),
        ),
    ]
