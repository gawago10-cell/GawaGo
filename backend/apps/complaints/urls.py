from django.urls import path

from apps.complaints.views import (
    ComplaintCreateView,
    ComplaintDetailView,
    ComplaintEvidenceView,
    ComplaintListView,
    ComplaintListAdminView,
    ComplaintRespondentBlockAdminView,
    ComplaintUpdateAdminView,
)

urlpatterns = [
    path("", ComplaintListView.as_view(), name="complaint-list"),
    path("create/", ComplaintCreateView.as_view(), name="complaint-create"),
    path("<int:pk>/", ComplaintDetailView.as_view(), name="complaint-detail"),
    path(
        "<int:pk>/evidence/<int:evidence_id>/",
        ComplaintEvidenceView.as_view(),
        name="complaint-evidence",
    ),
    path("admin/", ComplaintListAdminView.as_view(), name="complaint-list-admin"),
    path("admin/<int:pk>/", ComplaintUpdateAdminView.as_view(), name="complaint-update-admin"),
    path(
        "admin/<int:pk>/block/",
        ComplaintRespondentBlockAdminView.as_view(),
        name="complaint-block-admin",
    ),
]
