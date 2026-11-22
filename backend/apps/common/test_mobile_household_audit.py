"""Mobile household audit (2026-11-23): server-side fixes."""

from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.jobs.models import JobApplication, JobPosting
from apps.matching.services import get_worker_rate_label
from apps.reviews.models import Review


class RoundedRatingTests(TestCase):
    def setUp(self):
        self.household = make_user("mh-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("mh-worker", UserProfile.ROLE_WORKER)
        self.job = make_job(
            self.household,
            status=JobPosting.STATUS_COMPLETED,
            completed_at=timezone.now(),
        )
        JobApplication.objects.create(job=self.job, worker=self.worker, status=JobApplication.STATUS_COMPLETED)

    def review(self, **fields):
        return client_for(self.household).post(
            reverse("review-list-create"),
            {"target_username": self.worker.username, "job_id": self.job.id, **fields},
            format="json",
        )

    def test_an_exact_metric_average_is_accepted_and_rounded(self):
        # 4, 5, 4, 4 average 4.25; the field refused it before validate() ran.
        response = self.review(
            rating="4.25", quality_of_work=4, punctuality=5, communication=4, professionalism=4
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Review.objects.get().rating, Decimal("4.3"))

    def test_an_overall_rating_alone_is_rounded_to_one_decimal(self):
        response = self.review(rating="3.75")

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Review.objects.get().rating, Decimal("3.8"))


class WorkerRateLabelTests(TestCase):
    def test_the_rate_carries_its_unit(self):
        daily = make_user("mh-daily", UserProfile.ROLE_WORKER, daily_rate=Decimal("500"))
        hourly = make_user("mh-hourly", UserProfile.ROLE_WORKER, daily_rate=None, hourly_rate=Decimal("120"))

        self.assertEqual(get_worker_rate_label(daily.profile), "PHP 500.00 / day")
        self.assertEqual(get_worker_rate_label(hourly.profile), "PHP 120.00 / hour")
