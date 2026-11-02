"""Regression tests for the fourth system scan (2026-11-01), one class per
finding across the apps it touches."""

from datetime import timedelta
from decimal import Decimal
from types import SimpleNamespace

from django.core.cache import cache
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.analytics.services import build_dashboard_metrics, build_public_summary
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.jobs.models import JobApplication, JobPosting
from apps.jobs.services import (
    HOLD_GRACE_DAYS,
    MARK_DONE_REMINDER_TITLE,
    WorkerHold,
    hire_application,
    send_due_mark_done_reminders,
    worker_hold,
    workers_held_from,
)
from apps.matching.recommendations import score_pair_with_distance
from apps.notifications.models import Notification
from apps.reports.services import build_platform_report, resolve_period


def days_from_today(offset):
    return timezone.localdate() + timedelta(days=offset)


class FullTimeHoldStartsOnItsFirstDayTests(TestCase):
    """S4-2: a full-time job booked ahead only holds its own days until it starts."""

    def setUp(self):
        self.household = make_user("s4-ft-home", UserProfile.ROLE_HOUSEHOLD)
        self.other_home = make_user("s4-ft-other", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("s4-ft-worker", UserProfile.ROLE_WORKER, skills=["House Cleaning"])

    def hire_full_time(self, start, end):
        job = make_job(
            self.household, title="Live-in helper", schedule_type="Full-Time",
            job_start_date=start, job_end_date=end, status=JobPosting.STATUS_ASSIGNED,
        )
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)
        return job

    def test_a_future_full_time_job_leaves_earlier_days_free(self):
        self.hire_full_time(days_from_today(30), days_from_today(120))
        one_day = make_job(self.other_home, schedule_type="One-Time", job_start_date=days_from_today(4))

        self.assertIsNone(worker_hold(self.worker, one_day))
        self.assertNotIn(self.worker.id, workers_held_from(one_day))
        response = client_for(self.worker).post(reverse("job-apply", args=[one_day.id]), {}, format="json")
        self.assertEqual(response.status_code, 201, response.data)

    def test_a_future_full_time_job_still_holds_its_own_days(self):
        self.hire_full_time(days_from_today(30), days_from_today(120))
        clash = make_job(self.other_home, schedule_type="One-Time", job_start_date=days_from_today(40))

        hold = worker_hold(self.worker, clash)
        self.assertEqual(hold.kind, WorkerHold.SAME_DAYS)
        self.assertIn(self.worker.id, workers_held_from(clash))

    def test_a_started_full_time_job_holds_every_job(self):
        self.hire_full_time(days_from_today(-2), days_from_today(60))
        later = make_job(self.other_home, schedule_type="One-Time", job_start_date=days_from_today(90))

        hold = worker_hold(self.worker, later)
        self.assertEqual(hold.kind, WorkerHold.FULL_TIME)
        response = client_for(self.worker).post(reverse("job-apply", args=[later.id]), {}, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("marks it done", response.data["detail"])
        self.assertIn("again from", response.data["detail"])

    def test_hiring_onto_a_future_full_time_job_keeps_other_applications(self):
        earlier = make_job(self.other_home, title="This week", job_start_date=days_from_today(3))
        overlapping = make_job(self.other_home, title="Same month", job_start_date=days_from_today(35))
        kept = JobApplication.objects.create(job=earlier, worker=self.worker)
        closed = JobApplication.objects.create(job=overlapping, worker=self.worker)
        future = make_job(
            self.household, title="Live-in helper", schedule_type="Full-Time",
            job_start_date=days_from_today(30), job_end_date=days_from_today(120),
        )
        application = JobApplication.objects.create(job=future, worker=self.worker)

        hire_application(application.id, JobApplication.STATUS_PENDING, actor=self.household)

        kept.refresh_from_db()
        closed.refresh_from_db()
        self.assertEqual(kept.status, JobApplication.STATUS_PENDING)
        self.assertEqual(closed.status, JobApplication.STATUS_CLOSED)


class HoldLapsesAfterGraceDaysTests(TestCase):
    """S4-1: a job nobody marked done stops holding its worker after the grace days."""

    def setUp(self):
        self.household = make_user("s4-grace-home", UserProfile.ROLE_HOUSEHOLD)
        self.other_home = make_user("s4-grace-other", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("s4-grace-worker", UserProfile.ROLE_WORKER)
        self.target = make_job(self.other_home, title="Tomorrow", job_start_date=days_from_today(1))

    def hire_full_time_ending(self, end_offset):
        job = make_job(
            self.household, schedule_type="Full-Time", status=JobPosting.STATUS_ASSIGNED,
            job_start_date=days_from_today(end_offset - 10), job_end_date=days_from_today(end_offset),
        )
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)
        return job

    def test_the_hold_holds_through_the_last_grace_day(self):
        self.hire_full_time_ending(-HOLD_GRACE_DAYS)

        self.assertEqual(worker_hold(self.worker, self.target).kind, WorkerHold.FULL_TIME)

    def test_the_hold_ends_the_day_after_the_grace_days(self):
        self.hire_full_time_ending(-HOLD_GRACE_DAYS - 1)

        self.assertIsNone(worker_hold(self.worker, self.target))
        self.assertNotIn(self.worker.id, workers_held_from(self.target))


class WorkerWithdrawTests(TestCase):
    """S4-1: a worker can take back an application or back out before the start."""

    def setUp(self):
        self.household = make_user("s4-wd-home", UserProfile.ROLE_HOUSEHOLD)
        self.household.first_name, self.household.last_name = "Ana", "Reyes"
        self.household.save()
        self.worker = make_user("s4-wd-worker", UserProfile.ROLE_WORKER)
        self.worker.first_name, self.worker.last_name = "Ben", "Cruz"
        self.worker.save()
        self.job = make_job(self.household, job_start_date=days_from_today(5))

    def withdraw(self, application, reason="", user=None):
        return client_for(user or self.worker).post(
            reverse("job-application-withdraw", args=[application.id]), {"reason": reason}, format="json"
        )

    def test_a_pending_application_is_withdrawn_and_the_household_told(self):
        application = JobApplication.objects.create(job=self.job, worker=self.worker)

        response = self.withdraw(application)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], JobApplication.STATUS_WITHDRAWN)
        self.assertEqual(response.data["status_label"], "Withdrawn")
        note = Notification.objects.get(recipient=self.household, title="Application withdrawn")
        self.assertIn("Ben Cruz withdrew", note.message)

    def test_a_worker_who_withdrew_can_apply_again(self):
        application = JobApplication.objects.create(job=self.job, worker=self.worker)
        self.withdraw(application)

        detail = client_for(self.worker).get(reverse("job-detail", args=[self.job.id]))
        self.assertTrue(detail.data["can_apply"])
        response = client_for(self.worker).post(reverse("job-apply", args=[self.job.id]), {}, format="json")

        self.assertEqual(response.status_code, 201, response.data)
        application.refresh_from_db()
        self.assertEqual(application.status, JobApplication.STATUS_PENDING)

    def test_backing_out_needs_a_reason_and_reopens_the_job(self):
        application = JobApplication.objects.create(job=self.job, worker=self.worker)
        hire_application(application.id, JobApplication.STATUS_PENDING, actor=self.household)

        refused = self.withdraw(application)
        self.assertEqual(refused.status_code, 400)
        self.assertIn("why", refused.data["detail"])

        response = self.withdraw(application, reason="  I got sick.  ")
        self.assertEqual(response.status_code, 200, response.data)
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_OPEN)
        note = Notification.objects.get(recipient=self.household, title="Worker backed out")
        self.assertIn("Reason: I got sick.", note.message)
        self.assertIn("open again", note.message)
        self.assertIsNone(worker_hold(self.worker, make_job(self.household, job_start_date=days_from_today(5))))

    def test_backing_out_keeps_a_job_with_other_hires_under_way(self):
        self.job.worker_slots = 2
        self.job.save()
        other = make_user("s4-wd-other", UserProfile.ROLE_WORKER)
        first = JobApplication.objects.create(job=self.job, worker=self.worker)
        second = JobApplication.objects.create(job=self.job, worker=other)
        hire_application(first.id, JobApplication.STATUS_PENDING, actor=self.household)
        hire_application(second.id, JobApplication.STATUS_PENDING, actor=self.household)

        self.assertEqual(self.withdraw(first, reason="Family emergency").status_code, 200)

        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_ASSIGNED)
        note = Notification.objects.get(recipient=self.household, title="Worker backed out")
        self.assertNotIn("open again", note.message)

    def test_no_backing_out_once_the_job_has_started(self):
        self.job.job_start_date = timezone.localdate()
        self.job.save()
        application = JobApplication.objects.create(job=self.job, worker=self.worker)
        hire_application(application.id, JobApplication.STATUS_PENDING, actor=self.household)

        response = self.withdraw(application, reason="Changed my mind")

        self.assertEqual(response.status_code, 400)
        self.assertIn("started", response.data["detail"])

    def test_an_invitation_is_declined_not_withdrawn(self):
        application = JobApplication.objects.create(
            job=self.job, worker=self.worker, status=JobApplication.STATUS_HIRE_REQUESTED
        )

        response = self.withdraw(application)

        self.assertEqual(response.status_code, 400)
        self.assertIn("Decline", response.data["detail"])

    def test_only_the_worker_can_withdraw(self):
        application = JobApplication.objects.create(job=self.job, worker=self.worker)

        response = self.withdraw(application, user=self.household)

        self.assertEqual(response.status_code, 403)
        application.refresh_from_db()
        self.assertEqual(application.status, JobApplication.STATUS_PENDING)

    def test_the_household_cant_act_on_a_withdrawn_application(self):
        application = JobApplication.objects.create(job=self.job, worker=self.worker)
        self.withdraw(application)

        accept = client_for(self.household).patch(
            reverse("job-application-status", args=[application.id]), {"status": "hired"}, format="json"
        )
        invite = client_for(self.household).post(
            reverse("job-hire-request", args=[self.job.id]), {"worker_id": self.worker.id}, format="json"
        )

        self.assertEqual(accept.status_code, 400)
        self.assertEqual(invite.status_code, 400)
        self.assertIn("withdrew", invite.data["detail"])

    def test_flags_tell_the_clients_what_the_worker_can_do(self):
        application = JobApplication.objects.create(job=self.job, worker=self.worker)
        rows = client_for(self.worker).get(reverse("job-application-list")).data["results"]
        self.assertTrue(rows[0]["can_withdraw"])
        self.assertFalse(rows[0]["can_back_out"])

        hire_application(application.id, JobApplication.STATUS_PENDING, actor=self.household)
        rows = client_for(self.worker).get(reverse("job-application-list")).data["results"]
        self.assertFalse(rows[0]["can_withdraw"])
        self.assertTrue(rows[0]["can_back_out"])

        household_rows = client_for(self.household).get(
            reverse("job-application-list"), {"job_id": self.job.id}
        ).data["results"]
        self.assertFalse(household_rows[0]["can_back_out"])


