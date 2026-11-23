"""Mobile worker audit (2026-11-23): server-side fixes."""

from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.common.models import VerificationRequest
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.complaints.models import Complaint
from apps.jobs.models import JobApplication, JobPosting
from apps.notifications.models import Notification
from apps.notifications.services import create_notification
from apps.reviews.models import Review


def days_from_today(days):
    return timezone.localdate() + timedelta(days=days)


class OneRatingEverywhereTests(TestCase):
    """One review read 4.3 (rating), 4.2 (overall_rating) and 4.38 (the
    profile average)."""

    def setUp(self):
        self.worker = make_user("mw-worker", UserProfile.ROLE_WORKER)
        self.households = [make_user(f"mw-home-{n}", UserProfile.ROLE_HOUSEHOLD) for n in range(2)]
        self.jobs = []
        for household in self.households:
            job = make_job(household, status=JobPosting.STATUS_COMPLETED, completed_at=timezone.now())
            JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_COMPLETED)
            self.jobs.append(job)

    def review(self, index, **fields):
        return client_for(self.households[index]).post(
            reverse("review-list-create"),
            {"target_username": self.worker.username, "job_id": self.jobs[index].id, **fields},
            format="json",
        )

    def test_a_review_and_the_profile_read_the_same_rounded_numbers(self):
        # 4, 5, 4, 4 average 4.25: stored and shown as 4.3, not 4.2.
        first = self.review(0, rating="4.25", quality_of_work=4, punctuality=5, communication=4, professionalism=4)
        self.assertEqual(first.status_code, 201, first.data)
        second = self.review(1, rating=4.5)
        self.assertEqual(second.status_code, 201, second.data)

        listed = client_for(self.worker).get(reverse("review-list-create")).json()
        rows = listed.get("results", listed)
        by_job = {row["job"]: row for row in rows}
        self.assertEqual(by_job[self.jobs[0].id]["overall_rating"], 4.3)
        self.assertEqual(Decimal(by_job[self.jobs[0].id]["rating"]), Decimal("4.3"))

        profile = UserProfile.objects.get(user=self.worker)
        # (4.3 + 4.5) / 2 = 4.4; it was 4.38 from the unrounded 4.25.
        self.assertEqual(profile.average_rating, Decimal("4.4"))
        self.assertEqual(profile.display_rating, "4.4")

    def test_a_review_with_a_half_tenth_average_rounds_up_everywhere(self):
        # (4.3 + 4.4) / 2 = 4.35 -> 4.4, never 4.3.
        Review.objects.create(
            author=self.households[0], target=self.worker, job=self.jobs[0], rating=Decimal("4.3"),
            author_role=Review.ROLE_HOUSEHOLD, target_role=Review.ROLE_WORKER,
        )
        Review.objects.create(
            author=self.households[1], target=self.worker, job=self.jobs[1], rating=Decimal("4.4"),
            author_role=Review.ROLE_HOUSEHOLD, target_role=Review.ROLE_WORKER,
        )
        from apps.reviews.services import recalculate_user_rating

        recalculate_user_rating(self.worker)
        self.assertEqual(UserProfile.objects.get(user=self.worker).display_rating, "4.4")


