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
        ids = {item["id"] for item in response.json()["results"]}
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
        notification_payload = next(item for item in response.json()["results"] if item["id"] == self.notification.id)
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


class NotificationPaginationTests(TestCase):
    """The list used to return every notification in one response, so a user
    with a long history downloaded all of it on every poll."""

    def setUp(self):
        self.user = User.objects.create_user(username="paged-user", password="password")
        for index in range(25):
            Notification.objects.create(
                recipient=self.user,
                notification_type=Notification.TYPE_ACCOUNT_ACTIVITY,
                title=f"n{index}",
                message="m",
            )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_the_list_is_paged_and_loses_nothing(self):
        first = self.client.get(reverse("notification-list")).json()

        self.assertEqual(first["count"], 25)
        self.assertEqual(len(first["results"]), 20)
        self.assertIsNotNone(first["next"])

        second = self.client.get(first["next"]).json()
        self.assertEqual(len(second["results"]), 5)
        self.assertIsNone(second["next"])
        ids = {n["id"] for n in first["results"]} | {n["id"] for n in second["results"]}
        self.assertEqual(len(ids), 25)


class AdminAlertTests(TestCase):
    """Admin alerts (AGENTS.md III.A): admins hear about new queue items."""

    def setUp(self):
        self.superadmin = User.objects.create_user(
            username="alert-super", email="super@example.com", password="password", is_staff=True, is_superuser=True
        )
        self.staff_admin = User.objects.create_user(
            username="alert-staff", email="staff@example.com", password="password", is_staff=True
        )
        self.inactive_admin = User.objects.create_user(
            username="alert-inactive", password="password", is_staff=True, is_active=False
        )
        self.member = User.objects.create_user(username="alert-member", password="password")

    def test_notify_admins_reaches_every_active_admin_only(self):
        from apps.notifications.services import notify_admins

        with self.captureOnCommitCallbacks(execute=True):
            sent = notify_admins(title="New verification request", message="Waiting for review.")

        self.assertEqual(sent, 2)
        recipients = set(
            Notification.objects.filter(notification_type=Notification.TYPE_ADMIN_ALERT).values_list(
                "recipient__username", flat=True
            )
        )
        self.assertEqual(recipients, {"alert-super", "alert-staff"})
        self.assertEqual(sorted(message.to[0] for message in mail.outbox), ["staff@example.com", "super@example.com"])

    def test_superadmin_only_alerts_skip_plain_admins(self):
        from apps.notifications.services import notify_admins

        notify_admins(title="New complaint to review", message="Waiting.", superadmins_only=True)

        self.assertEqual(
            list(Notification.objects.values_list("recipient__username", flat=True)), ["alert-super"]
        )

    def test_filing_a_complaint_alerts_superadmins_without_naming_anyone(self):
        from apps.accounts.models import UserProfile
        from apps.jobs.models import JobApplication, JobPosting

        household = User.objects.create_user(username="alert-household", password="password")
        UserProfile.objects.create(user=household, role=UserProfile.ROLE_HOUSEHOLD, verification_status="verified")
        worker = User.objects.create_user(username="alert-worker", password="password")
        UserProfile.objects.create(user=worker, role=UserProfile.ROLE_WORKER, verification_status="verified")
        job = JobPosting.objects.create(
            household=household,
            title="Cleaning",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-01 09:00",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
        )
        JobApplication.objects.create(job=job, worker=worker)
        client = APIClient()
        client.force_authenticate(user=household)

        response = client.post(
            reverse("complaint-create"),
            {"job": job.id, "respondent": worker.id, "complaint_type": "no_show", "description": "Never came."},
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        alert = Notification.objects.get(notification_type=Notification.TYPE_ADMIN_ALERT)
        self.assertEqual(alert.recipient, self.superadmin)
        self.assertNotIn("alert-worker", alert.message)
        self.assertNotIn("alert-household", alert.message)
        self.assertFalse(Notification.objects.filter(recipient=worker).exists())
