import base64
import tempfile
from datetime import timedelta
from decimal import Decimal

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.contrib.auth import get_user_model
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.common.authentication import create_jwt_token
from apps.complaints.models import Complaint, ComplaintEvidence
from apps.jobs.models import JobApplication, JobPosting

User = get_user_model()


def authenticate(client, user):
    client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': user.id})}"


class ComplaintModelTest(TestCase):
    def setUp(self):
        self.complainant = User.objects.create_user(username="worker", password="testpass")
        self.respondent = User.objects.create_user(username="household", password="testpass")
        UserProfile.objects.create(user=self.complainant, role=UserProfile.ROLE_WORKER)
        UserProfile.objects.create(user=self.respondent, role=UserProfile.ROLE_HOUSEHOLD)

    def test_create_complaint(self):
        complaint = Complaint.objects.create(
            complainant=self.complainant,
            respondent=self.respondent,
            complaint_type=Complaint.TYPE_PAYMENT_ISSUE,
            description="Payment was not made after job completion",
            status=Complaint.STATUS_SUBMITTED,
        )
        self.assertEqual(complaint.complainant.username, "worker")
        self.assertEqual(complaint.status, Complaint.STATUS_SUBMITTED)


class ComplaintCreateViewTests(TestCase):
    def setUp(self):
        self.household = User.objects.create_user(username="report-household", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.worker = User.objects.create_user(username="report-worker", password="password")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.other_worker = User.objects.create_user(username="other-worker", password="password")
        UserProfile.objects.create(user=self.other_worker, role=UserProfile.ROLE_WORKER)

        self.job = JobPosting.objects.create(
            household=self.household,
            title="Deep clean",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Flexible schedule",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            status=JobPosting.STATUS_OPEN,
        )
        JobApplication.objects.create(job=self.job, worker=self.worker, status=JobApplication.STATUS_PENDING)

    def test_household_can_report_an_applicant_on_an_open_job(self):
        authenticate(self.client, self.household)

        response = self.client.post(
            reverse("complaint-create"),
            {
                "job": self.job.id,
                "respondent": self.worker.id,
                "complaint_type": "safety_concern",
                "description": "Worker behaved unsafely during the visit.",
            },
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["respondent_username"], "report-worker")
        self.assertEqual(response.data["complainant_username"], "report-household")
        self.assertEqual(response.data["job_status"], "open")

    def test_household_cannot_report_a_worker_with_no_application_on_the_job(self):
        authenticate(self.client, self.household)

        response = self.client.post(
            reverse("complaint-create"),
            {
                "job": self.job.id,
                "respondent": self.other_worker.id,
                "complaint_type": "other",
                "description": "Not actually involved in this job.",
            },
        )

        self.assertEqual(response.status_code, 400)

    def test_worker_report_always_targets_the_jobs_household(self):
        authenticate(self.client, self.worker)

        response = self.client.post(
            reverse("complaint-create"),
            {
                "job": self.job.id,
                "respondent": self.other_worker.id,  # ignored -- household is unambiguous
                "complaint_type": "payment_issue",
                "description": "Was not paid the agreed rate.",
            },
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["respondent_username"], "report-household")

    def test_unrelated_user_cannot_report_a_job(self):
        authenticate(self.client, self.other_worker)

        response = self.client.post(
            reverse("complaint-create"),
            {
                "job": self.job.id,
                "complaint_type": "other",
                "description": "I have nothing to do with this job.",
            },
        )

        self.assertEqual(response.status_code, 403)

    def test_job_is_required(self):
        authenticate(self.client, self.household)

        response = self.client.post(
            reverse("complaint-create"),
            {"complaint_type": "other", "description": "No job attached."},
        )

        self.assertEqual(response.status_code, 400)

    def test_non_numeric_respondent_is_rejected_cleanly_not_a_500(self):
        authenticate(self.client, self.household)

        response = self.client.post(
            reverse("complaint-create"),
            {
                "job": self.job.id,
                "respondent": "not-a-number",
                "complaint_type": "other",
                "description": "Malformed respondent id.",
            },
        )

        self.assertEqual(response.status_code, 400)


class ComplaintAdminViewTests(TestCase):
    def setUp(self):
        self.superadmin = User.objects.create_user(
            username="report-superadmin", password="password", is_staff=True, is_superuser=True
        )
        UserProfile.objects.create(user=self.superadmin, role=UserProfile.ROLE_HOUSEHOLD)
        self.household = User.objects.create_user(username="admin-test-household", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.worker = User.objects.create_user(username="admin-test-worker", password="password")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)

        self.complaint = Complaint.objects.create(
            complainant=self.household,
            respondent=self.worker,
            complaint_type=Complaint.TYPE_NO_SHOW,
            description="Worker never showed up.",
        )

    def test_superadmin_can_list_all_complaints(self):
        authenticate(self.client, self.superadmin)

        response = self.client.get(reverse("complaint-list-admin"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["results"]), 1)

    def test_non_superadmin_cannot_list_complaints(self):
        authenticate(self.client, self.household)

        response = self.client.get(reverse("complaint-list-admin"))

        self.assertEqual(response.status_code, 403)

    def test_admin_can_resolve_a_complaint(self):
        authenticate(self.client, self.superadmin)

        response = self.client.patch(
            reverse("complaint-update-admin", args=[self.complaint.id]),
            {"status": "resolved", "resolution": "Worker was warned."},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["status"], "resolved")
        self.assertEqual(response.data["resolution"], "Worker was warned.")

    def test_invalid_status_is_rejected(self):
        authenticate(self.client, self.superadmin)

        response = self.client.patch(
            reverse("complaint-update-admin", args=[self.complaint.id]),
            {"status": "not-a-real-status"},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 400)
        self.complaint.refresh_from_db()
        self.assertEqual(self.complaint.status, Complaint.STATUS_SUBMITTED)

    def test_complainant_is_notified_when_status_changes(self):
        authenticate(self.client, self.superadmin)

        self.client.patch(
            reverse("complaint-update-admin", args=[self.complaint.id]),
            {"status": "under_review"},
            content_type="application/json",
        )

        authenticate(self.client, self.household)
        notifications = self.client.get(reverse("notification-list"))
        matching = [
            item for item in notifications.data["results"] if "report" in item["message"].lower()
        ]
        self.assertTrue(matching)
        # The web household notification list is an allowlist of types, so the
        # category decides whether the filer ever sees this at all.
        self.assertEqual(matching[0]["notification_type"], "account_activity")


@override_settings(MEDIA_ROOT=tempfile.mkdtemp(), PRIVATE_MEDIA_ROOT=tempfile.mkdtemp())
class ComplaintEvidenceAndBlockingTests(TestCase):
    """Uploads go to temp directories so test runs don't litter the real
    media/ or private_media/ directories with fixture images."""

    def setUp(self):
        self.household = User.objects.create_user(username="ev-household", password="testpass")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.worker = User.objects.create_user(username="ev-worker", password="testpass")
        self.worker_profile = UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.admin = User.objects.create_superuser(username="ev-admin", password="testpass")

        self.job = JobPosting.objects.create(
            household=self.household,
            title="Leaky pipe",
            job_type="Plumbing",
            required_skill="Plumbing",
            schedule="One-Time",
            location_label="Tayabas",
            latitude=Decimal("13.98"),
            longitude=Decimal("121.56"),
            service_rate=Decimal("500.00"),
            worker_slots=1,
        )
        JobApplication.objects.create(job=self.job, worker=self.worker)

    def _png(self, name="evidence.png"):
        # 1x1 PNG so ImageField validation passes.
        raw = base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )
        return SimpleUploadedFile(name, raw, content_type="image/png")

    def test_household_can_attach_photo_evidence_to_a_report(self):
        authenticate(self.client, self.household)

        response = self.client.post(
            reverse("complaint-create"),
            {
                "job": self.job.id,
                "respondent": self.worker.id,
                "complaint_type": Complaint.TYPE_QUALITY_OF_WORK,
                "description": "Work was left unfinished, photo attached.",
                "evidence": [self._png("a.png"), self._png("b.png")],
            },
        )

        self.assertEqual(response.status_code, 201)
        body = response.json()
        self.assertEqual(len(body["evidence"]), 2)
        self.assertTrue(body["evidence"][0]["image_url"])
        self.assertEqual(ComplaintEvidence.objects.count(), 2)

    def test_non_image_evidence_is_rejected(self):
        authenticate(self.client, self.household)

        response = self.client.post(
            reverse("complaint-create"),
            {
                "job": self.job.id,
                "respondent": self.worker.id,
                "complaint_type": Complaint.TYPE_OTHER,
                "description": "Trying to upload a script.",
                "evidence": [SimpleUploadedFile("evil.exe", b"MZ", content_type="application/octet-stream")],
            },
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(Complaint.objects.count(), 0)

    def test_admin_can_block_and_restore_the_reported_account(self):
        complaint = Complaint.objects.create(
            complainant=self.household,
            respondent=self.worker,
            job=self.job,
            complaint_type=Complaint.TYPE_NO_SHOW,
            description="Never arrived.",
        )
        authenticate(self.client, self.admin)
        url = reverse("complaint-block-admin", kwargs={"pk": complaint.id})

        blocked = self.client.post(url, {"reason": "Repeated no-shows."}, content_type="application/json")
        self.assertEqual(blocked.status_code, 200)
        self.worker_profile.refresh_from_db()
        self.assertTrue(self.worker_profile.is_blocked)
        self.assertEqual(self.worker_profile.blocked_reason, "Repeated no-shows.")
        self.assertTrue(blocked.json()["respondent_is_blocked"])

        restored = self.client.post(url, {"blocked": False}, content_type="application/json")
        self.assertEqual(restored.status_code, 200)
        self.worker_profile.refresh_from_db()
        self.assertFalse(self.worker_profile.is_blocked)
        self.assertIsNone(self.worker_profile.blocked_at)

    def test_admin_can_suspend_a_worker_respondent_for_a_limited_duration(self):
        complaint = Complaint.objects.create(
            complainant=self.household,
            respondent=self.worker,
            job=self.job,
            complaint_type=Complaint.TYPE_NO_SHOW,
            description="Never arrived.",
        )
        authenticate(self.client, self.admin)
        url = reverse("complaint-block-admin", kwargs={"pk": complaint.id})

        response = self.client.post(
            url,
            {"reason": "First offense.", "duration_days": 3},
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertTrue(body["respondent_is_blocked"])
        self.assertIsNotNone(body["respondent_blocked_until"])

        self.worker_profile.refresh_from_db()
        self.assertTrue(self.worker_profile.is_blocked)
        self.assertIsNotNone(self.worker_profile.blocked_until)
        self.assertLess(
            self.worker_profile.blocked_until - timezone.now() - timedelta(days=3),
            timedelta(minutes=1),
        )

    def test_admin_can_suspend_a_household_respondent(self):
        """Suspension is symmetric: a worker can file against a household too,
        and blocking must not assume the respondent is always a worker."""
        complaint = Complaint.objects.create(
            complainant=self.worker,
            respondent=self.household,
            job=self.job,
            complaint_type=Complaint.TYPE_PAYMENT_ISSUE,
            description="Household never paid.",
        )
        authenticate(self.client, self.admin)
        url = reverse("complaint-block-admin", kwargs={"pk": complaint.id})

        response = self.client.post(url, {"duration_days": 7}, content_type="application/json")
        self.assertEqual(response.status_code, 200)

        household_profile = UserProfile.objects.get(user=self.household)
        self.assertTrue(household_profile.is_blocked)
        self.assertIsNotNone(household_profile.blocked_until)

    def test_invalid_suspension_duration_is_rejected(self):
        complaint = Complaint.objects.create(
            complainant=self.household,
            respondent=self.worker,
            job=self.job,
            complaint_type=Complaint.TYPE_NO_SHOW,
            description="Never arrived.",
        )
        authenticate(self.client, self.admin)
        url = reverse("complaint-block-admin", kwargs={"pk": complaint.id})

        response = self.client.post(url, {"duration_days": 5}, content_type="application/json")
        self.assertEqual(response.status_code, 400)
        self.worker_profile.refresh_from_db()
        self.assertFalse(self.worker_profile.is_blocked)

    def test_expired_suspension_lifts_itself_automatically(self):
        self.worker_profile.is_blocked = True
        self.worker_profile.blocked_at = timezone.now() - timedelta(days=8)
        self.worker_profile.blocked_reason = "Late arrival."
        self.worker_profile.blocked_until = timezone.now() - timedelta(minutes=1)
        self.worker_profile.save(update_fields=["is_blocked", "blocked_at", "blocked_reason", "blocked_until"])

        authenticate(self.client, self.worker)
        response = self.client.get(reverse("complaint-list"))
        self.assertEqual(response.status_code, 200)

        self.worker_profile.refresh_from_db()
        self.assertFalse(self.worker_profile.is_blocked)
        self.assertIsNone(self.worker_profile.blocked_until)

    def test_non_admin_cannot_block_an_account(self):
        complaint = Complaint.objects.create(
            complainant=self.household,
            respondent=self.worker,
            job=self.job,
            complaint_type=Complaint.TYPE_NO_SHOW,
            description="Never arrived.",
        )
        authenticate(self.client, self.household)

        response = self.client.post(
            reverse("complaint-block-admin", kwargs={"pk": complaint.id}),
            {},
            content_type="application/json",
        )

        self.assertEqual(response.status_code, 403)
        self.worker_profile.refresh_from_db()
        self.assertFalse(self.worker_profile.is_blocked)

    def test_blocked_account_cannot_authenticate_or_log_in(self):
        self.worker_profile.is_blocked = True
        self.worker_profile.save(update_fields=["is_blocked"])

        # An already-issued token stops working immediately.
        authenticate(self.client, self.worker)
        response = self.client.get(reverse("complaint-list"))
        self.assertEqual(response.status_code, 401)

        # And a fresh login is refused too.
        self.client.defaults.pop("HTTP_AUTHORIZATION", None)
        cache.clear()
        login = self.client.post(
            reverse("login"),
            {"username": "ev-worker", "password": "testpass"},
            content_type="application/json",
        )
        self.assertEqual(login.status_code, 403)


PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)


@override_settings(MEDIA_ROOT=tempfile.mkdtemp(), PRIVATE_MEDIA_ROOT=tempfile.mkdtemp())
class ComplaintConfidentialityTests(TestCase):
    """A report must stay invisible to the person it names while under
    review: only the complainant (and superadmins, through the admin
    endpoints) may see it, its evidence, or its internal notes."""

    def setUp(self):
        self.household = User.objects.create_user(username="conf-household", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.worker = User.objects.create_user(username="conf-worker", password="password")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.outsider = User.objects.create_user(username="conf-outsider", password="password")
        UserProfile.objects.create(user=self.outsider, role=UserProfile.ROLE_WORKER)
        self.superadmin = User.objects.create_user(
            username="conf-superadmin", password="password", is_staff=True, is_superuser=True
        )

        self.job = JobPosting.objects.create(
            household=self.household,
            title="Deep clean",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Saturday",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
        )
        JobApplication.objects.create(job=self.job, worker=self.worker)

        authenticate(self.client, self.household)
        created = self.client.post(
            reverse("complaint-create"),
            {
                "job": self.job.id,
                "respondent": self.worker.id,
                "complaint_type": Complaint.TYPE_QUALITY_OF_WORK,
                "description": "Broke a vase and hid it.",
                "evidence": [SimpleUploadedFile("IMG_0001.png", PNG_1X1, content_type="image/png")],
            },
        )
        self.assertEqual(created.status_code, 201)
        self.complaint = Complaint.objects.get(pk=created.json()["id"])
        self.evidence = self.complaint.evidence.get()

        authenticate(self.client, self.superadmin)
        self.client.patch(
            reverse("complaint-update-admin", args=[self.complaint.id]),
            {"status": "under_review", "admin_notes": "INTERNAL: checking CCTV"},
            content_type="application/json",
        )
        self.detail_url = reverse("complaint-detail", args=[self.complaint.id])
        self.evidence_url = reverse("complaint-evidence", args=[self.complaint.id, self.evidence.id])

    def test_complainant_sees_their_complaint_in_list_and_detail(self):
        authenticate(self.client, self.household)

        listed = self.client.get(reverse("complaint-list"))
        detail = self.client.get(self.detail_url)

        self.assertEqual([c["id"] for c in listed.json()["results"]], [self.complaint.id])
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.json()["description"], "Broke a vase and hid it.")

    def test_respondent_gets_empty_list_and_404_on_detail(self):
        authenticate(self.client, self.worker)

        self.assertEqual(self.client.get(reverse("complaint-list")).json()["results"], [])
        self.assertEqual(self.client.get(reverse("complaint-list"), {"status": "under_review"}).json()["results"], [])
        self.assertEqual(self.client.get(self.detail_url).status_code, 404)

    def test_unrelated_user_gets_empty_list_and_404_on_detail(self):
        authenticate(self.client, self.outsider)

        self.assertEqual(self.client.get(reverse("complaint-list")).json()["results"], [])
        self.assertEqual(self.client.get(self.detail_url).status_code, 404)

    def test_respondent_404_is_indistinguishable_from_a_missing_complaint(self):
        authenticate(self.client, self.worker)
        missing = self.client.get(reverse("complaint-detail", args=[999999]))
        real = self.client.get(self.detail_url)
        self.assertEqual((real.status_code, real.json()), (missing.status_code, missing.json()))

    def test_non_admin_responses_never_contain_admin_notes(self):
        authenticate(self.client, self.household)

        listed = self.client.get(reverse("complaint-list"))
        detail = self.client.get(self.detail_url)
        created = self.client.post(
            reverse("complaint-create"),
            {"job": self.job.id, "respondent": self.worker.id, "complaint_type": "other", "description": "x"},
            content_type="application/json",
        )

        for body in (listed.json()["results"][0], detail.json(), created.json()):
            self.assertNotIn("admin_notes", body)
        self.assertNotIn("INTERNAL", listed.content.decode() + detail.content.decode())

    def test_admin_endpoints_still_return_admin_notes(self):
        authenticate(self.client, self.superadmin)

        listed = self.client.get(reverse("complaint-list-admin"))
        updated = self.client.patch(
            reverse("complaint-update-admin", args=[self.complaint.id]),
            {"resolution": "Worker warned."},
            content_type="application/json",
        )
        blocked = self.client.post(
            reverse("complaint-block-admin", args=[self.complaint.id]),
            {"blocked": False},
            content_type="application/json",
        )

        self.assertEqual(listed.json()["results"][0]["admin_notes"], "INTERNAL: checking CCTV")
        self.assertEqual(updated.json()["admin_notes"], "INTERNAL: checking CCTV")
        self.assertEqual(blocked.json()["admin_notes"], "INTERNAL: checking CCTV")

    def test_evidence_is_served_only_to_complainant_and_superadmin(self):
        authenticate(self.client, self.household)
        own = self.client.get(self.evidence_url)
        self.assertEqual(own.status_code, 200)
        self.assertEqual(b"".join(own.streaming_content), PNG_1X1)
        self.assertEqual(own["X-Content-Type-Options"], "nosniff")

        authenticate(self.client, self.superadmin)
        self.assertEqual(self.client.get(self.evidence_url).status_code, 200)

        for user in (self.worker, self.outsider):
            authenticate(self.client, user)
            self.assertEqual(self.client.get(self.evidence_url).status_code, 404)

        self.client.defaults.pop("HTTP_AUTHORIZATION", None)
        self.assertEqual(self.client.get(self.evidence_url).status_code, 401)

    def test_evidence_is_stored_privately_under_a_random_name(self):
        from pathlib import Path

        from django.conf import settings

        name = self.evidence.image.name
        self.assertNotIn("IMG_0001", name)
        self.assertTrue((Path(settings.PRIVATE_MEDIA_ROOT) / name).exists())
        self.assertFalse((Path(settings.MEDIA_ROOT) / name).exists())

        authenticate(self.client, self.household)
        url = self.client.get(self.detail_url).json()["evidence"][0]["image_url"]
        self.assertTrue(url.endswith(self.evidence_url))
        self.assertNotIn("/media/", url)

    def test_respondent_is_never_notified_about_the_report(self):
        authenticate(self.client, self.superadmin)
        for new_status in ("resolved", "closed"):
            self.client.patch(
                reverse("complaint-update-admin", args=[self.complaint.id]),
                {"status": new_status},
                content_type="application/json",
            )

        authenticate(self.client, self.worker)
        notifications = self.client.get(reverse("notification-list")).json()["results"]
        self.assertEqual(notifications, [])
