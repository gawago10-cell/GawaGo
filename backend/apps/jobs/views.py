from decimal import Decimal, InvalidOperation

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import transaction
from django.shortcuts import get_object_or_404
from pathlib import Path
from rest_framework import status, viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.jobs.models import JobApplication, JobImage, JobPosting
from apps.jobs.serializers import (
    JobApplicationCreateSerializer,
    JobApplicationSerializer,
    JobApplicationStatusSerializer,
    JobCreateSerializer,
    JobPostingSerializer,
    applicant_sort_key,
)
from apps.jobs.services import (
    HiringApplicationStateError,
    HiringCapacityReached,
    HiringJobStateError,
    HiringWorkerSuspendedError,
    HiringWorkerVerificationError,
    close_open_applications,
    complete_job,
    hire_application,
    record_application_status_event,
    record_job_status_event,
)
from apps.notifications.models import Notification
from apps.notifications.services import create_notification
from apps.accounts.models import UserProfile, currently_suspended_q
from apps.common.audit import log_admin_action
from apps.common.models import AdminActionLog
from apps.common.pagination import paginated_response
from apps.common.uploads import UploadRejected, validate_image_upload
from apps.jobs.statuses import get_job_stage, get_stage_label

# AGENTS.md allows up to five reference photos on a job; the API used to take
# as many as were sent.
MAX_JOB_IMAGES = 5
from apps.common.background import enqueue
from apps.matching.services import get_cached_road_route
from apps.matching.tasks import JOB_MATCH_TASK_TIMEOUT_SECONDS, run_job_match_notifications

User = get_user_model()


ALLOWED_JOB_STATUS_TRANSITIONS = {
    JobPosting.STATUS_OPEN: {JobPosting.STATUS_OPEN, JobPosting.STATUS_CANCELLED},
    JobPosting.STATUS_ASSIGNED: {
        JobPosting.STATUS_ASSIGNED,
        JobPosting.STATUS_COMPLETION_REQUESTED,
        JobPosting.STATUS_COMPLETED,
        JobPosting.STATUS_CANCELLED,
    },
    JobPosting.STATUS_COMPLETION_REQUESTED: {
        JobPosting.STATUS_COMPLETION_REQUESTED,
        JobPosting.STATUS_COMPLETED,
        JobPosting.STATUS_CANCELLED,
    },
    JobPosting.STATUS_COMPLETED: {JobPosting.STATUS_COMPLETED},
    JobPosting.STATUS_CANCELLED: {JobPosting.STATUS_CANCELLED},
}


def ensure_worker_profile(user, role_hint=""):
    profile = getattr(user, "profile", None)
    normalized_hint = str(role_hint or "").strip().lower()
    if not profile:
        return UserProfile.objects.create(user=user, role=UserProfile.ROLE_WORKER)
    if profile.role != UserProfile.ROLE_WORKER and normalized_hint == UserProfile.ROLE_WORKER:
        profile.role = UserProfile.ROLE_WORKER
        profile.save(update_fields=["role"])
    return profile


def ensure_household_profile(user, role_hint=""):
    profile = getattr(user, "profile", None)
    normalized_hint = str(role_hint or "").strip().lower()
    if profile and profile.role == UserProfile.ROLE_HOUSEHOLD:
        return profile
    if normalized_hint != UserProfile.ROLE_HOUSEHOLD:
        return None
    if not profile:
        return UserProfile.objects.create(user=user, role=UserProfile.ROLE_HOUSEHOLD)
    profile.role = UserProfile.ROLE_HOUSEHOLD
    profile.save(update_fields=["role"])
    return profile


def build_schedule_label(validated_data):
    schedule = validated_data.get("schedule", "").strip()
    if schedule:
        return schedule
    schedule_type = validated_data.get("schedule_type", "").strip() or "Scheduled"
    job_start_date = validated_data.get("job_start_date")
    return f"{schedule_type} starting {job_start_date.isoformat()}"


