from django.urls import path

from apps.notifications.views import (
    NotificationDeleteView,
    NotificationListView,
    NotificationMarkReadView,
    NotificationUnreadCountView,
)

urlpatterns = [
    path("", NotificationListView.as_view(), name="notification-list"),
    path("unread-count/", NotificationUnreadCountView.as_view(), name="notification-unread-count"),
    path("<int:pk>/", NotificationDeleteView.as_view(), name="notification-delete"),
    path("<int:pk>/read/", NotificationMarkReadView.as_view(), name="notification-mark-read"),
]
