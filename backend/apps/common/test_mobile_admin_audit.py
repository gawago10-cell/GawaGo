"""Mobile admin audit (2026-11-22): verification documents say whether they
are images or PDFs, so the app can hold a decision it can't see."""

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.urls import reverse

from apps.accounts.models import UserProfile
from apps.common.test_flow_fixes import client_for, make_user
from apps.common.tests import REAL_PNG

PDF = b"%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n"


class VerificationDocumentTypeTests(TestCase):
    def setUp(self):
        self.admin = make_user("ma-admin", staff=True)
        self.applicant = make_user("ma-applicant", UserProfile.ROLE_HOUSEHOLD, verification_status="pending")

    def submit(self, secondary_name, secondary_bytes, content_type):
        response = client_for(self.applicant).post(
            reverse("verification-request-list-create"),
            {
                "primary_id_type": "national_id",
                "primary_id_number": "N01-11-000001",
                "primary_id_name": "id.png",
                "secondary_doc_name": secondary_name,
                "primary_id_file": SimpleUploadedFile("id.png", REAL_PNG, content_type="image/png"),
                "secondary_doc_file": SimpleUploadedFile(secondary_name, secondary_bytes, content_type=content_type),
            },
            format="multipart",
        )
        self.assertEqual(response.status_code, 201, response.data)

    def admin_row(self):
        rows = client_for(self.admin).get(reverse("verification-request-list-create")).data
        rows = rows.get("results", rows)
        return next(row for row in rows if row["worker_username"] == "ma-applicant")

    def test_a_pdf_document_is_named_as_one(self):
        self.submit("clearance.pdf", PDF, "application/pdf")

        row = self.admin_row()

        self.assertEqual(row["primary_id_file_type"], "image")
        self.assertEqual(row["secondary_doc_file_type"], "pdf")

    def test_image_documents_are_images(self):
        self.submit("clearance.png", REAL_PNG, "image/png")

        row = self.admin_row()

        self.assertEqual((row["primary_id_file_type"], row["secondary_doc_file_type"]), ("image", "image"))
