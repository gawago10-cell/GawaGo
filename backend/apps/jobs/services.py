from dataclasses import dataclass
from datetime import timedelta

from django.core.cache import cache
from django.db import transaction
from django.db.models import Avg, Count, F, OuterRef, Q, Subquery
from django.db.models.functions import Coalesce
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


class HiringHouseholdSuspendedError(HiringError):
    """The household can't use GawaGo right now, so its job takes nobody new."""


class HiringJobLapsedError(HiringError):
    """The job's days have passed, so nobody new can be hired for it."""


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


def jobs_accepting_applications(queryset):
    """Open jobs, plus jobs under way that still have openings: a job needing
    several workers keeps taking applicants after its first hire, so it stays
    in the market until every opening is filled (as JobApplicationView
    allows). The hired count is a subquery so other filters on applications
    can't skew it."""
    hired = (
        JobApplication.objects.filter(job=OuterRef("pk"), status=JobApplication.STATUS_HIRED)
        .values("job")
        .annotate(total=Count("pk"))
        .values("total")
    )
    return (
        queryset.annotate(hired_so_far=Coalesce(Subquery(hired), 0))
        .filter(
            Q(status=JobPosting.STATUS_OPEN)
            | Q(status=JobPosting.STATUS_ASSIGNED, hired_so_far__lt=F("worker_slots"))
        )
        .exclude(pk__in=lapsed_job_ids())
    )


def job_has_lapsed(job, today=None) -> bool:
    """The job's last day is behind us (system scan, 2026-11-01). A job that
    lapses with nobody hired leaves the market: workers can't apply or be
    hired for a day that has gone. A job without a start date never lapses."""
    days = job_days(job)
    return bool(days) and days[1] < (today or timezone.localdate())


def lapsed_job_ids():
    """Ids of open or under-way jobs whose last day has passed. Only jobs
    that started before today can qualify, so the scan stays small."""
    today = timezone.localdate()
    rows = JobPosting.objects.filter(
        status__in=[JobPosting.STATUS_OPEN, JobPosting.STATUS_ASSIGNED], job_start_date__lt=today
    ).values_list("id", "job_start_date", "job_end_date", "estimated_working_days")
    return [job_id for job_id, start, end, working_days in rows if _days(start, end, working_days)[1] < today]


def lapsed_note(job) -> str:
    """For the household: an open job whose day passed with nobody hired."""
    return (
        f"This job was set for {format_job_days(job_days(job))}. Workers no longer see it. "
        "Edit the dates to post it again, or cancel it."
    )


def lapsed_apply_message(job) -> str:
    return f"This job was set for {format_job_days(job_days(job))}, which has passed, so it isn't taking applicants."


def lapsed_hire_message(job) -> str:
    if job.status == JobPosting.STATUS_OPEN:
        return (
            f"This job was set for {format_job_days(job_days(job))}, which has passed. "
            "Edit the dates before hiring for it."
        )
    return f"This job's days ({format_job_days(job_days(job))}) have passed, so no one new can be hired for it."


# Terms a worker agreed to by applying. Changing one while they wait gets
# them a notice saying what changed (system scan, 2026-11-01).
JOB_TERM_LABELS = {
    "service_rate": "rate",
    "rate_type": "rate type",
    "job_start_date": "start date",
    "job_end_date": "end date",
    "estimated_working_days": "working days",
    "schedule_type": "schedule type",
}


def _term_text(job, field):
    value = getattr(job, field)
    if value in (None, ""):
        return "not set"
    if field == "service_rate":
        return f"PHP {value:,.2f}"
    if field == "rate_type":
        return job.get_rate_type_display()
    if field in ("job_start_date", "job_end_date"):
        return f"{value:%a}, {value:%b} {value.day}, {value.year}"
    return str(value)


def job_term_snapshot(job):
    return {field: _term_text(job, field) for field in JOB_TERM_LABELS}


