from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notifications", "0004_notification_account_activity_type"),
    ]

    operations = [
        migrations.AddField(
            model_name="notification",
            name="action_type",
            field=models.CharField(
                blank=True,
                choices=[
                    ("", "No action"),
                    ("hire_request", "Hire request"),
                    ("job_detail", "Job detail"),
                    ("review", "Review"),
                ],
                default="",
                max_length=40,
            ),
        ),
        migrations.AddField(
            model_name="notification",
            name="related_application_id",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="notification",
            name="related_job_id",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
    ]