class StageWordsTests(TestCase):
    def setUp(self):
        self.household = make_user("mw-sw-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("mw-sw-worker", UserProfile.ROLE_WORKER)

    def job(self, start_in_days, **fields):
        start = days_from_today(start_in_days)
        return make_job(self.household, job_start_date=start, job_end_date=start + timedelta(days=1), **fields)

    def worker_row(self, job):
        rows = client_for(self.worker).get(reverse("job-application-list")).json()
        rows = rows.get("results", rows)
        return next(row for row in rows if row["job_id"] == job.id)

    def test_a_hire_before_the_first_day_reads_hired_and_the_job_not_started(self):
        job = self.job(5, status=JobPosting.STATUS_ASSIGNED)
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)

        row = self.worker_row(job)
        self.assertEqual((row["status_stage"], row["status_label"]), ("hired", "Hired"))
        detail = client_for(self.household).get(reverse("job-detail", args=[job.id])).json()
        self.assertEqual((detail["status_stage"], detail["status_label"]), ("not_started", "Not started yet"))

    def test_from_the_first_day_it_reads_in_progress(self):
        job = self.job(0, status=JobPosting.STATUS_ASSIGNED)
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)

        self.assertEqual(self.worker_row(job)["status_label"], "In progress")
        detail = client_for(self.household).get(reverse("job-detail", args=[job.id])).json()
        self.assertEqual(detail["status_label"], "In progress")

    def invite(self, job):
        response = client_for(self.household).post(
            reverse("job-hire-request", args=[job.id]), {"worker_username": self.worker.username}, format="json"
        )
        self.assertEqual(response.status_code, 201, response.data)
        return JobApplication.objects.get(job=job, worker=self.worker)

    def test_a_hire_request_is_the_workers_to_answer(self):
        job = self.job(5)
        application = self.invite(job)

        self.assertEqual(self.worker_row(job)["status_label"], "Hire request received")
        rows = client_for(self.household).get(reverse("job-application-list")).json()
        rows = rows.get("results", rows)
        household_row = next(row for row in rows if row["id"] == application.id)
        self.assertEqual(household_row["status_label"], "Awaiting worker response")

    def test_a_withdrawn_invitation_is_not_a_rejection(self):
        job = self.job(5)
        application = self.invite(job)
        response = client_for(self.household).patch(
            reverse("job-application-status", args=[application.id]), {"status": "rejected"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)

        row = self.worker_row(job)
        self.assertEqual((row["status_stage"], row["status_label"]), ("invitation_withdrawn", "Invitation withdrawn"))

    def test_an_invitation_the_worker_turned_down_reads_declined(self):
        job = self.job(5)
        application = self.invite(job)
        response = client_for(self.worker).patch(
            reverse("job-application-decision", args=[application.id]), {"decision": "reject"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)

        self.assertEqual(self.worker_row(job)["status_label"], "Declined")

    def test_a_rejected_application_still_reads_rejected(self):
        job = self.job(5)
        application = JobApplication.objects.create(job=job, worker=self.worker)
        response = client_for(self.household).patch(
            reverse("job-application-status", args=[application.id]), {"status": "rejected"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)

        self.assertEqual(self.worker_row(job)["status_label"], "Rejected")


class UnverifiedWorkerSeesJobsTests(TestCase):
    """An unverified worker saw no jobs at all: Find Jobs lists only jobs the
    worker can apply to or is told why not."""

    def setUp(self):
        self.household = make_user("mw-uv-home", UserProfile.ROLE_HOUSEHOLD)
        start = days_from_today(5)
        self.job = make_job(self.household, job_start_date=start, job_end_date=start)
        self.worker = make_user("mw-uv-worker", UserProfile.ROLE_WORKER, verification_status="pending")

    def listed(self):
        rows = client_for(self.worker).get(reverse("job-list"), {"accepting": "true"}).json()
        rows = rows.get("results", rows)
        return next(row for row in rows if row["id"] == self.job.id)

    def test_a_worker_who_sent_nothing_is_told_to_get_verified(self):
        row = self.listed()

        self.assertFalse(row["can_apply"])
        self.assertEqual(row["apply_blocked_title"], "Get verified to apply.")
        self.assertIn("Get Verified", row["apply_blocked_reason"])

    def test_a_worker_under_review_is_told_to_wait(self):
        VerificationRequest.objects.create(
            worker=self.worker, primary_id_name="id.png", secondary_doc_name="doc.png",
            status=VerificationRequest.STATUS_PENDING,
        )

        self.assertEqual(self.listed()["apply_blocked_title"], "Your ID is being reviewed.")

    def test_a_verified_worker_gets_no_reason(self):
        self.worker.profile.verification_status = "verified"
        self.worker.profile.save(update_fields=["verification_status"])

        row = self.listed()
        self.assertTrue(row["can_apply"])
        self.assertEqual(row["apply_blocked_reason"], "")


class ProfileLimitTests(TestCase):
    def setUp(self):
        self.worker = make_user("mw-limits", UserProfile.ROLE_WORKER)
        self.client = client_for(self.worker)

    def patch(self, **fields):
        return self.client.patch(reverse("profile-me"), fields, format="json")

    def test_out_of_range_values_are_refused_with_plain_words(self):
        cases = [
            ({"years_experience": 200}, "years_experience", "Enter 60 years or fewer."),
            ({"years_experience": -3}, "years_experience", "Years of experience can't be negative."),
            ({"hourly_rate": "0.5"}, "hourly_rate", "Enter at least PHP 1, or leave it blank."),
            ({"daily_rate": "99999999"}, "daily_rate", "Enter PHP 100,000 or less."),
            ({"hourly_rate": "10001"}, "hourly_rate", "Enter PHP 10,000 or less."),
            ({"hourly_rate": "-50"}, "hourly_rate", "A rate can't be negative."),
        ]
        for fields, field, message in cases:
            with self.subTest(fields=fields):
                response = self.patch(**fields)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn(message, str(response.data[field]))

    def test_a_rate_of_zero_still_means_not_given(self):
        response = self.patch(hourly_rate="0", daily_rate="650", years_experience=60)

        self.assertEqual(response.status_code, 200, response.data)


class NotificationWordingTests(TestCase):
    def setUp(self):
        self.household = make_user("mw-nt-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("mw-nt-worker", UserProfile.ROLE_WORKER)
        self.superadmin = make_user("mw-nt-super", superuser=True)
        self.job = make_job(self.household, title="Deep clean today")

    def notifications(self, user):
        rows = client_for(user).get(reverse("notification-list")).json()
        return rows.get("results", rows)

    def test_a_complaint_update_names_its_job_and_opens_my_complaints(self):
        JobApplication.objects.create(job=self.job, worker=self.worker)
        complaint = Complaint.objects.create(
            complainant=self.worker, respondent=self.household, job=self.job,
            complaint_type=Complaint.TYPE_OTHER, description="The schedule kept changing.",
        )
        admin = client_for(self.superadmin)
        url = reverse("complaint-update-admin", args=[complaint.id])
        self.assertEqual(admin.patch(url, {"status": "under_review"}, format="json").status_code, 200)
        response = admin.patch(
            url, {"status": "resolved", "resolution": "Both sides agreed on a schedule."}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)

        notices = [row for row in self.notifications(self.worker) if row["title"] == "Your complaint has been updated"]
        self.assertEqual(len(notices), 2)
        for notice in notices:
            self.assertEqual(notice["action_type"], "complaint")
            self.assertIn("Deep clean today", notice["message"])
            self.assertNotIn("other complaint", notice["message"].lower())
        resolved = next(notice for notice in notices if "Resolved" in notice["message"])
        self.assertIn("Open My Complaints to read the resolution.", resolved["message"])

    def test_an_admin_is_not_named_to_a_worker(self):
        create_notification(
            recipient=self.worker, notification_type=Notification.TYPE_VERIFICATION,
            title="Certificate Rejected", message="Too blurry.", actor=self.superadmin, send_email=False,
        )
        create_notification(
            recipient=self.worker, notification_type=Notification.TYPE_APPLICATION,
            title="Hire request", message="Hi.", actor=self.household, send_email=False,
        )

        rows = {row["title"]: row for row in self.notifications(self.worker)}
        self.assertIsNone(rows["Certificate Rejected"]["actor_username"])
        self.assertIsNone(rows["Certificate Rejected"]["actor"])
        self.assertEqual(rows["Hire request"]["actor_username"], self.household.username)
