import tempfile
from datetime import timedelta
from decimal import Decimal
from unittest.mock import patch

from django.contrib.auth.models import User
from django.core import mail
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import (
    PasswordResetRequest,
    SkillRating,
    UserProfile,
    VerificationDocument,
    WorkerAvailability,
    WorkerCertification,
    WorkerSkill,
)
from apps.common.authentication import create_jwt_token
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

    def test_login_activates_existing_inactive_account_with_valid_password(self):
        user = User.objects.create_user(
            username="LegacyInactive",
            email="legacy.inactive@gmail.com",
            password="legacy-pass123",
            is_active=False,
        )
        UserProfile.objects.create(user=user, role=UserProfile.ROLE_HOUSEHOLD)

        response = self.client.post(
            reverse("login"),
            {"username": "LegacyInactive", "password": "legacy-pass123"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200)
        user.refresh_from_db()
        self.assertTrue(user.is_active)

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
class VerificationDocumentUploadTests(TestCase):
    """Uploads go to a temp MEDIA_ROOT so test runs don't litter media/."""

    def setUp(self):
        self.worker = User.objects.create_user(username="id-worker", password="worker-pass123")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.other = User.objects.create_user(username="id-other", password="other-pass123")
        UserProfile.objects.create(user=self.other, role=UserProfile.ROLE_WORKER)

    def authenticate(self, user):
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': user.id})}"

    def _upload(self):
        return SimpleUploadedFile("national-id.png", b"fake-image-bytes", content_type="image/png")

    def test_worker_can_upload_a_verification_document(self):
        self.authenticate(self.worker)

        response = self.client.post(
            reverse("verification-documents"),
            {
                "id_type": VerificationDocument.ID_TYPE_NATIONAL,
                "id_number": "1234-5678-9012",
                "document_file": self._upload(),
                "is_primary": True,
            },
        )

        self.assertEqual(response.status_code, 201)
        document = VerificationDocument.objects.get()
        # The serializer marks `user` read-only, so the view must pass it to
        # save() -- otherwise the non-nullable FK raises IntegrityError (500).
        self.assertEqual(document.user, self.worker)
        self.assertEqual(document.verification_status, VerificationDocument.STATUS_PENDING)

    def test_upload_cannot_be_attributed_to_another_user(self):
        self.authenticate(self.worker)

        response = self.client.post(
            reverse("verification-documents"),
            {
                "id_type": VerificationDocument.ID_TYPE_PASSPORT,
                "user": self.other.id,
                "document_file": self._upload(),
            },
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(VerificationDocument.objects.get().user, self.worker)

    def test_worker_only_sees_their_own_documents(self):
        VerificationDocument.objects.create(
            user=self.other,
            id_type=VerificationDocument.ID_TYPE_VOTER,
            document_file="verification_documents/other.png",
        )
        self.authenticate(self.worker)

        response = self.client.get(reverse("verification-documents"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), [])

    def test_worker_can_get_a_single_document_by_id(self):
        # GET on the detail URL used to crash: get(self, request) took no
        # doc_id, but the detail route still dispatches GET there.
        document = VerificationDocument.objects.create(
            user=self.worker,
            id_type=VerificationDocument.ID_TYPE_TIN,
            document_file="verification_documents/mine.png",
        )
        self.authenticate(self.worker)

        response = self.client.get(reverse("verification-document-detail", kwargs={"doc_id": document.id}))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["id_type"], VerificationDocument.ID_TYPE_TIN)

    def test_worker_cannot_get_another_users_document_by_id(self):
        document = VerificationDocument.objects.create(
            user=self.other,
            id_type=VerificationDocument.ID_TYPE_VOTER,
            document_file="verification_documents/other.png",
        )
        self.authenticate(self.worker)

        response = self.client.get(reverse("verification-document-detail", kwargs={"doc_id": document.id}))

        self.assertEqual(response.status_code, 404)


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
            certificate_file=SimpleUploadedFile("tesda.png", b"bytes", content_type="image/png"),
        )

    def authenticate(self, user):
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': user.id})}"

    def test_admin_sees_pending_certificates_with_the_owning_worker(self):
        self.authenticate(self.admin)

        response = self.client.get(reverse("certificate-admin-list"), {"status": "pending"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        # The queue lists certificates across all workers, so it has to say
        # whose each one is.
        self.assertEqual(response.data[0]["worker_username"], "cert-worker")

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
        self.assertEqual(len(response.data), 2)

    def test_certificate_payload_includes_worker_context_for_the_review_card(self):
        self.worker.first_name = "Cert"
        self.worker.last_name = "Worker"
        self.worker.save(update_fields=["first_name", "last_name"])
        self.worker.profile.location_label = "Isabang, Tayabas City"
        self.worker.profile.save(update_fields=["location_label"])
        self.authenticate(self.admin)

        response = self.client.get(reverse("certificate-admin-list"), {"status": "pending"})

        self.assertEqual(response.status_code, 200)
        record = response.data[0]
        self.assertEqual(record["worker_name"], "Cert Worker")
        self.assertEqual(record["worker_location_label"], "Isabang, Tayabas City")
        self.assertIsNotNone(record["worker_member_since"])
        self.assertEqual(record["certificate_type_label"], "Professional Certification")


@override_settings(MEDIA_ROOT=tempfile.mkdtemp())
class VerificationDocumentAdminTests(TestCase):
    """The admin approval workflow for the multi-ID-type documents (roadmap
    #12). Mirrors CertificateVerificationAdminTests above."""

    def setUp(self):
        self.worker = User.objects.create_user(username="doc-worker", password="worker-pass123")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.admin = User.objects.create_user(username="doc-admin", password="admin-pass123", is_staff=True)
        self.document = VerificationDocument.objects.create(
            user=self.worker,
            id_type=VerificationDocument.ID_TYPE_UMID,
            document_file=SimpleUploadedFile("umid.png", b"bytes", content_type="image/png"),
        )

    def authenticate(self, user):
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': user.id})}"

    def test_admin_sees_pending_documents_with_the_owning_user(self):
        self.authenticate(self.admin)

        response = self.client.get(reverse("verification-documents-admin"), {"status": "pending"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["user_username"], "doc-worker")

    def test_admin_can_get_a_single_document_by_id(self):
        # GET on the detail URL used to crash: get(self, request) took no
        # doc_id, but the detail route still dispatches GET there.
        self.authenticate(self.admin)

        response = self.client.get(reverse("verification-documents-admin-verify", kwargs={"doc_id": self.document.id}))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["user_username"], "doc-worker")

    def test_admin_get_for_a_missing_document_id_returns_404_not_500(self):
        self.authenticate(self.admin)

        response = self.client.get(reverse("verification-documents-admin-verify", kwargs={"doc_id": 999999}))

        self.assertEqual(response.status_code, 404)

    def test_worker_cannot_reach_the_admin_document_queue(self):
        self.authenticate(self.worker)

        response = self.client.get(reverse("verification-documents-admin"))

        self.assertEqual(response.status_code, 403)

    def test_admin_approval_marks_the_document_verified_and_notifies_the_worker(self):
        self.authenticate(self.admin)

        response = self.client.patch(
            reverse("verification-documents-admin-verify", kwargs={"doc_id": self.document.id}),
            {"verification_status": "approved", "verification_notes": "Checked."},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200)
        self.document.refresh_from_db()
        self.assertEqual(self.document.verification_status, "approved")
        self.assertEqual(self.document.verified_by, self.admin)
        self.assertTrue(
            Notification.objects.filter(recipient=self.worker, notification_type=Notification.TYPE_VERIFICATION).exists()
        )

    def test_status_all_returns_documents_regardless_of_status(self):
        self.document.verification_status = VerificationDocument.STATUS_APPROVED
        self.document.save(update_fields=["verification_status"])
        VerificationDocument.objects.create(
            user=self.worker,
            id_type=VerificationDocument.ID_TYPE_TIN,
            verification_status=VerificationDocument.STATUS_REJECTED,
        )
        self.authenticate(self.admin)

        response = self.client.get(reverse("verification-documents-admin"), {"status": "all"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 2)

    def test_document_payload_includes_user_context_for_the_review_card(self):
        self.worker.first_name = "Doc"
        self.worker.last_name = "Worker"
        self.worker.save(update_fields=["first_name", "last_name"])
        self.worker.profile.location_label = "Isabang, Tayabas City"
        self.worker.profile.save(update_fields=["location_label"])
        self.authenticate(self.admin)

        response = self.client.get(reverse("verification-documents-admin"), {"status": "pending"})

        self.assertEqual(response.status_code, 200)
        record = response.data[0]
        self.assertEqual(record["user_name"], "Doc Worker")
        self.assertEqual(record["user_location_label"], "Isabang, Tayabas City")
        self.assertIsNotNone(record["user_member_since"])


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
