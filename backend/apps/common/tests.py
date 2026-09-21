import tempfile

from django.contrib.auth.models import User
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from apps.accounts.models import UserProfile
from apps.common.models import VerificationRequest


TEMP_MEDIA_ROOT = tempfile.mkdtemp()


class VerificationRequestReviewTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_superuser(username="admin", password="password", email="admin@example.com")
        self.worker = User.objects.create_user(username="maria", password="password")
        self.profile = UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.request_record = VerificationRequest.objects.create(
            worker=self.worker,
            primary_id_name="primary-id.jpg",
            secondary_doc_name="barangay-clearance.jpg",
        )
        self.client.force_authenticate(user=self.admin)

    def test_approving_request_marks_worker_profile_verified(self):
        url = reverse("verification-request-review", args=[self.request_record.id])

        response = self.client.post(url, {"action": "approve"}, format="json")

        self.assertEqual(response.status_code, 200)
        self.request_record.refresh_from_db()
        self.profile.refresh_from_db()
        self.assertEqual(self.request_record.status, VerificationRequest.STATUS_APPROVED)
        self.assertEqual(self.profile.verification_status, "verified")

    def test_rejecting_request_marks_worker_profile_rejected(self):
        url = reverse("verification-request-review", args=[self.request_record.id])

        response = self.client.post(url, {"action": "reject", "review_note": "Please resubmit."}, format="json")

        self.assertEqual(response.status_code, 200)
        self.request_record.refresh_from_db()
        self.profile.refresh_from_db()
        self.assertEqual(self.request_record.status, VerificationRequest.STATUS_REJECTED)
        self.assertEqual(self.profile.verification_status, "rejected")


