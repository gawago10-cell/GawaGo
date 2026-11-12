"""Regression tests for the worker My Profile audit (2026-11-12): phone
format, completed jobs, and the session after a password or email change."""

from datetime import datetime, timedelta
from unittest.mock import patch

from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from apps.accounts.models import UserProfile
from apps.common.authentication import create_jwt_token
from apps.common.test_flow_fixes import make_job, make_user
from apps.jobs.models import JobApplication, JobPosting


def bearer(token):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
    return client


class _FiveSecondsAgo(datetime):
    @classmethod
    def now(cls, tz=None):
        return datetime.now(tz) - timedelta(seconds=5)


def login_token(user, earlier=False):
    """A sign-in token; ``earlier`` issues it a few seconds back, so a change
    stamped "now" is reliably after it (stamps are whole seconds)."""
    claims = {"user_id": user.id, "username": user.username, "role": "worker"}
    if not earlier:
        return create_jwt_token(claims)
    with patch("apps.common.authentication.datetime", _FiveSecondsAgo):
        return create_jwt_token(claims)


class ProfilePhoneTests(TestCase):
    def setUp(self):
        self.worker = make_user("audit-phone", UserProfile.ROLE_WORKER, skills=["Cooking"])
        self.client = bearer(login_token(self.worker))

    def patch_phone(self, phone):
        return self.client.patch(reverse("profile-me"), {"phone": phone}, format="json")

    def test_common_ways_of_writing_a_number_are_stored_like_sign_up(self):
        for typed in ["09123456789", "+63 912 345 6789", "0912-345-6789", "9123456789"]:
            response = self.patch_phone(typed)
            self.assertEqual(response.status_code, 200, (typed, response.data))
            self.worker.profile.refresh_from_db()
            self.assertEqual(self.worker.profile.phone, "9123456789", typed)

    def test_anything_else_is_refused(self):
        for typed in ["abc-not-a-phone", "0812345678", "12345"]:
            response = self.patch_phone(typed)
            self.assertEqual(response.status_code, 400, typed)
            self.assertIn("phone", response.data)


class CompletedJobsTests(TestCase):
    def test_jobs_done_counts_completed_jobs_rated_or_not(self):
        household = make_user("audit-home", UserProfile.ROLE_HOUSEHOLD)
        worker = make_user("audit-worker", UserProfile.ROLE_WORKER, skills=["Cooking"])
        for _ in range(2):
            job = make_job(household, status=JobPosting.STATUS_COMPLETED)
            JobApplication.objects.create(job=job, worker=worker, status=JobApplication.STATUS_COMPLETED)
        pending = make_job(household)
        JobApplication.objects.create(job=pending, worker=worker, status=JobApplication.STATUS_PENDING)

        response = bearer(login_token(worker)).get(reverse("profile-me"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["profile"]["completed_jobs"], 2)


class CredentialChangeSessionTests(TestCase):
    def setUp(self):
        self.worker = make_user("audit-session", UserProfile.ROLE_WORKER, skills=["Cooking"])
        self.this_device = login_token(self.worker, earlier=True)
        self.other_device = login_token(self.worker, earlier=True)

    def assert_signed_in(self, token, expected=True):
        status = bearer(token).get(reverse("profile-me")).status_code
        self.assertEqual(status == 200, expected, status)

    def test_changing_the_password_signs_out_other_devices_but_not_this_one(self):
        response = bearer(self.this_device).post(
            reverse("change-password"),
            {"current_password": "pass-12345", "new_password": "Fresh-pass-678"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assert_signed_in(response.data["access"])
        self.assert_signed_in(self.other_device, expected=False)

    def test_changing_the_email_keeps_this_device_signed_in(self):
        response = bearer(self.this_device).patch(
            reverse("profile-me"),
            {"email": "moved@example.com", "current_password": "pass-12345"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assert_signed_in(response.data["access"])
        self.assert_signed_in(self.other_device, expected=False)

    def test_other_profile_edits_leave_sessions_alone(self):
        response = bearer(self.this_device).patch(reverse("profile-me"), {"bio": "Masipag."}, format="json")

        self.assertEqual(response.status_code, 200, response.data)
        self.assertNotIn("access", response.data)
        self.assert_signed_in(self.other_device)
