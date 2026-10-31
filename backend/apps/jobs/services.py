from django.db import transaction
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.jobs.models import JobApplication, JobPosting, JobStatusEvent
from apps.notifications.models import Notification
from apps.notifications.services import create_notification, send_notification_email
from apps.reviews.models import Review


class HiringError(Exception):
    pass


class HiringCapacityReached(HiringError):
    pass


class HiringApplicationStateError(HiringError):
    pass


class HiringJobStateError(HiringError):
    pass


class HiringWorkerVerificationError(HiringError):
    pass


class HiringWorkerSuspendedError(HiringError):
    pass


class HiringWorkerOnFullTimeJobError(HiringError):
    """The worker is already hired on a full-time job that is under way."""

    def __init__(self, full_time_job):
        super().__init__(full_time_job)
        self.full_time_job = full_time_job


# Job types that take all of a worker's time. While one is in progress the
# worker can't apply elsewhere or be invited or hired (panel review,
# 2026-10-31). schedule_type is the posting form's wording, so a rename of
# these terms only needs this set updated.
FULL_TIME_SCHEDULE_TYPES = {"full-time", "full time", "fulltime"}
UNDERWAY_JOB_STATUSES = (JobPosting.STATUS_ASSIGNED, JobPosting.STATUS_COMPLETION_REQUESTED)


def is_full_time_job(job) -> bool:
    return (job.schedule_type or "").strip().lower() in FULL_TIME_SCHEDULE_TYPES


def active_full_time_job(worker, exclude_job_id=None):
    """The full-time job this worker is hired on and that is still under way,
    or None. ``exclude_job_id`` leaves out the job being acted on, so being
    hired on a job never blocks that same job."""
    jobs = (
        JobPosting.objects.filter(
            applications__worker=worker,
            applications__status=JobApplication.STATUS_HIRED,
            status__in=UNDERWAY_JOB_STATUSES,
        )
        .select_related("household")
        .order_by("job_start_date", "id")
    )
    if exclude_job_id is not None:
        jobs = jobs.exclude(pk=exclude_job_id)
    return next((job for job in jobs if is_full_time_job(job)), None)


def workers_on_full_time_jobs(exclude_job_id=None):
    """Ids of every worker currently held by a full-time job under way."""
    rows = JobApplication.objects.filter(
        status=JobApplication.STATUS_HIRED, job__status__in=UNDERWAY_JOB_STATUSES
    )
    if exclude_job_id is not None:
        rows = rows.exclude(job_id=exclude_job_id)
    return {
        worker_id
        for worker_id, schedule_type in rows.values_list("worker_id", "job__schedule_type")
        if (schedule_type or "").strip().lower() in FULL_TIME_SCHEDULE_TYPES
    }


def full_time_apply_message(full_time_job) -> str:
    """For the worker: why they can't take other work right now."""
    household = get_user_display_name(full_time_job.household)
    return (
        f"You're on a full-time job ({full_time_job.title}) until {household} marks it done. "
        "You can apply to other jobs after that."
    )


def full_time_hire_message(worker) -> str:
    """For another household: why this worker can't be invited or hired."""
    return (
        f"{get_user_display_name(worker)} is on a full-time job, so they can't be invited or hired "
        "until that job is done."
    )


def job_not_started_message(job):
    """Why the job can't be finished yet, or "" when it can.

    A job starting tomorrow could be marked done, confirmed and reviewed
    today, which is exactly the "rating for work that never happened" the
    completion gate exists to stop (AGENTS.md II.A). A job with no start
    date (schedule text only) is not held back.
    """
    if job.job_start_date and timezone.localdate() < job.job_start_date:
        return (
            f"This job starts on {job.job_start_date:%B} {job.job_start_date.day}, {job.job_start_date.year}. "
            "It can be marked complete once it has started."
        )
    return ""


def get_user_display_name(user) -> str:
    return user.get_full_name().strip() or user.username


def record_job_status_event(job, from_status, to_status, actor=None, note=""):
    if from_status == to_status:
        return None
    return JobStatusEvent.objects.create(
        job=job,
        entity=JobStatusEvent.ENTITY_JOB,
        from_status=from_status or "",
        to_status=to_status,
        actor=actor,
        note=note,
    )


def record_application_status_event(application, from_status, to_status, actor=None, note=""):
    if from_status == to_status:
        return None
    return JobStatusEvent.objects.create(
        job_id=application.job_id,
        application=application,
        entity=JobStatusEvent.ENTITY_APPLICATION,
        from_status=from_status or "",
        to_status=to_status,
        actor=actor,
        note=note,
    )


