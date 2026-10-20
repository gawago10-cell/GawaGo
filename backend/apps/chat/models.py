from django.conf import settings
from django.core.validators import MaxLengthValidator
from django.db import models

from apps.jobs.models import JobApplication

MAX_MESSAGE_LENGTH = 2000


class Message(models.Model):
    # A conversation is a hire: one JobApplication links exactly one worker to
    # one household's job, so the application id doubles as the conversation id.
    application = models.ForeignKey(JobApplication, on_delete=models.CASCADE, related_name="messages")
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="sent_messages")
    content = models.TextField(validators=[MaxLengthValidator(MAX_MESSAGE_LENGTH)])
    created_at = models.DateTimeField(auto_now_add=True)
    is_read = models.BooleanField(default=False)

    class Meta:
        ordering = ["created_at", "id"]
        indexes = [models.Index(fields=["application", "id"])]

    def __str__(self) -> str:
        return f"{self.sender.username} on application {self.application_id}"
