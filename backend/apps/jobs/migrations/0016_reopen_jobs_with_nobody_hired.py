from django.db import migrations

UNDERWAY = ["assigned", "completion_requested"]
HIRES = ["hired", "completed"]
NOTE = "Reopened: it was in progress with nobody hired."


def reopen_jobs_with_nobody_hired(apps, schema_editor):
    """Jobs left "in progress" after their only hire was removed (an account
    deleted, a hire changed in the admin) showed "No worker hired yet" and a
    "Mark as done" that could never be pressed. Open them again, as the
    worker's own back-out does, so they lapse or take workers like any other
    open job (household dashboard audit, 2026-11-13)."""
    JobPosting = apps.get_model("jobs", "JobPosting")
    JobApplication = apps.get_model("jobs", "JobApplication")
    JobStatusEvent = apps.get_model("jobs", "JobStatusEvent")
    hired_job_ids = JobApplication.objects.filter(status__in=HIRES).values("job_id")
    for job in JobPosting.objects.filter(status__in=UNDERWAY).exclude(id__in=hired_job_ids):
        previous_status = job.status
        job.status = "open"
        job.save(update_fields=["status"])
        JobStatusEvent.objects.create(
            job=job, entity="job", from_status=previous_status, to_status="open", note=NOTE
        )


class Migration(migrations.Migration):
    dependencies = [
        ("jobs", "0015_application_withdrawn"),
    ]

    operations = [
        migrations.RunPython(reopen_jobs_with_nobody_hired, migrations.RunPython.noop),
    ]
