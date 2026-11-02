"""Private uploads (IDs, certificates, complaint evidence) must survive a
redeploy and still never get a public link. On Render's free plan the disk
was wiped on every deploy, so every uploaded ID stopped opening (2026-11-03)."""

import io
import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError

from django.contrib.auth.models import User
from django.core.files.base import ContentFile
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from apps.accounts.models import UserProfile, WorkerCertification
from apps.common.models import VerificationRequest
from apps.complaints.models import Complaint, ComplaintEvidence
from apps.complaints.storage import CloudinaryPrivateStorage, LocalPrivateStorage, PrivateMediaStorage

CLOUDINARY_ON = {
    "USE_CLOUDINARY": True,
    "CLOUDINARY_CLOUD_NAME": "test-cloud",
    "CLOUDINARY_API_KEY": "test-key",
    "CLOUDINARY_API_SECRET": "test-secret",
}
NAME = "verification_documents/7/0123abcd.png"


class PrivateStorageBackendTests(TestCase):
    def test_no_public_url_in_either_mode(self):
        with self.assertRaises(ValueError):
            PrivateMediaStorage().url(NAME)
        with override_settings(**CLOUDINARY_ON):
            with self.assertRaises(ValueError):
                PrivateMediaStorage().url(NAME)

    def test_follows_use_cloudinary_on_every_call(self):
        storage = PrivateMediaStorage()
        self.assertIsInstance(storage._target(), LocalPrivateStorage)
        with override_settings(**CLOUDINARY_ON):
            self.assertIsInstance(storage._target(), CloudinaryPrivateStorage)

    @override_settings(PRIVATE_MEDIA_ROOT=tempfile.mkdtemp())
    def test_local_mode_writes_under_private_media_root(self):
        from django.conf import settings

        saved = PrivateMediaStorage().save(NAME, ContentFile(b"id-bytes"))
        self.assertTrue((Path(settings.PRIVATE_MEDIA_ROOT) / saved).exists())
        with PrivateMediaStorage().open(saved) as handle:
            self.assertEqual(handle.read(), b"id-bytes")

    @override_settings(**CLOUDINARY_ON)
    def test_cloudinary_upload_is_authenticated_raw(self):
        with patch("cloudinary.uploader.upload", return_value={"public_id": NAME}) as upload:
            saved = PrivateMediaStorage().save(NAME, ContentFile(b"id-bytes"))

        self.assertEqual(saved, NAME)
        kwargs = upload.call_args.kwargs
        self.assertEqual(kwargs["type"], "authenticated")
        self.assertEqual(kwargs["resource_type"], "raw")
        self.assertEqual(kwargs["public_id"], NAME)
        self.assertFalse(kwargs["overwrite"])

    @override_settings(**CLOUDINARY_ON)
    def test_cloudinary_open_uses_the_signed_api_download(self):
        """A signed delivery URL is refused for PDFs on free accounts, so the
        backend reads through the API download link instead."""
        from urllib.parse import parse_qs, urlparse

        response = MagicMock()
        response.__enter__.return_value.read.return_value = b"id-bytes"
        with patch("apps.complaints.storage.url_request.urlopen", return_value=response) as urlopen:
            with PrivateMediaStorage().open(NAME) as handle:
                self.assertEqual(handle.read(), b"id-bytes")

        url = urlparse(urlopen.call_args.args[0])
        query = parse_qs(url.query)
        self.assertEqual(url.netloc, "api.cloudinary.com")
        self.assertEqual(url.path, "/v1_1/test-cloud/raw/download")
        self.assertEqual(query["public_id"], [NAME])
        self.assertEqual(query["type"], ["authenticated"])
        self.assertIn("signature", query)
        self.assertNotIn("test-secret", urlopen.call_args.args[0])

    @override_settings(**CLOUDINARY_ON)
    def test_cloudinary_missing_asset_reads_as_missing_file(self):
        gone = HTTPError("https://res.cloudinary.com/x", 404, "Not Found", {}, io.BytesIO())
        with patch("apps.complaints.storage.url_request.urlopen", side_effect=gone):
            with self.assertRaises(FileNotFoundError):
                PrivateMediaStorage().open(NAME)

    @override_settings(**CLOUDINARY_ON)
    def test_cloudinary_other_errors_are_not_hidden(self):
        refused = HTTPError("https://res.cloudinary.com/x", 401, "Unauthorized", {}, io.BytesIO())
        with patch("apps.complaints.storage.url_request.urlopen", side_effect=refused):
            with self.assertRaises(HTTPError):
                PrivateMediaStorage().open(NAME)

    @override_settings(**CLOUDINARY_ON)
    def test_cloudinary_delete_targets_the_authenticated_asset(self):
        with patch("cloudinary.uploader.destroy") as destroy:
            PrivateMediaStorage().delete(NAME)

        destroy.assert_called_once_with(NAME, invalidate=True, resource_type="raw", type="authenticated")


@override_settings(MEDIA_ROOT=tempfile.mkdtemp(), PRIVATE_MEDIA_ROOT=tempfile.mkdtemp())
class MissingPrivateFileTests(TestCase):
    """A file whose row survives but whose bytes are gone answers 404 with a
    reason the admin can read, not a 500."""

    PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 16

    def setUp(self):
        self.client = APIClient()
        self.worker = User.objects.create_user(username="gone-worker", password="password")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.household = User.objects.create_user(username="gone-household", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.admin = User.objects.create_superuser(username="gone-admin", password="password", email="a@example.com")
        self.client.force_authenticate(user=self.admin)

    def test_verification_document(self):
        record = VerificationRequest.objects.create(
            worker=self.worker,
            primary_id_name="id.png",
            secondary_doc_name="doc.png",
            primary_id_file="verification_documents/1/gone.png",
        )
        response = self.client.get(reverse("verification-request-document", args=[record.id, "primary"]))

        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.data["detail"], "This document is no longer stored on the server, so it can't be opened.")

    def test_verification_document_still_opens_when_present(self):
        record = VerificationRequest.objects.create(worker=self.worker, primary_id_name="id.png", secondary_doc_name="doc.png")
        record.primary_id_file.save("id.png", SimpleUploadedFile("id.png", self.PNG, content_type="image/png"))

        response = self.client.get(reverse("verification-request-document", args=[record.id, "primary"]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(b"".join(response.streaming_content), self.PNG)

    def test_certificate_file(self):
        cert = WorkerCertification.objects.create(
            worker=self.worker, certificate_name="NC II", certificate_file="certifications/1/gone.png"
        )
        response = self.client.get(reverse("worker-certification-file", args=[cert.id]))

        self.assertEqual(response.status_code, 404)
        self.assertEqual(
            response.data["detail"], "This certificate file is no longer stored on the server, so it can't be opened."
        )

    def test_complaint_evidence(self):
        complaint = Complaint.objects.create(
            complainant=self.household,
            respondent=self.worker,
            complaint_type=Complaint.TYPE_NO_SHOW,
            description="Did not arrive",
        )
        evidence = ComplaintEvidence.objects.create(complaint=complaint, image="complaint_evidence/1/gone.png")
        response = self.client.get(reverse("complaint-evidence", args=[complaint.id, evidence.id]))

        self.assertEqual(response.status_code, 404)
        self.assertEqual(
            response.data["detail"], "This evidence photo is no longer stored on the server, so it can't be opened."
        )
