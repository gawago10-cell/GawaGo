from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("notifications", "0003_notification_accepted_type"),
    ]

    operations = [
        migrations.AlterField(
            model_name="notification",
            name="notification_type",
            field=models.CharField(
                choices=[
                    ("application", "Application"),
                    ("account_activity", "Account Activity"),
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
