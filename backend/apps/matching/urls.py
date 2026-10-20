from django.urls import path

from apps.matching.views import RecommendedJobsView, RecommendedWorkersView


urlpatterns = [
    path("recommended-workers/", RecommendedWorkersView.as_view(), name="recommended-workers"),
    path("recommended-jobs/", RecommendedJobsView.as_view(), name="recommended-jobs"),
]
