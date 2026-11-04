"""A permanently blocked person can't come back under a new account
(AGENTS.md II.D, 2026-11-05): their email and phone can't sign up, their
government ID number is rejected at verification, and a new account with
their full name is flagged for the superadmin."""

import base64
import tempfile
from datetime import timedelta

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone

from apps.accounts.banned import (
    EMAIL_BLOCKED_MESSAGE,
    ID_BLOCKED_MESSAGE,
    PHONE_BLOCKED_MESSAGE,
    normalize_id_number,
    normalize_name,
    normalize_phone,
)
from apps.accounts.models import BannedCredential, UserProfile
from apps.accounts.services import apply_account_suspension
from apps.common.models import VerificationRequest
from apps.common.test_flow_fixes import client_for, make_job, make_user
from apps.complaints.models import Complaint
from apps.notifications.models import Notification

REAL_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)
TEMP_PRIVATE = tempfile.mkdtemp()


def verification_payload(id_number="N01-23-456789"):
    return {
        "primary_id_type": "drivers_license",
        "primary_id_number": id_number,
        "secondary_doc_name": "clearance.png",
        "primary_id_file": SimpleUploadedFile("id.png", REAL_PNG, content_type="image/png"),
        "secondary_doc_file": SimpleUploadedFile("clearance.png", REAL_PNG, content_type="image/png"),
    }


def register_payload(**overrides):
    payload = {
        "username": "comeback",
        "email": "fresh@example.com",
        "password": "comeback-pass-123",
        "first_name": "Fresh",
        "last_name": "Person",
        "role": UserProfile.ROLE_HOUSEHOLD,
        "phone": "09170000000",
        "location_label": "Isabang, Tayabas City",
        "latitude": "13.9622745",
        "longitude": "121.5632841",
    }
    payload.update(overrides)
    return payload


class NormalizerTests(TestCase):
    def test_phone_forms_of_one_number_match(self):
        for value in ["0917 555 0106", "+63 917 555 0106", "639175550106", "917-555-0106"]:
            with self.subTest(value=value):
                self.assertEqual(normalize_phone(value), "09175550106")
        self.assertEqual(normalize_phone("123"), "")

    def test_id_numbers_ignore_case_and_separators(self):
        self.assertEqual(normalize_id_number("n01-23 456789"), "N0123456789")

    def test_names_ignore_case_punctuation_and_spacing(self):
        self.assertEqual(normalize_name("  Juan   Dela-Paz "), normalize_name("juan dela paz"))


