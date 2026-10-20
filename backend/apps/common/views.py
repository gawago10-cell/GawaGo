import mimetypes

from django.db import transaction
from django.http import FileResponse
from django.utils import timezone
from django.shortcuts import get_object_or_404
from rest_framework import generics, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import UserProfile
from apps.accounts.serializers import UserProfileSerializer
from apps.common.audit import log_admin_action
from apps.common.models import AdminActionLog, VerificationRequest
from apps.common.pagination import paginated_response
from apps.common.permissions import IsPlatformAdmin, IsPlatformSuperAdmin, is_platform_admin
from apps.common.serializers import AdminActionLogSerializer, VerificationRequestCreateSerializer, VerificationRequestSerializer
from apps.notifications.models import Notification
from apps.notifications.services import create_notification, notify_admins


class VerificationRequestListCreateView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def get(self, request):
        requests = (
            VerificationRequest.objects.select_related("worker", "worker__profile")
            .filter(worker__is_staff=False)
            .order_by("-submitted_at")
        )
        if not is_platform_admin(request.user):
            profile = getattr(request.user, "profile", None)
            if not profile or profile.role not in {UserProfile.ROLE_WORKER, UserProfile.ROLE_HOUSEHOLD}:
                return Response({"detail": "Not allowed."}, status=status.HTTP_403_FORBIDDEN)
            requests = requests.filter(worker=request.user)
        return paginated_response(
            request,
            requests.order_by("-submitted_at", "-id"),
            VerificationRequestSerializer,
            context={"request": request},
        )

    def post(self, request):
        serializer = VerificationRequestCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        account = request.user
        profile = getattr(account, "profile", None)
        if account.is_staff or not profile or profile.role not in {UserProfile.ROLE_WORKER, UserProfile.ROLE_HOUSEHOLD}:
            return Response({"detail": "Only worker and household accounts can submit verification requests."}, status=status.HTTP_403_FORBIDDEN)

        with transaction.atomic():
            profile = UserProfile.objects.select_for_update().get(pk=profile.pk)
            active_request = (
                VerificationRequest.objects.filter(worker=account)
                .exclude(status=VerificationRequest.STATUS_REJECTED)
                .order_by("-submitted_at")
                .first()
            )
            if active_request or profile.verification_status == "verified":
                message = (
                    "Your account is already verified."
                    if profile.verification_status == "verified"
                    else "Your verification request is already under review."
                )
                return Response({"detail": message}, status=status.HTTP_409_CONFLICT)

            request_record = VerificationRequest.objects.create(
                worker=account,
                primary_id_type=serializer.validated_data["primary_id_type"],
                primary_id_name=serializer.validated_data["primary_id_name"],
                secondary_doc_name=serializer.validated_data["secondary_doc_name"],
                primary_id_file=serializer.validated_data["primary_id_file"],
                secondary_doc_file=serializer.validated_data["secondary_doc_file"],
                notes=serializer.validated_data.get("notes", ""),
            )
            if profile.verification_status != "pending":
                profile.verification_status = "pending"
                profile.save(update_fields=["verification_status"])
        notify_admins(
            title="New verification request",
            message=f"@{account.username} ({profile.role}) submitted an ID for verification. "
            "Review it in the Verification Queue.",
        )
        return Response(
            {
                "verification_request": VerificationRequestSerializer(request_record, context={"request": request}).data,
                "account": {
                    "id": account.id,
                    "username": account.username,
                    "email": account.email,
                    "first_name": account.first_name,
                    "last_name": account.last_name,
                    "display_name": account.get_full_name().strip() or account.username,
                    "is_staff": account.is_staff,
                    "profile": UserProfileSerializer(profile, context={"request": request}).data,
                },
                "worker": {
                    "id": account.id,
                    "username": account.username,
                    "email": account.email,
                    "first_name": account.first_name,
                    "last_name": account.last_name,
                    "display_name": account.get_full_name().strip() or account.username,
                    "is_staff": account.is_staff,
                    "profile": UserProfileSerializer(profile, context={"request": request}).data,
                },
            },
            status=status.HTTP_201_CREATED,
        )


