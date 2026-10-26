import mimetypes

from django.http import FileResponse, Http404
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import UserProfile
from apps.accounts.services import SuspensionValidationError, apply_account_suspension, parse_blocked_flag
from apps.complaints.models import Complaint, ComplaintEvidence
from apps.complaints.serializers import ComplaintAdminSerializer, ComplaintSerializer
from apps.common.audit import log_admin_action
from apps.common.models import AdminActionLog
from apps.common.pagination import paginated_response
from apps.common.permissions import IsPlatformSuperAdmin, is_platform_superadmin
from apps.common.uploads import UploadRejected, validate_image_upload
from apps.jobs.models import JobApplication, JobPosting
from apps.notifications.models import Notification
from apps.notifications.services import create_notification, notify_admins

MAX_EVIDENCE_IMAGES = 5

# Submitted -> Under Review -> Resolved/Closed (AGENTS.md II.D), forward
# only. Any transition used to be accepted, so a resolved report could be
# pushed back to submitted and a closed one reopened, re-notifying the filer
# that their report had "been updated" each time. A report is also never
# settled without first being marked Under Review, so the filer always sees
# it was looked at before it was decided.
ALLOWED_COMPLAINT_TRANSITIONS = {
    Complaint.STATUS_SUBMITTED: {Complaint.STATUS_UNDER_REVIEW},
    Complaint.STATUS_UNDER_REVIEW: {Complaint.STATUS_RESOLVED, Complaint.STATUS_CLOSED},
    Complaint.STATUS_RESOLVED: {Complaint.STATUS_CLOSED},
    Complaint.STATUS_CLOSED: set(),
}


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
        job = JobPosting.objects.filter(pk=job_id).first() if str(job_id).isdigit() else None
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
            try:
                respondent_id = int(respondent_id)
            except (TypeError, ValueError):
                return Response(
                    {"detail": "Select the worker this report is about."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if not JobApplication.objects.filter(job=job, worker_id=respondent_id).exists():
                return Response(
                    {"detail": "That worker has no application on this job."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
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
            try:
                validate_image_upload(image_file)
            except UploadRejected as rejected:
                return Response({"detail": str(rejected)}, status=status.HTTP_400_BAD_REQUEST)

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
        # No names in the alert: the report stays confidential, and only the
        # superadmins who can open the queue are told it exists.
        notify_admins(
            title="New report to review",
            message=f"A new {complaint.get_complaint_type_display().lower()} report was filed. "
            "Review it in Reported Issues.",
            superadmins_only=True,
        )
        return Response(
            ComplaintSerializer(complaint, context={"request": request}).data,
            status=status.HTTP_201_CREATED,
        )


def filed_by(user):
    """The only complaints a household/worker may see: ones they filed.

    A report stays confidential from the person it names -- they must not be
    able to tell it exists, so every non-admin read goes through this and a
    respondent gets exactly what an unrelated user gets (nothing / 404)."""
    return Complaint.objects.select_related("complainant", "respondent", "job").prefetch_related(
        "evidence"
    ).filter(complainant=user)


class ComplaintListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        queryset = filed_by(request.user)
        status_filter = request.query_params.get("status")
        if status_filter:
            queryset = queryset.filter(status=status_filter)
        return paginated_response(request, queryset, ComplaintSerializer, context={"request": request})


class ComplaintDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        complaint = get_object_or_404(filed_by(request.user), pk=pk)
        return Response(ComplaintSerializer(complaint, context={"request": request}).data)


class ComplaintEvidenceView(APIView):
    """GET /api/complaints/<pk>/evidence/<evidence_id>/ -- streams one
    evidence photo to the complainant or a superadmin (the only roles that
    can see the complaint itself). Everyone else, including the respondent,
    gets a 404 so the response does not confirm the report exists."""

    permission_classes = [IsAuthenticated]

    def get(self, request, pk, evidence_id):
        complaints = Complaint.objects.all() if is_platform_superadmin(request.user) else filed_by(request.user)
        evidence = get_object_or_404(
            ComplaintEvidence.objects.filter(complaint__in=complaints), pk=evidence_id, complaint_id=pk
        )
        try:
            file = evidence.image.open("rb")
        except FileNotFoundError:
            raise Http404("Evidence file is missing.")
        content_type = mimetypes.guess_type(evidence.image.name)[0] or "application/octet-stream"
        response = FileResponse(file, content_type=content_type)
        response["Content-Disposition"] = "inline"
        response["X-Content-Type-Options"] = "nosniff"
        response["Cache-Control"] = "private, no-store"
        return response


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

        return paginated_response(request, queryset, ComplaintAdminSerializer, context={"request": request})


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
            allowed = ALLOWED_COMPLAINT_TRANSITIONS.get(complaint.status, set())
            if new_status != complaint.status and new_status not in allowed:
                return Response(
                    {
                        "detail": (
                            f"A report cannot move from {complaint.get_status_display()} to "
                            f"{dict(Complaint.STATUS_CHOICES)[new_status]}."
                        )
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            status_changed = new_status != complaint.status
            # Closing a report is the filer's answer, so it has to say
            # something: this used to accept a resolution of None.
            if status_changed and new_status in {Complaint.STATUS_RESOLVED, Complaint.STATUS_CLOSED}:
                resolution = request.data.get("resolution", complaint.resolution)
                if not str(resolution or "").strip():
                    return Response(
                        {"resolution": "Add a resolution note the filer can read."},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
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
        if status_changed and complaint.complainant_id:
            create_notification(
                recipient=complaint.complainant,
                notification_type=Notification.TYPE_ACCOUNT_ACTIVITY,
                title="Your report has been updated",
                message=f"Your {complaint.get_complaint_type_display().lower()} report is now: "
                f"{complaint.get_status_display()}.",
            )
        if status_changed:
            log_admin_action(
                request.user,
                AdminActionLog.ACTION_COMPLAINT_STATUS_CHANGED,
                target_label=f"Report #{complaint.id} ({complaint.get_complaint_type_display()})",
                target_type="complaint",
                target_id=complaint.id,
                detail=f"-> {complaint.get_status_display()}",
            )

        return Response(ComplaintAdminSerializer(complaint, context={"request": request}).data)


class ComplaintRespondentBlockAdminView(APIView):
    """POST /api/complaints/admin/<pk>/block/ -- suspend (timed or permanent)
    or restore the account a report was filed against, straight from the
    review queue. Works the same regardless of whether the respondent is a
    worker or a household -- the view only ever looks at complaint.respondent.

    Sets UserProfile.is_blocked rather than User.is_active on purpose: a block
    carries a reason and an optional end date shown to the user, which
    is_active can't. A block takes effect on the next request because
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

        blocked = parse_blocked_flag(request.data.get("blocked", True))
        reason = request.data.get("reason", "")
        try:
            apply_account_suspension(
                profile,
                blocked=blocked,
                reason=reason,
                duration_days=request.data.get("duration_days"),
            )
        except SuspensionValidationError as error:
            return Response({"detail": str(error)}, status=status.HTTP_400_BAD_REQUEST)

        log_admin_action(
            request.user,
            AdminActionLog.ACTION_USER_SUSPENDED if blocked else AdminActionLog.ACTION_USER_RESTORED,
            target_label=complaint.respondent.username,
            target_type="user",
            target_id=complaint.respondent_id,
            detail=f"{reason} (from report #{complaint.id})" if blocked else f"from report #{complaint.id}",
        )

        return Response(ComplaintAdminSerializer(complaint, context={"request": request}).data)
