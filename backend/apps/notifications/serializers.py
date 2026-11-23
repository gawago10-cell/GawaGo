from rest_framework import serializers

from apps.notifications.models import Notification


def _hides_actor(obj):
    """An admin who acted (a certificate decision, a verification review) is
    not named to a worker or household: the mobile app showed "From:
    @auditsuper" (mobile worker audit, 2026-11-23). Admins still see who."""
    actor = obj.actor
    recipient = obj.recipient
    return bool(actor and actor.is_staff and not (recipient and recipient.is_staff))


class NotificationSerializer(serializers.ModelSerializer):
    recipient_username = serializers.CharField(source="recipient.username", read_only=True)
    actor = serializers.SerializerMethodField()
    actor_username = serializers.SerializerMethodField()

    def get_actor(self, obj):
        return None if _hides_actor(obj) else obj.actor_id

    def get_actor_username(self, obj):
        if not obj.actor or _hides_actor(obj):
            return None
        return obj.actor.username

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
