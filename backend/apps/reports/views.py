import csv

from django.http import HttpResponse
from django.utils.dateparse import parse_date
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
        period = resolve_period(
            parse_date(request.query_params.get("start") or ""),
            parse_date(request.query_params.get("end") or ""),
        )
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
