from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("jobs", "0006_job_completion_workflow"),
        ("reviews", "0002_alter_review_rating_decimal"),
    ]

    operations = [
        migrations.AddField(
            model_name="review",
            name="job",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.CASCADE,
                related_name="reviews",
                to="jobs.jobposting",
            ),
        ),
    ]
