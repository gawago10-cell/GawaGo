"""Credentials of permanently blocked accounts (AGENTS.md II.D).

When a superadmin blocks an account permanently, its email, phone, the
government ID numbers it was verified with and its full name are recorded
as BannedCredential rows. A new signup or profile edit can't use a banned
email or phone, a verification request with a banned ID number is rejected
on arrival, and a request from someone with a banned account's full name is
flagged in the queue for the superadmin to compare. The person is never
told the reason is a ban, so the forms can't be used to find out who is
banned.
"""

import re

from apps.accounts.models import BannedCredential

EMAIL_BLOCKED_MESSAGE = (
    "This email can't be used to create a GawaGo account. If you think this is a mistake, contact support."
)
PHONE_BLOCKED_MESSAGE = (
    "This phone number can't be used for a GawaGo account. If you think this is a mistake, contact support."
)
ID_BLOCKED_MESSAGE = "We couldn't verify this ID. Contact support if you think this is a mistake."


def normalize_email(value) -> str:
    return str(value or "").strip().lower()


def normalize_phone(value) -> str:
    """Digits only, in the local 09XXXXXXXXX form, so "+63 917 555 0106",
    "639175550106" and "0917-555-0106" are one number. Too few digits to be
    a phone number gives "", which never matches."""
    digits = re.sub(r"\D", "", str(value or ""))
    if digits.startswith("63") and len(digits) == 12:
        digits = "0" + digits[2:]
    elif digits.startswith("9") and len(digits) == 10:
        digits = "0" + digits
    return digits if len(digits) >= 7 else ""


def normalize_id_number(value) -> str:
    """Letters and digits only, upper case: "N01-23-456789" and
    "n0123456789" are the same ID."""
    return re.sub(r"[^0-9A-Za-z]", "", str(value or "")).upper()


def normalize_name(value) -> str:
    """Case, punctuation and spacing ignored: "Juan  Dela-Paz" matches
    "juan dela paz"."""
    letters = re.sub(r"[^\w\s]", " ", str(value or ""), flags=re.UNICODE).replace("_", " ")
    return " ".join(letters.split()).casefold()


NORMALIZERS = {
    BannedCredential.KIND_EMAIL: normalize_email,
    BannedCredential.KIND_PHONE: normalize_phone,
    BannedCredential.KIND_ID_NUMBER: normalize_id_number,
    BannedCredential.KIND_NAME: normalize_name,
}


def banned_match(kind, value, exclude_user=None):
    """The ban row this value matches, or None. exclude_user skips the
    account's own rows, e.g. when it edits its own profile."""
    normalized = NORMALIZERS[kind](value)
    if not normalized:
        return None
    rows = BannedCredential.objects.filter(kind=kind, value=normalized)
    if exclude_user is not None:
        rows = rows.exclude(user=exclude_user)
    return rows.first()


def account_credentials(user):
    """(kind, normalized value) pairs a permanent block of this account
    records: its email, phone, every ID number it sent for verification and
    its full name. Empty values are left out."""
    profile = getattr(user, "profile", None)
    pairs = [
        (BannedCredential.KIND_EMAIL, normalize_email(user.email)),
        (BannedCredential.KIND_PHONE, normalize_phone(getattr(profile, "phone", ""))),
        (BannedCredential.KIND_NAME, normalize_name(user.get_full_name())),
    ]
    for number in user.verification_requests.values_list("primary_id_number", flat=True):
        pairs.append((BannedCredential.KIND_ID_NUMBER, normalize_id_number(number)))
    seen = set()
    result = []
    for pair in pairs:
        if pair[1] and pair not in seen:
            seen.add(pair)
            result.append(pair)
    return result


def sync_banned_credentials(profile) -> None:
    """Keep an account's ban rows in step with its block: a permanent block
    records its credentials, and anything else (a timed suspension or a
    restore) clears them."""
    user = profile.user
    BannedCredential.objects.filter(user=user).delete()
    if profile.is_blocked and profile.blocked_until is None:
        BannedCredential.objects.bulk_create(
            BannedCredential(kind=kind, value=value, user=user, username=user.username)
            for kind, value in account_credentials(user)
        )


def latest_id_number(user):
    """The most recent ID number this account sent, with its type label,
    for the admin screens; ("", "") when it never sent one."""
    request = (
        user.verification_requests.exclude(primary_id_number="")
        .order_by("-submitted_at", "-id")
        .first()
    )
    if not request:
        return "", ""
    return request.primary_id_number, request.get_primary_id_type_display()