def notify_applicants_of_changed_terms(job, before):
    """Tell everyone still waiting on this job (pending or invited) which of
    its terms the household just changed."""
    after = job_term_snapshot(job)
    changes = [
        f"{label} {before[field]} \u2192 {after[field]}"
        for field, label in JOB_TERM_LABELS.items()
        if before[field] != after[field]
    ]
    if not changes:
        return []
    waiting = list(
        job.applications.select_related("worker").filter(
            status__in=[JobApplication.STATUS_PENDING, JobApplication.STATUS_HIRE_REQUESTED]
        )
    )
    household = get_user_display_name(job.household)
    summary = "; ".join(changes)
    for application in waiting:
        still = "The invitation" if application.status == JobApplication.STATUS_HIRE_REQUESTED else "Your application"
        create_notification(
            recipient=application.worker,
            notification_type=Notification.TYPE_APPLICATION,
            title="Job details changed",
            message=f"{household} changed {job.title}: {summary}. {still} is still open.",
            actor=job.household,
            related_job_id=job.id,
            related_application_id=application.id,
            action_type=Notification.ACTION_JOB_DETAIL,
            action_url=f"/worker/jobs/{job.id}",
        )
    return waiting


def rate_guide(skill, rate_type):
    """What households usually offer for a service, from posts that weren't
    cancelled, so a new post starts from a fair figure (spec II.B). Worded
    here so web and mobile say the same thing; "" with too little data."""

    rate_type = rate_type if rate_type in dict(JobPosting.RATE_TYPE_CHOICES) else JobPosting.RATE_PER_DAY
    row = (
        JobPosting.objects.exclude(status=JobPosting.STATUS_CANCELLED)
        # Posts from before the PHP 1 minimum (PHP 0.11) made the guide read
        # "about PHP 0 / day" (Post a Job audit, 2026-11-13).
        .filter(required_skill__iexact=(skill or "").strip(), rate_type=rate_type, service_rate__gte=1)
        .aggregate(average=Avg("service_rate"), posts=Count("id"))
    )
    posts = row["posts"] or 0
    average = float(row["average"] or 0)
    unit = {
        JobPosting.RATE_PER_DAY: "day",
        JobPosting.RATE_PER_HOUR: "hour",
    }.get(rate_type)
    label = ""
    if posts >= 2 and average > 0:
        per = f" / {unit}" if unit else " for the job"
        label = f"{skill.strip()} usually posts at about PHP {average:,.0f}{per}."
    return {"skill": (skill or "").strip(), "rate_type": rate_type, "average_rate": round(average, 2), "posts": posts, "label": label}


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


# A hired job stops holding its worker this many days after its last day,
# even if the household never marks it done, so a household that goes quiet
# can't keep a worker off the market for good (fourth scan, 2026-11-01). The
# household is reminded to mark it done the day after its last day.
HOLD_GRACE_DAYS = 3


def hold_ends_on(days):
    """The last day a hired job with these days can hold its worker, or None
    for a job without dates (then only marking it done ends the hold)."""
    return days[1] + timedelta(days=HOLD_GRACE_DAYS) if days else None


def full_time_started(schedule_type, days, today=None) -> bool:
    """A full-time job takes all of a worker's time from its first day; one
    without dates is treated as already under way."""
    return _is_full_time(schedule_type) and (not days or days[0] <= (today or timezone.localdate()))


def _hold_kind(target_days, schedule_type, held_days, today):
    """How a hired job (its schedule type and days) keeps its worker from a
    job on ``target_days``: WorkerHold.FULL_TIME, WorkerHold.SAME_DAYS or
    None.

    Past its last day plus HOLD_GRACE_DAYS it holds nothing. Once a
    full-time job has started it holds the worker from every job until the
    household marks it done (panel review, 2026-10-31). Before that, and for
    every other job type, a job only holds its own days, since jobs have
    dates but no hours (panel review, 2026-11-01): a full-time job booked for
    next month no longer keeps the worker from a one-day job this week
    (fourth scan, 2026-11-01). A job without dates can't share days, so only
    a started full-time job holds the worker from it."""
    end = hold_ends_on(held_days)
    if end is not None and end < today:
        return None
    if full_time_started(schedule_type, held_days, today):
        return WorkerHold.FULL_TIME
    return WorkerHold.SAME_DAYS if days_overlap(target_days, held_days) else None


