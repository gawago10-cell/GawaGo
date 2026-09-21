import base64
import hashlib
import hmac
import json
import uuid
from datetime import datetime, timedelta, timezone

from django.conf import settings
from django.contrib.auth import get_user_model
from rest_framework import authentication, exceptions


def _b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def create_jwt_token(payload: dict, ttl_minutes: int = 60) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    claims = dict(payload)
    now = datetime.now(timezone.utc)
    claims["iat"] = int(now.timestamp())
    claims["exp"] = int((now + timedelta(minutes=ttl_minutes)).timestamp())
    claims.setdefault("jti", uuid.uuid4().hex)
    header_b64 = _b64url_encode(json.dumps(header, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    payload_b64 = _b64url_encode(json.dumps(claims, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
    signature = hmac.new(settings.SECRET_KEY.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return f"{header_b64}.{payload_b64}.{_b64url_encode(signature)}"


def decode_jwt_token(token: str) -> dict:
    try:
        header_b64, payload_b64, signature_b64 = token.split(".")
        signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
        expected = hmac.new(settings.SECRET_KEY.encode("utf-8"), signing_input, hashlib.sha256).digest()
        if not hmac.compare_digest(expected, _b64url_decode(signature_b64)):
            raise exceptions.AuthenticationFailed("Invalid token signature.")
        payload = json.loads(_b64url_decode(payload_b64))
        if int(payload["exp"]) < int(datetime.now(timezone.utc).timestamp()):
            raise exceptions.AuthenticationFailed("Token expired.")
        return payload
    except (ValueError, KeyError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise exceptions.AuthenticationFailed("Invalid token.") from exc


def revoke_token(payload: dict) -> None:
    """Blacklist one already-issued token (e.g. on logout) until it would
    have expired naturally. Silently does nothing for a token minted before
    the jti/exp claims existed -- there is nothing to key a revocation on."""
    from apps.common.models import RevokedToken

    jti = payload.get("jti")
    exp = payload.get("exp")
    user_id = payload.get("user_id")
    if not jti or not exp or not user_id:
        return
    expires_at = datetime.fromtimestamp(int(exp), tz=timezone.utc)
    RevokedToken.objects.get_or_create(
        jti=jti, defaults={"user_id": user_id, "expires_at": expires_at}
    )
    RevokedToken.objects.filter(expires_at__lt=datetime.now(timezone.utc)).delete()


class JWTAuthentication(authentication.BaseAuthentication):
    def authenticate_header(self, request):
        return "Bearer"

    def authenticate(self, request):
        from apps.common.models import RevokedToken

        header = authentication.get_authorization_header(request).decode("utf-8")
        if not header.startswith("Bearer "):
            return None
        token = header.split(" ", 1)[1].strip()
        payload = decode_jwt_token(token)
        jti = payload.get("jti")
        if jti and RevokedToken.objects.filter(jti=jti).exists():
            raise exceptions.AuthenticationFailed("Token has been revoked.")
        user_model = get_user_model()
        user = user_model.objects.filter(pk=payload.get("user_id"), is_active=True).first()
        if not user:
            raise exceptions.AuthenticationFailed("User not found.")
        profile = getattr(user, "profile", None)
        if profile is not None and profile.refresh_block_status():
            # Checked per-request rather than only at login so an admin block
            # takes effect immediately, even on a session already signed in.
            raise exceptions.AuthenticationFailed(profile.block_message)
        credentials_updated_at = getattr(profile, "credentials_updated_at", None)
        if credentials_updated_at is not None:
            issued_at = payload.get("iat")
            if issued_at is None or issued_at < credentials_updated_at.timestamp():
                raise exceptions.AuthenticationFailed(
                    "Session expired due to a security change. Please log in again."
                )
        return (user, payload)
