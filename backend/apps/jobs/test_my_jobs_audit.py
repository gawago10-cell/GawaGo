"""Household My Jobs audit (2026-11-13): the spend estimate, ratings the
household actually gave, and why a job was cancelled."""

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.jobs.models import JobApplication, JobPosting
from apps.reviews.models import Review


def days_from_today(offset):
    return timezone.localdate() + timedelta(days=offset)


class EstimatedValueTests(TestCase):
    def setUp(self):
        self.household = make_user("mj-home", UserProfile.ROLE_HOUSEHOLD)
        self.workers = [make_user(f"mj-worker{i}", UserProfile.ROLE_WORKER) for i in range(2)]

    def completed(self, **fields):
        job = make_job(self.household, status=JobPosting.STATUS_COMPLETED, **fields)
        for worker in self.workers:
            JobApplication.objects.create(job=job, worker=worker, status=JobApplication.STATUS_COMPLETED)
        return job

    def view(self, job, user=None):
        return client_for(user or self.household).get(reverse("job-detail", args=[job.id])).data

    def test_a_day_rate_counts_its_days_and_workers(self):
        job = self.completed(
            service_rate=Decimal("700.00"), job_start_date=days_from_today(-6), job_end_date=days_from_today(-2),
        )
        self.assertEqual(self.view(job)["estimated_value"], "7000.00")  # 700 x 5 days x 2 workers

    def test_a_fixed_rate_counts_its_workers_and_hourly_has_none(self):
        fixed = self.completed(service_rate=Decimal("1500.00"), rate_type=JobPosting.RATE_FIXED)
        hourly = self.completed(service_rate=Decimal("80.00"), rate_type=JobPosting.RATE_PER_HOUR)
        self.assertEqual(self.view(fixed)["estimated_value"], "3000.00")
        self.assertIsNone(self.view(hourly)["estimated_value"])

    def test_only_the_household_sees_it(self):
        job = self.completed(service_rate=Decimal("500.00"))
        self.assertIsNone(self.view(job, user=self.workers[0])["estimated_value"])

    def test_the_household_report_uses_the_same_estimate(self):
        self.completed(
            service_rate=Decimal("700.00"), job_start_date=days_from_today(-6), job_end_date=days_from_today(-2),
        )
        self.completed(service_rate=Decimal("80.00"), rate_type=JobPosting.RATE_PER_HOUR)

        summary = client_for(self.household).get(reverse("my-report")).data["summary"]

        self.assertEqual(summary["totalSpend"], 7000.0)
        self.assertEqual(summary["averageJobRate"], 390.0)  # the rates themselves


class RatingsGivenTests(TestCase):
    def test_the_automatic_rating_isnt_counted_as_given(self):
        household = make_user("rg-home", UserProfile.ROLE_HOUSEHOLD)
        worker = make_user("rg-worker", UserProfile.ROLE_WORKER)
        for rating, automatic in ((Decimal("5.0"), False), (Decimal("3.5"), True)):
            job = make_job(household, status=JobPosting.STATUS_COMPLETED)
            JobApplication.objects.create(job=job, worker=worker, status=JobApplication.STATUS_COMPLETED)
            Review.objects.create(
                author=household, target=worker, author_role="household", target_role="worker",
                job=job, rating=rating, is_system_generated=automatic,
            )

        summary = client_for(household).get(reverse("my-report")).data["summary"]

        self.assertEqual(summary["reviewsGiven"], 1)
        self.assertEqual(summary["averageRatingGiven"], 5.0)
        # The clients tell the two apart by is_automatic.
        reviews = client_for(household).get(reverse("review-list-create"), {"author_username": household.username}).data
        rows = reviews["results"] if isinstance(reviews, dict) else reviews
        self.assertEqual(sorted(row["is_automatic"] for row in rows), [False, True])


class CancelReasonTests(TestCase):
    def setUp(self):
        self.household = make_user("cr-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("cr-worker", UserProfile.ROLE_WORKER)

    def test_the_reason_given_is_kept_and_shown_to_the_household(self):
        job = make_job(
            self.household, status=JobPosting.STATUS_ASSIGNED,
            job_start_date=days_from_today(3), job_end_date=days_from_today(4),
        )
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)

        response = client_for(self.household).patch(
            reverse("job-detail", args=[job.id]),
            {"status": "cancelled", "cancel_reason": "We are moving house that week."},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        data = client_for(self.household).get(reverse("job-detail", args=[job.id])).data
        self.assertEqual(data["cancel_reason"], "We are moving house that week.")
        # The hire stays on record, so the card can name who was booked.
        self.assertEqual([(a["worker_username"], a["status"]) for a in data["applications"]], [("cr-worker", "hired")])
        # Not shown to the worker through the job itself.
        self.assertEqual(client_for(self.worker).get(reverse("job-detail", args=[job.id])).data["cancel_reason"], "")

    def test_a_job_cancelled_before_anyone_was_hired_has_no_reason(self):
        job = make_job(self.household, job_start_date=days_from_today(3))

        response = client_for(self.household).patch(reverse("job-detail", args=[job.id]), {"status": "cancelled"}, format="json")

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(client_for(self.household).get(reverse("job-detail", args=[job.id])).data["cancel_reason"], "")
