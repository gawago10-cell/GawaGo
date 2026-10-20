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
STAGE_AWAITING_CONFIRMATION = "awaiting_confirmation"
STAGE_COMPLETED = "completed"
STAGE_REJECTED = "rejected"
STAGE_CLOSED = "closed"
STAGE_CANCELLED = "cancelled"
STAGE_OPEN = "open"

STAGE_LABELS = {
    STAGE_PENDING: "Pending",
    STAGE_AWAITING_WORKER: "Awaiting worker response",
    STAGE_IN_PROGRESS: "In progress",
    STAGE_AWAITING_CONFIRMATION: "Awaiting confirmation",
    STAGE_COMPLETED: "Completed",
    STAGE_REJECTED: "Rejected",
    STAGE_CLOSED: "Closed",
    STAGE_CANCELLED: "Cancelled",
    STAGE_OPEN: "Open",
}


def get_application_stage(application_status, job_status=None):
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
        return STAGE_IN_PROGRESS
    if application_status == JobApplication.STATUS_HIRE_REQUESTED:
        return STAGE_AWAITING_WORKER
    return STAGE_PENDING


def get_job_stage(job_status):
    if job_status == JobPosting.STATUS_ASSIGNED:
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