class VerificationRequestReviewView(APIView):
    permission_classes = [IsPlatformAdmin]

    def post(self, request, pk):
        request_record = get_object_or_404(VerificationRequest.objects.select_related("worker", "worker__profile"), pk=pk)
        # A decided request is closed. Re-deciding one used to flip the
        # account's verification status each time, so an approved worker could
        # be quietly un-verified through a stale queue entry. A resubmission
        # creates a new request, which is what should be reviewed.
        if request_record.status != VerificationRequest.STATUS_PENDING:
            return Response(
                {
                    "detail": (
                        f"This request was already {request_record.get_status_display().lower()}. "
                        "Ask the applicant to resubmit if their documents changed."
                    )
                },
                status=status.HTTP_409_CONFLICT,
            )
        action = request.data.get("action")
        if action == "approve":
            request_record.status = VerificationRequest.STATUS_APPROVED
            request_record.review_note = "Approved by admin review."
            profile_status = "verified"
            notification_title = "Verification approved"
            notification_message = f"Your {request_record.worker.profile.get_role_display().lower()} account is now Verified."
        elif action == "reject":
            request_record.status = VerificationRequest.STATUS_REJECTED
            request_record.review_note = request.data.get("review_note", "Rejected by admin.")
            profile_status = "rejected"
            notification_title = "Verification rejected"
            notification_message = request_record.review_note
        else:
            return Response({"detail": "Action must be 'approve' or 'reject'."}, status=status.HTTP_400_BAD_REQUEST)
        request_record.reviewed_at = timezone.now()
        request_record.save(update_fields=["status", "review_note", "reviewed_at"])
        profile, _ = UserProfile.objects.get_or_create(user=request_record.worker, defaults={"role": UserProfile.ROLE_WORKER})
        profile.verification_status = profile_status
        profile.save(update_fields=["verification_status"])
        create_notification(
            recipient=request_record.worker,
            notification_type=Notification.TYPE_VERIFICATION,
            title=notification_title,
            message=notification_message,
        )
        log_admin_action(
            request.user,
            AdminActionLog.ACTION_VERIFICATION_APPROVED if action == "approve" else AdminActionLog.ACTION_VERIFICATION_REJECTED,
            target_label=request_record.worker.username,
            target_type="verification_request",
            target_id=request_record.id,
            detail=request_record.review_note,
        )
        request_data = VerificationRequestSerializer(request_record, context={"request": request}).data
        request_data["reviewed_by"] = request.user.get_full_name().strip() or request.user.username or "System Admin"
        return Response(
            {
                "verification_request": request_data,
                "account": {
                    "id": request_record.worker.id,
                    "username": request_record.worker.username,
                    "email": request_record.worker.email,
                    "first_name": request_record.worker.first_name,
                    "last_name": request_record.worker.last_name,
                    "display_name": request_record.worker.get_full_name().strip() or request_record.worker.username,
                    "is_staff": request_record.worker.is_staff,
                    "profile": UserProfileSerializer(profile, context={"request": request}).data,
                },
                "worker": {
                    "id": request_record.worker.id,
                    "username": request_record.worker.username,
                    "email": request_record.worker.email,
                    "first_name": request_record.worker.first_name,
                    "last_name": request_record.worker.last_name,
                    "display_name": request_record.worker.get_full_name().strip() or request_record.worker.username,
                    "is_staff": request_record.worker.is_staff,
                    "profile": UserProfileSerializer(profile, context={"request": request}).data,
                },
            }
        )


class VerificationRequestDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        request_record = get_object_or_404(VerificationRequest.objects.select_related("worker", "worker__profile"), pk=pk)
        if request_record.worker != request.user and not is_platform_admin(request.user):
            return Response({"detail": "Not allowed."}, status=status.HTTP_403_FORBIDDEN)
        return Response(
            {
                "verification_request": VerificationRequestSerializer(request_record, context={"request": request}).data,
                "worker": {
                    "id": request_record.worker.id,
                    "username": request_record.worker.username,
                    "email": request_record.worker.email,
                    "first_name": request_record.worker.first_name,
                    "last_name": request_record.worker.last_name,
                    "display_name": request_record.worker.get_full_name().strip() or request_record.worker.username,
                    "is_staff": request_record.worker.is_staff,
                    "profile": UserProfileSerializer(request_record.worker.profile, context={"request": request}).data if getattr(request_record.worker, "profile", None) else None,
                },
            }
        )


class VerificationRequestDocumentView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk, document_type):
        request_record = get_object_or_404(VerificationRequest.objects.select_related("worker"), pk=pk)
        if request_record.worker != request.user and not is_platform_admin(request.user):
            return Response({"detail": "Not allowed."}, status=status.HTTP_403_FORBIDDEN)
        if document_type == "primary":
            document = request_record.primary_id_file
        elif document_type == "secondary":
            document = request_record.secondary_doc_file
        else:
            return Response({"detail": "Document not found."}, status=status.HTTP_404_NOT_FOUND)
        if not document:
            return Response({"detail": "Document not found."}, status=status.HTTP_404_NOT_FOUND)
        # The type comes from the stored file, whose extension was validated
        # on upload -- never from the uploader-chosen display name, which
        # could claim .html and make the document render as a page.
        content_type = mimetypes.guess_type(document.name)[0] or "application/octet-stream"
        response = FileResponse(document.open("rb"), content_type=content_type)
        response["Content-Disposition"] = "inline"
        response["X-Content-Type-Options"] = "nosniff"
        response["Cache-Control"] = "private, no-store"
        return response


class AdminActionLogListView(generics.ListAPIView):
    """GET /api/common/admin-action-log/ -- the superadmin Audit Logs
    screen. Superuser-only, since it surfaces every admin's actions
    (account suspensions, complaint decisions, verification and
    certificate reviews, job edits/deletes made as an admin), not just
    the viewer's own.
    """

    permission_classes = [IsPlatformSuperAdmin]
    serializer_class = AdminActionLogSerializer
    queryset = AdminActionLog.objects.all()
