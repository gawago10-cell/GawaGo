"""Regression tests for the full-flow audit of 2026-11-04, one class per
finding (F2-F8, D1; F1 is in apps/matching/tests.py)."""

from datetime import timedelta
from unittest.mock import patch

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.accounts.services import apply_account_suspension
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.complaints.models import Complaint
from apps.jobs.models import JobApplication, JobPosting
from apps.matching.tasks import run_job_match_notifications
from apps.notifications.models import Notification
from apps.reviews.models import Review


def days_from_today(offset):
    return timezone.localdate() + timedelta(days=offset)


def titles(user):
    return list(Notification.objects.filter(recipient=user).values_list("title", flat=True))


class OnlyTheHouseholdMarksDoneTests(TestCase):
    """F2: an administrator's "completed" used to close the job and open reviews."""

    def setUp(self):
        self.household = make_user("fa-done-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("fa-done-worker", UserProfile.ROLE_WORKER)
        self.admin = make_user("fa-done-admin", superuser=True)
        self.job = make_job(
            self.household, status=JobPosting.STATUS_ASSIGNED,
            job_start_date=days_from_today(-1), job_end_date=days_from_today(0),
        )
        JobApplication.objects.create(job=self.job, worker=self.worker, status=JobApplication.STATUS_HIRED)

    def test_an_admin_cannot_mark_the_job_done(self):
        response = client_for(self.admin).patch(reverse("job-detail", args=[self.job.id]), {"status": "completed"}, format="json")

        self.assertEqual(response.status_code, 403)
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_ASSIGNED)
        self.assertNotIn("Job completed", titles(self.worker))

    def test_an_admin_can_still_cancel_it(self):
        response = client_for(self.admin).patch(
            reverse("job-detail", args=[self.job.id]), {"status": "cancelled", "cancel_reason": "Reported as fake."}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)

    def test_the_household_marks_it_done(self):
        response = client_for(self.household).patch(reverse("job-detail", args=[self.job.id]), {"status": "completed"}, format="json")

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], JobPosting.STATUS_COMPLETED)