def hold_on(job, hired_jobs, today=None):
    """Which of these hired jobs keeps the worker from ``job``, or None; a
    full-time hold wins over a same-days one. ``job`` itself never counts."""
    today = today or timezone.localdate()
    target = job_days(job)
    same_days = None
    for held in hired_jobs:
        if held.id == job.id:
            continue
        kind = _hold_kind(target, held.schedule_type, job_days(held), today)
        if kind == WorkerHold.FULL_TIME:
            return WorkerHold(kind, held)
        if kind and same_days is None:
            same_days = WorkerHold(kind, held)
    return same_days


def worker_hold(worker, job):
    return hold_on(job, hired_jobs_under_way(worker))


def workers_held_from(job):
    """Ids of workers another hired job keeps from ``job`` (``hold_on`` for
    every worker at once)."""
    today = timezone.localdate()
    target = job_days(job)
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
        if _hold_kind(target, schedule_type, _days(start, end, working_days), today)
    }


def hold_title(hold) -> str:
    """The short lead the clients put before ``hold_apply_message``."""
    return "On a full-time job." if hold.kind == WorkerHold.FULL_TIME else "Already hired on these days."


def hold_apply_message(hold) -> str:
    """For the worker: why they can't take this job. It is their own job, so
    the household is named."""
    household = get_user_display_name(hold.job.household)
    if hold.kind == WorkerHold.FULL_TIME:
        message = f"You're on a full-time job ({hold.job.title}) until {household} marks it done."
        end = hold_ends_on(job_days(hold.job))
        if end is None:
            return f"{message} You can apply to other jobs after that."
        free_from = end + timedelta(days=1)
        return f"{message} If they don't, you can apply to other jobs again from {format_job_days((free_from, free_from))}."
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
    if from_status in UNDERWAY_JOB_STATUSES and to_status not in UNDERWAY_JOB_STATUSES:
        clear_mark_done_reminders(job)
    return JobStatusEvent.objects.create(
        job=job,
        entity=JobStatusEvent.ENTITY_JOB,
        from_status=from_status or "",
        to_status=to_status,
        actor=actor,
        note=note,
    )


def reopen_if_nobody_hired(job_id, note=""):
    """A job left "in progress" with nobody hired goes back to open, so it
    lapses or takes workers again like any other open job. The worker's own
    back-out already does this (withdraw_application); this covers a hire
    removed any other way -- the worker's account deleted, or the hire
    changed in the Django admin -- which used to leave the job stuck: "No
    worker hired yet", and a "Mark as done" that could never be pressed.
    Returns True when the job was reopened."""
    with transaction.atomic():
        job = JobPosting.objects.select_for_update().filter(pk=job_id).first()
        if job is None or job.status not in UNDERWAY_JOB_STATUSES:
            return False
        if job.applications.filter(
            status__in=[JobApplication.STATUS_HIRED, JobApplication.STATUS_COMPLETED]
        ).exists():
            return False
        previous_status = job.status
        job.status = JobPosting.STATUS_OPEN
        job.save(update_fields=["status"])
        record_job_status_event(job, previous_status, job.status, note=note)
        return True


AWAITING_DECISION_STATUSES = (JobApplication.STATUS_PENDING, JobApplication.STATUS_HIRE_REQUESTED)


def settle_application_notifications(application_ids):
    """An application that stopped waiting on a decision no longer needs
    anyone's response: its hire request (or "New worker application") left
    "Needs your response" up for good, with blank job details once the job
    left the worker's list (flow audit, 2026-11-04). Review prompts keep
    theirs; the review clears them."""
    return (
        Notification.objects.filter(related_application_id__in=list(application_ids), requires_action=True)
        .exclude(action_type=Notification.ACTION_REVIEW)
        .update(requires_action=False)
    )


