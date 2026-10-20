from django.urls import path

from apps.jobs.views import (
    JobApplicationDecisionView,
    JobApplicationListView,
    JobApplicationStatusView,
    JobApplicationView,
    JobCompletionRequestView,
    JobHireRequestView,
    JobViewSet,
)

urlpatterns = [
    path("", JobViewSet.as_view({"get": "list", "post": "create"}), name="job-list"),
    path("<int:pk>/", JobViewSet.as_view({"get": "retrieve", "patch": "partial_update", "put": "update", "delete": "destroy"}), name="job-detail"),
    path("<int:job_id>/apply/", JobApplicationView.as_view(), name="job-apply"),
    path("<int:job_id>/hire-request/", JobHireRequestView.as_view(), name="job-hire-request"),
    path("<int:job_id>/request-completion/", JobCompletionRequestView.as_view(), name="job-request-completion"),
    path("applications/", JobApplicationListView.as_view(), name="job-application-list"),
    path("applications/<int:pk>/decision/", JobApplicationDecisionView.as_view(), name="job-application-decision"),
    path("applications/<int:pk>/status/", JobApplicationStatusView.as_view(), name="job-application-status"),
    path("applications/<str:pk>/status/", JobApplicationStatusView.as_view(), name="job-application-status-legacy"),
]
