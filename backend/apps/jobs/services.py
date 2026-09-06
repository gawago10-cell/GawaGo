from django.db import transaction
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.jobs.models import JobApplication, JobPosting
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


def hire_application(application_id: int, expected_status: str) -> JobApplication:
    with transaction.atomic():
        application_job_id = JobApplication.objects.only("job_id").get(pk=application_id).job_id
        job = JobPosting.objects.select_for_update().get(pk=application_job_id)
        application = (
            JobApplication.objects.select_for_update()
            .select_related("worker", "worker__profile", "job", "job__household")
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

        application.status = JobApplication.STATUS_HIRED
        application.save(update_fields=["status", "updated_at"])
        job.status = JobPosting.STATUS_ASSIGNED
        job.save(update_fields=["status"])

        if hired_count + 1 >= job.worker_slots:
            job.applications.filter(
                status__in=[JobApplication.STATUS_PENDING, JobApplication.STATUS_HIRE_REQUESTED]
            ).exclude(pk=application.pk).update(status=JobApplication.STATUS_CLOSED)

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


def complete_job(job: JobPosting) -> JobPosting:
    if job.status != JobPosting.STATUS_COMPLETED:
        job.status = JobPosting.STATUS_COMPLETED
    if job.completed_at is None:
        job.completed_at = timezone.now()
    job.save(update_fields=["status", "completed_at"])

    hired_applications = list(
        job.applications.select_related("worker").filter(status=JobApplication.STATUS_HIRED)
    )
    for application in hired_applications:
        application.status = JobApplication.STATUS_COMPLETED
        application.save(update_fields=["status", "updated_at"])
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
