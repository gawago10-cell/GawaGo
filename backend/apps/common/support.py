"""How a member reaches the GawaGo team, for messages that send them there.

Messages used to end "Contact support for assistance" although GawaGo has
no support contact (full audit, 2026-11-16). Now they name the address in
the GAWAGO_SUPPORT_EMAIL setting, and say nothing when none is set, rather
than pointing at a channel that doesn't exist.
"""

from django.conf import settings
from django.utils import timezone


def support_email() -> str:
    return str(getattr(settings, "SUPPORT_EMAIL", "") or "").strip()


def support_sentence(lead: str = "If you think this is a mistake, email") -> str:
    """" If you think this is a mistake, email help@example.com." with its
    leading space, or "" when no support address is set."""
    email = support_email()
    return f" {lead} {email}." if email else ""


def readable_datetime(value) -> str:
    """"Thu, Nov 19, 2026 at 9:23 PM" in the site's time zone, the way the
    screens write dates, instead of "2026-11-19 21:23"."""
    local = timezone.localtime(value)
    hour = local.strftime("%I").lstrip("0") or "12"
    return f"{local.strftime('%a, %b')} {local.day}, {local.year} at {hour}:{local.strftime('%M %p')}"


def readable_date(value) -> str:
    """"Thu, Nov 19, 2026"."""
    local = timezone.localtime(value)
    return f"{local.strftime('%a, %b')} {local.day}, {local.year}"
