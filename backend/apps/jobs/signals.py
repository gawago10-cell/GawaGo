"""Keeps a job's status honest when one of its hires disappears."""

from django.db import transaction
from django.db.models.signals import post_delete
from django.dispatch import receiver

from apps.jobs.models import JobApplication

HIRE_REMOVED_NOTE = "Reopened: the hired worker's record was removed."


@receiver(post_delete, sender=JobApplication)
def reopen_job_when_its_hire_is_deleted(sender, instance, **kwargs):
    """Deleting a worker's account deletes their applications with it, and
    left the job they were hired for "in progress" with nobody on it. Runs
    after commit: when the whole job is being deleted, it is gone by then
    and there is nothing to do."""
    if instance.status != JobApplication.STATUS_HIRED:
        return
    job_id = instance.job_id

    def reopen():
        from apps.jobs.services import reopen_if_nobody_hired

        reopen_if_nobody_hired(job_id, note=HIRE_REMOVED_NOTE)

    transaction.on_commit(reopen)
