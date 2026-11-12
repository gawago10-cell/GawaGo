"""Household notifications audit (2026-11-13): "Mark the job as done" is
answered once the job stops being in progress."""

import importlib
from datetime import timedelta

from django.apps import apps as django_apps
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.jobs.models import JobApplication, JobPosting
from apps.jobs.services import MARK_DONE_REMINDER_TITLE, send_due_mark_done_reminders
from apps.notifications.models import Notification


def days_from_today(offset):
    return timezone.localdate() + timedelta(days=offset)


class MarkDoneReminderTests(TestCase):
    def setUp(self):
        self.household = make_user("mr-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("mr-worker", UserProfile.ROLE_WORKER)
        self.job = make_job(
            self.household, status=JobPosting.STATUS_ASSIGNED,
            job_start_date=days_from_today(-5), job_end_date=days_from_today(-4),
        )
        self.hire = JobApplication.objects.create(job=self.job, worker=self.worker, status=JobApplication.STATUS_HIRED)
        self.assertEqual(send_due_mark_done_reminders(), 1)

    def reminders(self, **filters):
        return Notification.objects.filter(
            recipient=self.household, related_job_id=self.job.id, title=MARK_DONE_REMINDER_TITLE, **filters
        )

    def test_marking_the_job_done_answers_it(self):
        response = client_for(self.household).patch(reverse("job-detail", args=[self.job.id]), {"status": "completed"}, format="json")

        self.assertEqual(response.status_code, 200, response.data)
        reminder = self.reminders().get()
        self.assertFalse(reminder.requires_action)
        self.assertTrue(reminder.is_read)

    def test_cancelling_answers_it(self):
        response = client_for(self.household).patch(
            reverse("job-detail", args=[self.job.id]),
            {"status": "cancelled", "cancel_reason": "The worker never came."},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(self.reminders(requires_action=True).exists())

    def test_reopening_with_nobody_hired_answers_it_and_a_new_hire_is_reminded_again(self):
        with self.captureOnCommitCallbacks(execute=True):
            self.worker.delete()
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_OPEN)
        self.assertFalse(self.reminders(requires_action=True).exists())

        # Hired again for new dates that also pass: reminded again.
        other = make_user("mr-other", UserProfile.ROLE_WORKER)
        self.job.status = JobPosting.STATUS_ASSIGNED
        self.job.job_start_date = days_from_today(-3)
        self.job.job_end_date = days_from_today(-2)
        self.job.save()
        JobApplication.objects.create(job=self.job, worker=other, status=JobApplication.STATUS_HIRED)

        self.assertEqual(send_due_mark_done_reminders(), 1)
        self.assertEqual(self.reminders(requires_action=True).count(), 1)

    def test_a_reminder_still_waiting_isnt_sent_twice(self):
        self.reminders().update(is_read=True)  # read, but not answered
        self.assertEqual(send_due_mark_done_reminders(), 0)

    def test_the_migration_answers_reminders_already_left_behind(self):
        # As production has them: the job finished before this change.
        JobPosting.objects.filter(pk=self.job.pk).update(status=JobPosting.STATUS_COMPLETED)
        migration = importlib.import_module("apps.jobs.migrations.0017_clear_answered_mark_done_reminders")

        migration.clear_answered_reminders(django_apps, None)

        self.assertFalse(self.reminders(requires_action=True).exists())