class HouseholdCancelFlagsTests(TestCase):
    """S4-1: the household can cancel a hired job, and is told a reason is needed."""

    def setUp(self):
        self.household = make_user("s4-cancel-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("s4-cancel-worker", UserProfile.ROLE_WORKER)

    def detail(self, job, user=None):
        return client_for(user or self.household).get(reverse("job-detail", args=[job.id])).data

    def test_an_open_job_cancels_without_a_reason(self):
        job = make_job(self.household)

        data = self.detail(job)

        self.assertTrue(data["can_cancel"])
        self.assertFalse(data["cancel_needs_reason"])

    def test_a_hired_job_can_be_cancelled_with_a_reason(self):
        job = make_job(self.household, job_start_date=days_from_today(1))
        application = JobApplication.objects.create(job=job, worker=self.worker)
        hire_application(application.id, JobApplication.STATUS_PENDING, actor=self.household)

        data = self.detail(job)
        self.assertTrue(data["can_cancel"])
        self.assertTrue(data["cancel_needs_reason"])
        self.assertFalse(self.detail(job, user=self.worker)["can_cancel"])

        response = client_for(self.household).patch(
            reverse("job-detail", args=[job.id]),
            {"status": "cancelled", "cancel_reason": "The worker did not show up."},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertIsNone(worker_hold(self.worker, make_job(self.household, job_start_date=days_from_today(1))))

    def test_a_finished_job_cant_be_cancelled(self):
        job = make_job(self.household, status=JobPosting.STATUS_COMPLETED)

        self.assertFalse(self.detail(job)["can_cancel"])


class MarkDoneReminderTests(TestCase):
    """S4-1: the household is reminded once, the day after the job's last day."""

    def setUp(self):
        cache.clear()
        self.household = make_user("s4-remind-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("s4-remind-worker", UserProfile.ROLE_WORKER)

    def hired_job(self, start_offset, end_offset, status=JobPosting.STATUS_ASSIGNED):
        job = make_job(
            self.household, status=status,
            job_start_date=days_from_today(start_offset), job_end_date=days_from_today(end_offset),
        )
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)
        return job

    def reminders(self):
        return Notification.objects.filter(recipient=self.household, title=MARK_DONE_REMINDER_TITLE)

    def test_a_job_past_its_last_day_gets_one_reminder(self):
        job = self.hired_job(-3, -1)

        self.assertEqual(send_due_mark_done_reminders(), 1)
        self.assertEqual(send_due_mark_done_reminders(), 0)

        note = self.reminders().get()
        self.assertEqual(note.related_job_id, job.id)
        self.assertTrue(note.requires_action)
        self.assertEqual(note.action_url, f"/household/jobs/{job.id}")

    def test_no_reminder_on_or_before_the_last_day(self):
        self.hired_job(-3, 0)

        self.assertEqual(send_due_mark_done_reminders(), 0)

    def test_no_reminder_for_a_job_already_done(self):
        self.hired_job(-3, -1, status=JobPosting.STATUS_COMPLETED)

        self.assertEqual(send_due_mark_done_reminders(), 0)

    def test_reading_notifications_runs_the_pass(self):
        self.hired_job(-3, -1)

        client_for(self.household).get(reverse("notification-list"))

        self.assertEqual(self.reminders().count(), 1)


class AverageRatesByRateTypeTests(TestCase):
    """S4-3: day, hourly and fixed rates are averaged apart, under catalog names."""

    def setUp(self):
        self.household = make_user("s4-rates-home", UserProfile.ROLE_HOUSEHOLD)

    def test_hourly_posts_no_longer_skew_the_day_rate(self):
        make_job(self.household, required_skill="Plumbing", service_rate=Decimal("950.00"))
        make_job(self.household, required_skill="tubero", rate_type=JobPosting.RATE_PER_HOUR, service_rate=Decimal("100.00"))
        make_job(self.household, required_skill="Plumbing", rate_type=JobPosting.RATE_PER_HOUR, service_rate=Decimal("120.00"))

        rows = build_dashboard_metrics()["analytics"]["rateTransparency"]["averageRatesByCategory"]
        plumbing = {row["rateType"]: row for row in rows if row["skill"] == "Plumbing"}

        self.assertEqual(set(plumbing), {JobPosting.RATE_PER_DAY, JobPosting.RATE_PER_HOUR})
        self.assertEqual(plumbing[JobPosting.RATE_PER_DAY]["averageRate"], 950.0)
        self.assertEqual(plumbing[JobPosting.RATE_PER_DAY]["averageRateLabel"], "PHP 950.00 / day")
        self.assertEqual(plumbing[JobPosting.RATE_PER_HOUR]["count"], 2)
        self.assertEqual(plumbing[JobPosting.RATE_PER_HOUR]["averageRateLabel"], "PHP 110.00 / hour")

    def test_the_rate_trend_follows_day_rates_only(self):
        make_job(self.household, service_rate=Decimal("800.00"))
        make_job(self.household, rate_type=JobPosting.RATE_PER_HOUR, service_rate=Decimal("90.00"))

        trends = build_dashboard_metrics()["analytics"]["rateTransparency"]["pricingTrends"]

        self.assertEqual(trends[-1]["averageRate"], 800.0)
        self.assertEqual(trends[-1]["postings"], 1)


class AdminActiveJobsTests(TestCase):
    """S4-11: the admin counts the same market the home page counts."""

    def test_lapsed_jobs_are_out_and_multi_worker_jobs_with_openings_are_in(self):
        household = make_user("s4-active-home", UserProfile.ROLE_HOUSEHOLD)
        worker = make_user("s4-active-worker", UserProfile.ROLE_WORKER)
        make_job(household, title="Open")
        lapsed = make_job(household, title="Lapsed")
        JobPosting.objects.filter(pk=lapsed.pk).update(job_start_date=days_from_today(-3))
        crew = make_job(household, title="Crew", worker_slots=3, status=JobPosting.STATUS_ASSIGNED)
        JobApplication.objects.create(job=crew, worker=worker, status=JobApplication.STATUS_HIRED)

        metrics = build_dashboard_metrics()

        self.assertEqual(metrics["analytics"]["summary"]["activeJobs"], 2)
        self.assertEqual(metrics["open_jobs"], 1 + 2)
        self.assertEqual(build_public_summary()["openJobs"], 2)


class CompletedJobValueTests(TestCase):
    """S4-12: the report estimates each completed job's value."""

    def test_day_rates_count_their_days_and_workers_and_hourly_jobs_are_counted_apart(self):
        household = make_user("s4-value-home", UserProfile.ROLE_HOUSEHOLD)
        first = make_user("s4-value-w1", UserProfile.ROLE_WORKER)
        second = make_user("s4-value-w2", UserProfile.ROLE_WORKER)
        crew = make_job(
            household, status=JobPosting.STATUS_COMPLETED, service_rate=Decimal("700.00"),
            estimated_working_days=5, worker_slots=2,
        )
        JobApplication.objects.create(job=crew, worker=first, status=JobApplication.STATUS_COMPLETED)
        JobApplication.objects.create(job=crew, worker=second, status=JobApplication.STATUS_COMPLETED)
        fixed = make_job(
            household, status=JobPosting.STATUS_COMPLETED, rate_type=JobPosting.RATE_FIXED, service_rate=Decimal("1500.00"),
        )
        JobApplication.objects.create(job=fixed, worker=first, status=JobApplication.STATUS_COMPLETED)
        hourly = make_job(
            household, status=JobPosting.STATUS_COMPLETED, rate_type=JobPosting.RATE_PER_HOUR, service_rate=Decimal("80.00"),
        )
        JobApplication.objects.create(job=hourly, worker=first, status=JobApplication.STATUS_COMPLETED)

        summary = build_platform_report(resolve_period())["summary"]

        self.assertEqual(summary["completedJobValue"], 700 * 5 * 2 + 1500)
        self.assertEqual(summary["completedHourlyJobs"], 1)


class AiSkillFitTakesTheBestSkillTests(TestCase):
    """S4-4: listing more skills no longer lowers an exact skill match."""

    def test_an_exact_match_scores_full_skill_fit_whatever_else_is_listed(self):
        job = SimpleNamespace(required_skill="Plumbing")
        single = score_pair_with_distance(job, SimpleNamespace(skills=["Plumbing"]), 0.5)
        three = score_pair_with_distance(job, SimpleNamespace(skills=["Painting", "plumber", "Carpentry"]), 0.5)

        self.assertEqual(single["skill_similarity"], 1.0)
        self.assertEqual(three["skill_similarity"], 1.0)
        self.assertEqual(three["ai_score"], single["ai_score"])

    def test_no_shared_skill_still_scores_zero_skill_fit(self):
        job = SimpleNamespace(required_skill="Plumbing")
        result = score_pair_with_distance(job, SimpleNamespace(skills=["Cooking", "Laundry"]), 0.5)

        self.assertEqual(result["skill_similarity"], 0.0)


class NotificationNamesTests(TestCase):
    """S4-10: notifications name people, not their login usernames."""

    def test_applying_and_inviting_use_display_names(self):
        household = make_user("s4-name-home", UserProfile.ROLE_HOUSEHOLD)
        household.first_name, household.last_name = "Ana", "Reyes"
        household.save()
        worker = make_user("s4-name-worker", UserProfile.ROLE_WORKER)
        worker.first_name, worker.last_name = "Ben", "Cruz"
        worker.save()
        invitee = make_user("s4-name-invitee", UserProfile.ROLE_WORKER)
        job = make_job(household, worker_slots=2)

        client_for(worker).post(reverse("job-apply", args=[job.id]), {}, format="json")
        client_for(household).post(reverse("job-hire-request", args=[job.id]), {"worker_id": invitee.id}, format="json")

        applied = Notification.objects.get(recipient=household, title="New worker application")
        invited = Notification.objects.get(recipient=invitee, title="Hire request")
        self.assertIn("Ben Cruz applied", applied.message)
        self.assertIn("Ana Reyes wants to hire you", invited.message)
        self.assertNotIn("s4-name", applied.message + invited.message)


class PostingNeedsClosedOutJobsTests(TestCase):
    """2026-11-02: a household rates its worker (and marks the job done)
    before it posts another job."""

    def setUp(self):
        self.household = make_user("po-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("po-worker", UserProfile.ROLE_WORKER)
        self.worker.first_name, self.worker.last_name = "Ben", "Cruz"
        self.worker.save()

    def payload(self, **overrides):
        values = {
            "title": "New job", "job_type": "House Cleaning", "required_skill": "House Cleaning",
            "schedule": "One-Time starting soon", "location_label": "Isabang, Tayabas",
            "latitude": "13.9622745", "longitude": "121.5632841", "service_rate": "600.00",
            "schedule_type": "One-Time",
        }
        values.update(overrides)
        return values

    def post(self):
        return client_for(self.household).post(reverse("job-list"), self.payload(), format="json")

    def status(self):
        return client_for(self.household).get(reverse("job-posting-status")).data

    def hired_job(self, start_offset, end_offset, status=JobPosting.STATUS_ASSIGNED):
        job = make_job(
            self.household, title="Fence Painting", status=status,
            job_start_date=days_from_today(start_offset), job_end_date=days_from_today(end_offset),
        )
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_HIRED)
        return job

    def completed_job(self):
        job = make_job(self.household, title="Fence Painting", status=JobPosting.STATUS_COMPLETED)
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_COMPLETED)
        return job

    def review(self, job, system=False):
        from apps.reviews.models import Review

        return Review.objects.create(
            job=job, author=self.household, target=self.worker, author_role=Review.ROLE_HOUSEHOLD,
            target_role=Review.ROLE_WORKER, rating=Decimal("4.0"), is_system_generated=system,
        )

    def test_a_household_with_nothing_pending_can_post(self):
        self.assertTrue(self.status()["can_post"])
        self.assertEqual(self.post().status_code, 201)

    def test_a_job_past_its_last_day_must_be_marked_done_first(self):
        job = self.hired_job(-4, -1)

        response = self.post()

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.data["block_kind"], "mark_done")
        self.assertEqual(response.data["blocked_job_id"], job.id)
        self.assertIn("Mark it as done", response.data["detail"])
        self.assertFalse(JobPosting.objects.filter(title="New job").exists())
        self.assertEqual(self.status()["job_title"], "Fence Painting")

    def test_a_job_still_running_or_not_started_blocks_nothing(self):
        self.hired_job(-1, 2)
        self.hired_job(3, 5)

        self.assertEqual(self.post().status_code, 201)

    def test_a_finished_job_must_be_rated_first(self):
        job = self.completed_job()

        response = self.post()

        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.data["block_kind"], "rate")
        self.assertEqual(response.data["blocked_job_id"], job.id)
        self.assertIn("Rate Ben Cruz for Fence Painting", response.data["detail"])

    def test_the_automatic_placeholder_rating_does_not_unblock(self):
        job = self.completed_job()
        self.review(job, system=True)

        self.assertEqual(self.post().status_code, 403)

    def test_a_real_review_unblocks_posting(self):
        job = self.completed_job()
        self.review(job)

        self.assertTrue(self.status()["can_post"])
        self.assertEqual(self.post().status_code, 201)

    def test_marking_done_then_rating_clears_the_block_step_by_step(self):
        job = self.hired_job(-4, -1)
        self.assertEqual(self.status()["kind"], "mark_done")

        client_for(self.household).patch(
            reverse("job-detail", args=[job.id]), {"status": "completed"}, format="json"
        )
        self.assertEqual(self.status()["kind"], "rate")

        self.review(job)
        self.assertTrue(self.status()["can_post"])

    def test_cancelling_the_job_clears_the_mark_done_block(self):
        job = self.hired_job(-4, -1)

        response = client_for(self.household).patch(
            reverse("job-detail", args=[job.id]),
            {"status": "cancelled", "cancel_reason": "The worker never came."},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(self.status()["can_post"])

    def test_every_unrated_worker_on_a_crew_job_is_named(self):
        other = make_user("po-worker2", UserProfile.ROLE_WORKER)
        other.first_name, other.last_name = "Cara", "Diaz"
        other.save()
        job = self.completed_job()
        JobApplication.objects.create(job=job, worker=other, status=JobApplication.STATUS_COMPLETED)
        self.review(job)

        self.assertIn("Cara Diaz", self.status()["message"])
        self.assertNotIn("Ben Cruz", self.status()["message"])

    def test_another_households_unrated_job_blocks_nobody_else(self):
        elsewhere = make_user("po-other-home", UserProfile.ROLE_HOUSEHOLD)
        job = make_job(elsewhere, status=JobPosting.STATUS_COMPLETED)
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_COMPLETED)

        self.assertTrue(self.status()["can_post"])
