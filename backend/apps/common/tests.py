import base64
import io
import json
import os
import sys
import tempfile
from pathlib import Path
from types import ModuleType
from unittest.mock import patch
from urllib import error

from django.conf import settings
from django.contrib.auth.models import User
from django.core.cache import cache
from django.core.exceptions import ImproperlyConfigured
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.mail import send_mail
from django.test import override_settings
from django.test import TestCase
from django.urls import reverse
from rest_framework.renderers import JSONRenderer
from rest_framework.test import APIClient
from rest_framework.views import APIView

from apps.accounts.models import UserProfile
from apps.common.authentication import create_jwt_token
from apps.common.models import VerificationRequest


TEMP_MEDIA_ROOT = tempfile.mkdtemp()



# A real 1x1 PNG: uploads are validated by their contents now, not by
# the filename, so placeholder bytes named .png are refused.
REAL_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)

class AdminLoginRateLimitTests(TestCase):
    """Django's /admin/ sign-in form is a session login, so neither the DRF
    per-IP throttle nor the per-account lockout on the API's own login
    endpoint reaches it. Without this it was the one door onto a superuser
    account where a password could be guessed at without limit."""

    def setUp(self):
        cache.clear()
        self.url = reverse("admin:login")
        User.objects.create_superuser(username="root", password="root-pass-12345")

    def tearDown(self):
        cache.clear()

    def attempt(self, password="wrong-password", **extra):
        return self.client.post(
            self.url, {"username": "root", "password": password}, **extra
        )

    @override_settings(ADMIN_LOGIN_FAILURE_LIMIT=3)
    def test_repeated_failures_from_one_ip_are_locked_out(self):
        statuses = [self.attempt().status_code for _ in range(4)]

        # The admin re-renders its form with 200 when credentials are wrong.
        self.assertEqual(statuses[:3], [200, 200, 200])
        self.assertEqual(statuses[3], 429)

    @override_settings(ADMIN_LOGIN_FAILURE_LIMIT=3)
    def test_a_successful_login_clears_the_failure_count(self):
        self.attempt()
        self.attempt()

        signed_in = self.attempt(password="root-pass-12345")
        self.assertEqual(signed_in.status_code, 302)

        # Back to a clean slate: the two earlier failures must not combine
        # with later ones to lock out an account in normal use.
        self.assertEqual(self.attempt().status_code, 200)

    @override_settings(ADMIN_LOGIN_FAILURE_LIMIT=3)
    def test_the_lockout_is_per_ip(self):
        for _ in range(3):
            self.attempt(REMOTE_ADDR="10.0.0.1")

        self.assertEqual(self.attempt(REMOTE_ADDR="10.0.0.1").status_code, 429)
        self.assertEqual(self.attempt(REMOTE_ADDR="10.0.0.2").status_code, 200)

    @override_settings(ADMIN_LOGIN_FAILURE_LIMIT=3)
    def test_loading_the_login_page_is_not_a_failed_attempt(self):
        for _ in range(5):
            self.assertEqual(self.client.get(self.url).status_code, 200)

        self.assertEqual(self.attempt().status_code, 200)

    @override_settings(ADMIN_LOGIN_FAILURE_LIMIT=3)
    def test_the_api_login_endpoint_is_unaffected(self):
        # That endpoint has its own throttle and lockout; this middleware must
        # not add a second, stricter limit on top of it.
        for _ in range(4):
            response = self.client.post(
                reverse("login"),
                {"username": "root", "password": "wrong-password"},
                content_type="application/json",
            )
        self.assertEqual(response.status_code, 400)