@override_settings(MEDIA_ROOT=TEMP_MEDIA_ROOT)
class VerificationRequestPermissionTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.worker = User.objects.create_user(username="worker-permission", password="password")
        self.other_worker = User.objects.create_user(username="other-worker-permission", password="password")
        self.household = User.objects.create_user(username="household-permission", password="password")
        self.non_admin = User.objects.create_user(username="ordinary-user", password="password")
        self.admin = User.objects.create_superuser(username="admin-permission", password="password", email="admin@example.com")
        self.profile = UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        UserProfile.objects.create(user=self.other_worker, role=UserProfile.ROLE_WORKER)
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.request_record = VerificationRequest.objects.create(
            worker=self.worker,
            primary_id_name="primary-id.jpg",
            secondary_doc_name="barangay-clearance.jpg",
        )
        self.other_request_record = VerificationRequest.objects.create(
            worker=self.other_worker,
            primary_id_name="other-primary-id.jpg",
            secondary_doc_name="other-clearance.jpg",
        )

    def test_anonymous_user_cannot_submit_verification_request_by_worker_username(self):
        response = self.client.post(
            reverse("verification-request-list-create"),
            {
                "worker_username": self.worker.username,
                "primary_id_name": "new-id.jpg",
                "secondary_doc_name": "new-clearance.jpg",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 401)

    def test_worker_submits_verification_documents_as_private_files(self):
        self.request_record.delete()
        self.client.force_authenticate(user=self.worker)
        primary_file = SimpleUploadedFile("primary.png", b"primary-image", content_type="image/png")
        secondary_file = SimpleUploadedFile("clearance.pdf", b"%PDF-1.4", content_type="application/pdf")

        response = self.client.post(
            reverse("verification-request-list-create"),
            {
                "primary_id_name": "primary.png",
                "secondary_doc_name": "clearance.pdf",
                "primary_id_file": primary_file,
                "secondary_doc_file": secondary_file,
                "notes": "Please review.",
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 201)
        request_record = VerificationRequest.objects.get(pk=response.data["verification_request"]["id"])
        self.assertTrue(request_record.primary_id_file.name)
        self.assertTrue(request_record.secondary_doc_file.name)
        self.assertNotIn("primary-image", response.data["verification_request"]["primary_id_preview"])
        self.assertIn("/api/common/verification-requests/", response.data["verification_request"]["primary_id_preview"])

    def test_pending_verification_request_cannot_be_submitted_again(self):
        self.client.force_authenticate(user=self.worker)

        response = self.client.post(
            reverse("verification-request-list-create"),
            {
                "primary_id_name": "replacement.png",
                "secondary_doc_name": "replacement.pdf",
                "primary_id_file": SimpleUploadedFile(
                    "replacement.png",
                    b"replacement-image",
                    content_type="image/png",
                ),
                "secondary_doc_file": SimpleUploadedFile(
                    "replacement.pdf",
                    b"%PDF-1.4 replacement",
                    content_type="application/pdf",
                ),
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 409)
        self.assertIn("already under review", response.data["detail"])
        self.assertEqual(VerificationRequest.objects.filter(worker=self.worker).count(), 1)

    def test_rejected_verification_request_can_be_resubmitted(self):
        self.request_record.status = VerificationRequest.STATUS_REJECTED
        self.request_record.save(update_fields=["status"])
        self.profile.verification_status = "rejected"
        self.profile.save(update_fields=["verification_status"])
        self.client.force_authenticate(user=self.worker)

        response = self.client.post(
            reverse("verification-request-list-create"),
            {
                "primary_id_name": "corrected.png",
                "secondary_doc_name": "corrected.pdf",
                "primary_id_file": SimpleUploadedFile(
                    "corrected.png",
                    b"corrected-image",
                    content_type="image/png",
                ),
                "secondary_doc_file": SimpleUploadedFile(
                    "corrected.pdf",
                    b"%PDF-1.4 corrected",
                    content_type="application/pdf",
                ),
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 201)
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.verification_status, "pending")
        self.assertEqual(VerificationRequest.objects.filter(worker=self.worker).count(), 2)

    def test_verification_document_requires_owner_or_staff(self):
        self.request_record.primary_id_file.save(
            "primary.png",
            SimpleUploadedFile("primary.png", b"primary-image", content_type="image/png"),
        )
        url = reverse("verification-request-document", args=[self.request_record.id, "primary"])

        self.client.force_authenticate(user=self.other_worker)
        forbidden_response = self.client.get(url)

        self.client.force_authenticate(user=self.worker)
        owner_response = self.client.get(url)

        self.client.force_authenticate(user=self.admin)
        admin_response = self.client.get(url)

        self.assertEqual(forbidden_response.status_code, 403)
        self.assertEqual(owner_response.status_code, 200)
        self.assertEqual(admin_response.status_code, 200)

    def test_anonymous_user_cannot_list_verification_requests(self):
        response = self.client.get(reverse("verification-request-list-create"))

        self.assertEqual(response.status_code, 401)

    def test_anonymous_user_cannot_view_verification_request_detail(self):
        response = self.client.get(reverse("verification-request-detail", args=[self.request_record.id]))

        self.assertEqual(response.status_code, 401)

    def test_worker_can_only_list_own_verification_requests(self):
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("verification-request-list-create"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["id"], self.request_record.id)

    def test_worker_cannot_view_another_workers_verification_detail(self):
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("verification-request-detail", args=[self.other_request_record.id]))

        self.assertEqual(response.status_code, 403)

    def test_household_can_list_own_verification_requests(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.get(reverse("verification-request-list-create"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, [])

    def test_household_can_submit_verification_request(self):
        self.client.force_authenticate(user=self.household)
        primary_file = SimpleUploadedFile("household-primary.png", b"primary-image", content_type="image/png")
        secondary_file = SimpleUploadedFile("household-clearance.pdf", b"%PDF-1.4", content_type="application/pdf")

        response = self.client.post(
            reverse("verification-request-list-create"),
            {
                "primary_id_name": "household-primary.png",
                "secondary_doc_name": "household-clearance.pdf",
                "primary_id_file": primary_file,
                "secondary_doc_file": secondary_file,
            },
            format="multipart",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["verification_request"]["account_role"], UserProfile.ROLE_HOUSEHOLD)
        self.assertEqual(response.data["account"]["profile"]["role"], UserProfile.ROLE_HOUSEHOLD)

    def test_admin_can_approve_household_verification_request(self):
        household_request = VerificationRequest.objects.create(
            worker=self.household,
            primary_id_name="household-primary.png",
            secondary_doc_name="household-clearance.pdf",
        )
        self.client.force_authenticate(user=self.admin)

        response = self.client.post(
            reverse("verification-request-review", args=[household_request.id]),
            {"action": "approve"},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.household.profile.refresh_from_db()
        self.assertEqual(self.household.profile.verification_status, "verified")

    def test_admin_can_list_all_verification_requests(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get(reverse("verification-request-list-create"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 2)

    def test_non_admin_cannot_approve_verification_request(self):
        self.client.force_authenticate(user=self.non_admin)

        response = self.client.post(
            reverse("verification-request-review", args=[self.request_record.id]),
            {"action": "approve"},
            format="json",
        )

        self.assertEqual(response.status_code, 403)
        self.request_record.refresh_from_db()
        self.profile.refresh_from_db()
        self.assertEqual(self.request_record.status, VerificationRequest.STATUS_PENDING)
        self.assertEqual(self.profile.verification_status, "pending")

    def test_admin_can_approve_verification_request(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.post(
            reverse("verification-request-review", args=[self.request_record.id]),
            {"action": "approve"},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.request_record.refresh_from_db()
        self.assertEqual(self.request_record.status, VerificationRequest.STATUS_APPROVED)
