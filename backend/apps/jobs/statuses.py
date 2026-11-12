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
}


def get_application_stage(application_status, job_status=None, job=None):
    # The worker's own decision to step away reads the same whatever the job
    # did afterwards.
    if application_status == JobApplication.STATUS_WITHDRAWN:
        return STAGE_WITHDRAWN
    if job_status == JobPosting.STATUS_CANCELLED:
        return STAGE_CANCELLED
    if application_status == JobApplication.STATUS_REJECTED:
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
        return STAGE_IN_PROGRESS
    if job_status == JobPosting.STATUS_COMPLETION_REQUESTED:
        return STAGE_AWAITING_CONFIRMATION
    if job_status == JobPosting.STATUS_COMPLETED:
        return STAGE_COMPLETED
    if job_status == JobPosting.STATUS_CANCELLED:
        return STAGE_CANCELLED
    return STAGE_OPEN


def get_stage_label(stage):
    return STAGE_LABELS.get(stage, STAGE_LABELS[STAGE_PENDING])
