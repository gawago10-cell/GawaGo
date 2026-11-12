"""Notifications audit (2026-11-12): one "mark all read" request, and
notices that say what happened."""

from datetime import timedelta

from django.core import mail
from django.urls import reverse
from django.test import TestCase
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.jobs.models import JobApplication, JobPosting
from apps.notifications.models import Notification


def days_from_today(offset):
    return timezone.localdate() + timedelta(days=offset)


def notice(user, **filters):
    return Notification.objects.filter(recipient=user, **filters).order_by("-id").first()


class MarkAllReadTests(TestCase):
    def setUp(self):
        self.user = make_user("na-reader", UserProfile.ROLE_WORKER)
        self.other = make_user("na-other", UserProfile.ROLE_WORKER)
        for index in range(3):
            Notification.objects.create(
                recipient=self.user, notification_type=Notification.TYPE_APPLICATION, title=f"N{index}", message="x"
            )
        Notification.objects.create(
            recipient=self.user, notification_type=Notification.TYPE_APPLICATION, title="Old", message="x", is_read=True
        )
        Notification.objects.create(
            recipient=self.other, notification_type=Notification.TYPE_APPLICATION, title="Theirs", message="x"
        )

    def test_one_request_marks_only_my_unread_ones(self):
        response = client_for(self.user).post(reverse("notification-mark-all-read"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, {"updated": 3})
        self.assertFalse(Notification.objects.filter(recipient=self.user, is_read=False).exists())
        self.assertTrue(Notification.objects.filter(recipient=self.other, is_read=False).exists())
        count = client_for(self.user).get(reverse("notification-unread-count"))
        self.assertEqual(count.data, {"unread": 0})

    def test_signed_out_is_refused(self):
        from rest_framework.test import APIClient

        self.assertEqual(APIClient().post(reverse("notification-mark-all-read")).status_code, 401)


class ProfileNoticeTests(TestCase):
    def setUp(self):
        self.worker = make_user("na-profile", UserProfile.ROLE_WORKER, bio="Old bio", phone="9170000000")
        self.client = client_for(self.worker)

    def save(self, data):
        with self.captureOnCommitCallbacks(execute=True):
            response = self.client.patch(reverse("profile-me"), data, format="json")
        self.assertEqual(response.status_code, 200, response.data)

    def test_a_save_that_changes_nothing_sends_nothing(self):
        mail.outbox.clear()
        self.save({"bio": "Old bio", "phone": "09170000000", "first_name": "", "daily_rate": "600.00"})

        self.assertIsNone(notice(self.worker, notification_type=Notification.TYPE_ACCOUNT_ACTIVITY))
        self.assertEqual(mail.outbox, [])

    def test_a_routine_change_is_named_without_an_alarm(self):
        self.save({"bio": "New bio", "daily_rate": "650.00"})

        item = notice(self.worker, notification_type=Notification.TYPE_ACCOUNT_ACTIVITY)
        self.assertEqual(item.title, "Profile updated")
        self.assertEqual(item.message, "You changed your rates and bio.")

    def test_a_contact_change_warns(self):
        self.save({"email": "na-new@example.com", "current_password": "pass-12345", "bio": "New bio"})

        item = notice(self.worker, notification_type=Notification.TYPE_ACCOUNT_ACTIVITY)
        self.assertEqual(item.title, "Contact details changed")
        self.assertEqual(
            item.message, "You changed your email address and bio. If this wasn't you, reset your password right away."
        )
        self.assertNotIn("contact support", item.message)


class JobNoticeTests(TestCase):
    def setUp(self):
        self.household = make_user("na-home", UserProfile.ROLE_HOUSEHOLD)
        self.household.first_name, self.household.last_name = "Emman", "Aviles"
        self.household.save(update_fields=["first_name", "last_name"])
        self.worker = make_user("na-worker", UserProfile.ROLE_WORKER)

    def test_hiring_an_applicant_says_hired_with_the_start_day(self):
        start = days_from_today(3)
        job = make_job(self.household, title="Garden cleanup", job_start_date=start, job_end_date=start)
        application = JobApplication.objects.create(job=job, worker=self.worker)

        response = client_for(self.household).patch(
            reverse("job-application-status", args=[application.id]), {"status": "hired"}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)
        item = notice(self.worker, notification_type=Notification.TYPE_ACCEPTED)
        self.assertEqual(item.title, "You're hired")
        self.assertEqual(
            item.message,
            f"Emman Aviles hired you for Garden cleanup. It starts {start:%a}, {start:%b} {start.day}, {start.year}.",
        )

    def test_marked_done_names_who_and_asks_for_the_rating_until_given(self):
        job = make_job(
            self.household, title="Garden cleanup", status=JobPosting.STATUS_ASSIGNED,
            job_start_date=days_from_today(-1), job_end_date=days_from_today(0),
        )
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)

        response = client_for(self.household).patch(reverse("job-detail", args=[job.id]), {"status": "completed"}, format="json")
        self.assertEqual(response.status_code, 200, response.data)

        item = notice(self.worker, notification_type=Notification.TYPE_COMPLETION)
        self.assertEqual(item.title, "Job marked done")
        self.assertEqual(
            item.message,
            "Emman Aviles marked Garden cleanup as done. You can now rate the household; your feedback stays anonymous.",
        )
        self.assertTrue(item.requires_action)

        feedback = client_for(self.worker).post(
            reverse("review-list-create"),
            {"target_username": self.household.username, "job_id": job.id, "rating": 4},
            format="json",
        )
        self.assertEqual(feedback.status_code, 201, feedback.data)
        item.refresh_from_db()
        self.assertFalse(item.requires_action)

    def test_the_review_notice_gives_the_job_and_the_metric_average(self):
        job = make_job(
            self.household, title="Garden cleanup", status=JobPosting.STATUS_COMPLETED,
            job_start_date=days_from_today(-2),
        )
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_COMPLETED)

        response = client_for(self.household).post(
            reverse("review-list-create"),
            {
                "target_username": self.worker.username, "job_id": job.id,
                "quality_of_work": 5, "punctuality": 4, "communication": 5, "professionalism": 4,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        item = notice(self.worker, notification_type=Notification.TYPE_REVIEW)
        self.assertEqual(item.message, "Emman Aviles rated you 4.5 / 5 for Garden cleanup.")
