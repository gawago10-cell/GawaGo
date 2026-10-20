from django.db.models import Count, OuterRef, Q, Subquery
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.chat.models import Message
from apps.chat.serializers import ConversationSerializer, MessageSerializer
from apps.jobs.models import JobApplication, JobPosting

# Chat is only open while the work is live. A cancelled job leaves its
# application "hired", so the job status has to be checked as well.
CHAT_JOB_STATUSES = (JobPosting.STATUS_ASSIGNED, JobPosting.STATUS_COMPLETION_REQUESTED)
# First load returns the tail of the thread; polling with ?after= fetches the rest.
HISTORY_LIMIT = 200
NOT_ALLOWED = {"detail": "You can't access this conversation."}


def chat_open_applications(user):
    return JobApplication.objects.filter(
        Q(worker=user) | Q(job__household=user),
        status=JobApplication.STATUS_HIRED,
        job__status__in=CHAT_JOB_STATUSES,
    )


def get_conversation(user, hire_id):
    """The hire if `user` is one of its two parties and chat is open, else None.
    Missing, foreign and closed hires all look the same to the caller so the
    endpoint can't be used to probe which hire ids exist."""
    return (
        chat_open_applications(user)
        .select_related("job", "job__household", "worker")
        .filter(pk=hire_id)
        .first()
    )


class ConversationListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        latest = Message.objects.filter(application=OuterRef("pk")).order_by("-id")
        applications = list(
            chat_open_applications(user)
            .select_related("job", "job__household__profile", "worker__profile")
            .annotate(
                last_message_id=Subquery(latest.values("id")[:1]),
                unread_count=Count("messages", filter=Q(messages__is_read=False) & ~Q(messages__sender=user)),
            )
        )
        last_messages = Message.objects.select_related("sender").in_bulk(
            [a.last_message_id for a in applications if a.last_message_id]
        )
        for application in applications:
            application.last_message = last_messages.get(application.last_message_id)
        applications.sort(
            key=lambda a: (a.last_message.created_at if a.last_message else a.updated_at),
            reverse=True,
        )
        return Response(ConversationSerializer(applications, many=True, context={"request": request}).data)


class ConversationMessagesView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, hire_id):
        application = get_conversation(request.user, hire_id)
        if not application:
            return Response(NOT_ALLOWED, status=status.HTTP_403_FORBIDDEN)
        messages = application.messages.select_related("sender")
        after = request.query_params.get("after")
        if after not in (None, ""):
            try:
                after_id = int(after)
            except ValueError:
                return Response({"after": "Must be a message id."}, status=status.HTTP_400_BAD_REQUEST)
            messages = messages.filter(id__gt=after_id).order_by("id")
        else:
            messages = reversed(list(messages.order_by("-id")[:HISTORY_LIMIT]))
        return Response(MessageSerializer(messages, many=True, context={"request": request}).data)

    def post(self, request, hire_id):
        application = get_conversation(request.user, hire_id)
        if not application:
            return Response(NOT_ALLOWED, status=status.HTTP_403_FORBIDDEN)
        serializer = MessageSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save(application=application, sender=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class ConversationReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, hire_id):
        application = get_conversation(request.user, hire_id)
        if not application:
            return Response(NOT_ALLOWED, status=status.HTTP_403_FORBIDDEN)
        marked = application.messages.filter(is_read=False).exclude(sender=request.user).update(is_read=True)
        return Response({"marked_read": marked})
