"""Full end-to-end audit (2026-11-16): the server-side fixes."""

import importlib
from datetime import timedelta

from django.apps import apps as django_apps
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import UserProfile, WorkerCertification
from apps.accounts.services import apply_account_suspension
from apps.common.models import AdminActionLog, VerificationRequest
from apps.common.support import readable_datetime, support_sentence
from apps.common.test_flow_fixes import client_for, make_user
from apps.common.tests import REAL_PNG


def login(username, password="pass-12345"):
    return APIClient().post(reverse("login"), {"username": username, "password": password}, format="json")


def bearer(token):
    client = APIClient()
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
    return client


class HouseholdAddressTests(TestCase):
    def setUp(self):
        self.household = make_user("fa-home", UserProfile.ROLE_HOUSEHOLD, location_label="Isabang, 5 Rizal St")
        self.worker = make_user("fa-worker", UserProfile.ROLE_WORKER, location_label="Isabang, 12 Mabini St")

    def labels_for(self, viewer):
        rows = client_for(viewer).get(reverse("profile-list")).data["results"]
        return {row["username"]: row["location_label"] for row in rows}

    def test_other_members_get_only_the_households_barangay(self):
        labels = self.labels_for(self.worker)

        self.assertEqual(labels["fa-home"], "Isabang")

    def test_the_household_still_sees_its_own_street(self):
        self.assertEqual(self.labels_for(self.household)["fa-home"], "Isabang, 5 Rizal St")

    def test_staff_see_the_full_address(self):
        admin = make_user("fa-admin", staff=True)

        self.assertEqual(self.labels_for(admin)["fa-home"], "Isabang, 5 Rizal St")


class AdminSessionTests(TestCase):
    def setUp(self):
        self.admin = make_user("fa-staff", staff=True)

    def test_a_password_change_ends_an_admins_other_sessions(self):
        old_token = login("fa-staff").data["access"]
        self.assertEqual(bearer(old_token).get(reverse("verification-request-list-create")).status_code, 200)

        changed = bearer(old_token).post(
            reverse("change-password"), {"current_password": "pass-12345", "new_password": "Fresh#Pass2026"}, format="json"
        )

        self.assertEqual(changed.status_code, 200, changed.data)
        self.assertEqual(bearer(old_token).get(reverse("verification-request-list-create")).status_code, 401)
        self.assertEqual(
            bearer(changed.data["access"]).get(reverse("verification-request-list-create")).status_code, 200
        )

    def test_login_records_the_sign_in(self):
        self.assertIsNone(self.admin.last_login)

        self.assertEqual(login("fa-staff").status_code, 200)

        self.admin.refresh_from_db()
        self.assertIsNotNone(self.admin.last_login)

    def test_a_deactivated_admin_is_told_so_with_the_right_password_only(self):
        self.admin.is_active = False
        self.admin.save(update_fields=["is_active"])

        right = login("fa-staff")
        wrong = login("fa-staff", "not-the-password")

        self.assertEqual(right.status_code, 403)
        self.assertIn("deactivated", right.data["detail"])
        self.assertEqual(wrong.status_code, 400)
        self.assertEqual(wrong.data["detail"], "Invalid username or password.")


