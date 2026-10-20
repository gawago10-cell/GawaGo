import secrets

from django.conf import settings
from django.contrib.auth.models import User
from django.core.mail import send_mail
from django.utils import timezone

from apps.accounts.models import PasswordResetRequest, SignupVerificationRequest, UserProfile, WorkerSkill
from apps.notifications.models import Notification
from apps.notifications.services import create_notification


# A worker's skills live in two places that must agree: UserProfile.skills
# (at most 3, what Smart Matching and AI recommendations read) and one
# WorkerSkill row per skill (proficiency and household ratings, shown on the
# portfolio). The profile list is the source of truth for which skills are
# listed. Rows are never deleted to keep the two in step, so a skill's
# rating history survives being unlisted and comes back if it is re-added.
def skill_key(name) -> str:
    return " ".join(str(name or "").split()).casefold()


def ensure_portfolio_skills(user, skills) -> None:
    """Give every skill on the profile list a portfolio entry. Entries made
    here carry no proficiency, since the worker never stated one."""
    have = {skill_key(name) for name in WorkerSkill.objects.filter(worker=user).values_list("skill_name", flat=True)}
    for name in skills or []:
        key = skill_key(name)
        if key and key not in have:
            WorkerSkill.objects.create(worker=user, skill_name=" ".join(str(name).split()), proficiency="")
            have.add(key)


def listed_portfolio_skills(user):
    """The portfolio entries for skills currently on the worker's profile."""
    profile = getattr(user, "profile", None)
    listed = {skill_key(name) for name in (getattr(profile, "skills", None) or [])}
    return [skill for skill in user.portfolio_skills.all() if skill_key(skill.skill_name) in listed]


RESET_TOKEN_TTL_MINUTES = int(getattr(settings, "PASSWORD_RESET_TOKEN_TTL_MINUTES", 10))
SIGNUP_TOKEN_TTL_MINUTES = int(getattr(settings, "SIGNUP_VERIFICATION_TOKEN_TTL_MINUTES", 10))
MAX_RESET_ATTEMPTS = 5

# 3 or 7 days lifts itself automatically; omitted/None means a permanent block.
SUSPENSION_DURATION_DAYS_CHOICES = {3, 7}


class SuspensionValidationError(ValueError):
    """Raised when the requested suspend/restore parameters are invalid."""


def parse_blocked_flag(value) -> bool:
    """A form/JSON "blocked" value as a bool: "false", "0" and "no" mean a
    restore. Callers that log the action must use this too, or a restore
    sent as text is recorded as a suspension."""
    if isinstance(value, str):
        return value.strip().lower() not in {"false", "0", "no"}
    return bool(value)


def apply_account_suspension(profile: UserProfile, *, blocked=True, reason="", duration_days=None) -> None:
    """Suspend (timed or permanent) or restore an account, and notify the
    user. Shared by the complaint-review "block this respondent" action and
    the User Management "suspend this account" action so both stay in sync
    instead of drifting apart.

    Sets UserProfile.is_blocked rather than User.is_active on purpose: a
    block carries a reason and an optional end date shown to the user, which
    is_active can't. A block takes effect on the next
    request because JWTAuthentication checks it per-request, not just at
    login.

    Raises SuspensionValidationError if duration_days isn't 3, 7, or omitted.
    """
    blocked = parse_blocked_flag(blocked)

    # Restoring an account that was never suspended used to send an "Account
    # restored" notification and email anyway -- one test account collected
    # three of them.
    was_blocked = profile.refresh_block_status()
    if not blocked and not was_blocked:
        return

    blocked_until = None
    if blocked and duration_days not in (None, "", "null"):
        try:
            # A float like 3.5 used to be silently truncated to 3 days.
            numeric = float(duration_days)
        except (TypeError, ValueError):
            raise SuspensionValidationError("duration_days must be an integer.")
        if numeric != int(numeric):
            raise SuspensionValidationError("duration_days must be a whole number of days.")
        duration_days = int(numeric)
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
        # Say plainly that no reason was recorded rather than leaving the
        # notice looking truncated.
        if profile.blocked_reason:
            message += f" Reason: {profile.blocked_reason}"
        else:
            message += " No reason was recorded; contact support for details."
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
    # A 6-digit code must not survive enough guesses to be brute-forced; the
    # user requests a fresh code after this.
    if reset_request.attempts >= MAX_RESET_ATTEMPTS:
        return None
    if not reset_request.verify_token(token):
        reset_request.attempts += 1
        reset_request.save(update_fields=["attempts"])
        return None
    return reset_request