def hire_application(application_id: int, expected_status: str, actor=None) -> JobApplication:
    with transaction.atomic():
        application_job_id = JobApplication.objects.only("job_id").get(pk=application_id).job_id
        job = JobPosting.objects.select_for_update().get(pk=application_job_id)
        # worker__profile is a reverse one-to-one, so select_related joins it as
        # an OUTER JOIN -- and PostgreSQL refuses SELECT ... FOR UPDATE across
        # the nullable side of one. The profile is only read below, never locked,
        # so let it load lazily instead of widening the locked query.
        application = (
            JobApplication.objects.select_for_update()
            .select_related("worker", "job", "job__household")
            .get(pk=application_id)
        )

        if job.status in {JobPosting.STATUS_COMPLETED, JobPosting.STATUS_CANCELLED}:
            raise HiringJobStateError
        if application.status != expected_status:
            if (
                application.status == JobApplication.STATUS_CLOSED
                and job.applications.filter(status=JobApplication.STATUS_HIRED).count() >= job.worker_slots
            ):
                raise HiringCapacityReached
            raise HiringApplicationStateError

        worker_profile = getattr(application.worker, "profile", None)
        if (
            not worker_profile
            or worker_profile.role != UserProfile.ROLE_WORKER
            or worker_profile.verification_status != "verified"
        ):
            raise HiringWorkerVerificationError
        # A worker suspended after applying is out of the market: the invite
        # path already refuses them, and an instant accept must too.
        if worker_profile.refresh_block_status():
            raise HiringWorkerSuspendedError
        full_time_job = active_full_time_job(application.worker, exclude_job_id=job.id)
        if full_time_job:
            raise HiringWorkerOnFullTimeJobError(full_time_job)

        hired_count = job.applications.filter(status=JobApplication.STATUS_HIRED).exclude(
            pk=application.pk
        ).count()
        if hired_count >= job.worker_slots:
            raise HiringCapacityReached

        previous_application_status = application.status
        previous_job_status = job.status

        application.status = JobApplication.STATUS_HIRED
        application.save(update_fields=["status", "updated_at"])
        # Never move a job *backwards*: hiring another worker onto a job that
        # was already awaiting completion confirmation used to reset it to
        # "assigned" and silently discard the worker's completion request.
        # A job with openings left still accepts applications while assigned
        # (see JobApplicationView), so this does not close it early.
        if job.status == JobPosting.STATUS_OPEN:
            job.status = JobPosting.STATUS_ASSIGNED
            job.save(update_fields=["status"])

        record_application_status_event(
            application, previous_application_status, application.status, actor=actor
        )
        if job.status != previous_job_status:
            record_job_status_event(job, previous_job_status, job.status, actor=actor)

        crowded_out = []
        if hired_count + 1 >= job.worker_slots:
            crowded_out = close_open_applications(
                job, actor=actor, note="Closed automatically: job reached its worker limit."
            )
        # A full-time hire takes the worker off the market, so their other
        # open applications and invites close now rather than linger.
        released = (
            close_worker_open_applications(
                application.worker,
                exclude_job_id=job.id,
                actor=actor,
                note="Closed automatically: the worker took a full-time job.",
            )
            if is_full_time_job(job)
            else []
        )

    notify_closed_applicants(job, crowded_out, "was filled by another worker")
    notify_households_worker_unavailable(released)
    return application


def close_worker_open_applications(worker, exclude_job_id=None, actor=None, note=""):
    """Close every application of this worker still waiting on a decision
    (pending or invited) on other jobs, and return them."""
    open_applications = JobApplication.objects.select_related("job", "job__household", "worker").filter(
        worker=worker,
        status__in=[JobApplication.STATUS_PENDING, JobApplication.STATUS_HIRE_REQUESTED],
    )
    if exclude_job_id is not None:
        open_applications = open_applications.exclude(job_id=exclude_job_id)
    closed = list(open_applications)
    for other in closed:
        previous_status = other.status
        other.status = JobApplication.STATUS_CLOSED
        other.save(update_fields=["status", "updated_at"])
        record_application_status_event(other, previous_status, other.status, actor=actor, note=note)
    return closed


