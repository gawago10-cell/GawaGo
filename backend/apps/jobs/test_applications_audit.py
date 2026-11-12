"""Regression tests for the worker My Applications audit (2026-11-12): the
status after a job's last day, and telling an invitation from an
application."""

from datetime import timedelta
from unittest.mock import patch

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.jobs.models import JobApplication, JobPosting
from apps.jobs.statuses import STAGE_AWAITING_MARK_DONE, STAGE_IN_PROGRESS, get_application_stage


def days_from_today(offset):
    return timezone.localdate() + timedelta(days=offset)


class AwaitingMarkDoneStageTests(TestCase):
    def setUp(self):
        self.household = make_user("apps-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("apps-worker", UserProfile.ROLE_WORKER, skills=["House Cleaning"])

    def hired_on(self, start, end):
        job = make_job(
            self.household, status=JobPosting.STATUS_ASSIGNED, job_start_date=start, job_end_date=end
        )
        return JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)

    def stage_seen_by_worker(self, application):
        response = client_for(self.worker).get(reverse("job-application-list"))
        self.assertEqual(response.status_code, 200)
        rows = response.data.get("results", response.data)
        row = next(item for item in rows if item["id"] == application.id)
        return row["status_stage"], row["status_label"]

    def test_a_hire_past_its_last_day_waits_to_be_marked_done(self):
        application = self.hired_on(days_from_today(-4), days_from_today(-3))

        self.assertEqual(
            self.stage_seen_by_worker(application), (STAGE_AWAITING_MARK_DONE, "Waiting to be marked done")
        )

    def test_a_hire_on_or_before_its_last_day_is_in_progress(self):
        application = self.hired_on(days_from_today(-1), days_from_today(0))

        self.assertEqual(self.stage_seen_by_worker(application), (STAGE_IN_PROGRESS, "In progress"))

    def test_without_the_job_the_stage_is_unchanged(self):
        self.assertEqual(
            get_application_stage(JobApplication.STATUS_HIRED, JobPosting.STATUS_ASSIGNED), STAGE_IN_PROGRESS
        )


class InvitedFlagTests(TestCase):
    def setUp(self):
        self.household = make_user("invite-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("invite-worker", UserProfile.ROLE_WORKER, skills=["House Cleaning"])
        self.job = make_job(self.household, job_start_date=days_from_today(5), job_end_date=days_from_today(5))

    def invited_flag(self):
        response = client_for(self.worker).get(reverse("job-application-list"))
        rows = response.data.get("results", response.data)
        return next(item for item in rows if item["job_id"] == self.job.id)["invited"]

    def invite(self):
        response = client_for(self.household).post(
            reverse("job-hire-request", args=[self.job.id]), {"worker_id": self.worker.id}, format="json"
        )
        self.assertEqual(response.status_code, 201, response.data)

    def test_a_household_invitation_reads_as_invited(self):
        self.invite()

        self.assertTrue(self.invited_flag())

    def test_an_application_reads_as_applied(self):
        response = client_for(self.worker).post(reverse("job-apply", args=[self.job.id]), {}, format="json")
        self.assertEqual(response.status_code, 201, response.data)

        self.assertFalse(self.invited_flag())

    def test_an_applicant_invited_later_still_reads_as_applied(self):
        response = client_for(self.worker).post(reverse("job-apply", args=[self.job.id]), {}, format="json")
        self.assertEqual(response.status_code, 201, response.data)
        later = timezone.now() + timedelta(hours=2)
        with patch("django.utils.timezone.now", return_value=later):
            self.invite()

        self.assertFalse(self.invited_flag())


class HoldFreeFromTests(TestCase):
    """My Jobs: when a hired worker may take other jobs again after a job's
    last day, if the household never marks it done (audit 2026-11-12)."""

    def setUp(self):
        self.household = make_user("free-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("free-worker", UserProfile.ROLE_WORKER, skills=["House Cleaning"])

    def free_from(self, schedule_type, start, end):
        job = make_job(
            self.household, status=JobPosting.STATUS_ASSIGNED, schedule_type=schedule_type,
            job_start_date=start, job_end_date=end,
        )
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)
        rows = client_for(self.worker).get(reverse("job-application-list")).data
        rows = rows.get("results", rows)
        return next(item for item in rows if item["job_id"] == job.id)["hold_free_from"]

    def test_a_full_time_job_past_its_last_day_names_the_day_the_hold_ends(self):
        end = days_from_today(-1)
        self.assertEqual(self.free_from("Full-Time", days_from_today(-20), end), str(end + timedelta(days=4)))

    def test_a_one_time_job_holds_only_its_own_days(self):
        self.assertIsNone(self.free_from("One-Time", days_from_today(-2), days_from_today(-1)))

    def test_a_full_time_job_still_running_has_no_free_from(self):
        self.assertIsNone(self.free_from("Full-Time", days_from_today(-3), days_from_today(5)))
