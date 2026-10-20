from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("jobs", "0005_jobimage"),
    ]

    operations = [
        migrations.AddField(
            model_name="jobposting",
            name="completed_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name="jobapplication",
            name="status",
            field=models.CharField(
                choices=[
                    ("pending", "Pending"),
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