class ReviewerTests(TestCase):
    def setUp(self):
        self.admin = make_user("fa-reviewer", staff=True)
        self.admin.first_name, self.admin.last_name = "Rosa", "Admin"
        self.admin.save()
        self.worker = make_user("fa-applicant", UserProfile.ROLE_WORKER, verification_status="pending")
        self.request = VerificationRequest.objects.create(
            worker=self.worker, primary_id_name="National ID", secondary_doc_name="clearance.png"
        )

    def test_the_reviewer_is_kept_and_shown_to_admins_only(self):
        response = client_for(self.admin).post(
            reverse("verification-request-review", args=[self.request.pk]), {"action": "approve"}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.request.refresh_from_db()
        self.assertEqual(self.request.reviewed_by_name, "Rosa Admin")
        admin_rows = client_for(self.admin).get(reverse("verification-request-list-create")).data
        admin_rows = admin_rows.get("results", admin_rows)
        self.assertEqual(admin_rows[0]["reviewed_by"], "Rosa Admin")
        own_rows = client_for(self.worker).get(reverse("verification-request-list-create")).data
        own_rows = own_rows.get("results", own_rows)
        self.assertIsNone(own_rows[0]["reviewed_by"])

    def test_the_migration_takes_old_reviewers_from_the_audit_log(self):
        self.request.status = VerificationRequest.STATUS_APPROVED
        self.request.save(update_fields=["status"])
        AdminActionLog.objects.create(
            actor=self.admin, actor_username="fa-reviewer", action=AdminActionLog.ACTION_VERIFICATION_APPROVED,
            target_type="verification_request", target_id=self.request.pk,
        )
        migration = importlib.import_module("apps.common.migrations.0010_verificationrequest_reviewed_by_name")

        migration.backfill_reviewers(django_apps, None)

        self.request.refresh_from_db()
        self.assertEqual(self.request.reviewed_by_name, "Rosa Admin")


class SignupFieldErrorTests(TestCase):
    def test_a_taken_username_is_named_on_its_field(self):
        make_user("fa-taken", UserProfile.ROLE_HOUSEHOLD)

        response = APIClient().post(
            reverse("register"),
            {
                "username": "FA-TAKEN", "email": "someone-new@example.com", "password": "Signup#2026",
                "role": "household", "location_label": "Isabang, Tayabas City",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["username"], ["That username is already taken."])


class BlockMessageTests(TestCase):
    def setUp(self):
        self.worker = make_user("fa-blocked", UserProfile.ROLE_WORKER)
        self.profile = self.worker.profile

    def test_a_suspension_names_a_readable_date_and_no_missing_support_desk(self):
        apply_account_suspension(self.profile, blocked=True, reason="No-shows", duration_days=3)

        detail = login("fa-blocked").data["detail"]

        self.assertIn(f"suspended until {readable_datetime(self.profile.blocked_until)}.", detail)
        self.assertIn("Reason: No-shows.", detail)
        self.assertNotIn("support", detail.lower())

    @override_settings(SUPPORT_EMAIL="help@gawago.example")
    def test_a_configured_support_address_is_named(self):
        apply_account_suspension(self.profile, blocked=True, reason="Fake documents")

        self.assertTrue(login("fa-blocked").data["detail"].endswith("If you think this is a mistake, email help@gawago.example."))
        self.assertEqual(support_sentence(), " If you think this is a mistake, email help@gawago.example.")


class CertificateDecisionTests(TestCase):
    def setUp(self):
        self.admin = make_user("fa-cert-admin", staff=True)
        self.worker = make_user("fa-cert-worker", UserProfile.ROLE_WORKER)

    def certificate(self, status):
        return WorkerCertification.objects.create(
            worker=self.worker, certificate_name="Housekeeping NC II", verification_status=status
        )

    def decide(self, cert, status, notes=""):
        return client_for(self.admin).patch(
            reverse("certificate-admin-verify", args=[cert.id]),
            {"verification_status": status, "verification_notes": notes},
            format="json",
        )

    def test_the_same_decision_twice_is_refused(self):
        response = self.decide(self.certificate(WorkerCertification.STATUS_APPROVED), "approved")

        self.assertEqual(response.status_code, 409)

    def test_a_rejected_certificate_waits_for_a_new_copy(self):
        response = self.decide(self.certificate(WorkerCertification.STATUS_REJECTED), "approved")

        self.assertEqual(response.status_code, 409)

    def test_an_approval_can_be_withdrawn(self):
        cert = self.certificate(WorkerCertification.STATUS_APPROVED)

        response = self.decide(cert, "rejected", "TESDA has no record of it.")

        self.assertEqual(response.status_code, 200, response.data)
        cert.refresh_from_db()
        self.assertEqual(cert.verification_status, WorkerCertification.STATUS_REJECTED)
        self.assertFalse(cert.is_verified)


class CertificateDateTests(TestCase):
    def setUp(self):
        self.client = client_for(make_user("fa-dates", UserProfile.ROLE_WORKER))

    def send(self, **dates):
        payload = {
            "certificate_type": "tesda",
            "certificate_name": "Housekeeping NC II",
            "certificate_file": SimpleUploadedFile("cert.png", REAL_PNG, content_type="image/png"),
            **dates,
        }
        return self.client.post(reverse("worker-certification"), payload, format="multipart")

    def test_an_issue_date_in_the_future_is_refused(self):
        tomorrow = timezone.localdate() + timedelta(days=1)

        response = self.send(issue_date=tomorrow.isoformat())

        self.assertEqual(response.status_code, 400)
        self.assertIn("issue_date", response.data)

    def test_an_expiry_before_the_issue_date_is_refused(self):
        response = self.send(issue_date="2025-05-01", expiry_date="2025-04-01")

        self.assertEqual(response.status_code, 400)
        self.assertIn("expiry_date", response.data)

    def test_sensible_dates_are_kept(self):
        response = self.send(issue_date="2025-05-01", expiry_date="2028-05-01")

        self.assertEqual(response.status_code, 201, response.data)
