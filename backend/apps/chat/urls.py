from django.urls import path

from apps.chat.views import ConversationListView, ConversationMessagesView, ConversationReadView

urlpatterns = [
    path("", ConversationListView.as_view(), name="conversation-list"),
    path("<int:hire_id>/messages/", ConversationMessagesView.as_view(), name="conversation-messages"),
    path("<int:hire_id>/read/", ConversationReadView.as_view(), name="conversation-read"),
]
