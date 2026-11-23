from decimal import ROUND_HALF_UP, Decimal

from django.db import migrations

METRIC_FIELDS = ("quality_of_work", "punctuality", "communication", "professionalism")
STEP = Decimal("0.1")


def _round(value):
    return Decimal(str(value)).quantize(STEP, rounding=ROUND_HALF_UP)


def recompute_profile_averages(apps, schema_editor):
    """Profile averages were built from unrounded metric averages (a 4.25
    review and a 4.5 one gave 4.38) while each review reads 4.3. Recompute
    them the way recalculate_user_rating now does: each review rounded to one
    decimal, then their average rounded the same way (mobile worker audit,
    2026-11-23)."""
    Review = apps.get_model("reviews", "Review")
    UserProfile = apps.get_model("accounts", "UserProfile")
    for profile in UserProfile.objects.filter(role__in=["worker", "household"]).iterator():
        ratings = []
        for review in Review.objects.filter(target_id=profile.user_id):
            metrics = [getattr(review, field) for field in METRIC_FIELDS]
            metrics = [metric for metric in metrics if metric is not None]
            if metrics:
                ratings.append(_round(Decimal(sum(metrics)) / Decimal(len(metrics))))
            elif review.rating is not None:
                ratings.append(_round(review.rating))
        average = _round(sum(ratings, Decimal("0")) / len(ratings)) if ratings else None
        if profile.average_rating != average or profile.rating_count != len(ratings):
            profile.average_rating = average
            profile.rating_count = len(ratings)
            profile.save(update_fields=["average_rating", "rating_count"])


class Migration(migrations.Migration):

    dependencies = [
        ("reviews", "0010_rating_matches_metric_average"),
        ("accounts", "0026_backfill_portfolio_skills"),
    ]

    operations = [
        migrations.RunPython(recompute_profile_averages, migrations.RunPython.noop),
    ]
