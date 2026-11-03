from django.db import migrations

AWAITING_DECISION = ("pending", "hire_requested")


def settle(apps, schema_editor):
    """Hire requests and "New worker application" notices kept "Needs your
    response" after the application was answered, closed or withdrawn (flow
    audit, 2026-11-04). Clear the ones already in the database; new ones are
    cleared as the application moves (apps.jobs.services)."""
    Notification = apps.get_model("notifications", "Notification")
    JobApplication = apps.get_model("jobs", "JobApplication")
    stale = Notification.objects.filter(requires_action=True, related_application_id__isnull=False).exclude(
        action_type="review"
    )
    settled_ids = set(
        JobApplication.objects.filter(
            id__in=stale.values_list("related_application_id", flat=True)
        ).exclude(status__in=AWAITING_DECISION).values_list("id", flat=True)
    )
    stale.filter(related_application_id__in=settled_ids).update(requires_action=False)


class Migration(migrations.Migration):
    dependencies = [
        ("notifications", "0009_notification_review_admin_alert_types"),
        ("jobs", "0015_application_withdrawn"),
    ]

    operations = [
        migrations.RunPython(settle, migrations.RunPython.noop),
    ]
