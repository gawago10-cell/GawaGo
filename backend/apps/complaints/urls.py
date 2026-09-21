from django.urls import path

from apps.complaints.views import (
    ComplaintCreateView,
    ComplaintDetailView,
    ComplaintListView,
    ComplaintListAdminView,
    ComplaintRespondentBlockAdminView,
    ComplaintUpdateAdminView,
)

urlpatterns = [
    path("", ComplaintListView.as_view(), name="complaint-list"),
    path("create/", ComplaintCreateView.as_view(), name="complaint-create"),
    path("<int:pk>/", ComplaintDetailView.as_view(), name="complaint-detail"),
    path("admin/", ComplaintListAdminView.as_view(), name="complaint-list-admin"),
    path("admin/<int:pk>/", ComplaintUpdateAdminView.as_view(), name="complaint-update-admin"),
    path(
        "admin/<int:pk>/block/",
        ComplaintRespondentBlockAdminView.as_view(),
        name="complaint-block-admin",
    ),
]
