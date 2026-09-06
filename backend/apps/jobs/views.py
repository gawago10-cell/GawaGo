from django.contrib.auth import get_user_model
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
)
from apps.jobs.services import (
    HiringApplicationStateError,
    HiringCapacityReached,
    HiringJobStateError,
    HiringWorkerVerificationError,
    complete_job,
    hire_application,
)
from apps.notifications.models import Notification
from apps.notifications.services import create_notification
from apps.accounts.models import UserProfile

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
    preferred_date = validated_data.get("preferred_date")
    preferred_time = validated_data.get("preferred_time")
    return f"{schedule_type} on {preferred_date.isoformat()} at {preferred_time.strftime('%H:%M')}"


class JobViewSet(viewsets.ModelViewSet):
    queryset = JobPosting.objects.select_related("household").prefetch_related(
        "applications",
        "applications__worker",
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
        if params.get("status"):
            queryset = queryset.filter(status=params["status"])
        if params.get("job_type"):
            queryset = queryset.filter(job_type__icontains=params["job_type"])
        if params.get("location"):
            queryset = queryset.filter(location_label__icontains=params["location"])
        if params.get("required_skill"):
            queryset = queryset.filter(required_skill__icontains=params["required_skill"])
        if params.get("min_rate"):
            queryset = queryset.filter(service_rate__gte=params["min_rate"])
        if params.get("max_rate"):
            queryset = queryset.filter(service_rate__lte=params["max_rate"])
        return queryset

    def create(self, request, *args, **kwargs):
        serializer = JobCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        image_files = request.FILES.getlist("images")
        allowed_extensions = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif"}
        for image_file in image_files:
            if Path(image_file.name).suffix.lower() not in allowed_extensions:
                return Response(
                    {"detail": "Choose an image file for each reference attachment."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
        household = request.user
        auth_payload = request.auth if isinstance(request.auth, dict) else {}
        household_profile = ensure_household_profile(household, auth_payload.get("role", ""))
        if not household_profile:
            return Response({"detail": "Only households can create job postings."}, status=status.HTTP_403_FORBIDDEN)
        requested_status = serializer.validated_data.get("status", JobPosting.STATUS_OPEN)
        if requested_status != JobPosting.STATUS_OPEN:
            return Response({"detail": "New job postings must start as open."}, status=status.HTTP_400_BAD_REQUEST)
        job = JobPosting.objects.create(
            household=household,
            title=serializer.validated_data["title"],
            job_type=serializer.validated_data["job_type"],
            required_skill=serializer.validated_data["required_skill"],
            schedule=build_schedule_label(serializer.validated_data),
            schedule_type=serializer.validated_data.get("schedule_type", ""),
            preferred_date=serializer.validated_data.get("preferred_date"),
            preferred_time=serializer.validated_data.get("preferred_time"),
            description=serializer.validated_data.get("description", ""),
            location_label=serializer.validated_data["location_label"],
            latitude=serializer.validated_data["latitude"],
            longitude=serializer.validated_data["longitude"],
            service_rate=serializer.validated_data["service_rate"],
            worker_slots=serializer.validated_data["worker_slots"],
            status=JobPosting.STATUS_OPEN,
            job_start_date=serializer.validated_data.get("job_start_date"),
            job_end_date=serializer.validated_data.get("job_end_date"),
            estimated_working_days=serializer.validated_data.get("estimated_working_days"),
            max_distance_km=serializer.validated_data.get("max_distance_km", 1.0),
            geographic_boundary=serializer.validated_data.get("geographic_boundary", "1km"),
        )
        for index, image_file in enumerate(image_files):
            JobImage.objects.create(job=job, image=image_file, order=index)
        return Response(JobPostingSerializer(job, context={"request": request}).data, status=status.HTTP_201_CREATED)

    def perform_update(self, serializer):
        if serializer.instance.household != self.request.user and not self.request.user.is_staff:
            raise PermissionDenied("Only the job owner can update this posting.")
        requested_status = serializer.validated_data.get("status")
        should_complete = False
        if requested_status is not None:
            current_status = serializer.instance.status
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
        job = serializer.save()
        if should_complete:
            complete_job(job)

    def perform_destroy(self, instance):
        if instance.household != self.request.user and not self.request.user.is_staff:
            raise PermissionDenied("Only the job owner can delete this posting.")
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
        if job.status != JobPosting.STATUS_OPEN:
            return Response({"detail": "Workers can only apply to open jobs."}, status=status.HTTP_400_BAD_REQUEST)
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
        return Response(JobApplicationSerializer(application).data, status=status.HTTP_201_CREATED)


class JobApplicationListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        queryset = JobApplication.objects.select_related("job", "job__household", "worker").order_by("-applied_at")
        profile = getattr(request.user, "profile", None)
        job_id = request.query_params.get("job_id")
        status_filter = request.query_params.get("status")

        if job_id:
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

        return Response(JobApplicationSerializer(visible_applications, many=True, context={"request": request}).data)


class JobApplicationStatusView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, pk):
        if not str(pk).isdigit():
            return Response({"detail": "Application not found."}, status=status.HTTP_404_NOT_FOUND)
        application = JobApplication.objects.select_related("job", "worker").filter(pk=pk).first()
        if not application:
            return Response({"detail": "Application not found."}, status=status.HTTP_404_NOT_FOUND)
        if application.job.household != request.user and not request.user.is_staff:
            return Response({"detail": "Only the job owner can update application status."}, status=status.HTTP_403_FORBIDDEN)
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
                application = hire_application(application.id, JobApplication.STATUS_PENDING)
            except HiringCapacityReached:
                return Response({"detail": "This job already has enough hired workers."}, status=status.HTTP_400_BAD_REQUEST)
            except HiringWorkerVerificationError:
                return Response({"detail": "Only verified workers can be hired."}, status=status.HTTP_400_BAD_REQUEST)
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
            return Response(JobApplicationSerializer(application).data)
        if requested_status == JobApplication.STATUS_HIRE_REQUESTED:
            worker_profile = getattr(application.worker, "profile", None)
            if not worker_profile or worker_profile.verification_status != "verified":
                return Response({"detail": "Only verified workers can receive hire requests."}, status=status.HTTP_400_BAD_REQUEST)
            hired_count = application.job.applications.filter(status=JobApplication.STATUS_HIRED).count()
            if hired_count >= application.job.worker_slots:
                return Response({"detail": "This job already has enough hired workers."}, status=status.HTTP_400_BAD_REQUEST)
        application.status = requested_status
        application.save(update_fields=["status", "updated_at"])
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
        return Response(JobApplicationSerializer(application).data)


class JobHireRequestView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, job_id):
        job = get_object_or_404(JobPosting, pk=job_id)
        if job.household != request.user and not request.user.is_staff:
            return Response({"detail": "Only the job owner can send hire requests."}, status=status.HTTP_403_FORBIDDEN)
        if job.status in {JobPosting.STATUS_COMPLETED, JobPosting.STATUS_CANCELLED}:
            return Response({"detail": "Hire requests cannot be sent for completed or cancelled jobs."}, status=status.HTTP_400_BAD_REQUEST)
        worker_id = request.data.get("worker_id")
        worker_username = request.data.get("worker_username")
        worker = None
        if worker_id:
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
        application.status = JobApplication.STATUS_HIRE_REQUESTED
        application.save(update_fields=["status", "updated_at"])
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
        return Response(JobApplicationSerializer(application).data, status=status.HTTP_201_CREATED)


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

        if job.status != JobPosting.STATUS_COMPLETION_REQUESTED:
            job.status = JobPosting.STATUS_COMPLETION_REQUESTED
            job.save(update_fields=["status"])

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
                application = hire_application(application.id, JobApplication.STATUS_HIRE_REQUESTED)
            except HiringCapacityReached:
                return Response({"detail": "This job already has enough hired workers."}, status=status.HTTP_400_BAD_REQUEST)
            except HiringWorkerVerificationError:
                return Response({"detail": "Only verified workers can be hired."}, status=status.HTTP_400_BAD_REQUEST)
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
            application.status = JobApplication.STATUS_REJECTED
            application.save(update_fields=["status", "updated_at"])
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
        return Response(JobApplicationSerializer(application).data)
