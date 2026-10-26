from decimal import ROUND_HALF_UP, Decimal

from django.db import migrations

METRIC_FIELDS = ("quality_of_work", "punctuality", "communication", "professionalism")


def store_metric_average_as_rating(apps, schema_editor):
    """Reviews saved before the rating was derived from the metrics kept the
    star picker's value beside them, so `rating` and the metric average
    disagreed. Make the stored rating the average, as new reviews are."""
    Review = apps.get_model("reviews", "Review")
    for review in Review.objects.all().iterator():
        metrics = [getattr(review, field) for field in METRIC_FIELDS]
        metrics = [metric for metric in metrics if metric is not None]
        if not metrics:
            continue
        average = (Decimal(sum(metrics)) / Decimal(len(metrics))).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)
        if review.rating != average:
            review.rating = average
            review.save(update_fields=["rating"])


class Migration(migrations.Migration):

    dependencies = [
        ("reviews", "0009_review_author_username_alter_review_author"),
    ]

    operations = [
        migrations.RunPython(store_metric_average_as_rating, migrations.RunPython.noop),
    ]