class JobViewSet(viewsets.ModelViewSet):
    queryset = JobPosting.objects.select_related("household").prefetch_related(
        "applications",
        "applications__worker",
        "applications__worker__profile",
        "images",
    ).order_by("-created_at")
    serializer_class = JobPostingSerializer

    def get_permissions(self):
        if self.action in ("list", "retrieve"):
            return [AllowAny()]
        return [IsAuthenticated()]

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        if self.action == "list":
            # A job list serializes every job and its applicants; resolving
            # each route live would be one outbound HTTP request per row.
            context["route_lookup"] = "cache_only"
        return context

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params
        if params.get("mine", "").lower() in {"1", "true", "yes"}:
            user = getattr(self.request, "user", None)
            profile = getattr(user, "profile", None)
            if not user or not user.is_authenticated:
                return queryset.none()
            if getattr(profile, "role", None) == UserProfile.ROLE_HOUSEHOLD:
                queryset = queryset.filter(household=user)
            elif getattr(profile, "role", None) == UserProfile.ROLE_WORKER:
                queryset = queryset.filter(applications__worker=user).distinct()
            elif not user.is_staff:
                return queryset.none()
        # A worker's own job history, by user id. Public like the rest of
        # list/retrieve: this is the employment record a household reads off
        # an applicant's profile before hiring. Without this filter the
        # `worker` parameter both clients already send was silently ignored,
        # so every completed job on the platform came back as if one worker
        # had done all of them.
        worker_id = params.get("worker")
        if worker_id:
            try:
                # One filter() call so both conditions apply to the same
                # application row: jobs the worker only applied to are not
                # part of their employment record.
                queryset = queryset.filter(
                    applications__worker_id=int(worker_id),
                    applications__status__in=[JobApplication.STATUS_HIRED, JobApplication.STATUS_COMPLETED],
                ).distinct()
            except (TypeError, ValueError):
                return queryset.none()
        else:
            # Browsing the open market: a suspended household's jobs are out
            # of it. Their own list (mine=true) and a worker's employment
            # history keep showing them.
            if not params.get("mine") and not getattr(self.request.user, "is_staff", False):
                queryset = queryset.exclude(currently_suspended_q("household__profile__"))
        if params.get("status"):
            queryset = queryset.filter(status=params["status"])
        if params.get("job_type"):
            queryset = queryset.filter(job_type__icontains=params["job_type"])
        if params.get("location"):
            queryset = queryset.filter(location_label__icontains=params["location"])
        if params.get("required_skill"):
            queryset = queryset.filter(required_skill__icontains=params["required_skill"])
        for param, lookup in (("min_rate", "service_rate__gte"), ("max_rate", "service_rate__lte")):
            if params.get(param):
                try:
                    queryset = queryset.filter(**{lookup: Decimal(params[param])})
                except (InvalidOperation, ValueError):
                    return queryset.none()
        return queryset

    def create(self, request, *args, **kwargs):
        serializer = JobCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        image_files = request.FILES.getlist("images")
        if len(image_files) > MAX_JOB_IMAGES:
            return Response(
                {"detail": f"Attach at most {MAX_JOB_IMAGES} reference photos."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        for image_file in image_files:
            try:
                validate_image_upload(image_file)
            except UploadRejected as rejected:
                return Response({"detail": str(rejected)}, status=status.HTTP_400_BAD_REQUEST)
        household = request.user
        auth_payload = request.auth if isinstance(request.auth, dict) else {}
        household_profile = ensure_household_profile(household, auth_payload.get("role", ""))
        if not household_profile:
            return Response({"detail": "Only households can create job postings."}, status=status.HTTP_403_FORBIDDEN)
        if household_profile.verification_status != "verified":
            return Response(
                {"detail": "Your household account must be verified before you can post a job."},
                status=status.HTTP_403_FORBIDDEN,
            )
        requested_status = serializer.validated_data.get("status", JobPosting.STATUS_OPEN)
        if requested_status != JobPosting.STATUS_OPEN:
            return Response({"detail": "New job postings must start as open."}, status=status.HTTP_400_BAD_REQUEST)
        data = serializer.validated_data
        # The same posting twice (a double tap, or a retry after a timeout the
        # server had actually finished) used to create a second job and notify
        # every matching worker again. An identical *open* posting is a
        # duplicate; the same job re-posted after the first one closed is not.
        if JobPosting.objects.filter(
            household=household,
            status=JobPosting.STATUS_OPEN,
            title=data["title"],
            job_type=data["job_type"],
            required_skill=data["required_skill"],
            schedule=build_schedule_label(data),
            location_label=data["location_label"],
            service_rate=data["service_rate"],
        ).exists():
            return Response(
                {"detail": "You already have an open job posting with these exact details."},
                status=status.HTTP_409_CONFLICT,
            )
        with transaction.atomic():
            job = self._create_job(household, serializer.validated_data, image_files)
            # Runs only after the job (and its images) commit, and never for a
            # rolled-back create. The pass itself -- scoring every worker and
            # a routing call each -- happens outside this request.
            if getattr(settings, "ENABLE_JOB_MATCH_NOTIFICATIONS", True):
                transaction.on_commit(
                    lambda job_id=job.id: enqueue(
                        run_job_match_notifications, job_id, timeout=JOB_MATCH_TASK_TIMEOUT_SECONDS
                    )
                )
        return Response(JobPostingSerializer(job, context={"request": request}).data, status=status.HTTP_201_CREATED)

    def _create_job(self, household, data, image_files):
        job = JobPosting.objects.create(
            household=household,
            title=data["title"],
            job_type=data["job_type"],
            required_skill=data["required_skill"],
            schedule=build_schedule_label(data),
            schedule_type=data.get("schedule_type", ""),
            description=data.get("description", ""),
            location_label=data["location_label"],
            latitude=data["latitude"],
            longitude=data["longitude"],
            service_rate=data["service_rate"],
            rate_type=data.get("rate_type", JobPosting.RATE_PER_DAY),
            worker_slots=data["worker_slots"],
            status=JobPosting.STATUS_OPEN,
            job_start_date=data.get("job_start_date"),
            job_end_date=data.get("job_end_date"),
            estimated_working_days=data.get("estimated_working_days"),
            max_distance_km=data.get("max_distance_km", 1.0),
            geographic_boundary=data.get("geographic_boundary", "1km"),
        )
        for index, image_file in enumerate(image_files):
            JobImage.objects.create(job=job, image=image_file, order=index)
        return job

    def perform_update(self, serializer):
        if serializer.instance.household != self.request.user and not self.request.user.is_staff:
            raise PermissionDenied("Only the job owner can update this posting.")
        requested_status = serializer.validated_data.get("status")
        actor = self.request.user
        acted_as_admin = actor.is_staff and serializer.instance.household_id != actor.id
        with transaction.atomic():
            # Lock the row and re-read the status inside the transaction.
            # Without this, concurrent requests all passed the transition
            # check against the same stale value, so one completion could
            # send several "Job completed" notifications and write duplicate
            # status-history rows.
            current_status = (
                JobPosting.objects.select_for_update()
                .values_list("status", flat=True)
                .get(pk=serializer.instance.pk)
            )
            should_complete = False
            if requested_status is not None:
                allowed_statuses = ALLOWED_JOB_STATUS_TRANSITIONS.get(current_status, {current_status})
                if requested_status not in allowed_statuses:
                    raise ValidationError(
                        {
                            "status": (
                                f"Cannot change job status from {current_status} to {requested_status}."
                            )
                        }
                    )
                should_complete = current_status != JobPosting.STATUS_COMPLETED and requested_status == JobPosting.STATUS_COMPLETED
                if should_complete and not serializer.instance.applications.filter(status=JobApplication.STATUS_HIRED).exists():
                    raise ValidationError({"status": "Only jobs with hired workers can be completed."})
                if should_complete and not actor.is_staff:
                    household_profile = getattr(actor, "profile", None)
                    if not household_profile or household_profile.verification_status != "verified":
                        raise PermissionDenied("Your household account must be verified before you can complete a job.")
            previous_status = current_status
            serializer.instance.status = current_status
            job = serializer.save()
            status_changed = previous_status != job.status
            if should_complete:
                complete_job(job, actor=actor, previous_status=previous_status)
            elif status_changed:
                record_job_status_event(job, previous_status, job.status, actor=actor)
        if status_changed and job.status == JobPosting.STATUS_CANCELLED:
            self._notify_cancellation(job, actor=actor)
            # Nobody stays "pending" on a job that no longer exists, the same
            # as when a job completes. Hired applications are kept as the
            # record of who was booked; their stage already reads Cancelled.
            close_open_applications(job, actor=actor, note="Closed automatically: job was cancelled.")
        if acted_as_admin and status_changed:
            self._notify_owner_of_admin_action(job, actor, job.status)

    def _notify_cancellation(self, job, actor=None):
        # Name whoever actually cancelled: an administrator acting on a
        # report used to be reported to the worker as the household.
        by_admin = actor is not None and actor.is_staff and actor.id != job.household_id
        who = "An administrator" if by_admin else job.household.username
        active = job.applications.select_related("worker").filter(
            status__in=[
                JobApplication.STATUS_PENDING,
                JobApplication.STATUS_HIRE_REQUESTED,
                JobApplication.STATUS_HIRED,
            ]
        )
        for application in active:
            create_notification(
                recipient=application.worker,
                notification_type=Notification.TYPE_REJECTION,
                title="Job cancelled",
                message=f"{who} cancelled {job.title}.",
                actor=actor or job.household,
                related_job_id=job.id,
                related_application_id=application.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                action_url=f"/worker/jobs/{job.id}",
            )

    def _notify_owner_of_admin_action(self, job, actor, new_status):
        """The household owns the posting, so it has to be told when an
        administrator changes or removes it."""
        create_notification(
            recipient=job.household,
            notification_type=Notification.TYPE_ACCOUNT_ACTIVITY,
            title="An administrator updated your job",
            message=f"An administrator set {job.title} to {get_stage_label(get_job_stage(new_status))}.",
            actor=actor,
            related_job_id=job.id,
            action_type=Notification.ACTION_JOB_DETAIL,
            action_url=f"/household/jobs/{job.id}",
        )
        log_admin_action(
            actor,
            AdminActionLog.ACTION_JOB_UPDATED,
            target_label=f"{job.title} ({job.household.username})",
            target_type="job",
            target_id=job.id,
            detail=f"-> {get_stage_label(get_job_stage(new_status))}",
        )

    def perform_destroy(self, instance):
        if instance.household != self.request.user and not self.request.user.is_staff:
            raise PermissionDenied("Only the job owner can delete this posting.")
        # Applications anchor chat, reviews, skill ratings and reports, and
        # cascade with the job; a job anyone applied to is cancelled instead.
        if instance.status != JobPosting.STATUS_OPEN or instance.applications.exists():
            raise ValidationError(
                {"detail": "Only an open job with no applicants can be deleted. Cancel this job instead."}
            )
        if instance.household_id != self.request.user.id:
            create_notification(
                recipient=instance.household,
                notification_type=Notification.TYPE_ACCOUNT_ACTIVITY,
                title="An administrator removed your job",
                message=f"An administrator removed your job posting {instance.title}.",
                actor=self.request.user,
            )
            log_admin_action(
                self.request.user,
                AdminActionLog.ACTION_JOB_DELETED,
                target_label=f"{instance.title} ({instance.household.username})",
                target_type="job",
                target_id=instance.id,
            )
        instance.delete()


class JobApplicationView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, job_id):
        serializer = JobApplicationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        job = get_object_or_404(JobPosting, pk=job_id)
        worker = request.user
        profile = getattr(worker, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can apply to jobs."}, status=status.HTTP_403_FORBIDDEN)
        if profile.verification_status != "verified":
            return Response({"detail": "Only verified workers can apply to jobs."}, status=status.HTTP_403_FORBIDDEN)
        hired_count = job.applications.filter(status=JobApplication.STATUS_HIRED).count()
        # A job needing several workers keeps accepting applications while it
        # still has openings. It flips to "assigned" on the first hire so the
        # hired worker can get on with the job, which used to shut the
        # remaining openings out entirely.
        accepting = job.status == JobPosting.STATUS_OPEN or (
            job.status == JobPosting.STATUS_ASSIGNED and hired_count < job.worker_slots
        )
        if not accepting:
            return Response({"detail": "Workers can only apply to open jobs."}, status=status.HTTP_400_BAD_REQUEST)
        if hired_count >= job.worker_slots:
            return Response(
                {"detail": "This job already has enough hired workers."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        household_profile = getattr(job.household, "profile", None)
        if household_profile and household_profile.refresh_block_status():
            return Response(
                {"detail": "This job is no longer accepting applications."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        application, created = JobApplication.objects.get_or_create(
            job=job,
            worker=worker,
            defaults={"note": serializer.validated_data.get("note", "")},
        )
        if not created:
            return Response({"detail": "Worker already applied."}, status=status.HTTP_400_BAD_REQUEST)
        create_notification(
            recipient=job.household,
            notification_type=Notification.TYPE_APPLICATION,
            title="New worker application",
            message=f"{worker.username} applied to {job.title}.",
            actor=worker,
            related_job_id=job.id,
            related_application_id=application.id,
            action_type=Notification.ACTION_JOB_DETAIL,
            action_url=f"/household/jobs/{job.id}/applications",
            requires_action=True,
        )
        return Response(JobApplicationSerializer(application, context=write_response_context(request)).data, status=status.HTTP_201_CREATED)


def write_response_context(request):
    """Serializer context for the application echoed back after a write:
    the request makes photo URLs absolute, and the route comes from the cache
    only, so the action never waits on the routing service (the clients
    re-read the job, which resolves it, right after)."""
    return {"request": request, "route_lookup": "cache_only"}


class JobApplicationListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        queryset = JobApplication.objects.select_related("job", "job__household", "worker").order_by("-applied_at")
        profile = getattr(request.user, "profile", None)
        job_id = request.query_params.get("job_id")
        status_filter = request.query_params.get("status")

        if job_id:
            if not str(job_id).isdigit():
                return Response({"detail": "job_id must be a number."}, status=status.HTTP_400_BAD_REQUEST)
            queryset = queryset.filter(job_id=job_id)
        if status_filter:
            queryset = queryset.filter(status=status_filter)

        if request.user.is_staff:
            visible_applications = queryset
        elif profile and profile.role == UserProfile.ROLE_HOUSEHOLD:
            visible_applications = queryset.filter(job__household=request.user)
        elif profile and profile.role == UserProfile.ROLE_WORKER:
            visible_applications = queryset.filter(worker=request.user)
        else:
            visible_applications = JobApplication.objects.none()

        ordered = visible_applications.order_by("-applied_at", "-id")
        reads_as_household = request.user.is_staff or (profile and profile.role == UserProfile.ROLE_HOUSEHOLD)
        if job_id and reads_as_household:
            # One job's applicants, read by its household (or staff): the same
            # order the job detail serves, so the two lists never disagree.
            def sort_key(application):
                worker_profile = getattr(application.worker, "profile", None)
                distance_km = (
                    get_cached_road_route(application.job, worker_profile).get("distance_km")
                    if worker_profile
                    else None
                )
                return applicant_sort_key(application, distance_km)

            ordered = sorted(ordered.select_related("worker__profile"), key=sort_key)
        return paginated_response(
            request,
            ordered,
            JobApplicationSerializer,
            context={"request": request, "route_lookup": "cache_only"},
        )


class JobApplicationStatusView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, pk):
        if not str(pk).isdigit():
            return Response({"detail": "Application not found."}, status=status.HTTP_404_NOT_FOUND)
        application = JobApplication.objects.select_related("job", "worker").filter(pk=pk).first()
        if not application:
            return Response({"detail": "Application not found."}, status=status.HTTP_404_NOT_FOUND)
        # Hiring is the household's own decision. Staff deliberately get no
        # bypass here: an administrator reviewing IDs has no business hiring
        # or rejecting on a job they did not post.
        if application.job.household != request.user:
            return Response({"detail": "Only the job owner can update application status."}, status=status.HTTP_403_FORBIDDEN)
        household_profile = getattr(request.user, "profile", None)
        if not household_profile or household_profile.verification_status != "verified":
            return Response(
                {"detail": "Your household account must be verified before you can manage job applications."},
                status=status.HTTP_403_FORBIDDEN,
            )
        serializer = JobApplicationStatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        requested_status = serializer.validated_data["status"]
        if application.job.status in {JobPosting.STATUS_COMPLETED, JobPosting.STATUS_CANCELLED}:
            return Response({"detail": "Applications cannot be updated for completed or cancelled jobs."}, status=status.HTTP_400_BAD_REQUEST)
        if application.status in {JobApplication.STATUS_HIRED, JobApplication.STATUS_REJECTED, JobApplication.STATUS_CLOSED}:
            return Response({"detail": "This application has already been finalized."}, status=status.HTTP_400_BAD_REQUEST)
        if requested_status not in {
            JobApplication.STATUS_HIRE_REQUESTED,
            JobApplication.STATUS_HIRED,
            JobApplication.STATUS_REJECTED,
        }:
            return Response(
                {"detail": "Application status can only be changed to hire requested, hired, or rejected."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if requested_status == JobApplication.STATUS_HIRED:
            if application.status != JobApplication.STATUS_PENDING:
                return Response(
                    {"detail": "Only pending worker applications can be hired directly."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            try:
                application = hire_application(
                    application.id, JobApplication.STATUS_PENDING, actor=request.user
                )
            except HiringCapacityReached:
                return Response({"detail": "This job already has enough hired workers."}, status=status.HTTP_400_BAD_REQUEST)
            except HiringWorkerVerificationError:
                return Response({"detail": "Only verified workers can be hired."}, status=status.HTTP_400_BAD_REQUEST)
            except HiringWorkerSuspendedError:
                return Response(
                    {"detail": "This worker's account is suspended and can't be hired right now."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            except HiringJobStateError:
                return Response({"detail": "Applications cannot be updated for completed or cancelled jobs."}, status=status.HTTP_400_BAD_REQUEST)
            except HiringApplicationStateError:
                return Response(
                    {"detail": "Only pending worker applications can be hired directly."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            create_notification(
                recipient=application.worker,
                notification_type=Notification.TYPE_ACCEPTED,
                title="Application accepted",
                message=f"Your application for {application.job.title} was accepted.",
                actor=application.job.household,
                related_job_id=application.job_id,
                related_application_id=application.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                action_url=f"/worker/jobs/{application.job_id}",
            )
            return Response(JobApplicationSerializer(application, context=write_response_context(request)).data)
        if requested_status == JobApplication.STATUS_HIRE_REQUESTED:
            worker_profile = getattr(application.worker, "profile", None)
            if not worker_profile or worker_profile.verification_status != "verified":
                return Response({"detail": "Only verified workers can receive hire requests."}, status=status.HTTP_400_BAD_REQUEST)
            hired_count = application.job.applications.filter(status=JobApplication.STATUS_HIRED).count()
            if hired_count >= application.job.worker_slots:
                return Response({"detail": "This job already has enough hired workers."}, status=status.HTTP_400_BAD_REQUEST)
        previous_status = application.status
        application.status = requested_status
        application.save(update_fields=["status", "updated_at"])
        record_application_status_event(
            application, previous_status, application.status, actor=request.user
        )
        if application.status == JobApplication.STATUS_HIRE_REQUESTED:
            create_notification(
                recipient=application.worker,
                notification_type=Notification.TYPE_HIRING,
                title="Hire request",
                message=(
                    f"{application.job.household.username} wants to hire you for {application.job.title}. "
                    "Please accept or reject this request."
                ),
                actor=application.job.household,
                related_job_id=application.job_id,
                related_application_id=application.id,
                action_type=Notification.ACTION_HIRE_REQUEST,
                action_url=f"/worker/jobs/{application.job_id}",
                requires_action=True,
            )
        elif application.status == JobApplication.STATUS_REJECTED:
            create_notification(
                recipient=application.worker,
                notification_type=Notification.TYPE_REJECTION,
                title="Application rejected",
                message=f"Your application for {application.job.title} was rejected.",
                actor=application.job.household,
                related_job_id=application.job_id,
                related_application_id=application.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                action_url=f"/worker/jobs/{application.job_id}",
            )
        return Response(JobApplicationSerializer(application, context=write_response_context(request)).data)


class JobHireRequestView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, job_id):
        job = get_object_or_404(JobPosting, pk=job_id)
        # Same rule as JobApplicationStatusView: the second door into hiring,
        # so it gets the same lock. Staff get no bypass on either.
        if job.household != request.user:
            return Response({"detail": "Only the job owner can send hire requests."}, status=status.HTTP_403_FORBIDDEN)
        household_profile = getattr(request.user, "profile", None)
        if not household_profile or household_profile.verification_status != "verified":
            return Response(
                {"detail": "Your household account must be verified before you can hire workers."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if job.status in {JobPosting.STATUS_COMPLETED, JobPosting.STATUS_CANCELLED}:
            return Response({"detail": "Hire requests cannot be sent for completed or cancelled jobs."}, status=status.HTTP_400_BAD_REQUEST)
        worker_id = request.data.get("worker_id")
        worker_username = request.data.get("worker_username")
        worker = None
        if worker_id and str(worker_id).isdigit():
            worker = User.objects.filter(pk=worker_id).first()
        if not worker and worker_username:
            worker = User.objects.filter(username=worker_username).first()
        if not worker:
            return Response({"detail": "Worker not found."}, status=status.HTTP_404_NOT_FOUND)
        worker_profile = getattr(worker, "profile", None)
        if not worker_profile or worker_profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only worker accounts can receive hire requests."}, status=status.HTTP_400_BAD_REQUEST)
        if worker_profile.verification_status != "verified":
            return Response({"detail": "Only verified workers can receive hire requests."}, status=status.HTTP_400_BAD_REQUEST)
        if worker_profile.refresh_block_status():
            return Response({"detail": "This worker is not available for hire."}, status=status.HTTP_400_BAD_REQUEST)
        hired_count = job.applications.filter(status=JobApplication.STATUS_HIRED).count()
        if hired_count >= job.worker_slots:
            return Response({"detail": "This job already has enough hired workers."}, status=status.HTTP_400_BAD_REQUEST)
        application, _ = JobApplication.objects.get_or_create(job=job, worker=worker)
        if application.status == JobApplication.STATUS_HIRED:
            return Response({"detail": "This worker is already hired for this job."}, status=status.HTTP_400_BAD_REQUEST)
        if application.status == JobApplication.STATUS_HIRE_REQUESTED:
            return Response({"detail": "A hire request was already sent to this worker."}, status=status.HTTP_400_BAD_REQUEST)
        if application.status in {JobApplication.STATUS_REJECTED, JobApplication.STATUS_CLOSED, JobApplication.STATUS_COMPLETED}:
            return Response({"detail": "This application can no longer receive a hire request."}, status=status.HTTP_400_BAD_REQUEST)
        previous_status = application.status
        application.status = JobApplication.STATUS_HIRE_REQUESTED
        application.save(update_fields=["status", "updated_at"])
        record_application_status_event(
            application, previous_status, application.status, actor=request.user
        )
        create_notification(
            recipient=worker,
            notification_type=Notification.TYPE_HIRING,
            title="Hire request",
            message=f"{job.household.username} wants to hire you for {job.title}. Please accept or reject this request.",
            actor=job.household,
            related_job_id=job.id,
            related_application_id=application.id,
            action_type=Notification.ACTION_HIRE_REQUEST,
            action_url=f"/worker/jobs/{job.id}",
            requires_action=True,
        )
        return Response(JobApplicationSerializer(application, context=write_response_context(request)).data, status=status.HTTP_201_CREATED)


class JobCompletionRequestView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, job_id):
        job = get_object_or_404(JobPosting.objects.select_related("household"), pk=job_id)
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can request job completion."}, status=status.HTTP_403_FORBIDDEN)
        if job.status not in {JobPosting.STATUS_ASSIGNED, JobPosting.STATUS_COMPLETION_REQUESTED}:
            return Response(
                {"detail": "Completion can only be requested for assigned jobs."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        application = job.applications.filter(worker=request.user, status=JobApplication.STATUS_HIRED).first()
        if not application:
            return Response(
                {"detail": "Only the hired worker can request completion for this job."},
                status=status.HTTP_403_FORBIDDEN,
            )

        note = str(request.data.get("note", "")).strip()
        if note:
            application.note = note
            application.save(update_fields=["note", "updated_at"])

        newly_requested = job.status != JobPosting.STATUS_COMPLETION_REQUESTED
        if newly_requested:
            previous_status = job.status
            job.status = JobPosting.STATUS_COMPLETION_REQUESTED
            job.save(update_fields=["status"])
            record_job_status_event(job, previous_status, job.status, actor=request.user)

        # Only on the move into "awaiting confirmation", or when the worker
        # adds a note worth passing on: repeating the request used to send the
        # household another notification and email every time.
        if newly_requested or note:
            worker_name = request.user.get_full_name().strip() or request.user.username
            message = f"{worker_name} marked {job.title} as done. Please confirm if the service was completed."
            if note:
                message = f"{message} Worker note: {note}"
            create_notification(
                recipient=job.household,
                notification_type=Notification.TYPE_COMPLETION,
                title="Worker requested completion",
                message=message,
                actor=request.user,
                related_job_id=job.id,
                related_application_id=application.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                action_url=f"/household/jobs/{job.id}/completion",
                requires_action=True,
            )
        return Response(JobPostingSerializer(job, context={"request": request}).data)


class JobApplicationDecisionView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, pk):
        application = JobApplication.objects.select_related("job", "job__household", "worker").filter(pk=pk).first()
        if not application:
            return Response({"detail": "Application not found."}, status=status.HTTP_404_NOT_FOUND)
        if application.worker != request.user:
            return Response({"detail": "Only the requested worker can respond to this hire request."}, status=status.HTTP_403_FORBIDDEN)
        if application.status != JobApplication.STATUS_HIRE_REQUESTED:
            return Response({"detail": "This hire request is no longer pending."}, status=status.HTTP_400_BAD_REQUEST)
        decision = str(request.data.get("decision", "")).strip().lower()
        if decision not in {"accept", "reject"}:
            return Response({"detail": "Decision must be accept or reject."}, status=status.HTTP_400_BAD_REQUEST)
        if application.job.status in {JobPosting.STATUS_COMPLETED, JobPosting.STATUS_CANCELLED}:
            return Response({"detail": "This job is no longer available."}, status=status.HTTP_400_BAD_REQUEST)
        if decision == "accept":
            try:
                application = hire_application(
                    application.id, JobApplication.STATUS_HIRE_REQUESTED, actor=request.user
                )
            except HiringCapacityReached:
                return Response({"detail": "This job already has enough hired workers."}, status=status.HTTP_400_BAD_REQUEST)
            except HiringWorkerVerificationError:
                return Response({"detail": "Only verified workers can be hired."}, status=status.HTTP_400_BAD_REQUEST)
            except HiringWorkerSuspendedError:
                return Response(
                    {"detail": "This worker's account is suspended and can't be hired right now."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            except HiringJobStateError:
                return Response({"detail": "This job is no longer available."}, status=status.HTTP_400_BAD_REQUEST)
            except HiringApplicationStateError:
                return Response({"detail": "This hire request is no longer pending."}, status=status.HTTP_400_BAD_REQUEST)
            create_notification(
                recipient=application.job.household,
                notification_type=Notification.TYPE_ACCEPTED,
                title="Hire request accepted",
                message=f"{application.worker.username} accepted your hire request for {application.job.title}.",
                actor=application.worker,
                related_job_id=application.job_id,
                related_application_id=application.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                action_url=f"/household/jobs/{application.job_id}",
            )
        else:
            previous_status = application.status
            application.status = JobApplication.STATUS_REJECTED
            application.save(update_fields=["status", "updated_at"])
            record_application_status_event(
                application, previous_status, application.status, actor=request.user
            )
            create_notification(
                recipient=application.job.household,
                notification_type=Notification.TYPE_REJECTION,
                title="Hire request rejected",
                message=f"{application.worker.username} rejected your hire request for {application.job.title}.",
                actor=application.worker,
                related_job_id=application.job_id,
                related_application_id=application.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                action_url=f"/household/jobs/{application.job_id}",
            )
        return Response(JobApplicationSerializer(application, context=write_response_context(request)).data)
