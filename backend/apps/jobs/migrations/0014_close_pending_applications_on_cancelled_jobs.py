from django.db import migrations


def close_pending_on_cancelled(apps, schema_editor):
    """Cancelling a job used to leave its undecided applications pending
    forever, inflating active-application counts. Close them, as cancelling
    now does."""
    JobApplication = apps.get_model("jobs", "JobApplication")
    JobApplication.objects.filter(
        job__status="cancelled", status__in=["pending", "hire_requested"]
    ).update(status="closed")


class Migration(migrations.Migration):
    dependencies = [
        ("jobs", "0013_remove_preferred_date_time"),
    ]

    operations = [
        migrations.RunPython(close_pending_on_cancelled, migrations.RunPython.noop),
    ]