def notify_households_worker_unavailable(applications):
    """Tell each household whose applicant or invitee took a full-time job.
    The other household is never named."""
    for application in applications:
        worker_name = get_user_display_name(application.worker)
        create_notification(
            recipient=application.job.household,
            notification_type=Notification.TYPE_APPLICATION,
            title="Application closed",
            message=(
                f"{worker_name} took a full-time job and is no longer available. "
                f"Their application for {application.job.title} has been closed."
            ),
            actor=application.worker,
            related_job_id=application.job_id,
            related_application_id=application.id,
            action_type=Notification.ACTION_JOB_DETAIL,
            action_url=f"/household/jobs/{application.job_id}/applications",
        )


def close_open_applications(job, actor=None, note=""):
    """Close every application still waiting on a decision (pending or
    invited) and return them, so nobody is left pending on a job that no
    longer needs them."""
    closed = list(
        job.applications.select_related("worker").filter(
            status__in=[JobApplication.STATUS_PENDING, JobApplication.STATUS_HIRE_REQUESTED]
        )
    )
    for other in closed:
        previous_status = other.status
        other.status = JobApplication.STATUS_CLOSED
        other.save(update_fields=["status", "updated_at"])
        record_application_status_event(other, previous_status, other.status, actor=actor, note=note)
    return closed


def notify_closed_applicants(job, applications, reason):
    for other in applications:
        create_notification(
            recipient=other.worker,
            notification_type=Notification.TYPE_REJECTION,
            title="Position filled",
            message=f"{job.title} {reason}. Your application has been closed.",
            actor=job.household,
            related_job_id=job.id,
            related_application_id=other.id,
            action_type=Notification.ACTION_JOB_DETAIL,
            action_url=f"/worker/jobs/{job.id}",
        )


def create_household_review_reminder(job: JobPosting, application: JobApplication) -> None:
    already_reviewed = Review.objects.filter(
        job=job,
        author=job.household,
        target=application.worker,
        author_role=Review.ROLE_HOUSEHOLD,
        target_role=Review.ROLE_WORKER,
        rating__isnull=False,
    ).exists()
    if already_reviewed:
        return

    worker_name = get_user_display_name(application.worker)
    notification, created = Notification.objects.get_or_create(
        recipient=job.household,
        notification_type=Notification.TYPE_REVIEW_REMINDER,
        title="Review worker service",
        message=f"{job.title} is complete. Please submit feedback for {worker_name}.",
        related_job_id=job.id,
        related_application_id=application.id,
        action_type=Notification.ACTION_REVIEW,
        action_url=f"/household/jobs/{job.id}/review",
        requires_action=True,
        defaults={
            "actor": application.worker,
        },
    )
    if created:
        send_notification_email(job.household, notification.title, notification.message)


def complete_job(job: JobPosting, actor=None, previous_status=None) -> JobPosting:
    # Callers that persisted `completed` before calling in (the job PATCH
    # endpoint saves through its serializer) pass the status the job held
    # beforehand, otherwise the transition would look like a no-op here.
    previous_job_status = previous_status if previous_status is not None else job.status
    if job.status != JobPosting.STATUS_COMPLETED:
        job.status = JobPosting.STATUS_COMPLETED
    if job.completed_at is None:
        job.completed_at = timezone.now()
    job.save(update_fields=["status", "completed_at"])
    record_job_status_event(job, previous_job_status, job.status, actor=actor)
    leftover = close_open_applications(job, actor=actor, note="Closed automatically: job was completed.")
    notify_closed_applicants(job, leftover, "has been completed by another worker")

    hired_applications = list(
        job.applications.select_related("worker").filter(status=JobApplication.STATUS_HIRED)
    )
    for application in hired_applications:
        previous_application_status = application.status
        application.status = JobApplication.STATUS_COMPLETED
        application.save(update_fields=["status", "updated_at"])
        record_application_status_event(
            application, previous_application_status, application.status, actor=actor
        )
        create_notification(
            recipient=application.worker,
            notification_type=Notification.TYPE_COMPLETION,
            title="Job completed",
            message=f"{job.title} was marked completed.",
            actor=job.household,
            related_job_id=job.id,
            related_application_id=application.id,
            action_type=Notification.ACTION_REVIEW,
            action_url=f"/worker/jobs/{job.id}/review",
            requires_action=True,
        )

    completed_applications = job.applications.select_related("worker").filter(
        status=JobApplication.STATUS_COMPLETED
    )
    for application in completed_applications:
        create_household_review_reminder(job, application)
    return job
