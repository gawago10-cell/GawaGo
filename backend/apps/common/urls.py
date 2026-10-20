from django.urls import path

from apps.common.views import (
    AdminActionLogListView,
    VerificationRequestDetailView,
    VerificationRequestDocumentView,
    VerificationRequestListCreateView,
    VerificationRequestReviewView,
)


urlpatterns = [
    path("verification-requests/", VerificationRequestListCreateView.as_view(), name="verification-request-list-create"),
    path("verification-requests/<int:pk>/", VerificationRequestDetailView.as_view(), name="verification-request-detail"),
    path("verification-requests/<int:pk>/documents/<str:document_type>/", VerificationRequestDocumentView.as_view(), name="verification-request-document"),
    path("verification-requests/<int:pk>/review/", VerificationRequestReviewView.as_view(), name="verification-request-review"),
    path("admin-action-log/", AdminActionLogListView.as_view(), name="admin-action-log"),
]
