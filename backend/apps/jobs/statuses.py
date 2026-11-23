"""Canonical job/application status vocabulary.

The React web client and the Flutter app each used to map raw status strings
to their own display labels, which drifted: `hire_requested` rendered as
"Hire Request" in one client and "Hire Requested" in the other, and neither
agreed with the household-facing wording. Both clients now render the
`status_stage`/`status_label` pair produced here, so the vocabulary only
exists in one place.
"""

from .models import JobApplication, JobPosting

STAGE_PENDING = "pending"
STAGE_AWAITING_WORKER = "awaiting_worker"
STAGE_IN_PROGRESS = "in_progress"
STAGE_AWAITING_MARK_DONE = "awaiting_mark_done"
STAGE_AWAITING_CONFIRMATION = "awaiting_confirmation"
STAGE_COMPLETED = "completed"
STAGE_REJECTED = "rejected"
STAGE_CLOSED = "closed"
STAGE_CANCELLED = "cancelled"
STAGE_WITHDRAWN = "withdrawn"
STAGE_OPEN = "open"
# Hired, but the job's first day is still ahead: "In progress" read as if the
# work had begun (mobile worker audit, 2026-11-23).
STAGE_HIRED = "hired"
STAGE_NOT_STARTED = "not_started"
# An invitation that ended without work: the household took it back, or the
# worker turned it down. Both used to read "Rejected", though the worker never
# applied and nobody rejected an application (mobile worker audit, 2026-11-23).
STAGE_INVITATION_WITHDRAWN = "invitation_withdrawn"
STAGE_DECLINED = "declined"

STAGE_LABELS = {
    STAGE_PENDING: "Pending",
    STAGE_AWAITING_WORKER: "Awaiting worker response",
    STAGE_IN_PROGRESS: "In progress",
    STAGE_AWAITING_MARK_DONE: "Waiting to be marked done",
    STAGE_AWAITING_CONFIRMATION: "Awaiting confirmation",
    STAGE_COMPLETED: "Completed",
    STAGE_REJECTED: "Rejected",
    STAGE_CLOSED: "Closed",
    STAGE_CANCELLED: "Cancelled",
    STAGE_WITHDRAWN: "Withdrawn",
    STAGE_OPEN: "Open",
    STAGE_HIRED: "Hired",
    STAGE_NOT_STARTED: "Not started yet",
    STAGE_INVITATION_WITHDRAWN: "Invitation withdrawn",
    STAGE_DECLINED: "Declined",
}

# What the worker reads for their own application where the household's words
# would be wrong: a hire request waits on *them*.
WORKER_STAGE_LABELS = {
    STAGE_AWAITING_WORKER: "Hire request received",
}


def _job_not_started(job):
    """The job's first day is still ahead. A job without a start date counts
    as started, as before."""
    from django.utils import timezone

    from .services import job_days

    days = job_days(job)
    return bool(days) and timezone.localdate() < days[0]


def _invitation_outcome(application):
    """For an invitation that ended rejected: who ended it. The household
    withdrawing and the worker declining both set the status to rejected; the
    status event says which."""
    last = (
        application.status_events.filter(to_status=JobApplication.STATUS_REJECTED)
        .order_by("-created_at", "-id")
        .first()
    )
    if not last or last.from_status != JobApplication.STATUS_HIRE_REQUESTED:
        return None
    if last.actor_id and last.actor_id == application.worker_id:
        return STAGE_DECLINED
    return STAGE_INVITATION_WITHDRAWN


def get_application_stage(application_status, job_status=None, job=None, application=None):
    # The worker's own decision to step away reads the same whatever the job
    # did afterwards.
    if application_status == JobApplication.STATUS_WITHDRAWN:
        return STAGE_WITHDRAWN
    if job_status == JobPosting.STATUS_CANCELLED:
        return STAGE_CANCELLED
    if application_status == JobApplication.STATUS_REJECTED:
        # Callers that pass the application get who ended an invitation.
        if application is not None:
            return _invitation_outcome(application) or STAGE_REJECTED
        return STAGE_REJECTED
    if application_status == JobApplication.STATUS_CLOSED:
        return STAGE_CLOSED
    if application_status == JobApplication.STATUS_COMPLETED:
        return STAGE_COMPLETED
    # A job finishing only completes the work of whoever was hired; anyone
    # still pending or invited never worked it.
    if job_status == JobPosting.STATUS_COMPLETED:
        return STAGE_COMPLETED if application_status == JobApplication.STATUS_HIRED else STAGE_CLOSED
    if application_status == JobApplication.STATUS_HIRED:
        if job_status == JobPosting.STATUS_COMPLETION_REQUESTED:
            return STAGE_AWAITING_CONFIRMATION
        # Past the job's last day only the household can finish it
        # (can_mark_done); "In progress" read as if the work were still
        # going on (My Applications audit, 2026-11-12). Callers that pass
        # the job get this; the stage stays the same without it.
        if job is not None and job_status == JobPosting.STATUS_ASSIGNED:
            from .services import job_has_lapsed

            if job_has_lapsed(job):
                return STAGE_AWAITING_MARK_DONE
            if _job_not_started(job):
                return STAGE_HIRED
        return STAGE_IN_PROGRESS
    if application_status == JobApplication.STATUS_HIRE_REQUESTED:
        return STAGE_AWAITING_WORKER
    return STAGE_PENDING


def get_job_stage(job_status, job=None):
    if job_status == JobPosting.STATUS_ASSIGNED:
        # Callers that pass the job get the household's view of it: past its
        # last day it waits on them to mark it done (the dashboard said "In
        # progress" for a job that ended days before), and with nobody hired
        # it isn't under way at all. Without the job the stage is as before.
        if job is not None:
            from .services import job_has_lapsed

            if not job.applications.filter(
                status__in=[JobApplication.STATUS_HIRED, JobApplication.STATUS_COMPLETED]
            ).exists():
                return STAGE_OPEN
            if job_has_lapsed(job):
                return STAGE_AWAITING_MARK_DONE
            if _job_not_started(job):
                return STAGE_NOT_STARTED
        return STAGE_IN_PROGRESS
    if job_status == JobPosting.STATUS_COMPLETION_REQUESTED:
        return STAGE_AWAITING_CONFIRMATION
    if job_status == JobPosting.STATUS_COMPLETED:
        return STAGE_COMPLETED
    if job_status == JobPosting.STATUS_CANCELLED:
        return STAGE_CANCELLED
    return STAGE_OPEN


def get_stage_label(stage, viewer_is_worker=False):
    """The stage's words. `viewer_is_worker` is for the worker reading their
    own application (WORKER_STAGE_LABELS)."""
    if viewer_is_worker and stage in WORKER_STAGE_LABELS:
        return WORKER_STAGE_LABELS[stage]
    return STAGE_LABELS.get(stage, STAGE_LABELS[STAGE_PENDING])
