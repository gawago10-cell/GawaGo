import tempfile
from pathlib import Path
from datetime import timedelta
from decimal import Decimal
from unittest.mock import patch

from django.conf import settings
from django.contrib.auth.models import User
from django.core import mail
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.throttling import ScopedRateThrottle

from apps.accounts.models import (
    PasswordResetRequest,
    SkillRating,
    UserProfile,
    WorkerPortfolio,
    WorkerAvailability,
    WorkerCertification,
    WorkerSkill,
)
from apps.accounts.services import create_password_reset_request, validate_latest_reset_request
from apps.common.authentication import create_jwt_token
from apps.common.models import AdminActionLog
from apps.jobs.models import JobApplication, JobPosting
from apps.notifications.models import Notification


class RegisterLoginFlowTests(TestCase):
    def setUp(self):
        # Login is rate-limited per IP; clear the shared throttle cache so
        # tests don't trip each other's limits.
        cache.clear()

    def test_registered_worker_can_login_immediately(self):
        register_response = self.client.post(
            reverse("register"),
            {
                "username": "JuanWorker",
                "email": "juan.worker@gmail.com",
                "password": "worker-pass123",
                "first_name": "Juan",
                "last_name": "Worker",
                "role": UserProfile.ROLE_WORKER,
                "hourly_rate": "150.00",
                "location_label": "Isabang, Tayabas City",
                "latitude": "13.9622745",
                "longitude": "121.5632841",
            },
            content_type="application/json",
        )
        self.assertEqual(register_response.status_code, 201)

        user = User.objects.get(username="JuanWorker")
        self.assertTrue(user.is_active)
        self.assertTrue(user.check_password("worker-pass123"))

        login_response = self.client.post(
            reverse("login"),
            {"username": "JuanWorker", "password": "worker-pass123"},
            content_type="application/json",
        )
        self.assertEqual(login_response.status_code, 200)
        self.assertEqual(login_response.json()["username"], "JuanWorker")
        self.assertEqual(login_response.json()["role"], UserProfile.ROLE_WORKER)

    def test_worker_registration_requires_positive_rate_and_location(self):
        response = self.client.post(
            reverse("register"),
            {
                "username": "IncompleteWorker",
                "email": "incomplete.worker@gmail.com",
                "password": "worker-pass123",
                "role": UserProfile.ROLE_WORKER,
                "hourly_rate": "0.00",
            },
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("service_rate", response.json())
        self.assertFalse(User.objects.filter(username="IncompleteWorker").exists())

    def test_worker_registration_rejects_more_than_four_skills(self):
        response = self.client.post(
            reverse("register"),
            {
                "username": "TooManySkillsWorker",
                "email": "too.many.skills@gmail.com",
                "password": "worker-pass123",
                "role": UserProfile.ROLE_WORKER,
                "hourly_rate": "150.00",
                "location_label": "Isabang, Tayabas City",
                "latitude": "13.9622745",
                "longitude": "121.5632841",
                "skills": ["House Cleaning", "Cooking", "Laundry", "Gardening", "Driving"],
            },
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("skills", response.json())
        self.assertFalse(User.objects.filter(username="TooManySkillsWorker").exists())

    def test_household_registration_does_not_require_worker_rates(self):
        response = self.client.post(
            reverse("register"),
            {
                "username": "NewHousehold",
                "email": "new.household@gmail.com",
                "password": "household-pass123",
                "role": UserProfile.ROLE_HOUSEHOLD,
            },
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201)

    def test_login_refuses_a_deactivated_account(self):
        """Deactivating a user in Django admin must stick: a correct password
        used to flip is_active back on."""
        user = User.objects.create_user(
            username="Deactivated",
            email="deactivated@gmail.com",
            password="legacy-pass123",
            is_active=False,
        )
        UserProfile.objects.create(user=user, role=UserProfile.ROLE_HOUSEHOLD)

        response = self.client.post(
            reverse("login"),
            {"username": "Deactivated", "password": "legacy-pass123"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        user.refresh_from_db()
        self.assertFalse(user.is_active)

    def test_login_accepts_username_case_used_differently_from_registration(self):
        User.objects.create_user(username="MixedCaseUser", email="mixed@gmail.com", password="case-pass123")
        UserProfile.objects.create(user=User.objects.get(username="MixedCaseUser"), role=UserProfile.ROLE_HOUSEHOLD)

        response = self.client.post(
            reverse("login"),
            {"username": " mixedcaseuser ", "password": "case-pass123"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["username"], "MixedCaseUser")

    def test_staff_login_returns_admin_role(self):
        User.objects.create_user(
            username="StaffAdmin",
            email="staff.admin@gawago.test",
            password="admin-pass123",
            is_staff=True,
        )

        response = self.client.post(
            reverse("login"),
            {"username": "StaffAdmin", "password": "admin-pass123"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["role"], "admin")

    def test_superuser_login_returns_superadmin_role(self):
        User.objects.create_superuser(
            username="RootAdmin",
            email="root.admin@gawago.test",
            password="admin-pass123",
        )

        response = self.client.post(
            reverse("login"),
            {"username": "RootAdmin", "password": "admin-pass123"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["role"], "superadmin")


class PasswordResetFlowTests(TestCase):
    def setUp(self):
        # These endpoints are rate-limited per IP; clear the shared throttle
        # cache so tests don't trip each other's limits.
        cache.clear()
        self.user = User.objects.create_user(username="worker1", email="worker1@gmail.com", password="initial-pass123")

    @patch("apps.accounts.views.send_password_reset_email")
    @patch("apps.accounts.services.generate_reset_token", return_value="123456")
    def test_forgot_password_creates_reset_request(self, mock_generate_token, mock_send_email):
        response = self.client.post(reverse("forgot-password"), {"email": "worker1@gmail.com"}, content_type="application/json")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(PasswordResetRequest.objects.filter(email="worker1@gmail.com").exists())
        mock_generate_token.assert_called_once()
        mock_send_email.assert_called_once()

    @patch("apps.accounts.views.send_password_reset_email")
    @patch("apps.accounts.services.generate_reset_token", return_value="123456")
    def test_verify_and_reset_password(self, mock_generate_token, mock_send_email):
        self.client.post(reverse("forgot-password"), {"email": "worker1@gmail.com"}, content_type="application/json")

        verify_response = self.client.post(
            reverse("verify-reset-token"),
            {"email": "worker1@gmail.com", "token": "123456"},
            content_type="application/json",
        )
        self.assertEqual(verify_response.status_code, 200)

        reset_response = self.client.post(
            reverse("reset-password"),
            {"email": "worker1@gmail.com", "token": "123456", "new_password": "new-pass123"},
            content_type="application/json",
        )
        self.assertEqual(reset_response.status_code, 200)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("new-pass123"))

        reset_request = PasswordResetRequest.objects.get(email="worker1@gmail.com")
        self.assertIsNotNone(reset_request.used_at)
        self.assertGreater(reset_request.used_at, reset_request.created_at)

    @patch("apps.accounts.views.send_password_reset_email")
    @patch("apps.accounts.services.generate_reset_token", return_value="123456")
    def test_expired_code_is_rejected(self, mock_generate_token, mock_send_email):
        self.client.post(reverse("forgot-password"), {"email": "worker1@gmail.com"}, content_type="application/json")
        reset_request = PasswordResetRequest.objects.get(email="worker1@gmail.com")
        reset_request.expires_at = timezone.now() - timedelta(minutes=1)
        reset_request.save(update_fields=["expires_at"])

        response = self.client.post(
            reverse("verify-reset-token"),
            {"email": "worker1@gmail.com", "token": "123456"},
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 400)


class ProfileUpdateTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="worker-profile",
            email="worker.profile@gmail.com",
            password="worker-pass123",
        )
        self.profile = UserProfile.objects.create(
            user=self.user,
            role=UserProfile.ROLE_WORKER,
            hourly_rate="150.00",
            location_label="Isabang, Tayabas City",
            latitude="13.9622745",
            longitude="121.5632841",
        )
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': self.user.id})}"

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
    def test_profile_update_cannot_change_role(self):
        response = self.client.patch(
            reverse("profile-me"),
            {"role": UserProfile.ROLE_HOUSEHOLD, "phone": "09170000000"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200)
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.role, UserProfile.ROLE_WORKER)
        self.assertEqual(self.profile.phone, "09170000000")
        self.assertTrue(
            Notification.objects.filter(
                recipient=self.user,
                notification_type=Notification.TYPE_ACCOUNT_ACTIVITY,
                title="Profile updated",
            ).exists()
        )
        self.assertEqual(mail.outbox[-1].to, [self.user.email])
        self.assertEqual(mail.outbox[-1].subject, "GawaGo: Profile updated")

    def test_worker_cannot_clear_last_service_rate(self):
        response = self.client.patch(
            reverse("profile-me"),
            {"hourly_rate": None, "daily_rate": None},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("service_rate", response.json())
        self.profile.refresh_from_db()
        self.assertEqual(str(self.profile.hourly_rate), "150.00")

    def test_worker_cannot_clear_exact_location(self):
        response = self.client.patch(
            reverse("profile-me"),
            {"latitude": None, "longitude": None},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("location", response.json())
        self.profile.refresh_from_db()
        self.assertIsNotNone(self.profile.latitude)


class WorkerAvailabilityTests(TestCase):
    def setUp(self):
        self.worker = User.objects.create_user(username="availability-worker", password="worker-pass123")
        self.household = User.objects.create_user(username="availability-household", password="household-pass123")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)

    def authenticate(self, user):
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': user.id})}"

    def test_worker_can_replace_availability_windows(self):
        self.authenticate(self.worker)
        WorkerAvailability.objects.create(
            worker=self.worker,
            date="2026-06-01",
            start_time="08:00",
            end_time="09:00",
        )

        response = self.client.put(
            reverse("worker-availability"),
            {
                "availability_windows": [
                    {
                        "date": "2026-06-02",
                        "start_time": "09:00",
                        "end_time": "12:00",
                        "is_available": True,
                    },
                    {
                        "date": "2026-06-03",
                        "start_time": "13:00",
                        "end_time": "17:00",
                        "is_available": True,
                    },
                ]
            },
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(WorkerAvailability.objects.filter(worker=self.worker).count(), 2)
        self.assertEqual(response.json()[0]["date"], "2026-06-02")

    def test_household_cannot_manage_worker_availability(self):
        self.authenticate(self.household)

        response = self.client.get(reverse("worker-availability"))

        self.assertEqual(response.status_code, 403)

    def test_anonymous_user_cannot_manage_worker_availability(self):
        response = self.client.get(reverse("worker-availability"))

        self.assertEqual(response.status_code, 401)

    def test_availability_rejects_equal_start_and_end_time(self):
        self.authenticate(self.worker)

        response = self.client.put(
            reverse("worker-availability"),
            {
                "availability_windows": [
                    {
                        "date": "2026-06-02",
                        "start_time": "09:00",
                        "end_time": "09:00",
                        "is_available": True,
                    }
                ]
            },
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(WorkerAvailability.objects.filter(worker=self.worker).exists())

class PublicProfilePrivacyTests(TestCase):
    def setUp(self):
        self.worker = User.objects.create_user(
            username="public-worker",
            email="public.worker@gmail.com",
            password="worker-pass123",
        )
        UserProfile.objects.create(
            user=self.worker,
            role=UserProfile.ROLE_WORKER,
            phone="09171234567",
            skills=["House Cleaning"],
            latitude="13.9622745",
            longitude="121.5632841",
        )
        self.household = User.objects.create_user(
            username="profile-household",
            email="profile.household@gmail.com",
            password="household-pass123",
        )
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.admin = User.objects.create_superuser(
            username="profile-admin",
            email="profile.admin@gmail.com",
            password="admin-pass123",
        )

    def test_anonymous_profile_list_is_rejected(self):
        response = self.client.get(reverse("profile-list"))

        self.assertEqual(response.status_code, 401)

    def test_authenticated_profile_list_hides_private_contact_and_exact_location_fields(self):
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': self.household.id})}"

        response = self.client.get(reverse("profile-list"))

        self.assertEqual(response.status_code, 200)
        first_profile = response.json()["results"][0]
        self.assertNotIn("email", first_profile)
        self.assertNotIn("phone", first_profile)
        self.assertNotIn("verification_request", first_profile)
        self.assertNotIn("latitude", first_profile)
        self.assertNotIn("longitude", first_profile)
        self.assertNotIn("is_blocked", first_profile)
        self.assertNotIn("blocked_until", first_profile)
        self.assertNotIn("blocked_reason", first_profile)
        self.assertNotIn("is_staff", first_profile)

    def test_staff_profile_list_includes_private_contact_fields(self):
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': self.admin.id})}"

        response = self.client.get(reverse("profile-list"))

        self.assertEqual(response.status_code, 200)
        first_profile = response.json()["results"][0]
        self.assertIn("email", first_profile)
        self.assertIn("phone", first_profile)
        self.assertIn("latitude", first_profile)
        self.assertIn("longitude", first_profile)
        self.assertIn("is_blocked", first_profile)
        self.assertIn("is_staff", first_profile)
        self.assertIn("date_joined", first_profile)


class SkillRatingPermissionTests(TestCase):
    def setUp(self):
        cache.clear()
        self.household = User.objects.create_user(username="rating-household", password="household-pass123")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)

        self.worker = User.objects.create_user(username="rating-worker", password="worker-pass123")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)

        self.outsider = User.objects.create_user(username="rating-outsider", password="outsider-pass123")
        UserProfile.objects.create(user=self.outsider, role=UserProfile.ROLE_WORKER)

        self.job = JobPosting.objects.create(
            household=self.household,
            title="Leaky pipe",
            job_type="Plumbing",
            required_skill="Plumbing",
            schedule="One-Time",
            location_label="Tayabas",
            latitude=Decimal("13.9835094"),
            longitude=Decimal("121.5651925"),
            service_rate=Decimal("500.00"),
            worker_slots=1,
            status=JobPosting.STATUS_COMPLETED,
        )
        JobApplication.objects.create(job=self.job, worker=self.worker, status=JobApplication.STATUS_COMPLETED)

        self.worker_skill = WorkerSkill.objects.create(worker=self.worker, skill_name="Plumbing")
        self.outsider_skill = WorkerSkill.objects.create(worker=self.outsider, skill_name="Plumbing")

        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': self.household.id})}"

    def _url(self):
        return reverse("skill-rating", kwargs={"job_id": self.job.id})

    def test_household_can_rate_skill_of_worker_who_completed_the_job(self):
        response = self.client.post(
            self._url(),
            {"skill": self.worker_skill.id, "rating": 4},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(SkillRating.objects.filter(job=self.job, skill=self.worker_skill).count(), 1)

    def test_rating_outside_one_to_five_is_rejected(self):
        # Ratings feed WorkerSkill.average_rating, so an out-of-range value
        # would permanently skew the worker's displayed skill score.
        for invalid in (9.9, 0, -3):
            response = self.client.post(
                self._url(),
                {"skill": self.worker_skill.id, "rating": invalid},
                content_type="application/json",
            )
            self.assertEqual(response.status_code, 400, f"rating={invalid} should be rejected")

        self.assertFalse(SkillRating.objects.filter(skill=self.worker_skill).exists())

    def test_household_cannot_rate_skill_of_worker_who_never_worked_the_job(self):
        response = self.client.post(
            self._url(),
            {"skill": self.outsider_skill.id, "rating": 5},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 403)
        self.assertFalse(SkillRating.objects.filter(skill=self.outsider_skill).exists())

    def test_rating_by_skill_name_creates_the_skill_on_the_completed_worker(self):
        response = self.client.post(
            self._url(),
            {"skill_name": "Electrical Work", "worker_id": self.worker.id, "rating": 3},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201)
        created = WorkerSkill.objects.get(worker=self.worker, skill_name="Electrical Work")
        self.assertEqual(SkillRating.objects.get(skill=created).rating, Decimal("3.0"))


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class CertificateVerificationAdminTests(TestCase):
    """The admin approval workflow for worker certificates (roadmap #11).
    The endpoints shipped without a UI, so nothing exercised them before.
    """

    def setUp(self):
        self.worker = User.objects.create_user(username="cert-worker", password="worker-pass123")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.admin = User.objects.create_user(username="cert-admin", password="admin-pass123", is_staff=True)
        self.certificate = WorkerCertification.objects.create(
            worker=self.worker,
            certificate_name="TESDA Housekeeping NC II",
            issuer="TESDA",
            certificate_file=SimpleUploadedFile("tesda.png", PNG_BYTES, content_type="image/png"),
        )

    def authenticate(self, user):
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': user.id})}"

    def test_admin_sees_pending_certificates_with_the_owning_worker(self):
        self.authenticate(self.admin)

        response = self.client.get(reverse("certificate-admin-list"), {"status": "pending"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["results"]), 1)
        # The queue lists certificates across all workers, so it has to say
        # whose each one is.
        self.assertEqual(response.data["results"][0]["worker_username"], "cert-worker")

    def test_admin_can_get_a_single_certificate_by_id(self):
        # GET on the detail URL used to crash: get(self, request) took no
        # cert_id, but the detail route still dispatches GET there.
        self.authenticate(self.admin)

        response = self.client.get(reverse("certificate-admin-verify", kwargs={"cert_id": self.certificate.id}))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["worker_username"], "cert-worker")

    def test_admin_get_for_a_missing_certificate_id_returns_404_not_500(self):
        self.authenticate(self.admin)

        response = self.client.get(reverse("certificate-admin-verify", kwargs={"cert_id": 999999}))

        self.assertEqual(response.status_code, 404)

    def test_worker_cannot_reach_the_admin_certificate_queue(self):
        self.authenticate(self.worker)

        response = self.client.get(reverse("certificate-admin-list"))

        self.assertEqual(response.status_code, 403)

    def test_admin_approval_marks_the_certificate_verified_and_notifies_the_worker(self):
        self.authenticate(self.admin)

        response = self.client.patch(
            reverse("certificate-admin-verify", kwargs={"cert_id": self.certificate.id}),
            {"verification_status": "approved", "verification_notes": "Checked against TESDA registry."},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200)
        self.certificate.refresh_from_db()
        self.assertEqual(self.certificate.verification_status, "approved")
        self.assertTrue(self.certificate.is_verified)
        self.assertEqual(self.certificate.verified_by, self.admin)
        self.assertTrue(
            Notification.objects.filter(recipient=self.worker, notification_type=Notification.TYPE_VERIFICATION).exists()
        )

    def test_invalid_certificate_decision_is_rejected(self):
        self.authenticate(self.admin)

        response = self.client.patch(
            reverse("certificate-admin-verify", kwargs={"cert_id": self.certificate.id}),
            {"verification_status": "maybe"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        self.certificate.refresh_from_db()
        self.assertEqual(self.certificate.verification_status, "pending")

    def test_status_all_returns_certificates_regardless_of_status(self):
        """The Worker Credentials screen's header stats need every status at
        once to total up correctly, not just the tab's active filter."""
        self.certificate.verification_status = WorkerCertification.STATUS_APPROVED
        self.certificate.save(update_fields=["verification_status"])
        WorkerCertification.objects.create(
            worker=self.worker,
            certificate_name="Second cert",
            verification_status=WorkerCertification.STATUS_REJECTED,
        )
        self.authenticate(self.admin)

        response = self.client.get(reverse("certificate-admin-list"), {"status": "all"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["results"]), 2)

    def test_certificate_payload_includes_worker_context_for_the_review_card(self):
        self.worker.first_name = "Cert"
        self.worker.last_name = "Worker"
        self.worker.save(update_fields=["first_name", "last_name"])
        self.worker.profile.location_label = "Isabang, Tayabas City"
        self.worker.profile.save(update_fields=["location_label"])
        self.authenticate(self.admin)

        response = self.client.get(reverse("certificate-admin-list"), {"status": "pending"})

        self.assertEqual(response.status_code, 200)
        record = response.data["results"][0]
        self.assertEqual(record["worker_name"], "Cert Worker")
        self.assertEqual(record["worker_location_label"], "Isabang, Tayabas City")
        self.assertIsNotNone(record["worker_member_since"])
        self.assertEqual(record["certificate_type_label"], "Professional Certification")


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())


class UserAccountBlockAdminTests(TestCase):
    """The generic suspend/restore action behind the User Management screen
    (apps.accounts.services.apply_account_suspension), which mirrors the
    complaint-review "block this respondent" action but targets a username
    directly instead of going through a complaint record."""

    def setUp(self):
        self.worker = User.objects.create_user(username="um-worker", password="worker-pass123")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.admin = User.objects.create_superuser(username="um-admin", password="admin-pass123")
        self.staff_non_super = User.objects.create_user(username="um-staff", password="staff-pass123", is_staff=True)

    def authenticate(self, user):
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': user.id})}"

    def test_admin_can_suspend_and_restore_an_account_by_username(self):
        self.authenticate(self.admin)
        url = reverse("profile-block-admin", kwargs={"username": self.worker.username})

        blocked = self.client.post(url, {"reason": "Policy violation."}, content_type="application/json")
        self.assertEqual(blocked.status_code, 200)
        self.worker.profile.refresh_from_db()
        self.assertTrue(self.worker.profile.is_blocked)
        self.assertEqual(self.worker.profile.blocked_reason, "Policy violation.")
        self.assertTrue(blocked.json()["is_blocked"])

        restored = self.client.post(url, {"blocked": False}, content_type="application/json")
        self.assertEqual(restored.status_code, 200)
        self.worker.profile.refresh_from_db()
        self.assertFalse(self.worker.profile.is_blocked)

    def test_admin_can_suspend_for_a_limited_duration(self):
        self.authenticate(self.admin)
        url = reverse("profile-block-admin", kwargs={"username": self.worker.username})

        response = self.client.post(url, {"duration_days": 7}, content_type="application/json")

        self.assertEqual(response.status_code, 200)
        self.worker.profile.refresh_from_db()
        self.assertTrue(self.worker.profile.is_blocked)
        self.assertIsNotNone(self.worker.profile.blocked_until)

    def test_invalid_duration_is_rejected(self):
        self.authenticate(self.admin)
        url = reverse("profile-block-admin", kwargs={"username": self.worker.username})

        response = self.client.post(url, {"duration_days": 5}, content_type="application/json")

        self.assertEqual(response.status_code, 400)
        self.worker.profile.refresh_from_db()
        self.assertFalse(self.worker.profile.is_blocked)

    def test_a_staff_admin_who_is_not_superadmin_cannot_suspend(self):
        self.authenticate(self.staff_non_super)
        url = reverse("profile-block-admin", kwargs={"username": self.worker.username})

        response = self.client.post(url, {}, content_type="application/json")

        self.assertEqual(response.status_code, 403)

    def test_admin_accounts_cannot_be_suspended_via_user_management(self):
        self.authenticate(self.admin)
        url = reverse("profile-block-admin", kwargs={"username": self.staff_non_super.username})

        response = self.client.post(url, {}, content_type="application/json")

        self.assertEqual(response.status_code, 403)

    def test_unknown_username_returns_404(self):
        self.authenticate(self.admin)
        url = reverse("profile-block-admin", kwargs={"username": "does-not-exist"})

        response = self.client.post(url, {}, content_type="application/json")

        self.assertEqual(response.status_code, 404)


class AdminAccountManagementTests(TestCase):
    """The superadmin "Admin Management" screen. It used to be a hardcoded
    table with inert buttons; these lock in that it is backed by real data
    and that the destructive edges are closed."""

    def setUp(self):
        cache.clear()
        self.superadmin = User.objects.create_superuser(username="owner", password="owner-pass123")
        self.staff_admin = User.objects.create_user(
            username="staffer", password="staff-pass123", is_staff=True, email="staffer@example.com"
        )
        self.worker = User.objects.create_user(username="am-worker", password="worker-pass123")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.list_url = reverse("admin-account-list")

    def authenticate(self, user):
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': user.id})}"

    def detail_url(self, username):
        return reverse("admin-account-detail", kwargs={"username": username})

    def test_list_returns_only_staff_accounts_with_the_owner_first(self):
        self.authenticate(self.superadmin)

        response = self.client.get(self.list_url)

        self.assertEqual(response.status_code, 200)
        usernames = [row["username"] for row in response.json()]
        self.assertEqual(usernames, ["owner", "staffer"])
        self.assertNotIn("am-worker", usernames)
        self.assertEqual(response.json()[0]["role_label"], "Full System Control")
        self.assertEqual(response.json()[1]["role_label"], "Admin")

    def test_superadmin_can_create_a_staff_admin_that_can_then_log_in(self):
        self.authenticate(self.superadmin)

        response = self.client.post(
            self.list_url,
            {
                "username": "new-admin",
                "email": "New-Admin@Example.com",
                "password": "br4nd-new-pass",
                "first_name": "New",
                "last_name": "Admin",
            },
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 201)
        created = User.objects.get(username="new-admin")
        self.assertTrue(created.is_staff)
        # Minting another full-control account from a web form is not
        # something this screen is allowed to do.
        self.assertFalse(created.is_superuser)
        self.assertEqual(created.email, "new-admin@example.com")

        del self.client.defaults["HTTP_AUTHORIZATION"]
        login = self.client.post(
            reverse("login"),
            {"username": "new-admin", "password": "br4nd-new-pass"},
            content_type="application/json",
        )
        self.assertEqual(login.status_code, 200)
        self.assertEqual(login.json()["role"], "admin")

    def test_creating_an_admin_is_recorded_in_the_audit_log(self):
        self.authenticate(self.superadmin)

        self.client.post(
            self.list_url,
            {"username": "logged-admin", "email": "logged@example.com", "password": "br4nd-new-pass"},
            content_type="application/json",
        )

        entry = AdminActionLog.objects.get(action=AdminActionLog.ACTION_ADMIN_CREATED)
        self.assertEqual(entry.actor_username, "owner")
        self.assertEqual(entry.target_label, "logged-admin")

    def test_duplicate_username_or_email_is_a_validation_error(self):
        self.authenticate(self.superadmin)

        duplicate_name = self.client.post(
            self.list_url,
            {"username": "STAFFER", "email": "fresh@example.com", "password": "br4nd-new-pass"},
            content_type="application/json",
        )
        duplicate_email = self.client.post(
            self.list_url,
            {"username": "fresh-name", "email": "Staffer@example.com", "password": "br4nd-new-pass"},
            content_type="application/json",
        )

        self.assertEqual(duplicate_name.status_code, 400)
        self.assertEqual(duplicate_email.status_code, 400)
        self.assertEqual(User.objects.filter(is_staff=True).count(), 2)

    def test_a_weak_password_is_rejected(self):
        self.authenticate(self.superadmin)

        response = self.client.post(
            self.list_url,
            {"username": "weak-admin", "email": "weak@example.com", "password": "password"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(User.objects.filter(username="weak-admin").exists())

    def test_deactivating_an_admin_blocks_an_already_signed_in_session(self):
        token = create_jwt_token({"user_id": self.staff_admin.id})
        self.authenticate(self.superadmin)

        response = self.client.patch(
            self.detail_url("staffer"), {"is_active": False}, content_type="application/json"
        )

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json()["is_active"])
        self.staff_admin.refresh_from_db()
        self.assertFalse(self.staff_admin.is_active)
        self.assertEqual(
            AdminActionLog.objects.filter(action=AdminActionLog.ACTION_ADMIN_DEACTIVATED).count(), 1
        )

        # The token they were already holding stops working immediately.
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {token}"
        self.assertEqual(self.client.get(reverse("profile-me")).status_code, 401)

    def test_reactivating_an_admin_restores_access_and_is_logged(self):
        self.staff_admin.is_active = False
        self.staff_admin.save(update_fields=["is_active"])
        self.authenticate(self.superadmin)

        response = self.client.patch(
            self.detail_url("staffer"), {"is_active": True}, content_type="application/json"
        )

        self.assertEqual(response.status_code, 200)
        self.staff_admin.refresh_from_db()
        self.assertTrue(self.staff_admin.is_active)
        self.assertEqual(
            AdminActionLog.objects.filter(action=AdminActionLog.ACTION_ADMIN_REACTIVATED).count(), 1
        )

    def test_an_unchanged_is_active_does_not_write_a_duplicate_log_row(self):
        self.authenticate(self.superadmin)

        self.client.patch(self.detail_url("staffer"), {"is_active": True}, content_type="application/json")

        self.assertEqual(AdminActionLog.objects.count(), 0)

    def test_a_superadmin_cannot_deactivate_their_own_account(self):
        self.authenticate(self.superadmin)

        response = self.client.patch(
            self.detail_url("owner"), {"is_active": False}, content_type="application/json"
        )

        self.assertEqual(response.status_code, 400)
        self.superadmin.refresh_from_db()
        self.assertTrue(self.superadmin.is_active)

    def test_a_full_control_account_cannot_be_deactivated(self):
        other_owner = User.objects.create_superuser(username="other-owner", password="other-pass123")
        self.authenticate(self.superadmin)

        response = self.client.patch(
            self.detail_url("other-owner"), {"is_active": False}, content_type="application/json"
        )

        self.assertEqual(response.status_code, 403)
        other_owner.refresh_from_db()
        self.assertTrue(other_owner.is_active)

    def test_a_non_staff_account_is_not_reachable_through_this_screen(self):
        self.authenticate(self.superadmin)

        response = self.client.patch(
            self.detail_url("am-worker"), {"is_active": False}, content_type="application/json"
        )

        self.assertEqual(response.status_code, 404)
        self.worker.refresh_from_db()
        self.assertTrue(self.worker.is_active)

    def test_is_active_must_be_a_boolean(self):
        self.authenticate(self.superadmin)

        response = self.client.patch(
            self.detail_url("staffer"), {"is_active": "nope"}, content_type="application/json"
        )

        self.assertEqual(response.status_code, 400)

    def test_a_staff_admin_who_is_not_superadmin_cannot_manage_admins(self):
        self.authenticate(self.staff_admin)

        self.assertEqual(self.client.get(self.list_url).status_code, 403)
        self.assertEqual(
            self.client.patch(
                self.detail_url("staffer"), {"is_active": False}, content_type="application/json"
            ).status_code,
            403,
        )

    def test_an_anonymous_caller_cannot_manage_admins(self):
        self.assertEqual(self.client.get(self.list_url).status_code, 401)


class SignupThrottleTests(TestCase):
    """Registration tells a caller whether an email is already in use, which
    is only safe to leave in place if it can't be done in bulk."""

    def setUp(self):
        cache.clear()

    def payload(self, index):
        return {
            "username": f"probe{index}",
            "email": f"probe{index}@example.com",
            "password": "pr0be-pass-word",
            "role": UserProfile.ROLE_HOUSEHOLD,
        }

    def test_a_signup_rate_is_configured(self):
        # The test below supplies its own rate, so it would still pass if the
        # deployed setting went missing.
        self.assertIn("signup", settings.REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"])

    def test_repeated_signups_from_one_ip_are_throttled(self):
        # DRF reads DEFAULT_THROTTLE_RATES into a class attribute at import,
        # so override_settings can't reach it -- patch the class instead.
        with patch.dict(ScopedRateThrottle.THROTTLE_RATES, {"signup": "3/min"}):
            statuses = [
                self.client.post(
                    reverse("register"), self.payload(index), content_type="application/json"
                ).status_code
                for index in range(4)
            ]

        self.assertEqual(statuses[:3], [201, 201, 201])
        self.assertEqual(statuses[3], 429)


class AccountRoleTests(TestCase):
    """Login and /me agree on one account role; staff never read as worker."""

    def setUp(self):
        cache.clear()  # four logins per test; keep clear of the login throttle

    def _role_from(self, user, password="password"):
        from django.urls import reverse
        from rest_framework.test import APIClient

        client = APIClient()
        login = client.post(reverse("login"), {"username": user.username, "password": password}, format="json")
        self.assertEqual(login.status_code, 200, login.data)
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
        me = client.get(reverse("profile-me"))
        return login.data["role"], me.data["role"], (me.data["profile"] or {}).get("role")

    def test_roles_per_account_type(self):
        from django.contrib.auth.models import User
        from apps.accounts.models import UserProfile

        staff = User.objects.create_user(username="role-staff", password="password", is_staff=True)
        UserProfile.objects.create(user=staff)  # profile role defaults to "worker"
        superadmin = User.objects.create_user(username="role-super", password="password", is_staff=True, is_superuser=True)
        household = User.objects.create_user(username="role-house", password="password")
        UserProfile.objects.create(user=household, role=UserProfile.ROLE_HOUSEHOLD)
        worker = User.objects.create_user(username="role-worker", password="password")
        UserProfile.objects.create(user=worker, role=UserProfile.ROLE_WORKER)

        login_role, me_role, profile_role = self._role_from(staff)
        self.assertEqual((login_role, me_role), ("admin", "admin"))
        self.assertEqual(profile_role, "worker", "the defaulted profile role is why clients must not use it")
        self.assertEqual(self._role_from(superadmin), ("superadmin", "superadmin", None))
        # Reading /me must not create a worker profile for an admin: that
        # profile used to be counted as a worker on the dashboard.
        self.assertFalse(UserProfile.objects.filter(user=superadmin).exists())
        self.assertEqual(self._role_from(household)[:2], ("household", "household"))
        self.assertEqual(self._role_from(worker)[:2], ("worker", "worker"))


PNG_BYTES = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
    b"\x00\x00\x00\rIDATx\xdac\xfc\xcf\xc0P\x0f\x00\x04\x85\x01\x80\x84\xa9\x8c!\x00\x00\x00\x00IEND\xaeB`\x82"
)


@override_settings(MEDIA_ROOT=tempfile.mkdtemp(), PRIVATE_MEDIA_ROOT=tempfile.mkdtemp())
class AccountSecurityRegressionTests(TestCase):
    """Regressions from the 2026-09 QA pass."""

    def setUp(self):
        from rest_framework.test import APIClient

        cache.clear()
        self.client = APIClient()
        self.worker = User.objects.create_user(username="qa-worker", email="qa-worker@gmail.com", password="pass-12345")
        UserProfile.objects.create(
            user=self.worker, role=UserProfile.ROLE_WORKER, hourly_rate="100.00",
            location_label="Isabang, Tayabas", latitude="13.9622745", longitude="121.5632841",
        )
        self.other = User.objects.create_user(username="qa-other", email="qa-other@gmail.com", password="pass-12345")
        UserProfile.objects.create(user=self.other, role=UserProfile.ROLE_HOUSEHOLD)
        self.admin = User.objects.create_user(username="qa-admin", email="qa-admin@gmail.com", password="pass-12345", is_staff=True)

    def test_email_cannot_be_changed_to_another_accounts_email(self):
        self.client.force_authenticate(user=self.worker)

        response = self.client.patch(reverse("profile-me"), {"email": "QA-Other@gmail.com"}, format="json")

        self.assertEqual(response.status_code, 400)
        self.worker.refresh_from_db()
        self.assertEqual(self.worker.email, "qa-worker@gmail.com")

    def test_certificate_upload_rejects_html(self):
        self.client.force_authenticate(user=self.worker)

        response = self.client.post(
            reverse("worker-certification"),
            {"certificate_type": "tesda", "certificate_name": "NC II",
             "certificate_file": SimpleUploadedFile("cert.html", b"<script></script>", content_type="text/html")},
            format="multipart",
        )

        self.assertEqual(response.status_code, 400)

    def test_forgot_password_reply_does_not_reveal_registration(self):
        unknown = self.client.post(reverse("forgot-password"), {"email": "nobody@gmail.com"}, format="json")
        cache.clear()
        known = self.client.post(reverse("forgot-password"), {"email": "qa-worker@gmail.com"}, format="json")

        self.assertEqual(unknown.status_code, known.status_code)
        self.assertEqual(unknown.data, known.data)

    def test_reset_code_stops_working_after_five_wrong_guesses(self):
        reset_request, token = create_password_reset_request(self.worker)
        for _ in range(5):
            self.assertIsNone(validate_latest_reset_request("qa-worker@gmail.com", "000000" if token != "000000" else "111111"))

        self.assertIsNone(validate_latest_reset_request("qa-worker@gmail.com", token))

    def test_verification_preview_type_ignores_the_uploaders_display_name(self):
        self.client.force_authenticate(user=self.worker)
        created = self.client.post(
            reverse("verification-request-list-create"),
            {"primary_id_name": "evil.html", "secondary_doc_name": "b.png",
             "primary_id_file": SimpleUploadedFile("a.png", PNG_BYTES, content_type="image/png"),
             "secondary_doc_file": SimpleUploadedFile("b.png", PNG_BYTES, content_type="image/png")},
            format="multipart",
        )
        self.assertEqual(created.status_code, 201, created.data)
        request_id = created.data["verification_request"]["id"]

        response = self.client.get(reverse("verification-request-document", args=[request_id, "primary"]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "image/png")
        self.assertEqual(response["X-Content-Type-Options"], "nosniff")


class InputHardeningTests(TestCase):
    """Malformed or oversized input must get a 400, never a 500."""

    def setUp(self):
        from rest_framework.test import APIClient

        cache.clear()
        self.client = APIClient()
        self.household = User.objects.create_user(username="hard-household", password="pass-12345")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD, verification_status="verified")
        self.client.force_authenticate(user=self.household)

    def test_oversized_profile_fields_are_rejected(self):
        for payload in ({"location_label": "A" * 300}, {"first_name": "A" * 200}):
            with self.subTest(payload=list(payload)):
                self.assertEqual(self.client.patch(reverse("profile-me"), payload, format="json").status_code, 400)

    def test_non_numeric_filters_and_ids_are_rejected(self):
        self.assertEqual(self.client.get(reverse("job-application-list"), {"job_id": "abc"}).status_code, 400)
        self.assertEqual(self.client.get(reverse("job-list"), {"min_rate": "abc"}).status_code, 200)
        response = self.client.post(
            reverse("complaint-create"), {"job": "abc", "complaint_type": "other", "description": "x"}, format="json"
        )
        self.assertEqual(response.status_code, 404)

    def test_huge_worker_slots_rejected(self):
        response = self.client.post(reverse("job-list"), {
            "title": "t", "job_type": "Laundry", "required_skill": "Laundry", "schedule": "Mon",
            "location_label": "Isabang", "latitude": "13.96", "longitude": "121.56",
            "service_rate": "100", "worker_slots": 10**12,
        }, format="json")
        self.assertEqual(response.status_code, 400)

    def test_reading_a_portfolio_does_not_create_one(self):
        self.client.force_authenticate(user=None)

        response = self.client.get(reverse("worker-portfolio-public", args=[self.household.id]))

        self.assertEqual(response.status_code, 200)
        self.assertFalse(WorkerPortfolio.objects.filter(worker=self.household).exists())


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class MultipartProfileSkillsTests(TestCase):
    """Saving a profile with a photo sends multipart; `skills` then arrives
    as one JSON string inside a one-item list. It used to be stored as a
    single mangled skill, which zeroed the worker's AI skill match."""

    def test_skills_survive_a_multipart_save_with_a_photo(self):
        from rest_framework.test import APIClient

        worker = User.objects.create_user(username="multipart-worker", password="pass-12345")
        UserProfile.objects.create(
            user=worker, role=UserProfile.ROLE_WORKER, daily_rate="600.00",
            location_label="Isabang, Tayabas", latitude="13.9622745", longitude="121.5632841",
        )
        client = APIClient()
        client.force_authenticate(user=worker)

        response = client.patch(
            reverse("profile-me"),
            {
                "skills": '["House Cleaning", "Laundry"]',
                "profile_photo": SimpleUploadedFile("me.png", PNG_BYTES, content_type="image/png"),
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 200, response.data)
        worker.profile.refresh_from_db()
        self.assertEqual(worker.profile.skills, ["House Cleaning", "Laundry"])
        self.assertTrue(worker.profile.profile_photo)


class SkillListSyncTests(TestCase):
    """UserProfile.skills (what matching reads) and the portfolio's WorkerSkill
    rows are one list: changing either keeps the other in step, and no rating
    history is ever deleted to do it."""

    def setUp(self):
        from rest_framework.test import APIClient

        self.worker = User.objects.create_user(username="sync-worker", password="pass-12345")
        UserProfile.objects.create(
            user=self.worker, role=UserProfile.ROLE_WORKER, daily_rate="600.00",
            location_label="Isabang, Tayabas", latitude="13.9622745", longitude="121.5632841",
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.worker)

    def listed(self):
        response = self.client.get(reverse("worker-portfolio"))
        self.assertEqual(response.status_code, 200)
        return [(skill["skill_name"], skill["proficiency"]) for skill in response.data["skills"]]

    def profile_skills(self):
        self.worker.profile.refresh_from_db()
        return self.worker.profile.skills

    def test_saving_profile_skills_creates_portfolio_entries_without_a_proficiency(self):
        response = self.client.patch(reverse("profile-me"), {"skills": ["Laundry", "Cooking"]}, format="json")

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(sorted(self.listed()), [("Cooking", ""), ("Laundry", "")])

    def test_adding_a_portfolio_skill_adds_it_to_the_matching_list(self):
        response = self.client.post(
            reverse("worker-skill"), {"skill_name": "Laundry", "proficiency": "expert"}, format="json"
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(self.profile_skills(), ["Laundry"])
        self.assertEqual(self.listed(), [("Laundry", "expert")])

    def test_the_three_skill_cap_counts_the_profile_list(self):
        saved = self.client.patch(
            reverse("profile-me"), {"skills": ["Laundry", "Cooking", "Gardening"]}, format="json"
        )
        self.assertEqual(saved.status_code, 200, saved.data)

        response = self.client.post(
            reverse("worker-skill"), {"skill_name": "Plumbing", "proficiency": "expert"}, format="json"
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(self.profile_skills(), ["Laundry", "Cooking", "Gardening"])

    def test_removing_a_portfolio_skill_removes_it_from_matching(self):
        self.client.post(reverse("worker-skill"), {"skill_name": "Cooking", "proficiency": "beginner"}, format="json")
        created = self.client.post(
            reverse("worker-skill"), {"skill_name": "Laundry", "proficiency": "expert"}, format="json"
        )

        response = self.client.delete(reverse("worker-skill-detail", args=[created.data["id"]]))

        self.assertEqual(response.status_code, 204)
        self.assertEqual(self.profile_skills(), ["Cooking"])
        self.assertFalse(WorkerSkill.objects.filter(worker=self.worker, skill_name="Laundry").exists())

    def test_the_last_skill_cannot_be_removed(self):
        created = self.client.post(
            reverse("worker-skill"), {"skill_name": "Laundry", "proficiency": "expert"}, format="json"
        )

        response = self.client.delete(reverse("worker-skill-detail", args=[created.data["id"]]))

        self.assertEqual(response.status_code, 400)
        self.assertEqual(self.profile_skills(), ["Laundry"])

    def test_a_rated_skill_is_unlisted_not_deleted_and_comes_back_with_its_rating(self):
        household = User.objects.create_user(username="sync-home", password="pass-12345")
        UserProfile.objects.create(user=household, role=UserProfile.ROLE_HOUSEHOLD)
        job = JobPosting.objects.create(
            household=household, title="Laundry", job_type="Laundry", required_skill="Laundry",
            schedule="2026-06-01 09:00", location_label="Isabang, Tayabas", latitude="13.9622745",
            longitude="121.5632841", service_rate="500.00", status=JobPosting.STATUS_COMPLETED,
        )
        created = self.client.post(
            reverse("worker-skill"), {"skill_name": "Laundry", "proficiency": "expert"}, format="json"
        )
        skill = WorkerSkill.objects.get(pk=created.data["id"])
        SkillRating.objects.create(job=job, household=household, worker=self.worker, skill=skill, rating="4.5")
        skill.rating_count = 1
        skill.average_rating = Decimal("4.5")
        skill.save()

        saved = self.client.patch(reverse("profile-me"), {"skills": ["Cooking"]}, format="json")

        self.assertEqual(saved.status_code, 200, saved.data)
        self.assertEqual(self.listed(), [("Cooking", "")])
        self.assertTrue(SkillRating.objects.filter(skill=skill).exists())

        relisted = self.client.post(
            reverse("worker-skill"), {"skill_name": "laundry", "proficiency": "intermediate"}, format="json"
        )

        self.assertEqual(relisted.status_code, 201, relisted.data)
        self.assertEqual(relisted.data["id"], skill.id)
        self.assertEqual(relisted.data["rating_count"], 1)
        self.assertEqual(self.profile_skills(), ["Cooking", "Laundry"])

    def test_renaming_a_portfolio_skill_renames_it_for_matching(self):
        created = self.client.post(
            reverse("worker-skill"), {"skill_name": "Laundry", "proficiency": "expert"}, format="json"
        )

        response = self.client.patch(
            reverse("worker-skill-detail", args=[created.data["id"]]), {"skill_name": "Ironing"}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self.profile_skills(), ["Ironing"])
