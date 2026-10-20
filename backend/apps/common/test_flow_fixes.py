"""Regression tests for the 2026-10-19/20 full-flow audit fixes, one per
finding, across the apps they touch."""

import importlib
import tempfile
from datetime import timedelta
from decimal import Decimal
from unittest.mock import patch

from django.apps import apps as django_apps
from django.contrib.auth.models import User
from django.core.cache import cache
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import SkillRating, UserProfile, WorkerCertification, WorkerSkill
from apps.accounts.serializers import WorkerCertificationSerializer
from apps.analytics.services import build_dashboard_metrics
from apps.common.models import AdminActionLog, VerificationRequest
from apps.jobs.models import JobApplication, JobPosting
from apps.jobs.services import complete_job
from apps.matching.models import RouteDistanceCache
from apps.matching.recommendations import get_recommended_jobs
from apps.matching.services import build_match_results
from apps.notifications.models import Notification
from apps.reports.services import build_platform_report, resolve_period
from apps.reviews.models import Review
from apps.reviews.services import assign_due_default_worker_ratings, assign_due_default_worker_ratings_on_read

LAT, LON = Decimal("13.9622745"), Decimal("121.5632841")


def make_user(username, role=None, *, staff=False, superuser=False, **profile):
    user = User.objects.create_user(
        username=username, email=f"{username}@example.com", password="pass-12345",
        is_staff=staff or superuser, is_superuser=superuser,
    )
    if role:
        defaults = {"verification_status": "verified", "location_label": "Isabang, Tayabas", "latitude": LAT, "longitude": LON}
        if role == UserProfile.ROLE_WORKER:
            defaults["daily_rate"] = Decimal("600.00")
        defaults.update(profile)
        UserProfile.objects.create(user=user, role=role, **defaults)
    return user


def make_job(household, **fields):
    values = {
        "title": "Cleaning", "job_type": "House Cleaning", "required_skill": "House Cleaning",
        "schedule": "2026-06-01 09:00", "location_label": "Isabang, Tayabas",
        "latitude": LAT, "longitude": LON, "service_rate": Decimal("500.00"),
    }
    values.update(fields)
    return JobPosting.objects.create(household=household, **values)


def client_for(user):
    client = APIClient()
    client.force_authenticate(user=user)
    return client


