from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notifications", "0002_notification_completion_types"),
    ]

    operations = [
        migrations.AlterField(
            model_name="notification",
            name="notification_type",
            field=models.CharField(
                choices=[
                    ("application", "Application"),
                    ("accepted", "Accepted"),
                    ("hiring", "Hiring"),
                    ("rejection", "Rejection"),
                    ("verification", "Verification"),
                    ("analytics", "Analytics"),
                    ("completion", "Completion"),
                    ("review_reminder", "Review Reminder"),
                ],
                max_length=30,
            ),
        ),
    ]
