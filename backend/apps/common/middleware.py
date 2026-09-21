from django.conf import settings

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