class SkillSyncEdgeCaseTests(TestCase):
    def setUp(self):
        self.worker = make_user("edge-worker", UserProfile.ROLE_WORKER, skills=["Cooking"])
        self.client = client_for(self.worker)

    def test_a_skill_name_longer_than_its_portfolio_entry_is_refused(self):
        response = self.client.patch(reverse("profile-me"), {"skills": ["x" * 121]}, format="json")

        self.assertEqual(response.status_code, 400)
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.skills, ["Cooking"])

    def test_names_differing_only_in_spacing_are_one_skill(self):
        response = self.client.patch(
            reverse("profile-me"), {"skills": ["Electrical  work", "electrical work"]}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.skills, ["Electrical work"])
        self.assertEqual(WorkerSkill.objects.filter(worker=self.worker, skill_name="Electrical work").count(), 1)

    def test_renaming_a_rated_skill_leaves_its_ratings_on_the_old_skill(self):
        household = make_user("edge-home", UserProfile.ROLE_HOUSEHOLD)
        job = make_job(household, status=JobPosting.STATUS_COMPLETED)
        cooking = WorkerSkill.objects.create(worker=self.worker, skill_name="Cooking", proficiency="expert")
        SkillRating.objects.create(job=job, household=household, worker=self.worker, skill=cooking, rating="4.9")

        response = self.client.patch(
            reverse("worker-skill-detail", args=[cooking.id]), {"skill_name": "Electrical"}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertNotEqual(response.data["id"], cooking.id)
        self.assertEqual(response.data["skill_name"], "Electrical")
        self.assertEqual(response.data["rating_count"], 0)
        cooking.refresh_from_db()
        self.assertEqual(cooking.skill_name, "Cooking")
        self.assertTrue(SkillRating.objects.filter(skill=cooking).exists())
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.skills, ["Electrical"])

    def test_renaming_onto_a_removed_skill_lists_it_again(self):
        cooking = WorkerSkill.objects.create(worker=self.worker, skill_name="Cooking", proficiency="beginner")
        laundry = WorkerSkill.objects.create(worker=self.worker, skill_name="Laundry", proficiency="expert")

        response = self.client.patch(
            reverse("worker-skill-detail", args=[cooking.id]), {"skill_name": "laundry"}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["id"], laundry.id)
        self.assertFalse(WorkerSkill.objects.filter(pk=cooking.id).exists())
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.skills, ["Laundry"])

    def test_a_household_rated_skill_carries_no_proficiency(self):
        household = make_user("edge-rater", UserProfile.ROLE_HOUSEHOLD)
        job = make_job(household, status=JobPosting.STATUS_COMPLETED)
        JobApplication.objects.create(job=job, worker=self.worker, status=JobApplication.STATUS_COMPLETED)

        response = client_for(household).post(
            f"/api/accounts/jobs/{job.id}/skill-ratings/",
            {"skill_name": "  Deep   cleaning ", "worker_id": self.worker.id, "rating": 5},
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        skill = WorkerSkill.objects.get(worker=self.worker, skill_name="Deep cleaning")
        self.assertEqual(skill.proficiency, "")


class SkillSyncMigrationTests(TestCase):
    def run_migration(self):
        module = importlib.import_module("apps.accounts.migrations.0022_sync_profile_and_portfolio_skills")
        module.sync_skills(django_apps, None)

    def test_only_the_workers_own_unrated_skills_join_matching(self):
        household = make_user("mig-home", UserProfile.ROLE_HOUSEHOLD)
        worker = make_user("mig-worker", UserProfile.ROLE_WORKER, skills=["Cooking"])
        job = make_job(household, status=JobPosting.STATUS_COMPLETED)
        plumbing = WorkerSkill.objects.create(worker=worker, skill_name="Plumbing")
        SkillRating.objects.create(job=job, household=household, worker=worker, skill=plumbing, rating="4.0")
        WorkerSkill.objects.create(worker=worker, skill_name="Laundry", proficiency="expert")

        self.run_migration()

        worker.profile.refresh_from_db()
        self.assertEqual(worker.profile.skills, ["Cooking", "Laundry"])
        self.assertEqual(WorkerSkill.objects.get(worker=worker, skill_name="Cooking").proficiency, "")

    def test_an_over_long_skill_name_is_trimmed_instead_of_failing(self):
        worker = make_user("mig-long", UserProfile.ROLE_WORKER, skills=["y" * 130])

        self.run_migration()

        worker.profile.refresh_from_db()
        self.assertEqual(worker.profile.skills, ["y" * 120])
        self.assertTrue(WorkerSkill.objects.filter(worker=worker, skill_name="y" * 120).exists())


@override_settings(MEDIA_ROOT=tempfile.mkdtemp(), PRIVATE_MEDIA_ROOT=tempfile.mkdtemp())
class CertificateResubmissionTests(TestCase):
    def setUp(self):
        self.admin = make_user("cert-admin", staff=True)
        self.worker = make_user("cert-worker", UserProfile.ROLE_WORKER)
        self.cert = WorkerCertification.objects.create(
            worker=self.worker, certificate_type="tesda", certificate_name="Cookery NC II",
            verification_status=WorkerCertification.STATUS_APPROVED, is_verified=True,
            verified_by=self.admin, verified_at=timezone.now(),
        )

    def test_changing_an_approved_certificate_sends_it_back_for_review(self):
        response = client_for(self.worker).patch(
            reverse("worker-certification-detail", args=[self.cert.id]),
            {"certificate_name": "PRC Electrical License"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.cert.refresh_from_db()
        self.assertEqual(self.cert.verification_status, WorkerCertification.STATUS_PENDING)
        self.assertFalse(self.cert.is_verified)
        self.assertIsNone(self.cert.verified_by)
        self.assertTrue(
            Notification.objects.filter(
                recipient=self.admin, notification_type=Notification.TYPE_ADMIN_ALERT,
                title="Certificate resubmitted for review",
            ).exists()
        )

    def test_saving_the_same_details_keeps_the_approval(self):
        response = client_for(self.worker).patch(
            reverse("worker-certification-detail", args=[self.cert.id]),
            {"certificate_name": "Cookery NC II"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.cert.refresh_from_db()
        self.assertEqual(self.cert.verification_status, WorkerCertification.STATUS_APPROVED)
        self.assertTrue(self.cert.is_verified)

    def test_the_file_type_is_reported_for_the_extensionless_file_url(self):
        pdf = WorkerCertification(worker=self.worker, certificate_name="x", certificate_file="certs/a.pdf")
        image = WorkerCertification(worker=self.worker, certificate_name="y", certificate_file="certs/a.JPG")
        none = WorkerCertification(worker=self.worker, certificate_name="z")
        serializer = WorkerCertificationSerializer()

        self.assertEqual(serializer.get_certificate_file_type(pdf), "pdf")
        self.assertEqual(serializer.get_certificate_file_type(image), "image")
        self.assertEqual(serializer.get_certificate_file_type(none), "")


class HiringAndCancellationTests(TestCase):
    def setUp(self):
        self.household = make_user("hire-home", UserProfile.ROLE_HOUSEHOLD)
        self.worker = make_user("hire-worker", UserProfile.ROLE_WORKER, skills=["House Cleaning"])
        self.job = make_job(self.household, worker_slots=2)
        self.application = JobApplication.objects.create(job=self.job, worker=self.worker)

    def test_a_suspended_applicant_cannot_be_hired(self):
        profile = self.worker.profile
        profile.is_blocked = True
        profile.blocked_until = timezone.now() + timedelta(days=3)
        profile.save(update_fields=["is_blocked", "blocked_until"])

        response = client_for(self.household).patch(
            reverse("job-application-status", args=[self.application.id]), {"status": "hired"}, format="json"
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_PENDING)

    def test_cancelling_a_job_closes_its_undecided_applications(self):
        hired_worker = make_user("hire-hired", UserProfile.ROLE_WORKER, skills=["House Cleaning"])
        hired = JobApplication.objects.create(job=self.job, worker=hired_worker, status=JobApplication.STATUS_HIRED)

        response = client_for(self.household).patch(
            reverse("job-detail", args=[self.job.id]), {"status": "cancelled"}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.application.refresh_from_db()
        hired.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_CLOSED)
        self.assertEqual(hired.status, JobApplication.STATUS_HIRED)
        # The pending applicant was still told the job was cancelled.
        self.assertTrue(
            Notification.objects.filter(recipient=self.worker, title="Job cancelled").exists()
        )

    def test_editing_the_radius_moves_the_matching_distance_with_it(self):
        client = client_for(self.household)

        response = client.patch(reverse("job-detail", args=[self.job.id]), {"geographic_boundary": "10km"}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        self.job.refresh_from_db()
        self.assertEqual(float(self.job.max_distance_km), 10.0)

        response = client.patch(reverse("job-detail", args=[self.job.id]), {"max_distance_km": 50}, format="json")
        self.assertEqual(response.status_code, 400)
        self.job.refresh_from_db()
        self.assertEqual(float(self.job.max_distance_km), 10.0)


class ApplicantListOrderTests(TestCase):
    def test_the_application_list_and_job_detail_share_one_order(self):
        household = make_user("order-home", UserProfile.ROLE_HOUSEHOLD)
        job = make_job(household, geographic_boundary="unlimited")
        names = []
        for username, skills, km, status in [
            ("rejected-match", ["House Cleaning"], "0.5", JobApplication.STATUS_REJECTED),
            ("no-skill", ["Cooking"], "0.7", JobApplication.STATUS_PENDING),
            ("match-far", ["House Cleaning"], "4.0", JobApplication.STATUS_PENDING),
            ("match-near", ["House Cleaning"], "1.0", JobApplication.STATUS_PENDING),
        ]:
            worker = make_user(username, UserProfile.ROLE_WORKER, skills=skills)
            RouteDistanceCache.objects.create(
                job=job, worker_profile=worker.profile, job_latitude=LAT, job_longitude=LON,
                worker_latitude=LAT, worker_longitude=LON, distance_km=Decimal(km),
            )
            JobApplication.objects.create(job=job, worker=worker, status=status)
            names.append(username)
        client = client_for(household)

        detail = client.get(reverse("job-detail", args=[job.id])).data["applications"]
        listed = client.get(reverse("job-application-list"), {"job_id": job.id}).data["results"]

        expected = ["match-near", "match-far", "no-skill", "rejected-match"]
        self.assertEqual([row["worker_username"] for row in detail], expected)
        self.assertEqual([row["worker_username"] for row in listed], expected)


class ReviewFlowTests(TestCase):
    def setUp(self):
        cache.clear()
        self.household = make_user("rev-home", UserProfile.ROLE_HOUSEHOLD)
        self.first = make_user("rev-first", UserProfile.ROLE_WORKER)
        self.second = make_user("rev-second", UserProfile.ROLE_WORKER)
        self.job = make_job(self.household, worker_slots=2, status=JobPosting.STATUS_ASSIGNED)
        for worker in (self.first, self.second):
            JobApplication.objects.create(job=self.job, worker=worker, status=JobApplication.STATUS_HIRED)
        complete_job(self.job, actor=self.household)

    def review(self, worker):
        return client_for(self.household).post(
            reverse("review-list-create"),
            {"target_username": worker.username, "job_id": self.job.id, "rating": "5.0", "feedback": "Great"},
            format="json",
        )

    def test_each_worker_on_a_shared_job_can_be_reviewed(self):
        self.assertEqual(self.review(self.first).status_code, 201)

        applications = client_for(self.household).get(reverse("job-detail", args=[self.job.id])).data["applications"]
        flags = {row["worker_username"]: row["household_can_review"] for row in applications}

        self.assertEqual(flags, {"rev-first": False, "rev-second": True})

    def test_a_review_settles_its_reminder(self):
        reminder = Notification.objects.get(
            recipient=self.household, notification_type=Notification.TYPE_REVIEW_REMINDER, actor=self.first
        )
        self.assertFalse(reminder.is_read)

        self.review(self.first)

        reminder.refresh_from_db()
        self.assertTrue(reminder.is_read)
        self.assertFalse(reminder.requires_action)
        other = Notification.objects.get(
            recipient=self.household, notification_type=Notification.TYPE_REVIEW_REMINDER, actor=self.second
        )
        self.assertFalse(other.is_read)

    def test_the_default_rating_sweep_never_retries_a_placeholder(self):
        JobPosting.objects.filter(pk=self.job.pk).update(completed_at=timezone.now() - timedelta(days=4))

        self.assertEqual(assign_due_default_worker_ratings(), 2)
        self.assertEqual(assign_due_default_worker_ratings(), 0)
        self.assertEqual(Review.objects.filter(is_system_generated=True).count(), 2)

    def test_reads_share_one_sweep_cooldown(self):
        JobPosting.objects.filter(pk=self.job.pk).update(completed_at=timezone.now() - timedelta(days=4))

        self.assertEqual(assign_due_default_worker_ratings_on_read(), 2)
        Review.objects.all().delete()
        self.assertEqual(assign_due_default_worker_ratings_on_read(), 0)


class MatchingPrefilterTests(TestCase):
    def test_a_worker_outside_the_radius_as_the_crow_flies_costs_no_routing_call(self):
        household = make_user("pre-home", UserProfile.ROLE_HOUSEHOLD)
        job = make_job(household, geographic_boundary="1km", max_distance_km=Decimal("1"))
        far = make_user(
            "pre-far", UserProfile.ROLE_WORKER, skills=["House Cleaning"],
            latitude=Decimal("14.0500000"), longitude=Decimal("121.6500000"),
        )

        with patch("apps.matching.services.fetch_road_route") as route:
            results = build_match_results(job, [far.profile])

        route.assert_not_called()
        self.assertEqual(results, [])

    def test_recommended_jobs_leave_out_suspended_households(self):
        open_home = make_user("rec-open", UserProfile.ROLE_HOUSEHOLD)
        blocked_home = make_user(
            "rec-blocked", UserProfile.ROLE_HOUSEHOLD, is_blocked=True,
            blocked_until=timezone.now() + timedelta(days=3),
        )
        worker = make_user("rec-worker", UserProfile.ROLE_WORKER, skills=["House Cleaning"])
        kept = make_job(open_home, title="Open household job", geographic_boundary="unlimited")
        make_job(blocked_home, title="Suspended household job", geographic_boundary="unlimited")

        with patch("apps.matching.services.fetch_road_route", return_value={"distance_km": 1.0, "route_points": []}):
            jobs = [item["job"] for item in get_recommended_jobs(worker)]

        self.assertEqual(jobs, [kept])


class AdminCountsTests(TestCase):
    def test_admins_and_unsubmitted_accounts_are_left_out_of_head_counts(self):
        # An admin with a (defaulted) worker profile is not a worker.
        make_user("count-admin", UserProfile.ROLE_WORKER, staff=True)
        make_user("count-home", UserProfile.ROLE_HOUSEHOLD, verification_status="pending")
        waiting = make_user("count-waiting", UserProfile.ROLE_WORKER, verification_status="pending")
        VerificationRequest.objects.create(worker=waiting, primary_id_name="id.png", secondary_doc_name="b.png")

        summary = build_dashboard_metrics()["analytics"]["summary"]

        self.assertEqual(summary["totalWorkers"], 1)
        self.assertEqual(summary["pendingVerifications"], 1)

    def test_ongoing_matches_and_active_applications_ignore_finished_jobs(self):
        household = make_user("live-home", UserProfile.ROLE_HOUSEHOLD)
        worker = make_user("live-worker", UserProfile.ROLE_WORKER)
        live = make_job(household, status=JobPosting.STATUS_ASSIGNED)
        cancelled = make_job(household, title="Cancelled", status=JobPosting.STATUS_CANCELLED)
        JobApplication.objects.create(job=live, worker=worker, status=JobApplication.STATUS_HIRED)
        JobApplication.objects.create(job=cancelled, worker=worker, status=JobApplication.STATUS_HIRED)
        other = make_user("live-other", UserProfile.ROLE_WORKER)
        JobApplication.objects.create(job=cancelled, worker=other, status=JobApplication.STATUS_PENDING)

        summary = build_dashboard_metrics()["analytics"]["summary"]

        self.assertEqual(summary["ongoingMatches"], 1)
        self.assertEqual(summary["activeApplications"], 0)

    def test_the_report_totals_the_agreed_rate_of_completed_jobs(self):
        household = make_user("value-home", UserProfile.ROLE_HOUSEHOLD)
        make_job(household, service_rate=Decimal("500.00"), status=JobPosting.STATUS_COMPLETED)
        make_job(household, title="b", service_rate=Decimal("300.50"), status=JobPosting.STATUS_COMPLETED)
        make_job(household, title="c", service_rate=Decimal("999.00"), status=JobPosting.STATUS_CANCELLED)

        report = build_platform_report(resolve_period())

        self.assertEqual(report["summary"]["completedJobValue"], 800.5)

    def test_a_restore_sent_as_text_is_logged_as_a_restore(self):
        superadmin = make_user("log-super", superuser=True)
        target = make_user("log-target", UserProfile.ROLE_WORKER, is_blocked=True)

        response = client_for(superadmin).post(
            reverse("profile-block-admin", args=[target.username]), {"blocked": "false"}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(AdminActionLog.objects.get().action, AdminActionLog.ACTION_USER_RESTORED)


class UnreadCountTests(TestCase):
    def test_the_badge_endpoint_counts_only_unread_rows(self):
        user = make_user("badge-user", UserProfile.ROLE_WORKER)
        for index in range(3):
            Notification.objects.create(
                recipient=user, notification_type=Notification.TYPE_APPLICATION,
                title=f"n{index}", message="m", is_read=index == 0,
            )

        response = client_for(user).get(reverse("notification-unread-count"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, {"unread": 2})