class ProductionRendererTests(TestCase):
    """DRF's default renderer list includes BrowsableAPIRenderer, which serves
    an HTML UI with forms and a field-by-field schema at every endpoint.
    Nothing consumes HTML -- all three clients read JSON -- so in production
    it is only extra surface and extra detail about the API's shape."""

    JSON_ONLY = ["rest_framework.renderers.JSONRenderer"]

    def test_production_settings_declare_json_only(self):
        settings_module = Path(settings.BASE_DIR) / "backend" / "config" / "settings" / "production.py"
        probe = ModuleType("gawago_production_settings_probe")
        # `from .base import *` is relative, so the throwaway module has to
        # claim the real package to resolve it.
        probe.__package__ = "config.settings"
        probe.__file__ = str(settings_module)
        with patch.dict(
            os.environ,
            {
                "DJANGO_SECRET_KEY": "probe-secret-key-not-a-real-one",
                "DJANGO_ALLOWED_HOSTS": "example.com",
            },
        ):
            exec(compile(settings_module.read_text(encoding="utf-8"), str(settings_module), "exec"), probe.__dict__)

        self.assertEqual(probe.REST_FRAMEWORK["DEFAULT_RENDERER_CLASSES"], self.JSON_ONLY)

    def test_with_json_only_renderers_an_html_request_is_refused(self):
        admin = User.objects.create_superuser(username="renderer-admin", password="admin-pass123")
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': admin.id})}"

        # DRF reads DEFAULT_RENDERER_CLASSES into APIView.renderer_classes at
        # import, so override_settings cannot reach it (the same trap as
        # THROTTLE_RATES) -- patch the class attribute the views inherit.
        with patch.object(APIView, "renderer_classes", [JSONRenderer]):
            browser_like = self.client.get(reverse("profile-list"), HTTP_ACCEPT="text/html")
            normal = self.client.get(reverse("profile-list"), HTTP_ACCEPT="application/json")

        # No HTML representation exists to hand a browser any more.
        self.assertEqual(browser_like.status_code, 406)
        self.assertEqual(normal.status_code, 200)
        self.assertEqual(normal["Content-Type"], "application/json")


class BrevoAPIEmailBackendTests(TestCase):
    """Brevo's SMTP relay rejects unlisted IPs (525 Unauthorized IP address)
    and residential IPs here are dynamic, so password-reset codes stop going
    out after a router reboot. This backend uses Brevo's HTTP API, which has
    no IP allowlist."""

    BACKEND = "apps.common.email_backends.BrevoAPIEmailBackend"

    def captured_request(self, mock_urlopen):
        sent = mock_urlopen.call_args.args[0]
        return sent, json.loads(sent.data.decode("utf-8"))

    @override_settings(
        EMAIL_BACKEND=BACKEND, BREVO_API_KEY="test-api-key", DEFAULT_FROM_EMAIL="no-reply@gawago.ph"
    )
    def test_send_mail_posts_the_message_to_brevo(self):
        with patch("apps.common.email_backends.request.urlopen") as urlopen:
            sent = send_mail("Your GawaGo code", "Your code is 123456", None, ["worker@example.com"])

        self.assertEqual(sent, 1)
        api_request, payload = self.captured_request(urlopen)
        self.assertEqual(api_request.full_url, "https://api.brevo.com/v3/smtp/email")
        self.assertEqual(api_request.get_header("Api-key"), "test-api-key")
        self.assertEqual(payload["subject"], "Your GawaGo code")
        self.assertEqual(payload["textContent"], "Your code is 123456")
        self.assertEqual(payload["to"], [{"email": "worker@example.com"}])
        self.assertEqual(payload["sender"], {"email": "no-reply@gawago.ph"})

    @override_settings(EMAIL_BACKEND=BACKEND, BREVO_API_KEY="test-api-key")
    def test_a_display_name_in_the_from_address_is_split_out(self):
        with patch("apps.common.email_backends.request.urlopen") as urlopen:
            send_mail("s", "b", "GawaGo <no-reply@gawago.ph>", ["a@example.com"])

        _request, payload = self.captured_request(urlopen)
        self.assertEqual(payload["sender"], {"email": "no-reply@gawago.ph", "name": "GawaGo"})

    @override_settings(EMAIL_BACKEND=BACKEND, BREVO_API_KEY="test-api-key")
    def test_a_rejected_message_raises_with_brevos_own_reason(self):
        """An SMTP failure gives a bare code; the API explains itself, and
        that reason is what makes a misconfiguration diagnosable."""
        failure = error.HTTPError(
            "https://api.brevo.com/v3/smtp/email",
            401,
            "Unauthorized",
            {},
            io.BytesIO(b'{"message":"Key not found","code":"unauthorized"}'),
        )
        with patch("apps.common.email_backends.request.urlopen", side_effect=failure):
            with self.assertRaises(RuntimeError) as caught:
                send_mail("s", "b", None, ["a@example.com"])

        self.assertIn("Key not found", str(caught.exception))

    @override_settings(EMAIL_BACKEND=BACKEND, BREVO_API_KEY="test-api-key")
    def test_fail_silently_swallows_a_rejection(self):
        failure = error.HTTPError("u", 500, "err", {}, io.BytesIO(b"{}"))
        with patch("apps.common.email_backends.request.urlopen", side_effect=failure):
            sent = send_mail("s", "b", None, ["a@example.com"], fail_silently=True)

        self.assertEqual(sent, 0)

    @override_settings(EMAIL_BACKEND=BACKEND, BREVO_API_KEY="")
    def test_a_missing_api_key_is_reported_rather_than_silently_dropping_mail(self):
        with self.assertRaises(ValueError):
            send_mail("s", "b", None, ["a@example.com"])

    @override_settings(EMAIL_BACKEND=BACKEND, BREVO_API_KEY="test-api-key")
    def test_attachments_are_refused_rather_than_dropped(self):
        from django.core.mail import EmailMessage

        message = EmailMessage("s", "b", "f@example.com", ["a@example.com"])
        message.attach("report.csv", b"a,b\n1,2", "text/csv")
        with patch("apps.common.email_backends.request.urlopen"):
            with self.assertRaises(NotImplementedError):
                message.send()


