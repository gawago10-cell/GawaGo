from pathlib import Path

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import UserProfile
from apps.accounts.services import SuspensionValidationError, apply_account_suspension
from apps.complaints.models import Complaint, ComplaintEvidence
from apps.complaints.serializers import ComplaintAdminSerializer, ComplaintSerializer
from apps.common.permissions import IsPlatformSuperAdmin
from apps.jobs.models import JobApplication, JobPosting
from apps.notifications.models import Notification
from apps.notifications.services import create_notification

MAX_EVIDENCE_IMAGES = 5
ALLOWED_EVIDENCE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif"}


class ComplaintCreateView(APIView):
    """POST /api/complaints/create/

    Every report must be tied to a job the filer actually has a stake in --
    the job's household, or a worker who applied to it, at ANY job status
    (not just completed). That keeps every report traceable to a specific
    job/worker/household pair rather than an unverifiable free-floating
    accusation, while still letting a live concern be reported before the
    job finishes.

    The respondent is derived here, never accepted from the request body:
    a household names which of the job's applicants the report is about,
    and a worker's report always targets that job's household.
    """

    permission_classes = [IsAuthenticated]
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def post(self, request):
        job_id = request.data.get("job")
        if not job_id:
            return Response(
                {"detail": "A job is required to file a report."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        job = JobPosting.objects.filter(pk=job_id).first()
        if not job:
            return Response(
                {"detail": "Job posting not found."}, status=status.HTTP_404_NOT_FOUND
            )

        user = request.user
        if job.household_id == user.id:
            respondent_id = request.data.get("respondent")
            if not respondent_id:
                return Response(
                    {"detail": "Select the worker this report is about."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if not JobApplication.objects.filter(job=job, worker_id=respondent_id).exists():
                return Response(
                    {"detail": "That worker has no application on this job."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            respondent_id = int(respondent_id)
        elif JobApplication.objects.filter(job=job, worker=user).exists():
            respondent_id = job.household_id
        else:
            return Response(
                {"detail": "You can only report a job you posted or applied to."},
                status=status.HTTP_403_FORBIDDEN,
            )

        image_files = request.FILES.getlist("evidence")
        if len(image_files) > MAX_EVIDENCE_IMAGES:
            return Response(
                {"detail": f"Attach at most {MAX_EVIDENCE_IMAGES} photos."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        for image_file in image_files:
            if Path(image_file.name).suffix.lower() not in ALLOWED_EVIDENCE_EXTENSIONS:
                return Response(
                    {"detail": "Evidence must be an image file (JPG, PNG, WEBP, HEIC)."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        serializer = ComplaintSerializer(
            data={
                "job": job.id,
                "complaint_type": request.data.get("complaint_type"),
                "description": request.data.get("description"),
            }
        )
        serializer.is_valid(raise_exception=True)
        complaint = serializer.save(complainant=user, respondent_id=respondent_id)
        for index, image_file in enumerate(image_files):
            ComplaintEvidence.objects.create(complaint=complaint, image=image_file, order=index)
        return Response(
            ComplaintSerializer(complaint, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )


class ComplaintListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        queryset = Complaint.objects.select_related("complainant", "respondent", "job").filter(
            complainant=user
        ) | Complaint.objects.select_related("complainant", "respondent", "job").filter(respondent=user)
        queryset = queryset.distinct()

        status_filter = request.query_params.get("status")
        if status_filter:
            queryset = queryset.filter(status=status_filter)

        return Response(ComplaintSerializer(queryset, many=True, context={"request": request}).data)


class ComplaintDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        complaint = get_object_or_404(Complaint, pk=pk)
        if complaint.complainant != request.user and complaint.respondent != request.user:
            return Response({"error": "Permission denied"}, status=status.HTTP_403_FORBIDDEN)
        return Response(ComplaintSerializer(complaint, context={"request": request}).data)


class ComplaintListAdminView(APIView):
    permission_classes = [IsAuthenticated, IsPlatformSuperAdmin]

    def get(self, request):
        queryset = Complaint.objects.select_related(
            "complainant__profile", "respondent__profile", "job"
        ).all()

        status_filter = request.query_params.get("status")
        if status_filter:
            queryset = queryset.filter(status=status_filter)

        complaint_type_filter = request.query_params.get("type")
        if complaint_type_filter:
            queryset = queryset.filter(complaint_type=complaint_type_filter)

        return Response(ComplaintAdminSerializer(queryset, many=True, context={"request": request}).data)


class ComplaintUpdateAdminView(APIView):
    permission_classes = [IsAuthenticated, IsPlatformSuperAdmin]

    def patch(self, request, pk):
        complaint = get_object_or_404(Complaint, pk=pk)

        new_status = request.data.get("status")
        if new_status is not None:
            valid_statuses = {choice for choice, _label in Complaint.STATUS_CHOICES}
            if new_status not in valid_statuses:
                return Response(
                    {"detail": f"Invalid status. Choose one of: {', '.join(sorted(valid_statuses))}."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            status_changed = new_status != complaint.status
            complaint.status = new_status
        else:
            status_changed = False

        if "resolution" in request.data:
            complaint.resolution = request.data["resolution"]

        if "admin_notes" in request.data:
            complaint.admin_notes = request.data["admin_notes"]

        complaint.save()

        # Tell the filer their report moved, but not the respondent -- the
        # complaint stays confidential until admin resolves it, so the
        # person it was filed about is never notified a report exists.
        if status_changed:
            create_notification(
                recipient=complaint.complainant,
                notification_type=Notification.TYPE_ACCOUNT_ACTIVITY,
                title="Your report has been updated",
                message=f"Your {complaint.get_complaint_type_display().lower()} report is now: "
                f"{complaint.get_status_display()}.",
            )

        return Response(ComplaintAdminSerializer(complaint, context={"request": request}).data)


class ComplaintRespondentBlockAdminView(APIView):
    """POST /api/complaints/admin/<pk>/block/ -- suspend (timed or permanent)
    or restore the account a report was filed against, straight from the
    review queue. Works the same regardless of whether the respondent is a
    worker or a household -- the view only ever looks at complaint.respondent.

    Sets UserProfile.is_blocked rather than User.is_active on purpose: login
    reactivates inactive accounts that supply the right password, so is_active
    would be silently undone. A block takes effect on the next request because
    JWTAuthentication checks it per-request, not just at login.

    Body:
      blocked (bool, default True) -- False restores the account.
      reason (str) -- shown to the user, only stored when blocking.
      duration_days (int, optional) -- 3 or 7 for a timed suspension that
        lifts itself automatically; omitted/null means a permanent block.
    """

    permission_classes = [IsAuthenticated, IsPlatformSuperAdmin]

    def post(self, request, pk):
        complaint = get_object_or_404(Complaint, pk=pk)
        if not complaint.respondent_id:
            return Response(
                {"detail": "This report has no respondent to block."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if complaint.respondent.is_staff or complaint.respondent.is_superuser:
            return Response(
                {"detail": "Admin accounts cannot be blocked from the report queue."},
                status=status.HTTP_403_FORBIDDEN,
            )

        profile = UserProfile.objects.filter(user=complaint.respondent).first()
        if not profile:
            return Response(
                {"detail": "That account has no profile to block."},
                status=status.HTTP_404_NOT_FOUND,
            )

        try:
            apply_account_suspension(
                profile,
                blocked=request.data.get("blocked", True),
                reason=request.data.get("reason", ""),
                duration_days=request.data.get("duration_days"),
            )
        except SuspensionValidationError as error:
            return Response({"detail": str(error)}, status=status.HTTP_400_BAD_REQUEST)

        return Response(ComplaintAdminSerializer(complaint, context={"request": request}).data)
