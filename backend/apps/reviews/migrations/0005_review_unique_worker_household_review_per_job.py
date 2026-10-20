from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("reviews", "0004_review_unique_household_worker_review_per_job"),
    ]

    operations = [
        migrations.AddConstraint(
            model_name="review",
            constraint=models.UniqueConstraint(
                condition=models.Q(("author_role", "worker"), ("job__isnull", False), ("target_role", "household")),
                fields=("job", "author", "target"),
                name="unique_worker_household_review_per_job",
            ),
        ),
    ]
