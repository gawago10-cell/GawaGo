from rest_framework import serializers

from apps.chat.models import MAX_MESSAGE_LENGTH, Message
from apps.jobs.statuses import get_application_stage, get_stage_label


def display_name(user):
    return user.get_full_name().strip() or user.username


def profile_photo_url(user, request):
    photo = getattr(getattr(user, "profile", None), "profile_photo", None)
    if not photo:
        return ""
    return request.build_absolute_uri(photo.url) if request else photo.url


class MessageSerializer(serializers.ModelSerializer):
    conversation_id = serializers.IntegerField(source="application_id", read_only=True)
    sender_id = serializers.IntegerField(read_only=True)
    sender_name = serializers.SerializerMethodField()
    is_mine = serializers.SerializerMethodField()
    # trim_whitespace (on by default) turns a whitespace-only message into ""
    # so allow_blank=False rejects it.
    content = serializers.CharField(max_length=MAX_MESSAGE_LENGTH, allow_blank=False)

    class Meta:
        model = Message
        fields = ["id", "conversation_id", "sender_id", "sender_name", "is_mine", "content", "created_at", "is_read"]
        read_only_fields = ["id", "conversation_id", "sender_id", "sender_name", "is_mine", "created_at", "is_read"]

    def get_sender_name(self, obj):
        return display_name(obj.sender)

    def get_is_mine(self, obj):
        request = self.context.get("request")
        return bool(request and obj.sender_id == request.user.id)


class ConversationSerializer(serializers.Serializer):
    """One hire (JobApplication) as seen by one of its two participants."""

    def to_representation(self, application):
        request = self.context.get("request")
        job = application.job
        is_household = job.household_id == request.user.id
        other = application.worker if is_household else job.household
        last = application.last_message
        return {
            "id": application.id,
            "job_id": job.id,
            "job_title": job.title,
            "job_status": job.status,
            "status_label": get_stage_label(get_application_stage(application.status, job.status)),
            "service_rate": str(job.service_rate),
            "rate_type_label": job.get_rate_type_display(),
            "other_party": {
                "id": other.id,
                "username": other.username,
                "name": display_name(other),
                "role": "worker" if is_household else "household",
                "photo_url": profile_photo_url(other, request),
            },
            "last_message": MessageSerializer(last, context=self.context).data if last else None,
            "unread_count": application.unread_count,
        }
