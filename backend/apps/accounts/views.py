from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.mail import BadHeaderError
from django.db import transaction, models
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import (
    PasswordResetRequest,
    SignupVerificationRequest,
    UserProfile,
    WorkerAvailability,
    WorkerPortfolio,
    WorkerSkill,
    WorkerCertification,
    WorkerPortfolioItem,
    SkillRating,
    VerificationDocument,
)
from apps.accounts.serializers import (
    ForgotPasswordRequestSerializer,
    LoginSerializer,
    PasswordResetRequestSerializer,
    PublicUserProfileSerializer,
    RegisterSerializer,
    ProfileUpdateSerializer,
    ResetPasswordSerializer,
    SignupVerificationRequestSerializer,
    UserProfileSerializer,
    VerifyResetTokenSerializer,
    VerifySignupSerializer,
    WorkerAvailabilityBulkSerializer,
    WorkerAvailabilitySerializer,
    WorkerSkillSerializer,
    WorkerCertificationSerializer,
    WorkerPortfolioItemSerializer,
    SkillRatingSerializer,
    WorkerPortfolioSerializer,
)
from apps.notifications.models import Notification
from apps.notifications.services import create_notification
from apps.accounts.services import (
    create_password_reset_request,
    send_password_reset_email,
    validate_latest_reset_request,
)
from apps.common.authentication import create_jwt_token
from apps.common.permissions import is_platform_admin, is_platform_superadmin
from apps.reviews.services import assign_due_default_worker_ratings


def get_account_role(user, profile=None):
    if is_platform_superadmin(user):
        return "superadmin"
    if is_platform_admin(user):
        return "admin"
    return profile.role if profile else UserProfile.ROLE_WORKER


class UserProfileListView(generics.ListAPIView):
    permission_classes = [IsAuthenticated]
    queryset = UserProfile.objects.select_related("user").order_by("id")

    def get_queryset(self):
        assign_due_default_worker_ratings()
        return super().get_queryset()

    def get_serializer_class(self):
        if self.request.user.is_authenticated and self.request.user.is_staff:
            return UserProfileSerializer
        return PublicUserProfileSerializer

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context


