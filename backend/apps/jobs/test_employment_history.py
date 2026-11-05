"""A worker's employment history carries the household's own rating of each
job, so the worker's profile and the profile households open show the same
overall as the household's My Jobs (2026-11-05)."""

from decimal import Decimal

from django.test import TestCase
from django.urls import reverse

from apps.accounts.models import UserProfile
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.jobs.models import JobApplication, JobPosting
from apps.reviews.models import Review


class EmploymentHistoryRatingTests(TestCase):
    def setUp(self):
        self.household = make_user("hist-house", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("hist-worker", UserProfile.ROLE_WORKER, skills=["Laundry"])
        self.job = make_job(self.household, title="Laundry and Ironing", status=JobPosting.STATUS_COMPLETED)
        JobApplication.objects.create(job=self.job, worker=self.worker, status=JobApplication.STATUS_COMPLETED)

    def history(self, viewer):
        response = client_for(viewer).get(
            reverse("job-list"), {"worker": self.worker.id, "status": "completed"}
        )
        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data["results"] if isinstance(response.data, dict) else response.data
        return next(row for row in rows if row["id"] == self.job.id)

    def review(self, **fields):
        values = {
            "author": self.household, "target": self.worker, "author_role": "household",
            "target_role": "worker", "job": self.job, "rating": Decimal("5.0"),
        }
        values.update(fields)
        return Review.objects.create(**values)

    def test_the_households_rating_is_the_jobs_overall(self):
        self.review(rating=Decimal("4.5"), quality_of_work=5, punctuality=4)

        row = self.history(self.worker)

        self.assertEqual(
            row["household_rating"],
            {
                "rating": 4.5,
                "is_default": False,
                "metrics": [{"label": "Quality of work", "value": 5}, {"label": "Punctuality", "value": 4}],
            },
        )

    def test_households_see_the_same_rating(self):
        self.review(rating=Decimal("5.0"))
        other_household = make_user("hist-viewer", UserProfile.ROLE_HOUSEHOLD)

        self.assertEqual(self.history(other_household)["household_rating"]["rating"], 5.0)

    def test_the_automatic_rating_is_marked(self):
        self.review(rating=Decimal("3.5"), is_system_generated=True)

        self.assertTrue(self.history(self.worker)["household_rating"]["is_default"])

    def test_an_unrated_job_has_no_rating(self):
        self.assertIsNone(self.history(self.worker)["household_rating"])

    def test_the_worker_side_review_is_not_mistaken_for_it(self):
        Review.objects.create(
            author=self.worker, target=self.household, author_role="worker", target_role="household",
            job=self.job, rating=Decimal("2.0"),
        )

        self.assertIsNone(self.history(self.worker)["household_rating"])
