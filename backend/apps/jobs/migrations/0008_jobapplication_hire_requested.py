from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("jobs", "0007_jobposting_preferred_date_jobposting_preferred_time_and_more"),
    ]

    operations = [
        migrations.AlterField(
            model_name="jobapplication",
            name="status",
            field=models.CharField(
                choices=[
                    ("pending", "Pending"),
                    ("hire_requested", "Hire Requested"),
                    ("hired", "Hired"),
                    ("rejected", "Rejected"),
                    ("closed", "Closed"),
                    ("completed", "Completed"),
                ],
                default="pending",
                max_length=20,
            ),
        ),
    ]
