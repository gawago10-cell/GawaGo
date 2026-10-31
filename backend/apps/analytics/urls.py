from django.urls import path

from apps.analytics.views import DashboardMetricsView, PublicSummaryView


urlpatterns = [
    path("dashboard-metrics/", DashboardMetricsView.as_view(), name="dashboard-metrics"),
    path("public-summary/", PublicSummaryView.as_view(), name="public-summary"),
]
