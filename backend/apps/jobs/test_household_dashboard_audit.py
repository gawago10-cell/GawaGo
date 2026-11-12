"""Household dashboard audit (2026-11-13): a job's own status words, and a
job left "in progress" with nobody hired."""

import importlib
from datetime import timedelta

from django.apps import apps as django_apps
from django.contrib.admin.sites import AdminSite
from django.test import RequestFactory, TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.accounts.services import apply_account_suspension
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.jobs.admin import JobApplicationAdmin
from apps.jobs.models import JobApplication, JobPosting, JobStatusEvent


def days_from_today(offset):
    return timezone.localdate() + timedelta(days=offset)


class JobStageTests(TestCase):
    def setUp(self):
        self.household = make_user("hd-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("hd-worker", UserProfile.ROLE_WORKER)

    def job_view(self, job):
        response = client_for(self.household).get(reverse("job-detail", args=[job.id]))
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def test_a_hired_job_past_its_last_day_waits_to_be_marked_done(self):
        job = make_job(
            self.household, status=JobPosting.STATUS_ASSIGNED,
            job_start_date=days_from_today(-5), job_end_date=days_from_today(-4), estimated_working_days=1,
        )
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)

        data = self.job_view(job)

        self.assertEqual(data["status_stage"], "awaiting_mark_done")
        self.assertEqual(data["status_label"], "Waiting to be marked done")
        self.assertTrue(data["can_mark_done"])

    def test_a_hired_job_still_running_is_in_progress(self):
        job = make_job(
            self.household, status=JobPosting.STATUS_ASSIGNED,
            job_start_date=days_from_today(-1), job_end_date=days_from_today(2),
        )
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)

        self.assertEqual(self.job_view(job)["status_label"], "In progress")

    def test_a_suspended_workers_hire_still_counts(self):
        job = make_job(
            self.household, status=JobPosting.STATUS_ASSIGNED,
            job_start_date=days_from_today(-5), job_end_date=days_from_today(-4),
        )
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)
        apply_account_suspension(self.worker.profile, blocked=True, reason="Test", duration_days=7)

        data = self.job_view(job)

        self.assertEqual(data["status_label"], "Waiting to be marked done")
        self.assertTrue(data["can_mark_done"])
        hire = data["applications"][0]
        self.assertEqual(hire["worker_name"], self.worker.username)
        self.assertFalse(hire["worker_available"])

    def test_in_progress_with_nobody_hired_says_why_it_cant_be_marked_done(self):
        job = make_job(
            self.household, status=JobPosting.STATUS_ASSIGNED,
            job_start_date=days_from_today(-5), job_end_date=days_from_today(-4),
        )

        data = self.job_view(job)

        self.assertEqual(data["status_stage"], "open")
        self.assertFalse(data["can_mark_done"])
        self.assertEqual(
            data["mark_done_note"],
            "Nobody is hired on this job any more, so it can't be marked done. You can cancel it.",
        )
        self.assertTrue(data["can_cancel"])


class NobodyHiredReopensTests(TestCase):
    def setUp(self):
        self.household = make_user("hd2-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("hd2-worker", UserProfile.ROLE_WORKER)
        self.job = make_job(
            self.household, status=JobPosting.STATUS_ASSIGNED,
            job_start_date=days_from_today(-5), job_end_date=days_from_today(-4),
        )
        self.hire = JobApplication.objects.create(job=self.job, worker=self.worker, status=JobApplication.STATUS_HIRED)

    def test_deleting_the_hired_workers_account_reopens_the_job(self):
        with self.captureOnCommitCallbacks(execute=True):
            self.worker.delete()

        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_OPEN)
        event = JobStatusEvent.objects.get(job=self.job, to_status=JobPosting.STATUS_OPEN)
        self.assertEqual(event.from_status, JobPosting.STATUS_ASSIGNED)
        self.assertEqual(event.note, "Reopened: the hired worker's record was removed.")
        # The household now sees the lapsed open job, not a stuck one.
        data = client_for(self.household).get(reverse("job-detail", args=[self.job.id])).data
        self.assertTrue(data["expired_note"])

    def test_deleting_the_whole_job_is_fine(self):
        with self.captureOnCommitCallbacks(execute=True):
            self.household.delete()

        self.assertFalse(JobPosting.objects.filter(pk=self.job.pk).exists())

    def test_one_hire_of_two_removed_keeps_the_job_in_progress(self):
        other = make_user("hd2-other", UserProfile.ROLE_WORKER)
        JobApplication.objects.create(job=self.job, worker=other, status=JobApplication.STATUS_HIRED)

        with self.captureOnCommitCallbacks(execute=True):
            self.worker.delete()

        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_ASSIGNED)

    def test_changing_the_hire_in_the_admin_reopens_the_job(self):
        admin = make_user("hd2-admin", superuser=True)
        request = RequestFactory().post("/")
        request.user = admin
        self.hire.status = JobApplication.STATUS_CLOSED

        with self.captureOnCommitCallbacks(execute=True):
            JobApplicationAdmin(JobApplication, AdminSite()).save_model(request, self.hire, None, change=True)

        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_OPEN)
        self.assertTrue(JobStatusEvent.objects.filter(job=self.job, note__contains="admin").exists())

    def test_the_migration_reopens_jobs_already_stuck(self):
        stuck = make_job(
            self.household, title="Gardening", status=JobPosting.STATUS_ASSIGNED,
            job_start_date=days_from_today(-5), job_end_date=days_from_today(-4),
        )
        migration = importlib.import_module("apps.jobs.migrations.0016_reopen_jobs_with_nobody_hired")

        migration.reopen_jobs_with_nobody_hired(django_apps, None)

        stuck.refresh_from_db()
        self.job.refresh_from_db()
        self.assertEqual(stuck.status, JobPosting.STATUS_OPEN)
        self.assertEqual(self.job.status, JobPosting.STATUS_ASSIGNED)  # it has its hire
        self.assertTrue(
            JobStatusEvent.objects.filter(job=stuck, from_status="assigned", to_status="open").exists()
        )


class RateGuideIgnoresOldSubPesoRatesTests(TestCase):
    """Post a Job audit (2026-11-13): two PHP 0.11 posts from before the
    PHP 1 minimum made the hint read "about PHP 0 / day"."""

    def test_rates_under_one_peso_are_left_out(self):
        household = make_user("rg-home", UserProfile.ROLE_HOUSEHOLD)
        for rate in ("0.11", "0.11", "500.00", "700.00"):
            make_job(household, required_skill="Gardening", service_rate=rate)

        guide = client_for(household).get(reverse("job-rate-guide"), {"skill": "Gardening", "rate_type": "per_day"}).data

        self.assertEqual(guide["posts"], 2)
        self.assertEqual(guide["label"], "Gardening usually posts at about PHP 600 / day.")

    def test_only_old_sub_peso_rates_give_no_hint(self):
        household = make_user("rg2-home", UserProfile.ROLE_HOUSEHOLD)
        for _ in range(3):
            make_job(household, required_skill="Gardening", service_rate="0.11")

        guide = client_for(household).get(reverse("job-rate-guide"), {"skill": "Gardening", "rate_type": "per_day"}).data

        self.assertEqual(guide["label"], "")