class RegisterView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        username = data["username"].strip()
        email = data["email"].strip().lower()

        if User.objects.filter(username__iexact=username).exists():
            return Response({"detail": "Username already exists."}, status=status.HTTP_400_BAD_REQUEST)
        if User.objects.filter(email__iexact=email).exists():
            return Response({"detail": "Email already exists."}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            user = User.objects.create_user(
                username=username,
                email=email,
                password=data["password"],
                first_name=data.get("first_name", ""),
                last_name=data.get("last_name", ""),
            )
            profile = UserProfile.objects.create(
                user=user,
                role=data["role"],
                phone=data.get("phone", ""),
                bio=data.get("bio", ""),
                years_experience=data.get("years_experience", 0),
                skills=data.get("skills", []),
                hourly_rate=data.get("hourly_rate"),
                daily_rate=data.get("daily_rate"),
                location_label=data.get("location_label", ""),
                latitude=data.get("latitude"),
                longitude=data.get("longitude"),
            )
        return Response(
            {
                "detail": "Account created. You can now log in.",
                "user": {
                    "id": user.id,
                    "username": user.username,
                    "email": user.email,
                    "first_name": user.first_name,
                    "last_name": user.last_name,
                },
                "profile": UserProfileSerializer(profile, context={"request": request}).data,
            },
            status=status.HTTP_201_CREATED,
        )


class LoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        username = serializer.validated_data["username"].strip()
        password = serializer.validated_data["password"]
        matched_user = (
            User.objects.filter(username__iexact=username).first()
            or User.objects.filter(email__iexact=username).first()
        )
        if matched_user and not matched_user.is_active and matched_user.check_password(password):
            matched_user.is_active = True
            matched_user.save(update_fields=["is_active"])
        user = authenticate(
            request,
            username=matched_user.username if matched_user else username,
            password=password,
        )
        if not user:
            return Response({"detail": "Invalid username or password."}, status=status.HTTP_400_BAD_REQUEST)
        profile = UserProfile.objects.filter(user=user).first()
        account_role = get_account_role(user, profile)
        return Response(
            {
                "detail": "Login successful.",
                "access": create_jwt_token({"user_id": user.id, "username": user.username, "role": account_role}),
                "username": user.username,
                "email": user.email,
                "display_name": user.get_full_name() or user.username,
                "role": account_role,
                "is_staff": user.is_staff,
                "profile": UserProfileSerializer(profile, context={"request": request}).data if profile else None,
            }
        )


class VerifySignupView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = VerifySignupSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data["email"].strip().lower()
        token = serializer.validated_data["token"].strip()
        request_obj = SignupVerificationRequest.objects.filter(email=email).select_related("user").first()
        if not request_obj or not request_obj.verify_token(token):
            return Response({"detail": "Invalid or expired verification code."}, status=status.HTTP_400_BAD_REQUEST)
        request_obj.verified_at = request_obj.verified_at or timezone.now()
        request_obj.save(update_fields=["verified_at"])
        request_obj.user.is_active = True
        request_obj.user.save(update_fields=["is_active"])
        return Response({"detail": "Email verified and account activated."}, status=status.HTTP_200_OK)


class ForgotPasswordRequestView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = ForgotPasswordRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data["email"].strip().lower()
        user = User.objects.filter(email__iexact=email).first()
        if not user:
            return Response({"detail": "If the email exists, a reset code has been sent."}, status=status.HTTP_200_OK)

        reset_request, token = create_password_reset_request(user)
        try:
            send_password_reset_email(user, token)
        except (BadHeaderError, OSError, ValueError) as exc:
            reset_request.delete()
            return Response({"detail": f"Unable to send reset code: {exc}"}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        return Response({"detail": "Reset code sent.", "expires_at": reset_request.expires_at}, status=status.HTTP_200_OK)


class VerifyResetTokenView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = VerifyResetTokenSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data["email"].strip().lower()
        token = serializer.validated_data["token"].strip()
        reset_request = validate_latest_reset_request(email, token)
        if not reset_request:
            return Response({"detail": "Invalid or expired reset code."}, status=status.HTTP_400_BAD_REQUEST)
        return Response({"detail": "Code verified.", "expires_at": reset_request.expires_at}, status=status.HTTP_200_OK)


class ResetPasswordView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = ResetPasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data["email"].strip().lower()
        token = serializer.validated_data["token"].strip()
        new_password = serializer.validated_data["new_password"]

        reset_request = validate_latest_reset_request(email, token)
        if not reset_request:
            return Response({"detail": "Invalid or expired reset code."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            validate_password(new_password, user=reset_request.user)
        except ValidationError as exc:
            return Response({"detail": exc.messages[0]}, status=status.HTTP_400_BAD_REQUEST)

        reset_request.user.set_password(new_password)
        reset_request.user.save(update_fields=["password"])
        reset_request.used_at = reset_request.used_at or timezone.now()
        reset_request.save(update_fields=["used_at"])
        return Response({"detail": "Password reset successful."}, status=status.HTTP_200_OK)


class LogoutView(APIView):
    def post(self, request):
        if request.user.is_authenticated:
            request.session.flush()
        return Response({"detail": "Logged out."}, status=status.HTTP_200_OK)


class MeProfileView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def get(self, request):
        profile, _ = UserProfile.objects.get_or_create(user=request.user, defaults={"role": UserProfile.ROLE_WORKER})
        return Response(
            {
                "user": {
                    "id": request.user.id,
                    "username": request.user.username,
                    "email": request.user.email,
                    "first_name": request.user.first_name,
                    "last_name": request.user.last_name,
                },
                "profile": UserProfileSerializer(profile, context={"request": request}).data,
            }
        )

    def patch(self, request):
        user = request.user
        profile, _ = UserProfile.objects.get_or_create(user=user, defaults={"role": UserProfile.ROLE_WORKER})
        serializer = ProfileUpdateSerializer(
            data=request.data,
            partial=True,
            context={"profile": profile},
        )
        serializer.is_valid(raise_exception=True)

        if "first_name" in serializer.validated_data:
            user.first_name = serializer.validated_data["first_name"]
        if "last_name" in serializer.validated_data:
            user.last_name = serializer.validated_data["last_name"]
        if "email" in serializer.validated_data:
            user.email = serializer.validated_data["email"].strip().lower()
        user.save()

        for field in ["phone", "bio", "years_experience", "skills", "hourly_rate", "daily_rate", "location_label", "latitude", "longitude", "profile_photo"]:
            if field in serializer.validated_data:
                setattr(profile, field, serializer.validated_data[field])
        profile.save()
        create_notification(
            recipient=user,
            notification_type=Notification.TYPE_ACCOUNT_ACTIVITY,
            title="Profile updated",
            message="Your GawaGo account profile was updated. If you did not make this change, please reset your password or contact support.",
        )
        return Response({
            "detail": "Profile updated.",
            "user": {
                "id": user.id,
                "username": user.username,
                "email": user.email,
                "first_name": user.first_name,
                "last_name": user.last_name,
            },
            "profile": UserProfileSerializer(profile, context={"request": request}).data,
        })


class WorkerAvailabilityView(APIView):
    permission_classes = [IsAuthenticated]

    def get_worker_profile(self, request):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return None
        return profile

    def get(self, request):
        if not self.get_worker_profile(request):
            return Response({"detail": "Only workers can manage availability."}, status=status.HTTP_403_FORBIDDEN)
        windows = request.user.availability_windows.filter(is_available=True).order_by("date", "start_time")
        return Response(WorkerAvailabilitySerializer(windows, many=True).data)

    def put(self, request):
        if not self.get_worker_profile(request):
            return Response({"detail": "Only workers can manage availability."}, status=status.HTTP_403_FORBIDDEN)
        serializer = WorkerAvailabilityBulkSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            request.user.availability_windows.all().delete()
            windows = [
                WorkerAvailability(worker=request.user, **window)
                for window in serializer.validated_data["availability_windows"]
            ]
            WorkerAvailability.objects.bulk_create(windows)
        saved_windows = request.user.availability_windows.filter(is_available=True).order_by("date", "start_time")
        return Response(WorkerAvailabilitySerializer(saved_windows, many=True).data)


class WorkerPortfolioView(APIView):
    permission_classes = [AllowAny]
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def get(self, request, user_id=None):
        if user_id is None:
            if not request.user.is_authenticated:
                return Response({"detail": "Authentication required."}, status=status.HTTP_401_UNAUTHORIZED)
            user_id = request.user.id
        user = User.objects.filter(id=user_id).first()
        if not user:
            return Response({"detail": "User not found."}, status=status.HTTP_404_NOT_FOUND)
        portfolio, _ = WorkerPortfolio.objects.get_or_create(worker=user)
        return Response(WorkerPortfolioSerializer(portfolio, context={"request": request}).data)

    def patch(self, request):
        if not request.user.is_authenticated:
            return Response({"detail": "Authentication required."}, status=status.HTTP_401_UNAUTHORIZED)
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can manage portfolio."}, status=status.HTTP_403_FORBIDDEN)
        portfolio, _ = WorkerPortfolio.objects.get_or_create(worker=request.user)
        serializer = WorkerPortfolioSerializer(portfolio, data=request.data, partial=True, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class WorkerSkillView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can manage skills."}, status=status.HTTP_403_FORBIDDEN)
        serializer = WorkerSkillSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        skill = serializer.save(worker=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    def delete(self, request, skill_id):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can manage skills."}, status=status.HTTP_403_FORBIDDEN)
        skill = WorkerSkill.objects.filter(id=skill_id, worker=request.user).first()
        if not skill:
            return Response({"detail": "Skill not found."}, status=status.HTTP_404_NOT_FOUND)
        skill.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    def patch(self, request, skill_id):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can manage skills."}, status=status.HTTP_403_FORBIDDEN)
        skill = WorkerSkill.objects.filter(id=skill_id, worker=request.user).first()
        if not skill:
            return Response({"detail": "Skill not found."}, status=status.HTTP_404_NOT_FOUND)
        serializer = WorkerSkillSerializer(skill, data=request.data, partial=True, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class WorkerCertificationView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def post(self, request):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can manage certifications."}, status=status.HTTP_403_FORBIDDEN)
        serializer = WorkerCertificationSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save(worker=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    def delete(self, request, cert_id):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can manage certifications."}, status=status.HTTP_403_FORBIDDEN)
        cert = WorkerCertification.objects.filter(id=cert_id, worker=request.user).first()
        if not cert:
            return Response({"detail": "Certification not found."}, status=status.HTTP_404_NOT_FOUND)
        cert.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    def patch(self, request, cert_id):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can manage certifications."}, status=status.HTTP_403_FORBIDDEN)
        cert = WorkerCertification.objects.filter(id=cert_id, worker=request.user).first()
        if not cert:
            return Response({"detail": "Certification not found."}, status=status.HTTP_404_NOT_FOUND)
        serializer = WorkerCertificationSerializer(cert, data=request.data, partial=True, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class WorkerPortfolioItemView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def post(self, request):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can manage portfolio items."}, status=status.HTTP_403_FORBIDDEN)
        serializer = WorkerPortfolioItemSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save(worker=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    def delete(self, request, item_id):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can manage portfolio items."}, status=status.HTTP_403_FORBIDDEN)
        item = WorkerPortfolioItem.objects.filter(id=item_id, worker=request.user).first()
        if not item:
            return Response({"detail": "Portfolio item not found."}, status=status.HTTP_404_NOT_FOUND)
        item.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    def patch(self, request, item_id):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return Response({"detail": "Only workers can manage portfolio items."}, status=status.HTTP_403_FORBIDDEN)
        item = WorkerPortfolioItem.objects.filter(id=item_id, worker=request.user).first()
        if not item:
            return Response({"detail": "Portfolio item not found."}, status=status.HTTP_404_NOT_FOUND)
        serializer = WorkerPortfolioItemSerializer(item, data=request.data, partial=True, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)


class SkillRatingView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_HOUSEHOLD:
            return Response({"detail": "Only households can rate skills."}, status=status.HTTP_403_FORBIDDEN)
        serializer = SkillRatingSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save(household=request.user)
        skill_id = serializer.validated_data.get("skill").id
        skill = WorkerSkill.objects.get(id=skill_id)
        skill.rating_count = SkillRating.objects.filter(skill=skill).count()
        skill.average_rating = SkillRating.objects.filter(skill=skill).aggregate(models.Avg("rating"))["rating__avg"]
        skill.save()
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class CertificateVerificationAdminView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        if not (user.is_staff or user.is_superuser):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)

        status_filter = request.query_params.get("status", WorkerCertification.STATUS_PENDING)
        certs = WorkerCertification.objects.select_related("worker", "verified_by").filter(
            verification_status=status_filter
        ).order_by("-created_at")

        serializer = WorkerCertificationSerializer(certs, many=True, context={"request": request})
        return Response(serializer.data)

    def patch(self, request, cert_id):
        user = request.user
        if not (user.is_staff or user.is_superuser):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)

        cert = WorkerCertification.objects.filter(id=cert_id).first()
        if not cert:
            return Response({"detail": "Certificate not found."}, status=status.HTTP_404_NOT_FOUND)

        verification_status = request.data.get("verification_status")
        if verification_status not in [WorkerCertification.STATUS_APPROVED, WorkerCertification.STATUS_REJECTED]:
            return Response({"detail": "Invalid status."}, status=status.HTTP_400_BAD_REQUEST)

        cert.verification_status = verification_status
        cert.verified_by = user
        cert.verified_at = timezone.now()
        cert.verification_notes = request.data.get("verification_notes", "")

        if verification_status == WorkerCertification.STATUS_APPROVED:
            cert.is_verified = True

        cert.save()

        create_notification(
            recipient=cert.worker,
            notification_type=Notification.TYPE_VERIFICATION,
            title="Certificate Verified" if verification_status == WorkerCertification.STATUS_APPROVED else "Certificate Rejected",
            message=f"Your certificate '{cert.certificate_name}' has been {verification_status}.",
            actor=user,
        )

        serializer = WorkerCertificationSerializer(cert, context={"request": request})
        return Response(serializer.data)


class VerificationDocumentView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def post(self, request):
        data = request.data.copy()
        data["user"] = request.user.id

        serializer = VerificationDocumentSerializer(data=data, context={"request": request})
        if serializer.is_valid():
            doc = serializer.save()
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    def get(self, request):
        docs = VerificationDocument.objects.select_related("verified_by").filter(user=request.user)
        serializer = VerificationDocumentSerializer(docs, many=True, context={"request": request})
        return Response(serializer.data)

    def delete(self, request, doc_id):
        doc = VerificationDocument.objects.filter(id=doc_id, user=request.user).first()
        if not doc:
            return Response({"detail": "Document not found."}, status=status.HTTP_404_NOT_FOUND)
        doc.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class VerificationDocumentAdminView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        if not (user.is_staff or user.is_superuser):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)

        status_filter = request.query_params.get("status", VerificationDocument.STATUS_PENDING)
        docs = VerificationDocument.objects.select_related("user", "verified_by").filter(
            verification_status=status_filter
        ).order_by("-created_at")

        serializer = VerificationDocumentSerializer(docs, many=True, context={"request": request})
        return Response(serializer.data)

    def patch(self, request, doc_id):
        user = request.user
        if not (user.is_staff or user.is_superuser):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)

        doc = VerificationDocument.objects.filter(id=doc_id).first()
        if not doc:
            return Response({"detail": "Document not found."}, status=status.HTTP_404_NOT_FOUND)

        verification_status = request.data.get("verification_status")
        if verification_status not in [VerificationDocument.STATUS_APPROVED, VerificationDocument.STATUS_REJECTED]:
            return Response({"detail": "Invalid status."}, status=status.HTTP_400_BAD_REQUEST)

        doc.verification_status = verification_status
        doc.verified_by = user
        doc.verified_at = timezone.now()
        doc.verification_notes = request.data.get("verification_notes", "")
        doc.save()

        create_notification(
            recipient=doc.user,
            notification_type=Notification.TYPE_VERIFICATION,
            title="ID Verified" if verification_status == VerificationDocument.STATUS_APPROVED else "ID Verification Failed",
            message=f"Your {doc.get_id_type_display()} has been {verification_status}.",
            actor=user,
        )

        serializer = VerificationDocumentSerializer(doc, context={"request": request})
        return Response(serializer.data)