class SuspensionReleasesOpenApplicationsTests(TestCase):
    """F3 and D1: what a suspension means for the people the account deals with."""

    def setUp(self):
        self.household = make_user("fa-sus-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("fa-sus-worker", UserProfile.ROLE_WORKER)
        self.other_worker = make_user("fa-sus-other", UserProfile.ROLE_WORKER)

    def suspend(self, user, reason="Reported for abuse."):
        apply_account_suspension(user.profile, blocked=True, reason=reason, duration_days=3)

    def test_a_suspended_households_invitations_close_and_the_worker_is_told(self):
        job = make_job(self.household, job_start_date=days_from_today(5))
        invite = JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRE_REQUESTED)
        pending = JobApplication.objects.create(job=job, worker=self.other_worker)

        self.suspend(self.household)

        invite.refresh_from_db()
        pending.refresh_from_db()
        self.assertEqual(invite.status, JobApplication.STATUS_CLOSED)
        self.assertEqual(pending.status, JobApplication.STATUS_CLOSED)
        notice = Notification.objects.get(recipient=self.worker, title="Job not available")
        self.assertIn("their invitation has been closed", notice.message)
        self.assertNotIn("Reported", notice.message)
        self.assertNotIn("suspend", notice.message.lower())

    def test_an_invitation_from_a_suspended_household_cannot_be_accepted(self):
        job = make_job(self.household, job_start_date=days_from_today(5))
        self.suspend(self.household)
        invite = JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRE_REQUESTED)

        response = client_for(self.worker).patch(
            reverse("job-application-decision", args=[invite.id]), {"decision": "accept"}, format="json"
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["detail"], "This job is no longer available.")
        invite.refresh_from_db()
        self.assertEqual(invite.status, JobApplication.STATUS_HIRE_REQUESTED)

    def test_the_household_hears_when_its_hired_worker_is_suspended(self):
        job = make_job(self.household, title="Garden day", status=JobPosting.STATUS_ASSIGNED, job_start_date=days_from_today(4))
        hire = JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)

        self.suspend(self.worker)

        notice = Notification.objects.get(recipient=self.household, title="Your worker may not be available")
        self.assertIn("Garden day", notice.message)
        self.assertNotIn("Reported", notice.message)
        hire.refresh_from_db()
        self.assertEqual(hire.status, JobApplication.STATUS_HIRED)

    def test_the_hired_worker_hears_when_the_household_is_suspended(self):
        job = make_job(self.household, title="Laundry day", status=JobPosting.STATUS_ASSIGNED, job_start_date=days_from_today(4))
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)

        self.suspend(self.household)

        notice = Notification.objects.get(recipient=self.worker, title="Your job may not go ahead")
        self.assertIn("You can still back out before it starts.", notice.message)

    def test_a_suspended_workers_open_applications_close(self):
        job = make_job(self.household, title="Ironing", job_start_date=days_from_today(4))
        application = JobApplication.objects.create(job=job, worker=self.worker)

        self.suspend(self.worker)

        application.refresh_from_db()
        self.assertEqual(application.status, JobApplication.STATUS_CLOSED)
        notice = Notification.objects.get(recipient=self.household, title="Application closed")
        self.assertIn("isn't available right now", notice.message)

    def test_finished_holds_and_repeat_suspensions_send_nothing(self):
        old = make_job(self.household, status=JobPosting.STATUS_ASSIGNED, job_start_date=days_from_today(-10))
        JobApplication.objects.create(job=old, worker=self.worker, status=JobApplication.STATUS_HIRED)
        live = make_job(self.household, status=JobPosting.STATUS_ASSIGNED, job_start_date=days_from_today(3))
        JobApplication.objects.create(job=live, worker=self.worker, status=JobApplication.STATUS_HIRED)

        self.suspend(self.worker)
        self.suspend(self.worker, reason="Extended.")

        notices = Notification.objects.filter(recipient=self.household, title="Your worker may not be available")
        self.assertEqual([n.related_job_id for n in notices], [live.id])


class ClosedApplicantsCanComeBackTests(TestCase):
    """F4: a back-out reopened a slot, but whoever the full job had closed out
    stayed locked out of it."""

    def setUp(self):
        self.household = make_user("fa-back-home", UserProfile.ROLE_HOUSEHOLD)
        self.hired = make_user("fa-back-hired", UserProfile.ROLE_WORKER)
        self.closed_out = make_user("fa-back-closed", UserProfile.ROLE_WORKER)
        self.job = make_job(self.household, job_start_date=days_from_today(5), status=JobPosting.STATUS_ASSIGNED)
        self.hire = JobApplication.objects.create(job=self.job, worker=self.hired, status=JobApplication.STATUS_HIRED)
        self.closed = JobApplication.objects.create(job=self.job, worker=self.closed_out, status=JobApplication.STATUS_CLOSED)

    def back_out(self):
        response = client_for(self.hired).post(
            reverse("job-application-withdraw", args=[self.hire.id]), {"reason": "Sick."}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)

    def test_while_the_job_is_full_they_still_cannot_apply(self):
        response = client_for(self.closed_out).post(reverse("job-apply", args=[self.job.id]), {}, format="json")

        self.assertEqual(response.status_code, 400)

    def test_they_can_apply_again_once_a_slot_reopens(self):
        self.back_out()
        detail = client_for(self.closed_out).get(reverse("job-detail", args=[self.job.id]))
        self.assertTrue(detail.data["can_apply"])

        response = client_for(self.closed_out).post(reverse("job-apply", args=[self.job.id]), {}, format="json")

        self.assertEqual(response.status_code, 201, response.data)
        self.closed.refresh_from_db()
        self.assertEqual(self.closed.status, JobApplication.STATUS_PENDING)

    def test_the_household_can_invite_them_again(self):
        self.back_out()

        response = client_for(self.household).post(
            reverse("job-hire-request", args=[self.job.id]), {"worker_id": self.closed_out.id}, format="json"
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["status"], JobApplication.STATUS_HIRE_REQUESTED)

    def test_a_rejection_stays_final(self):
        self.back_out()
        self.closed.status = JobApplication.STATUS_REJECTED
        self.closed.save(update_fields=["status"])

        response = client_for(self.household).post(
            reverse("job-hire-request", args=[self.job.id]), {"worker_id": self.closed_out.id}, format="json"
        )

        self.assertEqual(response.status_code, 400)


