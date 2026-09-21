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

        hired_count = job.applications.filter(status=JobApplication.STATUS_HIRED).exclude(
            pk=application.pk
        ).count()
        if hired_count >= job.worker_slots:
            raise HiringCapacityReached

        previous_application_status = application.status
        previous_job_status = job.status

        application.status = JobApplication.STATUS_HIRED
        application.save(update_fields=["status", "updated_at"])
        job.status = JobPosting.STATUS_ASSIGNED
        job.save(update_fields=["status"])

        record_application_status_event(
            application, previous_application_status, application.status, actor=actor
        )
        record_job_status_event(job, previous_job_status, job.status, actor=actor)

        if hired_count + 1 >= job.worker_slots:
            crowded_out = list(
                job.applications.filter(
                    status__in=[JobApplication.STATUS_PENDING, JobApplication.STATUS_HIRE_REQUESTED]
                ).exclude(pk=application.pk)
            )
            for other in crowded_out:
                previous_status = other.status
                other.status = JobApplication.STATUS_CLOSED
                other.save(update_fields=["status", "updated_at"])
                record_application_status_event(
                    other,
                    previous_status,
                    other.status,
                    actor=actor,
                    note="Closed automatically: job reached its worker limit.",
                )

    return application


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
