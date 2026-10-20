from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("jobs", "0008_jobapplication_hire_requested"),
    ]

    operations = [
        migrations.AlterField(
            model_name="jobposting",
            name="status",
            field=models.CharField(
                choices=[
                    ("open", "Open"),
                    ("assigned", "Assigned"),
                    ("completion_requested", "Completion Requested"),
                    ("completed", "Completed"),
                    ("cancelled", "Cancelled"),
                ],
                default="open",
                max_length=20,
            ),
        ),
    ]