class JobMatchAlertsNeedVerificationTests(TestCase):
    """F5: an unverified worker was told about jobs they can't apply to."""

    def test_only_verified_workers_are_alerted(self):
        household = make_user("fa-alert-home", UserProfile.ROLE_HOUSEHOLD)
        verified = make_user("fa-alert-ok", UserProfile.ROLE_WORKER, skills=["House Cleaning"])
        pending = make_user("fa-alert-pending", UserProfile.ROLE_WORKER, skills=["House Cleaning"], verification_status="pending")
        job = make_job(household, job_start_date=days_from_today(3))

        with patch("apps.matching.tasks.get_road_route_for_match", return_value={"distance_km": 0.2, "route_points": []}):
            run_job_match_notifications(job.id)

        alerted = set(
            Notification.objects.filter(notification_type=Notification.TYPE_JOB_MATCH, related_job_id=job.id)
            .values_list("recipient_id", flat=True)
        )
        self.assertIn(verified.id, alerted)
        self.assertNotIn(pending.id, alerted)


class ResolutionStaysOnceResolvedTests(TestCase):
    """F6: a resolved complaint's answer could be saved as blank."""

    def setUp(self):
        self.superadmin = make_user("fa-res-admin", superuser=True)
        filer = make_user("fa-res-filer", UserProfile.ROLE_WORKER)
        named = make_user("fa-res-named", UserProfile.ROLE_HOUSEHOLD)
        self.complaint = Complaint.objects.create(
            complainant=filer, respondent=named, complaint_type=Complaint.TYPE_NO_SHOW,
            description="Did not pay.", status=Complaint.STATUS_RESOLVED, resolution="Warned the household.",
        )

    def patch(self, data):
        return client_for(self.superadmin).patch(reverse("complaint-update-admin", args=[self.complaint.id]), data, format="json")

    def test_it_cannot_be_emptied(self):
        response = self.patch({"resolution": "  "})

        self.assertEqual(response.status_code, 400)
        self.complaint.refresh_from_db()
        self.assertEqual(self.complaint.resolution, "Warned the household.")

    def test_it_can_be_reworded(self):
        response = self.patch({"resolution": "Warned the household in writing."})

        self.assertEqual(response.status_code, 200)
        self.complaint.refresh_from_db()
        self.assertEqual(self.complaint.resolution, "Warned the household in writing.")


