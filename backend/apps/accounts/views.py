import mimetypes

from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.core.cache import cache
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.mail import BadHeaderError
from django.db import IntegrityError, transaction, models
from django.http import FileResponse, Http404
from django.utils import timezone
from rest_framework import exceptions, generics, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
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
)
from apps.accounts.serializers import (
    MAX_WORKER_SKILLS,
    AdminAccountCreateSerializer,
    AdminAccountSerializer,
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
from apps.common.audit import log_admin_action
from apps.common.models import AdminActionLog
from apps.common.pagination import paginated_response
from apps.jobs.models import JobApplication, JobPosting
from apps.notifications.models import Notification
from apps.notifications.services import create_notification, notify_admins
from apps.accounts.services import (
    SuspensionValidationError,
    apply_account_suspension,
    create_password_reset_request,
    ensure_portfolio_skills,
    parse_blocked_flag,
    skill_key,
    send_password_reset_email,
    validate_latest_reset_request,
)
from apps.common.authentication import create_jwt_token, decode_jwt_token, revoke_token
from apps.common.permissions import IsPlatformAdmin, IsPlatformSuperAdmin, is_platform_admin, is_platform_superadmin
from apps.reviews.services import assign_due_default_worker_ratings_on_read


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
        assign_due_default_worker_ratings_on_read()
        queryset = super().get_queryset()
        if not self.request.user.is_staff:
            # A suspended account is out of the marketplace, and staff
            # accounts are not browsable by members.
            queryset = queryset.not_suspended().filter(user__is_staff=False)
        return queryset

    def get_serializer_class(self):
        if self.request.user.is_authenticated and self.request.user.is_staff:
            return UserProfileSerializer
        return PublicUserProfileSerializer

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["request"] = self.request
        return context


class UserAccountBlockAdminView(APIView):
    """POST /api/accounts/profiles/<username>/block/ -- suspend (timed or
    permanent) or restore any household or worker account, for the User
    Management screen. Shares its logic with the complaint-review "block
    this respondent" action (apps.accounts.services.apply_account_suspension)
    so the two stay in sync, but targets a user directly instead of going
    through a complaint record.

    Body:
      blocked (bool, default True) -- False restores the account.
      reason (str) -- shown to the user, only stored when blocking.
      duration_days (int, optional) -- 3 or 7 for a timed suspension that
        lifts itself automatically; omitted/null means a permanent block.
    """

    permission_classes = [IsAuthenticated, IsPlatformSuperAdmin]

    def post(self, request, username):
        target_user = User.objects.filter(username=username).first()
        if not target_user:
            return Response({"detail": "User not found."}, status=status.HTTP_404_NOT_FOUND)
        if target_user.is_staff or target_user.is_superuser:
            return Response(
                {"detail": "Admin accounts cannot be blocked from User Management."},
                status=status.HTTP_403_FORBIDDEN,
            )

        profile = UserProfile.objects.filter(user=target_user).first()
        if not profile:
            return Response({"detail": "That account has no profile to block."}, status=status.HTTP_404_NOT_FOUND)

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
            target_label=target_user.username,
            target_type="user",
            target_id=target_user.id,
            detail=reason if blocked else "",
        )

        serializer_class = UserProfileSerializer if request.user.is_staff else PublicUserProfileSerializer
        return Response(serializer_class(profile, context={"request": request}).data)


