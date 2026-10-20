import csv

from django.http import HttpResponse
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.permissions import IsPlatformAdmin
from apps.reports.services import (
    build_platform_report,
    build_report_for_user,
    report_to_csv_rows,
    resolve_period,
)


def _parse_bound(raw, field):
    """A date bound, or None when it wasn't given.

    parse_date() returns None for text that isn't a date at all but *raises*
    for a well-formed yet impossible one like 2026-02-30, which used to come
    back as a 500 and a debug page. Both are the caller's mistake, so both get
    the same validation error rather than one being silently replaced by the
    default window.
    """
    if raw is None or not str(raw).strip():
        return None
    try:
        parsed = parse_date(str(raw).strip())
    except ValueError:
        parsed = None
    if parsed is None:
        raise ValidationError({field: "Use a real date in YYYY-MM-DD form."})
    return parsed


class _ReportView(APIView):
    """Shared plumbing for the report endpoints.

    Both endpoints accept the same ?start=&end=&export= query params and
    differ only in which report they build, so the period parsing and the
    JSON/CSV branch live here once.

    The CSV switch is `export`, not `format`: DRF reserves `format` for
    content negotiation, and a `?format=csv` with no CSV renderer
    registered 404s before the view ever runs.
    """

    def build(self, request, period):
        raise NotImplementedError

    def get(self, request):
        try:
            period = resolve_period(
                _parse_bound(request.query_params.get("start"), "start"),
                _parse_bound(request.query_params.get("end"), "end"),
            )
        except ValidationError as invalid:
            return Response(invalid.detail, status=status.HTTP_400_BAD_REQUEST)
        report = self.build(request, period)

        if request.query_params.get("export") == "csv":
            return _csv_response(report)
        return Response(report)


class MyReportView(_ReportView):
    """GET /api/reports/me/

    The signed-in user's own activity report -- household or worker,
    chosen from their profile role.
    """

    permission_classes = [IsAuthenticated]

    def build(self, request, period):
        # Staff have no household/worker activity of their own, so this used to
        # hand them an all-zero "worker" report. The platform report is theirs
        # (AGENTS.md IV.B: only admins get an activity-report screen).
        if request.user.is_staff:
            raise PermissionDenied("Administrators should use the platform report.")
        return build_report_for_user(request.user, period)


class PlatformReportView(_ReportView):
    """GET /api/reports/platform/ -- platform-wide report for administrators."""

    permission_classes = [IsPlatformAdmin]

    def build(self, request, period):
        return build_platform_report(period)


def _csv_response(report):
    filename = f"gawago-{report['scope']}-report-{report['period']['start']}-to-{report['period']['end']}.csv"
    response = HttpResponse(content_type="text/csv")
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    writer = csv.writer(response)
    writer.writerows(report_to_csv_rows(report))
    return response