def record_application_status_event(application, from_status, to_status, actor=None, note=""):
    if from_status == to_status:
        return None
    if to_status not in AWAITING_DECISION_STATUSES:
        settle_application_notifications([application.id])
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
        if job_has_lapsed(job):
            raise HiringJobLapsedError
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
        # An invitation sent before the household was suspended can't be
        # accepted into a job nobody can manage (flow audit, 2026-11-04).
        household_profile = getattr(job.household, "profile", None)
        if household_profile and household_profile.refresh_block_status():
            raise HiringHouseholdSuspendedError
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
        # full-time job that has started, those sharing one of its days
        # otherwise (see _hold_kind).
        full_time = full_time_started(job.schedule_type, job_days(job))
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

    notify_closed_applicants(
        job, crowded_out, "Position filled", f"{job.title} was filled by another worker. Your application has been closed."
    )
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


def notify_closed_applicants(job, applications, title, message):
    for other in applications:
        create_notification(
            recipient=other.worker,
            notification_type=Notification.TYPE_REJECTION,
            title=title,
            message=message,
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
    # The household marked it done; nobody else "completed" it.
    notify_closed_applicants(
        job,
        leftover,
        "Job closed",
        f"{get_user_display_name(job.household)} marked {job.title} as done. Your application has been closed.",
    )

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
            title="Job marked done",
            message=(
                f"{get_user_display_name(job.household)} marked {job.title} as done. "
                "You can now rate the household; your feedback stays anonymous."
            ),
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


# --- Stepping away from a job (fourth scan, 2026-11-01) --------------------

FINISHED_JOB_STATUSES = (JobPosting.STATUS_COMPLETED, JobPosting.STATUS_CANCELLED)
WITHDRAW_REASON_MAX_LENGTH = 300


class WithdrawError(Exception):
    """Why the worker can't step away; str() is the message for them."""


def can_withdraw_application(application) -> bool:
    """A worker can take back an application the household hasn't decided on."""
    return (
        application.status == JobApplication.STATUS_PENDING
        and application.job.status not in FINISHED_JOB_STATUSES
    )


def can_back_out_of_hire(application, today=None) -> bool:
    """A hired worker can back out until the job's first day. After that the
    household decides: it marks the job done or cancels it. A job without a
    start date counts as started, as it does for marking it done."""
    job = application.job
    return (
        application.status == JobApplication.STATUS_HIRED
        and job.status in UNDERWAY_JOB_STATUSES
        and job.job_start_date is not None
        and (today or timezone.localdate()) < job.job_start_date
    )


def clean_reason(value) -> str:
    return " ".join(str(value or "").split())[:WITHDRAW_REASON_MAX_LENGTH]


def withdraw_application(application_id: int, worker, reason: str = "") -> JobApplication:
    """The worker steps away: a pending application is taken back, or a hire
    is given up before the job starts (a reason is then required, since the
    household was counting on them). A job left with nobody hired opens
    again so the household can hire someone else."""
    reason = clean_reason(reason)
    with transaction.atomic():
        job_id = JobApplication.objects.only("job_id").get(pk=application_id).job_id
        job = JobPosting.objects.select_for_update().select_related("household").get(pk=job_id)
        application = JobApplication.objects.select_for_update().select_related("worker").get(pk=application_id)
        application.job = job
        if application.worker_id != worker.id:
            raise PermissionError
        backing_out = application.status == JobApplication.STATUS_HIRED
        if application.status == JobApplication.STATUS_HIRE_REQUESTED:
            raise WithdrawError("This is an invitation. Decline it instead.")
        if backing_out:
            if not can_back_out_of_hire(application):
                raise WithdrawError(
                    "This job has started, so you can't back out of it here. "
                    "Talk to the household; they can mark it done or cancel it."
                )
            if not reason:
                raise WithdrawError("Tell the household why you can't take this job.")
        elif not can_withdraw_application(application):
            raise WithdrawError("This application can't be withdrawn any more.")

        previous_status = application.status
        application.status = JobApplication.STATUS_WITHDRAWN
        application.save(update_fields=["status", "updated_at"])
        record_application_status_event(application, previous_status, application.status, actor=worker, note=reason)

        reopened = False
        if (
            backing_out
            and job.status in UNDERWAY_JOB_STATUSES
            and not job.applications.filter(status=JobApplication.STATUS_HIRED).exists()
        ):
            previous_job_status = job.status
            job.status = JobPosting.STATUS_OPEN
            job.save(update_fields=["status"])
            record_job_status_event(
                job, previous_job_status, job.status, actor=worker, note="The hired worker backed out before the job started."
            )
            reopened = True

    worker_name = get_user_display_name(worker)
    if backing_out:
        create_notification(
            recipient=job.household,
            notification_type=Notification.TYPE_APPLICATION,
            title="Worker backed out",
            message=(
                f"{worker_name} can't take {job.title} after all and backed out before it started. Reason: {reason}"
                + (" The job is open again, so you can hire someone else." if reopened else "")
            ),
            actor=worker,
            related_job_id=job.id,
            related_application_id=application.id,
            action_type=Notification.ACTION_JOB_DETAIL,
            action_url=f"/household/jobs/{job.id}/applications",
        )
    else:
        create_notification(
            recipient=job.household,
            notification_type=Notification.TYPE_APPLICATION,
            title="Application withdrawn",
            message=f"{worker_name} withdrew their application for {job.title}.",
            actor=worker,
            related_job_id=job.id,
            related_application_id=application.id,
            action_type=Notification.ACTION_JOB_DETAIL,
            action_url=f"/household/jobs/{job.id}/applications",
        )
    return application


# --- When an account is suspended (flow audit, 2026-11-04) -----------------

def _open_on_jobs(applications):
    return applications.select_related("job", "job__household", "worker").filter(
        status__in=[JobApplication.STATUS_PENDING, JobApplication.STATUS_HIRE_REQUESTED],
        job__status__in=[JobPosting.STATUS_OPEN, *UNDERWAY_JOB_STATUSES],
    )


def _hires_still_ahead(applications):
    """Hires on jobs not yet done whose hold hasn't lapsed (see HOLD_GRACE_DAYS)."""
    today = timezone.localdate()
    hires = applications.select_related("job", "job__household", "worker").filter(
        status=JobApplication.STATUS_HIRED, job__status__in=UNDERWAY_JOB_STATUSES
    )
    return [
        hire for hire in hires
        if (hold_ends_on(job_days(hire.job)) is None or hold_ends_on(job_days(hire.job)) >= today)
    ]


def _when(job):
    days = job_days(job)
    return f" on {format_job_days(days)}" if days else ""


def release_suspended_account(user):
    """What a suspension means for the people this account deals with.

    Applications and invitations still waiting on a decision close, since the
    suspended side can't act on them: a worker could otherwise accept an
    invitation from a household that can no longer sign in. The other side of
    each hire is told the job may not go ahead, but the hire itself stays: a
    timed suspension can end before the job's day, and the household decides
    whether to cancel (D1, flow audit, 2026-11-04). Complaints are
    confidential, so nobody is told why or that a report was involved."""
    profile = getattr(user, "profile", None)
    if profile is None:
        return
    name = get_user_display_name(user)
    note = "Closed automatically: the other party can't use GawaGo right now."
    if profile.role == UserProfile.ROLE_HOUSEHOLD:
        closed = list(_open_on_jobs(JobApplication.objects.filter(job__household=user)))
        for application in closed:
            previous_status = application.status
            application.status = JobApplication.STATUS_CLOSED
            application.save(update_fields=["status", "updated_at"])
            record_application_status_event(application, previous_status, application.status, note=note)
            create_notification(
                recipient=application.worker,
                notification_type=Notification.TYPE_REJECTION,
                title="Job not available",
                message=(
                    f"{name} isn't taking workers for {application.job.title} right now, so "
                    f"{'their invitation' if previous_status == JobApplication.STATUS_HIRE_REQUESTED else 'your application'} "
                    "has been closed. If the job opens again, you can apply again."
                ),
                actor=None,
                related_job_id=application.job_id,
                related_application_id=application.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                action_url=f"/worker/jobs/{application.job_id}",
            )
        for hire in _hires_still_ahead(JobApplication.objects.filter(job__household=user)):
            message = (
                f"{name} can't use GawaGo for now, so {hire.job.title}{_when(hire.job)} may not go ahead. "
                "Check with them directly before the job day."
            )
            if can_back_out_of_hire(hire):
                message += " You can still back out before it starts."
            create_notification(
                recipient=hire.worker,
                notification_type=Notification.TYPE_APPLICATION,
                title="Your job may not go ahead",
                message=message,
                related_job_id=hire.job_id,
                related_application_id=hire.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                action_url=f"/worker/jobs/{hire.job_id}",
            )
    elif profile.role == UserProfile.ROLE_WORKER:
        closed = list(_open_on_jobs(JobApplication.objects.filter(worker=user)))
        for application in closed:
            previous_status = application.status
            application.status = JobApplication.STATUS_CLOSED
            application.save(update_fields=["status", "updated_at"])
            record_application_status_event(application, previous_status, application.status, note=note)
            create_notification(
                recipient=application.job.household,
                notification_type=Notification.TYPE_APPLICATION,
                title="Application closed",
                message=f"{name} isn't available right now. Their application for {application.job.title} has been closed.",
                related_job_id=application.job_id,
                related_application_id=application.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                action_url=f"/household/jobs/{application.job_id}/applications",
            )
        for hire in _hires_still_ahead(JobApplication.objects.filter(worker=user)):
            create_notification(
                recipient=hire.job.household,
                notification_type=Notification.TYPE_APPLICATION,
                title="Your worker may not be available",
                message=(
                    f"{name} can't use GawaGo for now, so they may not be able to do {hire.job.title}{_when(hire.job)}. "
                    "You can wait for them, or cancel the job, saying why, and post it again."
                ),
                related_job_id=hire.job_id,
                related_application_id=hire.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                action_url=f"/household/jobs/{hire.job_id}",
            )


# --- Reminding the household to mark a job done ----------------------------

MARK_DONE_REMINDER_TITLE = "Mark the job as done"


def clear_mark_done_reminders(job) -> int:
    """The job is no longer in progress (marked done, cancelled, or reopened
    with nobody hired), so "Mark the job as done" is answered. It used to stay
    an unread to-do for good (household notifications audit, 2026-11-13)."""
    return Notification.objects.filter(
        notification_type=Notification.TYPE_COMPLETION,
        related_job_id=job.id,
        title=MARK_DONE_REMINDER_TITLE,
        requires_action=True,
    ).update(requires_action=False, is_read=True)
MARK_DONE_REMINDER_COOLDOWN_SECONDS = 300
MARK_DONE_REMINDER_LOCK_KEY = "jobs:mark_done_reminders_lock"


def send_due_mark_done_reminders(today=None) -> int:
    """The day after a hired job's last day, remind its household once to
    mark it done or cancel it (fourth scan, 2026-11-01). Without this a job
    nobody closed stayed "In progress" for good."""
    today = today or timezone.localdate()
    jobs = (
        JobPosting.objects.filter(
            status__in=UNDERWAY_JOB_STATUSES,
            job_start_date__lt=today,
            applications__status=JobApplication.STATUS_HIRED,
        )
        .distinct()
        .select_related("household")
    )
    sent = 0
    for job in jobs:
        days = job_days(job)
        if not days or days[1] >= today:
            continue
        # Only a reminder still waiting counts: a job reopened and hired
        # again that runs past its new last day is reminded again.
        already_reminded = Notification.objects.filter(
            recipient_id=job.household_id,
            notification_type=Notification.TYPE_COMPLETION,
            related_job_id=job.id,
            title=MARK_DONE_REMINDER_TITLE,
            requires_action=True,
        ).exists()
        if already_reminded:
            continue
        create_notification(
            recipient=job.household,
            notification_type=Notification.TYPE_COMPLETION,
            title=MARK_DONE_REMINDER_TITLE,
            message=(
                f"{job.title} was set to end on {format_job_days((days[1], days[1]))}. "
                "If the work is finished, mark it as done so you can review your worker. "
                "If it didn't happen, cancel it and say why."
            ),
            related_job_id=job.id,
            action_type=Notification.ACTION_JOB_DETAIL,
            action_url=f"/household/jobs/{job.id}",
            requires_action=True,
        )
        sent += 1
    return sent


def send_due_mark_done_reminders_on_read() -> int:
    """Run the reminder pass from ordinary reads, at most once per cooldown
    window, the same way the default-rating sweep runs (no scheduler on the
    free hosting plan)."""
    if not cache.add(MARK_DONE_REMINDER_LOCK_KEY, True, MARK_DONE_REMINDER_COOLDOWN_SECONDS):
        return 0
    return send_due_mark_done_reminders()


# --- Closing out a job before posting another (2026-11-02) -----------------

POST_BLOCK_MARK_DONE = "mark_done"
POST_BLOCK_RATE = "rate"


def _names(users):
    names = [get_user_display_name(user) for user in users]
    return ", ".join(names[:-1]) + f" and {names[-1]}" if len(names) > 1 else (names[0] if names else "your worker")


def posting_block(household, today=None):
    """Why this household can't post a new job yet, or None.

    A household finishes one hire before it starts another: a hired job whose
    last day has passed must be marked done, and a finished job's workers must
    be rated by the household. The automatic 3.5 placeholder doesn't count as
    a rating (a real review replaces it), the same rule as ``can_review``. A
    job still running, or one that hasn't started, blocks nothing.

    Returns ``{"kind", "job", "message"}`` for the oldest job still waiting,
    so the clients can send the household straight to it."""
    today = today or timezone.localdate()

    hired = (
        JobPosting.objects.filter(
            household=household,
            status__in=UNDERWAY_JOB_STATUSES,
            job_start_date__lt=today,
            applications__status=JobApplication.STATUS_HIRED,
        )
        .distinct()
        .order_by("job_start_date", "id")
    )
    for job in hired:
        if job_has_lapsed(job, today):
            return {
                "kind": POST_BLOCK_MARK_DONE,
                "job": job,
                "message": (
                    f"{job.title} was set to end on {format_job_days((job_days(job)[1], job_days(job)[1]))}. "
                    "Mark it as done, or cancel it, and rate your worker before you post another job."
                ),
            }

    completed = (
        JobPosting.objects.filter(
            household=household,
            status=JobPosting.STATUS_COMPLETED,
            applications__status=JobApplication.STATUS_COMPLETED,
        )
        .distinct()
        .order_by("completed_at", "id")
    )
    for job in completed:
        workers = [
            application.worker
            for application in job.applications.select_related("worker").filter(
                status=JobApplication.STATUS_COMPLETED
            )
        ]
        rated = set(
            Review.objects.filter(
                job=job,
                author=household,
                author_role=Review.ROLE_HOUSEHOLD,
                target_role=Review.ROLE_WORKER,
                is_system_generated=False,
            ).values_list("target_id", flat=True)
        )
        unrated = [worker for worker in workers if worker.id not in rated]
        if unrated:
            return {
                "kind": POST_BLOCK_RATE,
                "job": job,
                "message": f"Rate {_names(unrated)} for {job.title} before you post another job.",
            }
    return None