@override_settings(PRIVATE_MEDIA_ROOT=TEMP_PRIVATE)
class BannedCredentialTests(TestCase):
    def setUp(self):
        cache.clear()
        self.superadmin = make_user("ban-super", superuser=True)
        self.banned = make_user(
            "Worker6", UserProfile.ROLE_WORKER, phone="0917 555 0106", skills=["House Cleaning"]
        )
        self.banned.email = "w6.sample@gmail.com"
        self.banned.first_name = "Juan"
        self.banned.last_name = "Dela Paz"
        self.banned.save(update_fields=["email", "first_name", "last_name"])
        VerificationRequest.objects.create(
            worker=self.banned,
            primary_id_type="drivers_license",
            primary_id_name="Driver's License",
            primary_id_number="N01-23-456789",
            secondary_doc_name="clearance.png",
            status=VerificationRequest.STATUS_APPROVED,
        )

    def ban(self, **kwargs):
        kwargs.setdefault("reason", "Repeated no-shows.")
        apply_account_suspension(self.banned.profile, blocked=True, **kwargs)

    def test_a_permanent_block_records_email_phone_id_number_and_name(self):
        self.ban()

        rows = set(BannedCredential.objects.filter(user=self.banned).values_list("kind", "value"))
        self.assertEqual(
            rows,
            {
                ("email", "w6.sample@gmail.com"),
                ("phone", "09175550106"),
                ("id_number", "N0123456789"),
                ("name", "juan dela paz"),
            },
        )

    def test_a_timed_suspension_records_nothing_and_a_restore_clears_the_ban(self):
        self.ban(duration_days=3)
        self.assertFalse(BannedCredential.objects.exists())

        apply_account_suspension(self.banned.profile, blocked=False)
        self.ban()
        self.assertTrue(BannedCredential.objects.filter(user=self.banned).exists())

        apply_account_suspension(self.banned.profile, blocked=False)
        self.assertFalse(BannedCredential.objects.exists())

    def test_the_block_endpoint_records_the_ban(self):
        response = client_for(self.superadmin).post(
            reverse("profile-block-admin", args=[self.banned.username]),
            {"blocked": True, "reason": "Fraud."},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(BannedCredential.objects.filter(user=self.banned).count(), 4)

    def test_signup_with_a_banned_email_is_refused_without_saying_banned(self):
        self.ban()

        response = self.client.post(
            reverse("register"), register_payload(email="W6.Sample@gmail.com"), content_type="application/json"
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["detail"], EMAIL_BLOCKED_MESSAGE)
        self.assertNotIn("ban", response.json()["detail"].lower())
        self.assertFalse(UserProfile.objects.filter(user__username="comeback").exists())

    def test_signup_with_a_banned_phone_in_another_format_is_refused(self):
        self.ban()

        response = self.client.post(
            reverse("register"), register_payload(phone="+63 917 555 0106"), content_type="application/json"
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["detail"], PHONE_BLOCKED_MESSAGE)

    def test_signup_with_clean_credentials_still_works(self):
        self.ban()

        response = self.client.post(reverse("register"), register_payload(), content_type="application/json")

        self.assertEqual(response.status_code, 201, response.content)

    def test_a_banned_phone_cannot_be_moved_onto_another_account(self):
        self.ban()
        other = make_user("other-house", UserProfile.ROLE_HOUSEHOLD)

        response = client_for(other).patch(reverse("profile-me"), {"phone": "09175550106"}, format="json")

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["phone"][0], PHONE_BLOCKED_MESSAGE)

    def test_a_verification_with_a_banned_id_number_is_rejected_on_arrival(self):
        self.ban()
        newcomer = make_user("jpaz_new", UserProfile.ROLE_WORKER, verification_status="pending", skills=["Cooking"])

        response = client_for(newcomer).post(
            reverse("verification-request-list-create"), verification_payload("n01 23 456789"), format="multipart"
        )

        self.assertEqual(response.status_code, 201, response.data)
        request_data = response.data["verification_request"]
        self.assertEqual(request_data["status"], VerificationRequest.STATUS_REJECTED)
        self.assertEqual(request_data["review_note"], ID_BLOCKED_MESSAGE)
        # The applicant's own copy never names the banned account.
        self.assertIsNone(request_data["ban_check"])
        newcomer.profile.refresh_from_db()
        self.assertEqual(newcomer.profile.verification_status, "rejected")
        record = VerificationRequest.objects.get(worker=newcomer)
        self.assertEqual(record.banned_match_username, "Worker6")
        self.assertTrue(
            Notification.objects.filter(recipient=self.superadmin, title="Verification rejected automatically").exists()
        )
        self.assertTrue(
            Notification.objects.filter(recipient=newcomer, title="Verification rejected", message=ID_BLOCKED_MESSAGE).exists()
        )

        admin_view = client_for(self.superadmin).get(reverse("verification-request-list-create"))
        row = next(item for item in admin_view.data["results"] if item["worker_username"] == "jpaz_new")
        self.assertEqual(row["ban_check"]["id_number_match"], "Worker6")

    def test_a_clean_id_number_waits_for_review(self):
        self.ban()
        newcomer = make_user("clean-new", UserProfile.ROLE_WORKER, verification_status="pending", skills=["Cooking"])

        response = client_for(newcomer).post(
            reverse("verification-request-list-create"), verification_payload("ZZ-998877"), format="multipart"
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["verification_request"]["status"], VerificationRequest.STATUS_PENDING)

    def test_the_id_number_is_required(self):
        newcomer = make_user("no-number", UserProfile.ROLE_WORKER, verification_status="pending", skills=["Cooking"])
        payload = verification_payload()
        payload.pop("primary_id_number")

        response = client_for(newcomer).post(reverse("verification-request-list-create"), payload, format="multipart")

        self.assertEqual(response.status_code, 400)
        self.assertIn("primary_id_number", response.data)

    def test_a_banned_accounts_full_name_is_flagged_for_admins(self):
        self.ban()
        namesake = make_user("juandp2", UserProfile.ROLE_WORKER, verification_status="pending", skills=["Cooking"])
        namesake.first_name = "JUAN"
        namesake.last_name = "Dela-Paz"
        namesake.save(update_fields=["first_name", "last_name"])

        client_for(namesake).post(
            reverse("verification-request-list-create"), verification_payload("QQ-112233"), format="multipart"
        )

        admin_view = client_for(self.superadmin).get(reverse("verification-request-list-create"))
        row = next(item for item in admin_view.data["results"] if item["worker_username"] == "juandp2")
        self.assertEqual(row["status"], VerificationRequest.STATUS_PENDING)
        self.assertEqual(row["ban_check"], {"id_number_match": "", "name_match": "Worker6"})

    def test_the_complaint_review_shows_the_respondents_id_number(self):
        household = make_user("filer", UserProfile.ROLE_HOUSEHOLD)
        complaint = Complaint.objects.create(
            complainant=household, respondent=self.banned, complaint_type=Complaint.TYPE_NO_SHOW, description="No show."
        )

        response = client_for(self.superadmin).get(reverse("complaint-list-admin"))

        self.assertEqual(response.status_code, 200, response.data)
        row = next(item for item in response.data["results"] if item["id"] == complaint.id)
        self.assertEqual(row["respondent_detail"]["id_number"], "N01-23-456789")
        self.assertEqual(row["respondent_detail"]["id_type_label"], "Driver's License")


class ComplaintHeatMapTests(TestCase):
    def setUp(self):
        self.superadmin = make_user("heat-super", superuser=True)
        self.admin = make_user("heat-admin", staff=True)
        household = make_user("heat-house", UserProfile.ROLE_HOUSEHOLD)
        worker = make_user("heat-worker", UserProfile.ROLE_WORKER)
        job = make_job(household, location_label="Anos, Tayabas City", job_start_date=timezone.localdate() + timedelta(days=1))
        Complaint.objects.create(
            complainant=household, respondent=worker, job=job, complaint_type=Complaint.TYPE_NO_SHOW, description="x"
        )

    def heat_map(self, user):
        response = client_for(user).get(reverse("dashboard-metrics"))
        self.assertEqual(response.status_code, 200)
        return {row["barangay"]: row for row in response.data["analytics"]["heatMapData"]}

    def test_superadmins_see_complaints_per_barangay(self):
        rows = self.heat_map(self.superadmin)

        self.assertEqual(rows["Anos"]["complaints"], 1)
        self.assertEqual(rows["Isabang"]["complaints"], 0)
        self.assertNotIn("pendingVerifications", rows["Anos"])

    def test_other_admins_get_no_complaint_counts(self):
        rows = self.heat_map(self.admin)

        self.assertNotIn("complaints", rows["Anos"])