class AdminAccountListCreateView(APIView):
    """GET/POST /api/accounts/admin/admins/ -- the superadmin "Admin
    Management" screen.

    Only staff accounts appear here; households and workers are managed from
    User Management instead. Created accounts are always plain staff admins
    (is_staff, never is_superuser): minting another full-control account from
    a web form is not something this screen should be able to do.
    """

    permission_classes = [IsAuthenticated, IsPlatformSuperAdmin]

    def get(self, request):
        # Superusers first so the owner account heads the table, then by name.
        admins = User.objects.filter(is_staff=True).order_by("-is_superuser", "username")
        return Response(AdminAccountSerializer(admins, many=True).data)

    def post(self, request):
        serializer = AdminAccountCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        # The uniqueness checks above race with a concurrent signup; the
        # unique indexes on username/email are the real guard, and this turns
        # hitting one into a validation error rather than a 500.
        try:
            with transaction.atomic():
                admin_user = User.objects.create_user(
                    username=data["username"],
                    email=data["email"],
                    password=data["password"],
                    first_name=data.get("first_name", ""),
                    last_name=data.get("last_name", ""),
                    is_staff=True,
                )
        except IntegrityError:
            return Response(
                {"detail": "That username or email was just taken. Please try again."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        log_admin_action(
            request.user,
            AdminActionLog.ACTION_ADMIN_CREATED,
            target_label=admin_user.username,
            target_type="admin",
            target_id=admin_user.id,
        )
        return Response(AdminAccountSerializer(admin_user).data, status=status.HTTP_201_CREATED)


class AdminAccountDetailView(APIView):
    """PATCH /api/accounts/admin/admins/<username>/ -- activate or deactivate
    one staff admin.

    Deactivating is preferred over deleting: it is reversible, it keeps the
    account's audit-log history attributable, and it takes effect on any
    session already signed in because JWTAuthentication only resolves
    is_active users.
    """

    permission_classes = [IsAuthenticated, IsPlatformSuperAdmin]

    def patch(self, request, username):
        target = User.objects.filter(username=username, is_staff=True).first()
        if not target:
            return Response({"detail": "Admin account not found."}, status=status.HTTP_404_NOT_FOUND)
        if target.pk == request.user.pk:
            return Response(
                {"detail": "You cannot deactivate your own account."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if target.is_superuser:
            return Response(
                {"detail": "A full-control admin account cannot be deactivated here."},
                status=status.HTTP_403_FORBIDDEN,
            )

        is_active = request.data.get("is_active")
        if not isinstance(is_active, bool):
            return Response(
                {"detail": "is_active must be true or false."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if target.is_active != is_active:
            target.is_active = is_active
            target.save(update_fields=["is_active"])
            log_admin_action(
                request.user,
                AdminActionLog.ACTION_ADMIN_REACTIVATED if is_active else AdminActionLog.ACTION_ADMIN_DEACTIVATED,
                target_label=target.username,
                target_type="admin",
                target_id=target.id,
            )
        return Response(AdminAccountSerializer(target).data)


class RegisterView(APIView):
    permission_classes = [AllowAny]
    # Unthrottled, this endpoint could be used to test addresses in bulk: the
    # reply distinguishes "email already exists" from a successful signup, and
    # a generic message is not a fix (it costs real signup usability without
    # preventing enumeration via timing or the username check). Rate limiting
    # is what actually stops it being done at scale.
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "signup"

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

        # These checks race: simultaneous signups both passed them, and the
        # database then either raised (a 500 for a duplicate username) or --
        # with no unique index on the address -- quietly created two accounts
        # sharing one email, which breaks login-by-email and password reset.
        # The unique indexes added in migration 0019 are the real guard; this
        # turns hitting one into the same validation error as the check above.
        try:
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
                if profile.role == UserProfile.ROLE_WORKER:
                    ensure_portfolio_skills(user, profile.skills)
        except IntegrityError:
            return Response(
                {"detail": "That username or email was just taken. Please try again."},
                status=status.HTTP_400_BAD_REQUEST,
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


# The "login" throttle scope above is per-IP, so a distributed brute force
# (many IPs, one target account) was unslowed. This adds a per-account
# counter on top: 10 wrong passwords for the same identifier locks it out
# for 15 minutes, using the identical failure response either way so a
# lockout can't be told apart from an ordinary wrong password (SEC-06).
LOGIN_FAILURE_LIMIT = 10
LOGIN_LOCKOUT_SECONDS = 15 * 60


def _login_failure_cache_key(identifier: str) -> str:
    return f"accounts:login_failures:{identifier.strip().lower()}"


class LoginView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "login"

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        username = serializer.validated_data["username"].strip()
        password = serializer.validated_data["password"]

        failure_key = _login_failure_cache_key(username)
        if cache.get(failure_key, 0) >= LOGIN_FAILURE_LIMIT:
            return Response({"detail": "Invalid username or password."}, status=status.HTTP_400_BAD_REQUEST)

        matched_user = (
            User.objects.filter(username__iexact=username).first()
            or User.objects.filter(email__iexact=username).first()
        )
        user = authenticate(
            request,
            username=matched_user.username if matched_user else username,
            password=password,
        )
        if not user:
            cache.set(failure_key, cache.get(failure_key, 0) + 1, LOGIN_LOCKOUT_SECONDS)
            return Response({"detail": "Invalid username or password."}, status=status.HTTP_400_BAD_REQUEST)
        cache.delete(failure_key)
        profile = UserProfile.objects.filter(user=user).first()
        if profile and profile.refresh_block_status():
            return Response({"detail": profile.block_message}, status=status.HTTP_403_FORBIDDEN)
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
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "password_reset"

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
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "password_reset"

    def post(self, request):
        serializer = ForgotPasswordRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = serializer.validated_data["email"].strip().lower()
        # Same reply whether or not the email is registered, so this endpoint
        # can't be used to find out who has an account.
        sent = Response({"detail": "If the email exists, a reset code has been sent."}, status=status.HTTP_200_OK)
        user = User.objects.filter(email__iexact=email).first()
        if not user:
            return sent

        reset_request, token = create_password_reset_request(user)
        try:
            send_password_reset_email(user, token)
        except (BadHeaderError, OSError, ValueError) as exc:
            reset_request.delete()
            return Response({"detail": f"Unable to send reset code: {exc}"}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
        return sent


class VerifyResetTokenView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "password_reset"

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
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "password_reset"

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
        profile = getattr(reset_request.user, "profile", None)
        if profile:
            profile.credentials_updated_at = timezone.now()
            profile.save(update_fields=["credentials_updated_at"])
        reset_request.used_at = reset_request.used_at or timezone.now()
        reset_request.save(update_fields=["used_at"])
        return Response({"detail": "Password reset successful."}, status=status.HTTP_200_OK)


class LogoutView(APIView):
    def post(self, request):
        auth_header = request.headers.get("Authorization", "")
        if auth_header.startswith("Bearer "):
            token = auth_header.split(" ", 1)[1].strip()
            try:
                payload = decode_jwt_token(token)
            except exceptions.AuthenticationFailed:
                payload = None
            if payload:
                revoke_token(payload)
        if request.user.is_authenticated:
            request.session.flush()
        return Response({"detail": "Logged out."}, status=status.HTTP_200_OK)


class MeProfileView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def get(self, request):
        if request.user.is_staff:
            # Reading their own account must not turn an administrator into a
            # "worker" profile, which then counted as one in every head count.
            profile = UserProfile.objects.filter(user=request.user).first()
        else:
            profile, _ = UserProfile.objects.get_or_create(user=request.user, defaults={"role": UserProfile.ROLE_WORKER})
        return Response(
            {
                # The account role, same as login returns. profile.role is not
                # it: it defaults to "worker" even for staff admins.
                "role": get_account_role(request.user, profile),
                "user": {
                    "id": request.user.id,
                    "username": request.user.username,
                    "email": request.user.email,
                    "first_name": request.user.first_name,
                    "last_name": request.user.last_name,
                },
                "profile": UserProfileSerializer(profile, context={"request": request}).data if profile else None,
            }
        )

    def patch(self, request):
        user = request.user
        profile, _ = UserProfile.objects.get_or_create(user=user, defaults={"role": UserProfile.ROLE_WORKER})
        serializer = ProfileUpdateSerializer(
            data=request.data,
            partial=True,
            context={"profile": profile, "user": user},
        )
        serializer.is_valid(raise_exception=True)

        data = serializer.validated_data
        user_fields = []
        if "first_name" in data:
            user.first_name = data["first_name"]
            user_fields.append("first_name")
        if "last_name" in data:
            user.last_name = data["last_name"]
            user_fields.append("last_name")
        email_changed = "email" in data and data["email"].strip().lower() != (user.email or "").strip().lower()
        if "email" in data:
            user.email = data["email"].strip().lower()
            user_fields.append("email")

        # Lock the row and write only the fields this request changed: a full
        # save from a copy read earlier used to put back whatever a concurrent
        # write had just changed (a portfolio skill, a verification approval,
        # a suspension, a recalculated rating).
        with transaction.atomic():
            profile = UserProfile.objects.select_for_update().get(pk=profile.pk)
            if user_fields:
                user.save(update_fields=user_fields)
            profile_fields = []
            if email_changed:
                # Same "every previously issued token is now stale" guard used
                # by password reset -- an email change is just as
                # credential-sensitive.
                profile.credentials_updated_at = timezone.now()
                profile_fields.append("credentials_updated_at")
            for field in ["phone", "bio", "years_experience", "skills", "hourly_rate", "daily_rate", "location_label", "latitude", "longitude", "profile_photo"]:
                if field in data:
                    setattr(profile, field, data[field])
                    profile_fields.append(field)
            if profile_fields:
                profile.save(update_fields=profile_fields)
            if "skills" in data and profile.role == UserProfile.ROLE_WORKER:
                ensure_portfolio_skills(user, profile.skills)
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
        # A read must not write: an unsaved empty portfolio serializes the
        # same, and anonymous GETs used to create a row for any user id.
        portfolio = WorkerPortfolio.objects.filter(worker=user).first() or WorkerPortfolio(worker=user)
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
    """A worker's portfolio skills. UserProfile.skills is the list matching
    reads, so every change here is made to that list too (see
    apps.accounts.services). The profile is locked and re-read inside each
    write: the list is read-modify-written, and the copy cached on
    request.user may be stale."""

    permission_classes = [IsAuthenticated]

    @staticmethod
    def _worker_profile(user):
        profile = getattr(user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_WORKER:
            return None
        return profile

    def post(self, request):
        if not self._worker_profile(request.user):
            return Response({"detail": "Only workers can manage skills."}, status=status.HTTP_403_FORBIDDEN)
        serializer = WorkerSkillSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        skill_name = " ".join(str(serializer.validated_data.get("skill_name", "")).split())
        with transaction.atomic():
            profile = UserProfile.objects.select_for_update().get(user=request.user)
            listed = list(profile.skills or [])
            # The portfolio lists exactly the profile's skills (what matching
            # reads), so listing the same skill twice is meaningless.
            if skill_key(skill_name) in {skill_key(name) for name in listed}:
                return Response(
                    {"skill_name": "That skill is already on your portfolio."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if len(listed) >= MAX_WORKER_SKILLS:
                return Response(
                    {"skill_name": f"You can list at most {MAX_WORKER_SKILLS} skills."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            # A skill unlisted earlier keeps its row (and its ratings); listing
            # it again brings that row back instead of tripping the unique
            # constraint.
            skill = WorkerSkill.objects.filter(worker=request.user, skill_name__iexact=skill_name).first()
            if skill:
                skill.proficiency = serializer.validated_data.get("proficiency", skill.proficiency or "beginner")
                skill.save(update_fields=["proficiency", "updated_at"])
            else:
                skill = serializer.save(worker=request.user, skill_name=skill_name)
            profile.skills = listed + [skill.skill_name]
            profile.save(update_fields=["skills"])
        return Response(WorkerSkillSerializer(skill).data, status=status.HTTP_201_CREATED)

    def delete(self, request, skill_id):
        if not self._worker_profile(request.user):
            return Response({"detail": "Only workers can manage skills."}, status=status.HTTP_403_FORBIDDEN)
        skill = WorkerSkill.objects.filter(id=skill_id, worker=request.user).first()
        if not skill:
            return Response({"detail": "Skill not found."}, status=status.HTTP_404_NOT_FOUND)
        with transaction.atomic():
            profile = UserProfile.objects.select_for_update().get(user=request.user)
            remaining = [name for name in (profile.skills or []) if skill_key(name) != skill_key(skill.skill_name)]
            # Same rule as the profile form: a worker with no skills cannot be
            # matched to anything.
            if not remaining and profile.skills:
                return Response(
                    {"detail": "Keep at least one skill. Add another before removing this one."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            profile.skills = remaining
            profile.save(update_fields=["skills"])
            # Household ratings are part of the worker's record: an entry
            # that has any is unlisted, not deleted.
            if not skill.skill_ratings.exists():
                skill.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    def patch(self, request, skill_id):
        if not self._worker_profile(request.user):
            return Response({"detail": "Only workers can manage skills."}, status=status.HTTP_403_FORBIDDEN)
        skill = WorkerSkill.objects.filter(id=skill_id, worker=request.user).first()
        if not skill:
            return Response({"detail": "Skill not found."}, status=status.HTTP_404_NOT_FOUND)
        serializer = WorkerSkillSerializer(skill, data=request.data, partial=True, context={"request": request})
        serializer.is_valid(raise_exception=True)
        old_key = skill_key(skill.skill_name)
        new_name = " ".join(str(serializer.validated_data.get("skill_name", skill.skill_name)).split())
        proficiency = serializer.validated_data.get("proficiency", skill.proficiency)
        with transaction.atomic():
            profile = UserProfile.objects.select_for_update().get(user=request.user)
            listed = list(profile.skills or [])
            listed_keys = {skill_key(name) for name in listed}
            # Only listed skills are on the portfolio; an unlisted row is
            # rating history, not something the worker can edit.
            if old_key not in listed_keys:
                return Response({"detail": "Skill not found."}, status=status.HTTP_404_NOT_FOUND)
            if skill_key(new_name) == old_key:
                skill.skill_name = new_name
                skill.proficiency = proficiency
                skill.save(update_fields=["skill_name", "proficiency", "updated_at"])
                target = skill
            else:
                if skill_key(new_name) in listed_keys:
                    return Response(
                        {"skill_name": "That skill is already on your portfolio."},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
                # A skill removed earlier keeps its row; renaming onto it
                # lists that row again rather than tripping the unique name.
                target = (
                    WorkerSkill.objects.filter(worker=request.user, skill_name__iexact=new_name)
                    .exclude(pk=skill.pk)
                    .first()
                )
                if target:
                    target.proficiency = proficiency
                    target.save(update_fields=["proficiency", "updated_at"])
                    if not skill.skill_ratings.exists():
                        skill.delete()
                elif skill.skill_ratings.exists():
                    # Household ratings belong to the skill they were given
                    # for: renaming Cooking to Electrical must not carry a
                    # cooking rating over. The rated row stays as history.
                    target = WorkerSkill.objects.create(
                        worker=request.user, skill_name=new_name, proficiency=proficiency
                    )
                else:
                    skill.skill_name = new_name
                    skill.proficiency = proficiency
                    skill.save(update_fields=["skill_name", "proficiency", "updated_at"])
                    target = skill
            # The rename has to reach the list matching reads, or the worker
            # keeps being matched on the old name.
            profile.skills = [target.skill_name if skill_key(name) == old_key else name for name in listed]
            profile.save(update_fields=["skills"])
        return Response(WorkerSkillSerializer(target).data)


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
        notify_admins(
            title="New certificate to review",
            message=f"@{request.user.username} uploaded a certificate for approval. "
            "Review it in the credentials queue.",
        )
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
        data = serializer.validated_data
        content_changed = "certificate_file" in data or any(
            field in data and data[field] != getattr(cert, field)
            for field in ("certificate_type", "certificate_name", "issuer", "issue_date", "expiry_date")
        )
        # An approval covers the document an admin actually looked at. A new
        # file or different details is a new claim: it goes back to the queue
        # and loses the verified badge until it is reviewed again.
        resubmitted = content_changed and cert.verification_status != WorkerCertification.STATUS_PENDING
        if resubmitted:
            serializer.save(
                verification_status=WorkerCertification.STATUS_PENDING,
                is_verified=False,
                verified_by=None,
                verified_at=None,
                verification_notes="",
            )
            notify_admins(
                title="Certificate resubmitted for review",
                message=f"@{request.user.username} changed a certificate that was already reviewed. "
                "Review it in the credentials queue.",
            )
        else:
            serializer.save()
        return Response(serializer.data)


class WorkerCertificationFileView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, cert_id):
        from apps.common.permissions import is_platform_admin

        cert = WorkerCertification.objects.filter(id=cert_id).select_related("worker").first()
        if not cert or not cert.certificate_file:
            return Response({"detail": "Certificate not found."}, status=status.HTTP_404_NOT_FOUND)
        # Owner and admins can always see it under review; anyone else only
        # once it's approved -- a pending or rejected credential is an
        # unverified or turned-down claim, not something to publish (F16).
        is_owner_or_admin = cert.worker_id == request.user.id or is_platform_admin(request.user)
        if not is_owner_or_admin and cert.verification_status != WorkerCertification.STATUS_APPROVED:
            return Response({"detail": "Certificate not found."}, status=status.HTTP_404_NOT_FOUND)
        content_type = mimetypes.guess_type(cert.certificate_file.name)[0] or "application/octet-stream"
        response = FileResponse(cert.certificate_file.open("rb"), content_type=content_type)
        response["Content-Disposition"] = "inline"
        response["X-Content-Type-Options"] = "nosniff"
        response["Cache-Control"] = "private, no-store"
        return response


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

    def post(self, request, job_id):
        profile = getattr(request.user, "profile", None)
        if not profile or profile.role != UserProfile.ROLE_HOUSEHOLD:
            return Response({"detail": "Only households can rate skills."}, status=status.HTTP_403_FORBIDDEN)

        try:
            job = JobPosting.objects.get(pk=job_id, household=request.user)
        except JobPosting.DoesNotExist:
            return Response({"detail": "Job posting not found."}, status=status.HTTP_404_NOT_FOUND)

        if job.status != JobPosting.STATUS_COMPLETED:
            return Response(
                {"detail": "Skills can only be rated once the job is completed."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        serializer = SkillRatingSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        skill = serializer.validated_data.get("skill")
        if skill is None:
            skill_name = " ".join(serializer.validated_data["skill_name"].split())
            worker_id = request.data.get("worker_id") or request.data.get("worker")
            if worker_id and not str(worker_id).isdigit():
                return Response({"detail": "worker_id must be a number."}, status=status.HTTP_400_BAD_REQUEST)
            completed_applications = job.applications.filter(status=JobApplication.STATUS_COMPLETED)
            application = (
                completed_applications.filter(worker_id=worker_id).first()
                if worker_id
                else completed_applications.first()
            )
            if not application:
                return Response(
                    {"detail": "No completed worker found for this job."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            skill = WorkerSkill.objects.filter(
                worker=application.worker, skill_name__iexact=skill_name
            ).first()
            if not skill:
                # Deliberate: a household may rate work the worker never
                # listed, and the skill is added so the rating has something to
                # hang off (see the test of the same name). Note that this is
                # the one path by which a household adds an entry to someone
                # else's portfolio. It is not subject to the 3-skill cap and
                # stays off the listed skills (and matching) unless the worker
                # lists it; the rating still shows on their job history.
                skill = WorkerSkill.objects.create(worker=application.worker, skill_name=skill_name, proficiency="")
        elif not job.applications.filter(
            worker=skill.worker, status=JobApplication.STATUS_COMPLETED
        ).exists():
            # A skill id is client-supplied, so it could belong to any worker.
            # Without this, a household could attach a rating to someone who
            # never worked this job.
            return Response(
                {"detail": "That skill belongs to a worker who did not complete this job."},
                status=status.HTTP_403_FORBIDDEN,
            )
        # skill_name is resolved above into a real WorkerSkill; it isn't a
        # SkillRating model field, so it must not reach Model.objects.create().
        serializer.validated_data.pop("skill_name", None)
        # One rating per household, job and skill: rating the same skill twice
        # hit the unique constraint and surfaced as a 500. A second rating
        # replaces the first instead.
        existing = SkillRating.objects.filter(
            job=job, household=request.user, worker=skill.worker, skill=skill
        ).first()
        if existing:
            for field, value in serializer.validated_data.items():
                setattr(existing, field, value)
            existing.save()
        else:
            serializer.save(job=job, household=request.user, worker=skill.worker, skill=skill)

        skill.rating_count = SkillRating.objects.filter(skill=skill).count()
        skill.average_rating = SkillRating.objects.filter(skill=skill).aggregate(models.Avg("rating"))["rating__avg"]
        skill.save()
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class CertificateVerificationAdminView(APIView):
    permission_classes = [IsAuthenticated, IsPlatformAdmin]

    def get(self, request, cert_id=None):
        # The detail URL (.../<cert_id>/) also routes GET here for PATCH's
        # sake, so this has to accept the id rather than only the list route.
        if cert_id is not None:
            cert = WorkerCertification.objects.select_related("worker", "verified_by").filter(id=cert_id).first()
            if not cert:
                return Response({"detail": "Certificate not found."}, status=status.HTTP_404_NOT_FOUND)
            return Response(WorkerCertificationSerializer(cert, context={"request": request}).data)

        status_filter = request.query_params.get("status", WorkerCertification.STATUS_PENDING)
        certs = WorkerCertification.objects.select_related("worker", "worker__profile", "verified_by").order_by("-created_at")
        if status_filter and status_filter != "all":
            certs = certs.filter(verification_status=status_filter)

        return paginated_response(
            request,
            certs.order_by("-created_at", "-id"),
            WorkerCertificationSerializer,
            context={"request": request},
        )

    def patch(self, request, cert_id):
        user = request.user
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

        # Derived, not accumulated: rejecting a previously approved credential
        # has to drop the verified badge too.
        cert.is_verified = verification_status == WorkerCertification.STATUS_APPROVED

        cert.save()

        create_notification(
            recipient=cert.worker,
            notification_type=Notification.TYPE_VERIFICATION,
            title="Certificate Verified" if verification_status == WorkerCertification.STATUS_APPROVED else "Certificate Rejected",
            message=f"Your certificate '{cert.certificate_name}' has been {verification_status}.",
            actor=user,
        )
        log_admin_action(
            user,
            AdminActionLog.ACTION_CERTIFICATE_APPROVED
            if verification_status == WorkerCertification.STATUS_APPROVED
            else AdminActionLog.ACTION_CERTIFICATE_REJECTED,
            target_label=f"{cert.certificate_name} ({cert.worker.username})",
            target_type="certificate",
            target_id=cert.id,
            detail=cert.verification_notes,
        )

        serializer = WorkerCertificationSerializer(cert, context={"request": request})
        return Response(serializer.data)
