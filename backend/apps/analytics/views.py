from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.analytics.serializers import DashboardMetricsSerializer
from apps.analytics.services import build_dashboard_metrics, build_public_summary
from apps.common.permissions import IsPlatformAdmin, is_platform_superadmin
from apps.reviews.services import assign_due_default_worker_ratings_on_read


class DashboardMetricsView(APIView):
    permission_classes = [IsPlatformAdmin]

    def get(self, request):
        assign_due_default_worker_ratings_on_read()
        data = build_dashboard_metrics(include_complaints=is_platform_superadmin(request.user))
        serializer = DashboardMetricsSerializer(data=data)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.validated_data)


class PublicSummaryView(APIView):
    """GET /api/analytics/public-summary/: the home page's totals for anyone,
    signed in or not. Counts only, no names. Visitors can't load profiles,
    so the page used to count an empty list and show 0 verified workers and
    0 accounts (second scan, 2026-11-01)."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        return Response(build_public_summary())

