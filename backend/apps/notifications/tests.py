from django.contrib.auth.models import User
from django.core import mail
from django.test import override_settings
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from apps.notifications.models import Notification
from apps.notifications.services import create_notification


class NotificationPermissionTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.recipient = User.objects.create_user(username="notify-recipient", password="password")
        self.other_user = User.objects.create_user(username="notify-other", password="password")
        self.notification = Notification.objects.create(
            recipient=self.recipient,
            notification_type=Notification.TYPE_APPLICATION,
            title="Application update",
            message="A worker applied.",
        )
        self.other_notification = Notification.objects.create(
            recipient=self.other_user,
            notification_type=Notification.TYPE_REJECTION,
            title="Other update",
            message="Private notification.",
        )

    def test_anonymous_user_cannot_list_notifications_by_username(self):
        response = self.client.get(
            reverse("notification-list"),
            {"username": self.recipient.username},
        )

        self.assertEqual(response.status_code, 401)

    def test_authenticated_user_only_lists_own_notifications(self):
        self.client.force_authenticate(user=self.recipient)

        response = self.client.get(reverse("notification-list"))

        self.assertEqual(response.status_code, 200)
        ids = {item["id"] for item in response.json()}
        self.assertIn(self.notification.id, ids)
        self.assertNotIn(self.other_notification.id, ids)

    def test_non_recipient_cannot_mark_notification_read(self):
        self.client.force_authenticate(user=self.other_user)

        response = self.client.patch(
            reverse("notification-mark-read", args=[self.notification.id]),
            {},
            format="json",
        )

        self.assertEqual(response.status_code, 404)
        self.notification.refresh_from_db()
        self.assertFalse(self.notification.is_read)

    def test_staff_user_cannot_mark_another_users_notification_read(self):
        staff_user = User.objects.create_user(username="notify-admin", password="password", is_staff=True)
        self.client.force_authenticate(user=staff_user)

        response = self.client.patch(
            reverse("notification-mark-read", args=[self.notification.id]),
            {},
            format="json",
        )

        self.assertEqual(response.status_code, 404)
        self.notification.refresh_from_db()
        self.assertFalse(self.notification.is_read)

    def test_recipient_can_mark_notification_read(self):
        self.client.force_authenticate(user=self.recipient)

        response = self.client.patch(
            reverse("notification-mark-read", args=[self.notification.id]),
            {},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.notification.refresh_from_db()
        self.assertTrue(self.notification.is_read)

    def test_recipient_can_delete_notification(self):
        self.client.force_authenticate(user=self.recipient)

        response = self.client.delete(
            reverse("notification-delete", args=[self.notification.id]),
        )

        self.assertEqual(response.status_code, 204)
        self.assertFalse(Notification.objects.filter(pk=self.notification.id).exists())

    def test_non_recipient_cannot_delete_notification(self):
        self.client.force_authenticate(user=self.other_user)

        response = self.client.delete(
            reverse("notification-delete", args=[self.notification.id]),
        )

        self.assertEqual(response.status_code, 404)
        self.assertTrue(Notification.objects.filter(pk=self.notification.id).exists())

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
    def test_create_notification_sends_full_detail_email(self):
        self.recipient.email = "notify-recipient@example.com"
        self.recipient.save(update_fields=["email"])
        detail_message = "This is a longer notification message with schedule, location, and rate details."

        notification = create_notification(
            recipient=self.recipient,
            notification_type=Notification.TYPE_ACCOUNT_ACTIVITY,
            title="Detailed account activity",
            message=detail_message,
            actor=self.other_user,
            related_job_id=10,
            related_application_id=20,
            action_type=Notification.ACTION_HIRE_REQUEST,
            action_url="/worker/jobs/10",
            requires_action=True,
        )

        self.assertEqual(notification.recipient, self.recipient)
        self.assertEqual(notification.actor, self.other_user)
        self.assertEqual(notification.related_job_id, 10)
        self.assertEqual(notification.related_application_id, 20)
        self.assertEqual(notification.action_type, Notification.ACTION_HIRE_REQUEST)
        self.assertEqual(notification.action_url, "/worker/jobs/10")
        self.assertTrue(notification.requires_action)
        self.assertEqual(len(mail.outbox), 1)
        self.assertEqual(mail.outbox[0].to, [self.recipient.email])
        self.assertEqual(mail.outbox[0].subject, "GawaGo: Detailed account activity")
        self.assertIn(detail_message, mail.outbox[0].body)

    def test_notification_list_includes_action_context(self):
        self.notification.related_job_id = 11
        self.notification.related_application_id = 22
        self.notification.action_type = Notification.ACTION_HIRE_REQUEST
        self.notification.actor = self.other_user
        self.notification.action_url = "/worker/jobs/11"
        self.notification.requires_action = True
        self.notification.save(
            update_fields=[
                "related_job_id",
                "related_application_id",
                "action_type",
                "actor",
                "action_url",
                "requires_action",
            ]
        )
        self.client.force_authenticate(user=self.recipient)

        response = self.client.get(reverse("notification-list"))

        self.assertEqual(response.status_code, 200)
        notification_payload = next(item for item in response.json() if item["id"] == self.notification.id)
        self.assertEqual(notification_payload["related_job_id"], 11)
        self.assertEqual(notification_payload["related_application_id"], 22)
        self.assertEqual(notification_payload["action_type"], Notification.ACTION_HIRE_REQUEST)
        self.assertEqual(notification_payload["actor"], self.other_user.id)
        self.assertEqual(notification_payload["actor_username"], self.other_user.username)
        self.assertEqual(notification_payload["action_url"], "/worker/jobs/11")
        self.assertTrue(notification_payload["requires_action"])


class EmailTimeoutSettingTests(TestCase):
    """A missing EMAIL_TIMEOUT lets Django's SMTP backend fall back to the OS
    socket default (minutes), so an unreachable mail host hangs whatever
    request triggered the email -- e.g. complete_job sends one inline per
    hired worker. Django's SMTP backend reads settings.EMAIL_TIMEOUT
    directly, so asserting the setting is what actually wires the fix in."""

    def test_email_timeout_is_configured(self):
        from django.conf import settings

        self.assertIsNotNone(settings.EMAIL_TIMEOUT)
        self.assertLessEqual(settings.EMAIL_TIMEOUT, 30)

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend", EMAIL_TIMEOUT=10)
    def test_smtp_backend_picks_up_the_configured_timeout(self):
        from django.core.mail import get_connection

        connection = get_connection()
        self.assertEqual(connection.timeout, 10)
