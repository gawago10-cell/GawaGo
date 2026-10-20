from rest_framework import serializers

from apps.notifications.models import Notification


class NotificationSerializer(serializers.ModelSerializer):
    recipient_username = serializers.CharField(source="recipient.username", read_only=True)
    actor_username = serializers.CharField(source="actor.username", read_only=True, allow_null=True)

    class Meta:
        model = Notification
        fields = [
            "id",
            "recipient",
            "recipient_username",
            "actor",
            "actor_username",
            "notification_type",
            "title",
            "message",
            "related_job_id",
            "related_application_id",
            "action_type",
            "action_url",
            "requires_action",
            "is_read",
            "created_at",
        ]
        read_only_fields = ["id", "recipient_username", "actor_username", "created_at"]