class CloudinaryStorageTests(TestCase):
    """Cloudinary backs PUBLIC uploads only. A delivery URL is public to
    anyone holding it, so routing government IDs, worker certificates or
    complaint evidence through it would undo the private-media fix --
    these lock that boundary in place."""

    def test_private_media_never_uses_cloudinary(self):
        from apps.accounts.models import UserProfile, WorkerCertification
        from apps.common.models import VerificationRequest
        from apps.complaints.models import ComplaintEvidence
        from apps.complaints.storage import PrivateMediaStorage

        private_fields = [
            (WorkerCertification, "certificate_file"),
            (VerificationRequest, "primary_id_file"),
            (VerificationRequest, "secondary_doc_file"),
            (ComplaintEvidence, "image"),
        ]
        for model, field_name in private_fields:
            with self.subTest(field=f"{model.__name__}.{field_name}"):
                storage = model._meta.get_field(field_name).storage
                # Pinned on the field, so it ignores the default backend.
                self.assertIsInstance(storage, PrivateMediaStorage)

        # ...and that storage refuses to produce a public link at all.
        with self.assertRaises(ValueError):
            PrivateMediaStorage().url("certifications/1/secret.png")

        # Public media, by contrast, pins nothing and follows the default
        # backend -- which is what Cloudinary is allowed to replace.
        from apps.jobs.models import JobImage

        for model, field_name in [
            (UserProfile, "profile_photo"),
            (JobImage, "image"),
        ]:
            with self.subTest(field=f"{model.__name__}.{field_name}"):
                storage = model._meta.get_field(field_name).storage
                self.assertNotIsInstance(storage, PrivateMediaStorage)

    @override_settings(
        USE_CLOUDINARY=True,
        CLOUDINARY_CLOUD_NAME="test-cloud",
        CLOUDINARY_API_KEY="test-key",
        CLOUDINARY_API_SECRET="test-secret",
    )
    def test_saving_keeps_the_public_id_cloudinary_actually_assigned(self):
        """Cloudinary renames on collision, so the name Django stores has to
        come back from the response, not from what we asked for."""
        from apps.common.cloudinary_storage import CloudinaryMediaStorage

        storage = CloudinaryMediaStorage()
        with patch(
            "cloudinary.uploader.upload",
            return_value={"public_id": "jobs/2026/10/07/abc123_xy", "format": "png"},
        ) as upload:
            stored = storage._save("jobs/2026/10/07/abc123.png", SimpleUploadedFile("x.png", REAL_PNG))

        self.assertEqual(stored, "jobs/2026/10/07/abc123_xy.png")
        self.assertEqual(upload.call_args.kwargs["public_id"], "jobs/2026/10/07/abc123")
        self.assertFalse(upload.call_args.kwargs["overwrite"])

    @override_settings(
        USE_CLOUDINARY=True,
        CLOUDINARY_CLOUD_NAME="test-cloud",
        CLOUDINARY_API_KEY="test-key",
        CLOUDINARY_API_SECRET="test-secret",
    )
    def test_url_is_built_from_the_stored_name(self):
        from apps.common.cloudinary_storage import CloudinaryMediaStorage

        url = CloudinaryMediaStorage().url("jobs/2026/10/07/abc123.png")

        self.assertIn("test-cloud", url)
        self.assertIn("jobs/2026/10/07/abc123", url)
        self.assertTrue(url.startswith("https://"))

    def test_the_default_storage_is_local_unless_cloudinary_is_enabled(self):
        self.assertEqual(
            settings.STORAGES["default"]["BACKEND"],
            "django.core.files.storage.FileSystemStorage",
        )

    def _load_base_with_cloudinary_on(self, **env):
        probe = ModuleType("gawago_cloudinary_settings_probe")
        base = Path(settings.BASE_DIR) / "backend" / "config" / "settings" / "base.py"
        probe.__file__ = str(base)
        with (
            patch.dict(
                os.environ,
                {
                    "DJANGO_DEBUG": "True",
                    "USE_CLOUDINARY": "True",
                    "DJANGO_USE_SQLITE_FOR_TESTS": "False",
                    "DJANGO_USE_SQLITE_FOR_DEV": "False",
                    "DJANGO_DB_ENGINE": "postgresql",
                    **env,
                },
            ),
            # Cloudinary is forced off while `"test" in sys.argv`, so without
            # this the probe would never reach the branch under test.
            patch.object(sys, "argv", ["manage.py", "runserver"]),
            patch("dotenv.load_dotenv", return_value=False),
        ):
            for name in ("CLOUDINARY_URL", "CLOUDINARY_CLOUD_NAME", "CLOUDINARY_API_KEY", "CLOUDINARY_API_SECRET"):
                if name not in env:
                    os.environ.pop(name, None)
            exec(compile(base.read_text(encoding="utf-8"), str(base), "exec"), probe.__dict__)
        return probe

    def test_enabling_cloudinary_without_credentials_refuses_to_boot(self):
        """Silently falling back to local disk on an ephemeral host would
        lose every upload at the next redeploy."""
        with self.assertRaises(ImproperlyConfigured):
            self._load_base_with_cloudinary_on()

    def test_the_combined_cloudinary_url_is_accepted(self):
        """The dashboard offers one copyable credential; accepting it means
        the secret is pasted rather than retyped from a font where capital I
        and lowercase l look identical."""
        probe = self._load_base_with_cloudinary_on(
            CLOUDINARY_URL="cloudinary://123456789:s3cr3t-value@my-cloud"
        )

        self.assertEqual(probe.CLOUDINARY_CLOUD_NAME, "my-cloud")
        self.assertEqual(probe.CLOUDINARY_API_KEY, "123456789")
        self.assertEqual(probe.CLOUDINARY_API_SECRET, "s3cr3t-value")
        self.assertEqual(
            probe.STORAGES["default"]["BACKEND"],
            "apps.common.cloudinary_storage.CloudinaryMediaStorage",
        )

    def test_a_malformed_cloudinary_url_is_rejected(self):
        with self.assertRaises(ImproperlyConfigured):
            self._load_base_with_cloudinary_on(CLOUDINARY_URL="https://not-a-cloudinary-url")

    def test_cloudinary_is_forced_off_while_running_tests(self):
        """Uploads during the suite must never reach the real account: it
        would make every run slow, network-dependent, and quietly spend the
        plan's credits."""
        self.assertFalse(settings.USE_CLOUDINARY)
        self.assertEqual(
            settings.STORAGES["default"]["BACKEND"],
            "django.core.files.storage.FileSystemStorage",
        )


