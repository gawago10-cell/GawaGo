"""Send email through Brevo's HTTP API instead of its SMTP relay.

Brevo's SMTP relay refuses any IP that isn't on the account's authorised
list, which fails as `525 5.7.1 Unauthorized IP address`. That list is
painful for this project: residential IPs here are dynamic, so a router
reboot silently stops password-reset codes going out, and every deployment
host has to be added by hand.

The transactional API has no such allowlist, travels over HTTPS (port 443,
which networks that block outbound SMTP still allow), and returns a JSON
reason instead of a bare SMTP code. Django's email API is unchanged --
`send_mail` and friends keep working exactly as before -- so this swaps in
via EMAIL_BACKEND alone.
"""

import json
from urllib import error, request

from django.conf import settings
from django.core.mail.backends.base import BaseEmailBackend

BREVO_SEND_URL = "https://api.brevo.com/v3/smtp/email"


class BrevoAPIEmailBackend(BaseEmailBackend):
    def __init__(self, fail_silently=False, **kwargs):
        super().__init__(fail_silently=fail_silently, **kwargs)
        self.api_key = getattr(settings, "BREVO_API_KEY", "")
        self.timeout = getattr(settings, "EMAIL_TIMEOUT", 10)

    def send_messages(self, email_messages):
        if not email_messages:
            return 0
        if not self.api_key:
            if self.fail_silently:
                return 0
            raise ValueError(
                "BREVO_API_KEY is not set, so EMAIL_BACKEND=BrevoAPIEmailBackend "
                "cannot send. Set it, or switch EMAIL_BACKEND back to SMTP."
            )
        return sum(1 for message in email_messages if self._send(message))

    def _payload(self, message):
        from_email = message.from_email or settings.DEFAULT_FROM_EMAIL
        name, _, address = from_email.rpartition("<")
        sender = {"email": address.rstrip(">").strip() or from_email}
        if name.strip():
            sender["name"] = name.strip().strip('"')

        payload = {
            "sender": sender,
            "to": [{"email": recipient} for recipient in message.to],
            "subject": message.subject,
            "textContent": message.body,
        }
        if message.cc:
            payload["cc"] = [{"email": recipient} for recipient in message.cc]
        if message.bcc:
            payload["bcc"] = [{"email": recipient} for recipient in message.bcc]
        if message.reply_to:
            payload["replyTo"] = {"email": message.reply_to[0]}
        # EmailMultiAlternatives puts an HTML body here; nothing sends one
        # today, but dropping it silently would be a surprise if anything does.
        for content, mimetype in getattr(message, "alternatives", []) or []:
            if mimetype == "text/html":
                payload["htmlContent"] = content
                break
        return payload

    def _send(self, message):
        if not message.to:
            return False
        if message.attachments:
            # Not implemented rather than silently dropped: no caller attaches
            # anything today, and losing one without a word would be worse.
            if self.fail_silently:
                return False
            raise NotImplementedError(
                "BrevoAPIEmailBackend does not send attachments yet."
            )

        payload = json.dumps(self._payload(message)).encode("utf-8")
        api_request = request.Request(
            BREVO_SEND_URL,
            data=payload,
            method="POST",
            headers={
                "api-key": self.api_key,
                "content-type": "application/json",
                "accept": "application/json",
            },
        )
        try:
            with request.urlopen(api_request, timeout=self.timeout):
                return True
        except error.HTTPError as exc:
            if self.fail_silently:
                return False
            detail = exc.read().decode("utf-8", "replace")[:300]
            raise RuntimeError(f"Brevo rejected the message (HTTP {exc.code}): {detail}") from exc
        except (OSError, error.URLError) as exc:
            if self.fail_silently:
                return False
            raise RuntimeError(f"Could not reach Brevo: {exc}") from exc
