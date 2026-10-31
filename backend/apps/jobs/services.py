from dataclasses import dataclass
from datetime import timedelta

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


class HiringWorkerUnavailableError(HiringError):
    """Another job holds the worker: a full-time one under way, or one on the
    same days (see ``worker_hold``)."""

    def __init__(self, hold):
        super().__init__(hold)
        self.hold = hold


# Job types that take all of a worker's time. While one is in progress the
# worker can't apply elsewhere or be invited or hired (panel review,
# 2026-10-31). schedule_type is the posting form's wording, so a rename of
# these terms only needs this set updated.
FULL_TIME_SCHEDULE_TYPES = {"full-time", "full time", "fulltime"}
UNDERWAY_JOB_STATUSES = (JobPosting.STATUS_ASSIGNED, JobPosting.STATUS_COMPLETION_REQUESTED)


def is_full_time_job(job) -> bool:
    return _is_full_time(job.schedule_type)


def _is_full_time(schedule_type) -> bool:
    return (schedule_type or "").strip().lower() in FULL_TIME_SCHEDULE_TYPES


def _days(start, end, working_days):
    if not start:
        return None
    if end and end >= start:
        return start, end
    return start, start + timedelta(days=max(working_days or 1, 1) - 1)


def job_days(job):
    """The first and last calendar day a job takes, or None without a start
    date. With no end date it runs for its working days from the start, so a
    one-day job ends the day it starts."""
    return _days(job.job_start_date, job.job_end_date, job.estimated_working_days)


def days_overlap(first, second) -> bool:
    return bool(first and second and first[0] <= second[1] and second[0] <= first[1])


def format_job_days(days) -> str:
    """"Sun, Nov 8 – Mon, Nov 9, 2026", or one day when the job is a day long."""
    start, end = days

    def day(value, with_year=True):
        text = f"{value:%a}, {value:%b} {value.day}"
        return f"{text}, {value.year}" if with_year else text

    if start == end:
        return day(start)
    return f"{day(start, with_year=start.year != end.year)} – {day(end)}"


@dataclass(frozen=True)
class WorkerHold:
    """Why a worker can't take a job: ``job`` is the hired job holding them."""

    kind: str
    job: JobPosting

    FULL_TIME = "full_time"
    SAME_DAYS = "same_days"


def hired_jobs_under_way(worker):
    return list(
        JobPosting.objects.filter(
            applications__worker=worker,
            applications__status=JobApplication.STATUS_HIRED,
            status__in=UNDERWAY_JOB_STATUSES,
        )
        .select_related("household")
        .order_by("job_start_date", "id")
    )


def hold_on(job, hired_jobs):
    """Which of these hired jobs keeps the worker from ``job``, or None.

    A full-time job under way holds them from everything; any other job
    holds them from jobs sharing one of its days, whatever the job type,
    since jobs have dates but no hours (panel review, 2026-11-01). A job
    without a start date can't be checked for days, so only full-time holds
    apply to it. ``job`` itself never counts."""
    others = [held for held in hired_jobs if held.id != job.id]
    full_time = next((held for held in others if is_full_time_job(held)), None)
    if full_time:
        return WorkerHold(WorkerHold.FULL_TIME, full_time)
    days = job_days(job)
    same_days = next((held for held in others if days_overlap(days, job_days(held))), None)
    return WorkerHold(WorkerHold.SAME_DAYS, same_days) if same_days else None


def worker_hold(worker, job):
    return hold_on(job, hired_jobs_under_way(worker))


def workers_held_from(job):
    """Ids of workers another hired job keeps from ``job`` (``hold_on`` for
    every worker at once)."""
    days = job_days(job)
    rows = (
        JobApplication.objects.filter(status=JobApplication.STATUS_HIRED, job__status__in=UNDERWAY_JOB_STATUSES)
        .exclude(job_id=job.id)
        .values_list(
            "worker_id", "job__schedule_type", "job__job_start_date", "job__job_end_date", "job__estimated_working_days"
        )
    )
    return {
        worker_id
        for worker_id, schedule_type, start, end, working_days in rows
        if _is_full_time(schedule_type) or days_overlap(days, _days(start, end, working_days))
    }


def hold_title(hold) -> str:
    """The short lead the clients put before ``hold_apply_message``."""
    return "On a full-time job." if hold.kind == WorkerHold.FULL_TIME else "Already hired on these days."


def hold_apply_message(hold) -> str:
    """For the worker: why they can't take this job. It is their own job, so
    the household is named."""
    household = get_user_display_name(hold.job.household)
    if hold.kind == WorkerHold.FULL_TIME:
        return (
            f"You're on a full-time job ({hold.job.title}) until {household} marks it done. "
            "You can apply to other jobs after that."
        )
    return (
        f"You're already hired for {hold.job.title} ({household}) on {format_job_days(job_days(hold.job))}. "
        "You can apply to jobs on other days."
    )


def hold_hire_message(worker, hold) -> str:
    """For another household: why this worker can't be invited or hired. The
    household holding the worker is never named."""
    name = get_user_display_name(worker)
    if hold.kind == WorkerHold.FULL_TIME:
        return f"{name} is on a full-time job, so they can't be invited or hired until that job is done."
    return (
        f"{name} is already hired for another job on {format_job_days(job_days(hold.job))}, "
        "so they can't be invited or hired for these days."
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
        hold = worker_hold(application.worker, job)
        if hold:
            raise HiringWorkerUnavailableError(hold)

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
        # The worker's other open applications and invites that this hire
        # rules out close now rather than linger: all of them for a
        # full-time job, those sharing one of its days otherwise.
        full_time = is_full_time_job(job)
        released = close_worker_open_applications(
            application.worker,
            exclude_job_id=job.id,
            all_jobs=full_time,
            days=job_days(job),
            actor=actor,
            note=(
                "Closed automatically: the worker took a full-time job."
                if full_time
                else "Closed automatically: the worker was hired for another job on the same days."
            ),
        )

    notify_closed_applicants(job, crowded_out, "was filled by another worker")
    notify_households_worker_unavailable(released, full_time=full_time)
    return application


def close_worker_open_applications(worker, exclude_job_id=None, all_jobs=False, days=None, actor=None, note=""):
    """Close this worker's applications still waiting on a decision (pending
    or invited) on other jobs, and return them: all of them with
    ``all_jobs``, otherwise only those on jobs sharing one of ``days`` (none
    when ``days`` is None, and never a job without dates)."""
    open_applications = JobApplication.objects.select_related("job", "job__household", "worker").filter(
        worker=worker,
        status__in=[JobApplication.STATUS_PENDING, JobApplication.STATUS_HIRE_REQUESTED],
    )
    if exclude_job_id is not None:
        open_applications = open_applications.exclude(job_id=exclude_job_id)
    closed = [other for other in open_applications if all_jobs or days_overlap(days, job_days(other.job))]
    for other in closed:
        previous_status = other.status
        other.status = JobApplication.STATUS_CLOSED
        other.save(update_fields=["status", "updated_at"])
        record_application_status_event(other, previous_status, other.status, actor=actor, note=note)
    return closed


def notify_households_worker_unavailable(applications, full_time=False):
    """Tell each household whose applicant or invitee was hired elsewhere,
    on a full-time job or on the same days. The other household is never
    named."""
    taken = "took a full-time job" if full_time else "was hired for another job on the same days"
    for application in applications:
        worker_name = get_user_display_name(application.worker)
        create_notification(
            recipient=application.job.household,
            notification_type=Notification.TYPE_APPLICATION,
            title="Application closed",
            message=(
                f"{worker_name} {taken} and is no longer available. "
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
