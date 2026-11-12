from django.db import migrations

UNDERWAY = ["assigned", "completion_requested"]


def clear_answered_reminders(apps, schema_editor):
    """"Mark the job as done" reminders for jobs already marked done,
    cancelled or reopened stayed unread to-dos; clear them, as the job's
    status change now does (household notifications audit, 2026-11-13)."""
    Notification = apps.get_model("notifications", "Notification")
    JobPosting = apps.get_model("jobs", "JobPosting")
    underway_ids = JobPosting.objects.filter(status__in=UNDERWAY).values("id")
    Notification.objects.filter(
        notification_type="completion",
        title="Mark the job as done",
        requires_action=True,
    ).exclude(related_job_id__in=underway_ids).update(requires_action=False, is_read=True)


class Migration(migrations.Migration):
    dependencies = [
        ("jobs", "0016_reopen_jobs_with_nobody_hired"),
        ("notifications", "0010_settle_answered_action_notifications"),
    ]

    operations = [
        migrations.RunPython(clear_answered_reminders, migrations.RunPython.noop),
    ]
