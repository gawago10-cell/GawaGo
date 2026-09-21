import secrets

from django.conf import settings
from django.contrib.auth.models import User
from django.core.mail import send_mail
from django.utils import timezone

from apps.accounts.models import PasswordResetRequest, SignupVerificationRequest, UserProfile
from apps.notifications.models import Notification
from apps.notifications.services import create_notification


RESET_TOKEN_TTL_MINUTES = int(getattr(settings, "PASSWORD_RESET_TOKEN_TTL_MINUTES", 10))
SIGNUP_TOKEN_TTL_MINUTES = int(getattr(settings, "SIGNUP_VERIFICATION_TOKEN_TTL_MINUTES", 10))

# 3 or 7 days lifts itself automatically; omitted/None means a permanent block.
SUSPENSION_DURATION_DAYS_CHOICES = {3, 7}


class SuspensionValidationError(ValueError):
    """Raised when the requested suspend/restore parameters are invalid."""


def apply_account_suspension(profile: UserProfile, *, blocked=True, reason="", duration_days=None) -> None:
    """Suspend (timed or permanent) or restore an account, and notify the
    user. Shared by the complaint-review "block this respondent" action and
    the User Management "suspend this account" action so both stay in sync
    instead of drifting apart.

    Sets UserProfile.is_blocked rather than User.is_active on purpose: login
    reactivates inactive accounts that supply the right password, so
    is_active would be silently undone. A block takes effect on the next
    request because JWTAuthentication checks it per-request, not just at
    login.

    Raises SuspensionValidationError if duration_days isn't 3, 7, or omitted.
    """
    if isinstance(blocked, str):
        blocked = blocked.lower() not in {"false", "0", "no"}
    blocked = bool(blocked)

    blocked_until = None
    if blocked and duration_days not in (None, "", "null"):
        try:
            duration_days = int(duration_days)
        except (TypeError, ValueError):
            raise SuspensionValidationError("duration_days must be an integer.")
        if duration_days not in SUSPENSION_DURATION_DAYS_CHOICES:
            raise SuspensionValidationError("duration_days must be one of: 3, 7.")
        blocked_until = timezone.now() + timezone.timedelta(days=duration_days)

    profile.is_blocked = blocked
    profile.blocked_at = timezone.now() if blocked else None
    profile.blocked_reason = reason if blocked else ""
    profile.blocked_until = blocked_until
    profile.save(update_fields=["is_blocked", "blocked_at", "blocked_reason", "blocked_until"])

    if blocked:
        title = f"Account suspended for {duration_days} days" if blocked_until else "Account blocked"
        message = f"Your account has been {'suspended' if blocked_until else 'blocked'} by an administrator."
        if blocked_until:
            message += f" It will be restored automatically on {timezone.localtime(blocked_until).strftime('%Y-%m-%d')}."
        if profile.blocked_reason:
            message += f" Reason: {profile.blocked_reason}"
    else:
        title = "Account restored"
        message = "Your account has been restored. You can sign in again."

    create_notification(
        recipient=profile.user,
        notification_type=Notification.TYPE_ACCOUNT_ACTIVITY,
        title=title,
        message=message,
    )


def generate_reset_token() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def generate_signup_token() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def create_password_reset_request(user: User) -> tuple[PasswordResetRequest, str]:
    token = generate_reset_token()
    reset_request = PasswordResetRequest.create_request(user, token, ttl_minutes=RESET_TOKEN_TTL_MINUTES)
    return reset_request, token


def create_signup_verification_request(user: User) -> tuple[SignupVerificationRequest, str]:
    token = generate_signup_token()
    signup_request = SignupVerificationRequest.create_request(user, token, ttl_minutes=SIGNUP_TOKEN_TTL_MINUTES)
    return signup_request, token


def send_password_reset_email(user: User, token: str) -> None:
    subject = "GawaGo password reset code"
    message = (
        f"Hello {user.get_username()},\n\n"
        f"Your GawaGo password reset code is: {token}\n\n"
        f"This code expires in {RESET_TOKEN_TTL_MINUTES} minutes.\n"
        "If you did not request this, you can ignore this email."
    )
    send_mail(subject, message, getattr(settings, "DEFAULT_FROM_EMAIL", None), [user.email], fail_silently=False)


def send_signup_verification_email(user: User, token: str) -> None:
    subject = "GawaGo account verification code"
    message = (
        f"Hello {user.get_username()},\n\n"
        f"Your GawaGo account verification code is: {token}\n\n"
        f"This code expires in {SIGNUP_TOKEN_TTL_MINUTES} minutes.\n"
        "Enter this code before logging in to activate your account."
    )
    send_mail(subject, message, getattr(settings, "DEFAULT_FROM_EMAIL", None), [user.email], fail_silently=False)


def validate_latest_reset_request(email: str, token: str) -> PasswordResetRequest | None:
    reset_request = PasswordResetRequest.objects.filter(email=email).order_by("-created_at").first()
    if not reset_request:
        return None
    if reset_request.is_expired or reset_request.is_used:
        return None
    if not reset_request.verify_token(token):
        reset_request.attempts += 1
        reset_request.save(update_fields=["attempts"])
        return None
    return reset_request
