from rest_framework.response import Response
from rest_framework.views import APIView

from apps.analytics.serializers import DashboardMetricsSerializer
from apps.analytics.services import build_dashboard_metrics
from apps.common.permissions import IsPlatformAdmin
from apps.reviews.services import assign_due_default_worker_ratings


class DashboardMetricsView(APIView):
    permission_classes = [IsPlatformAdmin]

    def get(self, request):
        assign_due_default_worker_ratings()
        data = build_dashboard_metrics()
        serializer = DashboardMetricsSerializer(data=data)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.validated_data)
