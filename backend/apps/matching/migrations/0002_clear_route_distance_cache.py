from django.db import migrations


def clear_route_cache(apps, schema_editor):
    """Cached routes measured a pin far from any mapped road between two
    distant roads (a worker 0.39 km away read as 8 km). They are only a
    cache, so dropping them lets every pair be measured again with the
    snapping limit (flow audit, 2026-11-04)."""
    apps.get_model("matching", "RouteDistanceCache").objects.all().delete()


class Migration(migrations.Migration):
    dependencies = [
        ("matching", "0001_route_distance_cache"),
    ]

    operations = [
        migrations.RunPython(clear_route_cache, migrations.RunPython.noop),
    ]
