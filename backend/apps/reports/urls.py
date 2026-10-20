from django.urls import path

from apps.reports.views import MyReportView, PlatformReportView


urlpatterns = [
    path("me/", MyReportView.as_view(), name="my-report"),
    path("platform/", PlatformReportView.as_view(), name="platform-report"),
]
