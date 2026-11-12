"""Regression tests for the My Complaints audit (2026-11-12): what the filer
sees about the person and the job, and the automatic rating flag."""

from django.test import TestCase
from django.urls import reverse

from apps.accounts.models import UserProfile
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.complaints.models import Complaint
from apps.jobs.models import JobPosting
from apps.reviews.models import Review


class FilerViewTests(TestCase):
    def setUp(self):
        self.household = make_user("mc-home", UserProfile.ROLE_HOUSEHOLD)
        self.household.first_name, self.household.last_name = "Emman", "Aviles"
        self.household.save()
        self.worker = make_user("mc-worker", UserProfile.ROLE_WORKER, skills=["House Cleaning"])
        self.job = make_job(self.household, title="Taga ayos ng Aircon", location_label="Alupay, Tayabas City, Quezon")
        Complaint.objects.create(
            complainant=self.worker, respondent=self.household, job=self.job,
            complaint_type="payment_issue", description="Not paid.",
        )

    def filed(self):
        rows = client_for(self.worker).get(reverse("complaint-list")).data
        return rows.get("results", rows)[0]

    def test_the_filer_sees_the_persons_name_and_nothing_private(self):
        row = self.filed()

        self.assertEqual(row["respondent_name"], "Emman Aviles")
        for private in ("respondent_detail", "complainant_detail", "admin_notes"):
            self.assertNotIn(private, row)

    def test_the_job_line_names_the_barangay_only(self):
        self.assertEqual(self.filed()["job_title"], "Taga ayos ng Aircon at Alupay")


class AutomaticRatingFlagTests(TestCase):
    def test_reviews_say_whether_the_rating_was_automatic(self):
        household = make_user("auto-home", UserProfile.ROLE_HOUSEHOLD)
        worker = make_user("auto-worker", UserProfile.ROLE_WORKER, skills=["House Cleaning"])
        job = make_job(household, status=JobPosting.STATUS_COMPLETED)
        Review.objects.create(
            job=job, author=household, target=worker, author_role="household", target_role="worker",
            rating=3.5, is_system_generated=True,
        )

        rows = client_for(worker).get(reverse("review-list-create"), {"target": worker.id}).data
        rows = rows.get("results", rows)

        self.assertTrue(rows)
        self.assertTrue(all("is_automatic" in row for row in rows))
        self.assertTrue(any(row["is_automatic"] for row in rows))