class DatabaseEngineDefaultTests(TestCase):
    """DJANGO_DB_ENGINE defaulted to mysql, so omitting that one line from a
    production .env sent Django to port 3306 instead of PostgreSQL -- and
    only the MySQL branch needs a driver requirements.txt no longer installs.

    The live DATABASES setting can't be asserted on here: the suite forces
    SQLite (`"test" in sys.argv`), so that branch is the only one taken while
    tests run. This loads base.py the way a server would instead."""

    def load_base_settings(self, **env):
        base = Path(settings.BASE_DIR) / "backend" / "config" / "settings" / "base.py"
        probe = ModuleType("gawago_base_settings_probe")
        probe.__file__ = str(base)
        with (
            patch.dict(
                os.environ,
                {
                    # Debug on so the "secret key must be set" guard doesn't fire.
                    "DJANGO_DEBUG": "True",
                    "DJANGO_USE_SQLITE_FOR_TESTS": "False",
                    "DJANGO_USE_SQLITE_FOR_DEV": "False",
                    **env,
                },
            ),
            # `"test" in sys.argv` forces SQLite, which would hide the branch
            # under test; this is what a `runserver`/gunicorn process sees.
            patch.object(sys, "argv", ["manage.py", "runserver"]),
            # base.py re-reads the developer's .env on exec, which would
            # otherwise supply DJANGO_DB_ENGINE and decide the answer for us.
            patch("dotenv.load_dotenv", return_value=False),
        ):
            if "DJANGO_DB_ENGINE" not in env:
                os.environ.pop("DJANGO_DB_ENGINE", None)
            exec(compile(base.read_text(encoding="utf-8"), str(base), "exec"), probe.__dict__)
        return probe

    def test_omitting_the_engine_gives_postgresql(self):
        probe = self.load_base_settings()

        self.assertEqual(probe.DATABASES["default"]["ENGINE"], "django.db.backends.postgresql")
        self.assertEqual(probe.DATABASES["default"]["PORT"], "5432")

    def test_mysql_is_still_selectable(self):
        probe = self.load_base_settings(DJANGO_DB_ENGINE="mysql", DJANGO_MYSQL_DRIVER="mysqlclient")

        self.assertEqual(probe.DATABASES["default"]["ENGINE"], "django.db.backends.mysql")

    def test_requirements_does_not_install_a_mysql_driver_by_default(self):
        """mysqlclient builds against MySQL system headers, so listing it here
        broke `pip install -r requirements.txt` on a PostgreSQL host."""
        backend_dir = Path(settings.BASE_DIR) / "backend"
        default = (backend_dir / "requirements.txt").read_text(encoding="utf-8")
        mysql_extra = (backend_dir / "requirements-mysql.txt").read_text(encoding="utf-8")

        requirement_lines = [
            line.strip()
            for line in default.splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]
        self.assertFalse([line for line in requirement_lines if "mysqlclient" in line.lower()])
        self.assertFalse([line for line in requirement_lines if "pymysql" in line.lower()])
        self.assertIn("psycopg", default)
        # ...but MySQL is still supported, just opt-in.
        self.assertIn("mysqlclient", mysql_extra)
        self.assertIn("-r requirements.txt", mysql_extra)


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
        primary_file = SimpleUploadedFile("primary.png", REAL_PNG, content_type="image/png")
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
                    REAL_PNG,
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
                    REAL_PNG,
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
            SimpleUploadedFile("primary.png", REAL_PNG, content_type="image/png"),
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
        self.assertEqual(len(response.data["results"]), 1)
        self.assertEqual(response.data["results"][0]["id"], self.request_record.id)

    def test_worker_cannot_view_another_workers_verification_detail(self):
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("verification-request-detail", args=[self.other_request_record.id]))

        self.assertEqual(response.status_code, 403)

    def test_household_can_list_own_verification_requests(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.get(reverse("verification-request-list-create"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["results"], [])

    def test_household_can_submit_verification_request(self):
        self.client.force_authenticate(user=self.household)
        primary_file = SimpleUploadedFile("household-primary.png", REAL_PNG, content_type="image/png")
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
        self.assertEqual(len(response.data["results"]), 2)

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


@override_settings(MEDIA_ROOT=TEMP_MEDIA_ROOT)
class VerificationIdTypeTests(TestCase):
    """The eight government ID types live on this flow -- the one whose
    approval actually flips profile.verification_status. They used to sit on a
    second, parallel model whose approval changed nothing on the account."""

    PNG = REAL_PNG

    def setUp(self):
        self.client = APIClient()
        self.worker = User.objects.create_user(username="id-type-worker", password="password")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.admin = User.objects.create_superuser(
            username="id-type-admin", password="password", email="a@example.com"
        )

    def _submit(self, **extra):
        self.client.force_authenticate(user=self.worker)
        payload = {
            "secondary_doc_name": "Barangay Clearance",
            "primary_id_file": SimpleUploadedFile("id.png", self.PNG, content_type="image/png"),
            "secondary_doc_file": SimpleUploadedFile("doc.png", self.PNG, content_type="image/png"),
        }
        payload.update(extra)
        return self.client.post(
            reverse("verification-request-list-create"), payload, format="multipart"
        )

    def test_every_listed_id_type_is_accepted_and_labelled_from_the_choice(self):
        for id_type, label in VerificationRequest.ID_TYPE_CHOICES:
            if id_type == VerificationRequest.ID_TYPE_OTHER:
                continue
            with self.subTest(id_type=id_type):
                VerificationRequest.objects.all().delete()
                self.worker.profile.verification_status = "unverified"
                self.worker.profile.save(update_fields=["verification_status"])

                response = self._submit(primary_id_type=id_type)

                self.assertEqual(response.status_code, 201, response.data)
                record = VerificationRequest.objects.get()
                self.assertEqual(record.primary_id_type, id_type)
                # The label is derived, so it can never contradict the type.
                self.assertEqual(record.primary_id_name, label)

    def test_other_requires_the_submitter_to_name_the_id(self):
        response = self._submit(primary_id_type=VerificationRequest.ID_TYPE_OTHER)

        self.assertEqual(response.status_code, 400)
        self.assertIn("primary_id_name", response.data)

    def test_other_keeps_the_typed_name(self):
        response = self._submit(
            primary_id_type=VerificationRequest.ID_TYPE_OTHER,
            primary_id_name="PRC Professional ID",
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(VerificationRequest.objects.get().primary_id_name, "PRC Professional ID")

    def test_an_unknown_id_type_is_rejected(self):
        response = self._submit(primary_id_type="drivers_licence_typo")

        self.assertEqual(response.status_code, 400)
        self.assertIn("primary_id_type", response.data)

    def test_approving_a_typed_request_still_verifies_the_account(self):
        """The whole point of moving the ID types here: approval must reach
        the profile, which is what the retired parallel model never did."""
        self._submit(primary_id_type=VerificationRequest.ID_TYPE_PASSPORT)
        record = VerificationRequest.objects.get()
        self.client.force_authenticate(user=self.admin)

        response = self.client.post(
            reverse("verification-request-review", args=[record.id]),
            {"action": "approve"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.verification_status, "verified")

    def test_the_serializer_exposes_the_type_and_its_label(self):
        self._submit(primary_id_type=VerificationRequest.ID_TYPE_UMID)
        self.client.force_authenticate(user=self.admin)

        response = self.client.get(reverse("verification-request-list-create"))

        row = response.data["results"][0] if isinstance(response.data, dict) else response.data[0]
        self.assertEqual(row["primary_id_type"], VerificationRequest.ID_TYPE_UMID)
        self.assertEqual(row["primary_id_type_label"], "UMID")