class JobsNeedAStartDateTests(TestCase):
    """F7: the API took schedule text alone, and a job without dates never
    lapsed, never blocked the next post and could be finished any day."""

    def setUp(self):
        self.household = make_user("fa-date-home", UserProfile.ROLE_HOUSEHOLD)

    def test_posting_without_a_start_date_is_refused(self):
        response = client_for(self.household).post(
            reverse("job-list"),
            {
                "title": "Weekend laundry", "job_type": "Laundry", "required_skill": "Laundry",
                "schedule": "Any weekend", "location_label": "Isabang, Tayabas",
                "latitude": "13.9622745", "longitude": "121.5632841", "service_rate": "500",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("job_start_date", response.data)

    def test_an_edit_cannot_clear_the_start_date(self):
        job = make_job(self.household, job_start_date=days_from_today(4))

        response = client_for(self.household).patch(reverse("job-detail", args=[job.id]), {"job_start_date": None}, format="json")

        self.assertEqual(response.status_code, 400)
        job.refresh_from_db()
        self.assertEqual(job.job_start_date, days_from_today(4))


class ReviewNoticeUsesTheNameTests(TestCase):
    """F8: the worker read "a new review from <username>"."""

    def test_the_reviewer_is_named(self):
        household = make_user("fa-rev-home", UserProfile.ROLE_HOUSEHOLD)
        household.first_name, household.last_name = "Maria", "Santos"
        household.save(update_fields=["first_name", "last_name"])
        worker = make_user("fa-rev-worker", UserProfile.ROLE_WORKER)
        job = make_job(household, status=JobPosting.STATUS_COMPLETED, job_start_date=days_from_today(-2))
        JobApplication.objects.create(job=job, worker=worker, status=JobApplication.STATUS_COMPLETED)

        response = client_for(household).post(
            reverse("review-list-create"), {"target_username": worker.username, "job_id": job.id, "rating": 5}, format="json"
        )

        self.assertEqual(response.status_code, 201, response.data)
        notice = Notification.objects.get(recipient=worker, notification_type=Notification.TYPE_REVIEW)
        self.assertEqual(notice.message, "You received a new review from Maria Santos.")
        self.assertTrue(Review.objects.filter(job=job, author=household).exists())


class AnsweredRequestsStopAskingTests(TestCase):
    """A hire request kept "Needs your response" after the worker answered it,
    and the web card then showed blank job details."""

    def setUp(self):
        self.household = make_user("fa-ask-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("fa-ask-worker", UserProfile.ROLE_WORKER)
        self.job = make_job(self.household, job_start_date=days_from_today(6))

    def invite(self):
        response = client_for(self.household).post(
            reverse("job-hire-request", args=[self.job.id]), {"worker_id": self.worker.id}, format="json"
        )
        self.assertEqual(response.status_code, 201, response.data)
        return response.data["id"]

    def request_notice(self):
        return Notification.objects.get(recipient=self.worker, action_type=Notification.ACTION_HIRE_REQUEST)

    def test_accepting_settles_the_request(self):
        application_id = self.invite()
        self.assertTrue(self.request_notice().requires_action)

        client_for(self.worker).patch(reverse("job-application-decision", args=[application_id]), {"decision": "accept"}, format="json")

        self.assertFalse(self.request_notice().requires_action)

    def test_declining_settles_the_request(self):
        application_id = self.invite()

        client_for(self.worker).patch(reverse("job-application-decision", args=[application_id]), {"decision": "reject"}, format="json")

        self.assertFalse(self.request_notice().requires_action)

    def test_the_households_new_application_notice_settles_when_decided(self):
        response = client_for(self.worker).post(reverse("job-apply", args=[self.job.id]), {}, format="json")
        notice = Notification.objects.get(recipient=self.household, title="New worker application")
        self.assertTrue(notice.requires_action)

        client_for(self.household).patch(
            reverse("job-application-status", args=[response.data["id"]]), {"status": "rejected"}, format="json"
        )

        notice.refresh_from_db()
        self.assertFalse(notice.requires_action)

    def test_review_prompts_keep_asking(self):
        application = JobApplication.objects.create(job=self.job, worker=self.worker, status=JobApplication.STATUS_HIRED)
        prompt = Notification.objects.create(
            recipient=self.household, notification_type=Notification.TYPE_REVIEW_REMINDER, title="Review worker service",
            message="Please review.", related_application_id=application.id, action_type=Notification.ACTION_REVIEW,
            requires_action=True,
        )
        from apps.jobs.services import record_application_status_event

        record_application_status_event(application, JobApplication.STATUS_HIRED, JobApplication.STATUS_COMPLETED)

        prompt.refresh_from_db()
        self.assertTrue(prompt.requires_action)
