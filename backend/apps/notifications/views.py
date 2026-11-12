from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.pagination import paginated_response
from apps.jobs.services import send_due_mark_done_reminders_on_read
from apps.notifications.models import Notification
from apps.notifications.serializers import NotificationSerializer


class NotificationListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        # The mark-done reminder pass rides on reads (cooldown-bound), so a
        # household that only checks its notifications still gets it.
        send_due_mark_done_reminders_on_read()
        queryset = Notification.objects.select_related("recipient").filter(recipient=request.user)
        return paginated_response(request, queryset, NotificationSerializer)


class NotificationUnreadCountView(APIView):
    """GET /api/notifications/unread-count/ -- just the badge number, so a
    client polling for it doesn't download every page of notifications."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        send_due_mark_done_reminders_on_read()
        return Response({"unread": Notification.objects.filter(recipient=request.user, is_read=False).count()})


class NotificationMarkReadView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, pk):
        notification = get_object_or_404(Notification, pk=pk, recipient=request.user)
        notification.is_read = True
        notification.save(update_fields=["is_read"])
        return Response(NotificationSerializer(notification).data)


class NotificationMarkAllReadView(APIView):
    """POST /api/notifications/read-all/ -- "Mark all as read" used to send
    one request per notification the account ever had, read or not."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        updated = Notification.objects.filter(recipient=request.user, is_read=False).update(is_read=True)
        return Response({"updated": updated})


class NotificationDeleteView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, pk):
        notification = get_object_or_404(Notification, pk=pk, recipient=request.user)
        notification.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
