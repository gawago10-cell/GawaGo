from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth.models import User
from django.core import mail
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import (
    PasswordResetRequest,
    UserProfile,
    WorkerAvailability,
)
from apps.common.authentication import create_jwt_token
from apps.notifications.models import Notification


class RegisterLoginFlowTests(TestCase):
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

        self.assertEqual(response.status_code, 403)

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

        self.assertEqual(response.status_code, 403)

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

    def test_staff_profile_list_includes_private_contact_fields(self):
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': self.admin.id})}"

        response = self.client.get(reverse("profile-list"))

        self.assertEqual(response.status_code, 200)
        first_profile = response.json()["results"][0]
        self.assertIn("email", first_profile)
        self.assertIn("phone", first_profile)
        self.assertIn("latitude", first_profile)
        self.assertIn("longitude", first_profile)
