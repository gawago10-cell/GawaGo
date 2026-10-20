from django.conf import settings
from django.core.cache import cache
from django.http import HttpResponse
from django.urls import NoReverseMatch, reverse

# Applies only to HTML Django renders itself (admin, DRF's browsable API, error
# pages). The React SPA ships its own CSP in index.html -- it is served by Vite
# or a static host, never by Django, so a header set here would never reach it.
DEFAULT_CSP = (
    "default-src 'self'; "
    "script-src 'self' 'unsafe-inline'; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data:; "
    "object-src 'none'; "
    "base-uri 'self'; "
    "frame-ancestors 'none'"
)


class StripControlCharactersMiddleware:
    """Drops NUL and other C0 control characters from query parameters.

    `?status=%00` reached PostgreSQL and came back as a 500: the database
    refuses NUL bytes in text, which is right, but the caller should get a
    normal response rather than a server error. Control characters carry no
    meaning in any filter this API accepts, so they are removed rather than
    rejected.
    """

    TRANSLATION = {code: None for code in range(32) if code not in (9, 10, 13)}

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        query = request.META.get("QUERY_STRING", "")
        if any(chr(code) in query for code in self.TRANSLATION):
            request.META["QUERY_STRING"] = query.translate(self.TRANSLATION)
        if hasattr(request, "GET"):
            cleaned = request.GET.copy()
            changed = False
            for key in list(cleaned.keys()):
                values = cleaned.getlist(key)
                scrubbed = [value.translate(self.TRANSLATION) for value in values]
                if scrubbed != values:
                    cleaned.setlist(key, scrubbed)
                    changed = True
            if changed:
                cleaned._mutable = False
                request.GET = cleaned
        return self.get_response(request)


class AdminLoginRateLimitMiddleware:
    """Rate-limits failed logins at Django's admin sign-in form.

    The API's own login is throttled two ways (per-IP via DRF, plus a
    per-account lockout), but `/admin/` is Django's session login and none of
    that reaches it -- so the one door that opens onto a superuser account was
    the only one a password could be guessed at without limit.

    Counted per-IP and *not* per-username on purpose: a per-account lockout
    here would let anyone lock the real superuser out of the admin by
    deliberately failing a few logins, which trades a brute-force risk for a
    denial-of-service one.

    Only POSTs to the admin login URL are counted, and only failures: the
    admin re-renders the form with 200 when credentials are wrong and
    redirects (302) when they are right, so a success clears the counter
    instead of contributing to a lockout.

    This is the application-level half. A `limit_req` rule in nginx is still
    worth having in front of it at the reverse proxy -- that one also
    sheds the load before it reaches Django.
    """

    CACHE_KEY_PREFIX = "admin:login_failures:"

    def __init__(self, get_response):
        self.get_response = get_response
        self.limit = getattr(settings, "ADMIN_LOGIN_FAILURE_LIMIT", 10)
        self.lockout_seconds = getattr(settings, "ADMIN_LOGIN_LOCKOUT_SECONDS", 15 * 60)
        # Resolved on first use, not here: the URL conf is not guaranteed to be
        # loadable while middleware is still being constructed.
        self._login_path = None
        self._login_path_resolved = False

    def _admin_login_path(self):
        if not self._login_path_resolved:
            self._login_path_resolved = True
            try:
                self._login_path = reverse("admin:login")
            except NoReverseMatch:
                # The admin isn't mounted in this configuration.
                self._login_path = None
        return self._login_path

    def _cache_key(self, request):
        from rest_framework.throttling import BaseThrottle

        # Same client-IP derivation the API throttles use, so both honour
        # REST_FRAMEWORK["NUM_PROXIES"] identically rather than one of them
        # trusting a client-supplied X-Forwarded-For.
        return f"{self.CACHE_KEY_PREFIX}{BaseThrottle().get_ident(request)}"

    def __call__(self, request):
        login_path = self._admin_login_path()
        is_login_attempt = (
            login_path is not None and request.method == "POST" and request.path == login_path
        )
        if not is_login_attempt:
            return self.get_response(request)

        cache_key = self._cache_key(request)
        if cache.get(cache_key, 0) >= self.limit:
            return HttpResponse(
                "Too many failed sign-in attempts. Try again later.",
                status=429,
                content_type="text/plain",
            )

        response = self.get_response(request)
        if 300 <= response.status_code < 400:
            # Signed in -- drop the record rather than leaving a partial count
            # to expire on its own.
            cache.delete(cache_key)
        else:
            cache.set(cache_key, cache.get(cache_key, 0) + 1, self.lockout_seconds)
        return response


class ContentSecurityPolicyMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response
        self.policy = getattr(settings, "CONTENT_SECURITY_POLICY", DEFAULT_CSP)

    def __call__(self, request):
        response = self.get_response(request)
        content_type = response.headers.get("Content-Type", "")
        if "text/html" in content_type and "Content-Security-Policy" not in response.headers:
            response.headers["Content-Security-Policy"] = self.policy
        return response
