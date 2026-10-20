import os
import sys
from pathlib import Path

from corsheaders.defaults import default_headers
from django.core.exceptions import ImproperlyConfigured

try:
    from dotenv import load_dotenv
except ImportError:
    def load_dotenv(*args, **kwargs):
        return False

BASE_DIR = Path(__file__).resolve().parents[3]

# Load environment variables from common local env files.
load_dotenv(BASE_DIR / ".env")
load_dotenv(BASE_DIR / "backend" / ".env")
load_dotenv(BASE_DIR / "frontend" / ".env")

_INSECURE_DEFAULT_SECRET_KEY = "change-me-for-local-development"
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", _INSECURE_DEFAULT_SECRET_KEY)

DEBUG = os.environ.get("DJANGO_DEBUG", "False") == "True"

# config.settings.production already refuses to boot without a real secret
# key, but nothing stops a deployment from pointing DJANGO_SETTINGS_MODULE at
# this base module directly with debug off. create_jwt_token HMACs with
# SECRET_KEY, so the well-known placeholder above would let anyone forge a
# token for any user_id -- refuse the same way production.py does, here too.
if not DEBUG and SECRET_KEY == _INSECURE_DEFAULT_SECRET_KEY:
    raise ImproperlyConfigured(
        "DJANGO_SECRET_KEY must be set to a real value when DJANGO_DEBUG is not True."
    )
ALLOWED_HOSTS = [host.strip() for host in os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1").split(",") if host.strip()]

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "corsheaders",
    "django_q",
    "apps.accounts",
    "apps.jobs",
    "apps.matching",
    "apps.reviews",
    "apps.notifications",
    "apps.analytics",
    "apps.common",
    "apps.complaints",
    "apps.reports",
    "apps.chat",
]

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "apps.common.authentication.JWTAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticatedOrReadOnly",
    ],
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 20,
    "DEFAULT_THROTTLE_RATES": {
        "login": "10/min",
        "password_reset": "5/min",
        # Per-IP, and behind NAT one IP can be a whole room (a demo where
        # every evaluator signs up at once), so this is set well above any
        # legitimate burst -- it exists to make testing addresses in bulk
        # impractical, not to ration signups.
        "signup": os.environ.get("SIGNUP_THROTTLE_RATE", "20/min"),
    },
    # Proxies in front of Django. Left unset, DRF trusts the whole
    # client-supplied X-Forwarded-For header, so a random value per request
    # escapes the login and password-reset throttles.
    "NUM_PROXIES": int(os.environ.get("DRF_NUM_PROXIES", "0")),
}

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "apps.common.middleware.StripControlCharactersMiddleware",
    "apps.common.middleware.AdminLoginRateLimitMiddleware",
    "apps.common.middleware.ContentSecurityPolicyMiddleware",
]

# Failed sign-ins allowed at Django's /admin/ form before that IP is locked
# out, and for how long. Per-IP only -- see the middleware's docstring for why
# this deliberately isn't per-account.
ADMIN_LOGIN_FAILURE_LIMIT = int(os.environ.get("ADMIN_LOGIN_FAILURE_LIMIT", "10"))
ADMIN_LOGIN_LOCKOUT_SECONDS = int(os.environ.get("ADMIN_LOGIN_LOCKOUT_SECONDS", str(15 * 60)))

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

SETTINGS_MODULE = os.environ.get("DJANGO_SETTINGS_MODULE", "")
USE_SQLITE_FOR_TESTS = os.environ.get("DJANGO_USE_SQLITE_FOR_TESTS", "False") == "True" or "test" in sys.argv

RUNNING_TESTS = "test" in sys.argv

# Proactive AI job-match notifications (apps.matching.tasks), scheduled by the
# job-create view with transaction.on_commit + apps.common.background.enqueue.
# Off during the test suite so ordinary job-creating tests don't run a scoring
# pass with a routing call per worker; the job-match tests switch it back on.
ENABLE_JOB_MATCH_NOTIFICATIONS = os.environ.get(
    "ENABLE_JOB_MATCH_NOTIFICATIONS", "False" if RUNNING_TESTS else "True"
) == "True"
JOB_MATCH_NOTIFY_THRESHOLD = float(os.environ.get("JOB_MATCH_NOTIFY_THRESHOLD", "0.5"))

# How apps.common.background.enqueue() runs work: "django_q" (a qcluster
# process, using this database as the queue), "thread" (in-process daemon
# thread) or "sync" (inline -- tests/debugging only).
BACKGROUND_TASK_BACKEND = os.environ.get(
    "BACKGROUND_TASK_BACKEND", "sync" if RUNNING_TESTS else "django_q"
).strip().lower()

# Django-Q2, ORM broker: the queue lives in the existing database, no Redis.
# A task is killed after `timeout` seconds; one not acknowledged within
# `retry` seconds (e.g. its worker died) is re-queued, at most `max_attempts`
# times -- the job-match task is idempotent, so a re-run is harmless.
Q_CLUSTER = {
    "name": "gawago",
    "orm": "default",
    "workers": int(os.environ.get("Q_WORKERS", "2")),
    "timeout": int(os.environ.get("Q_TIMEOUT_SECONDS", "600")),
    "retry": int(os.environ.get("Q_RETRY_SECONDS", "720")),
    "max_attempts": 3,
    "ack_failures": True,
    "catch_up": False,
    "save_limit": 250,
    "poll": 2,
}

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"simple": {"format": "%(asctime)s %(levelname)s %(name)s: %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "simple"}},
    "loggers": {
        "apps": {"handlers": ["console"], "level": os.environ.get("APP_LOG_LEVEL", "INFO"), "propagate": False},
    },
}
USE_SQLITE_FOR_DEV = (
    SETTINGS_MODULE.endswith(".development")
    and os.environ.get("DJANGO_USE_SQLITE_FOR_DEV", "True") == "True"
)
MYSQL_DRIVER = os.environ.get("DJANGO_MYSQL_DRIVER", "auto").strip().lower()


def configure_mysql_driver():
    if MYSQL_DRIVER in {"mysqlclient", "mysqldb"}:
        return
    if MYSQL_DRIVER == "pymysql":
        try:
            import pymysql
        except ImportError as exc:
            raise ImportError(
                "DJANGO_MYSQL_DRIVER=pymysql requires PyMySQL. "
                "Install backend dependencies with: pip install -r backend/requirements.txt"
            ) from exc

        pymysql.install_as_MySQLdb()
        return
    if MYSQL_DRIVER == "auto":
        try:
            import MySQLdb  # noqa: F401
        except ImportError:
            try:
                import pymysql
            except ImportError as exc:
                raise ImportError(
                    "Neither mysqlclient nor PyMySQL is installed. "
                    "Install backend dependencies with: pip install -r backend/requirements.txt"
                ) from exc

            pymysql.install_as_MySQLdb()
        return
    raise ValueError("DJANGO_MYSQL_DRIVER must be one of: auto, mysqlclient, pymysql")

if USE_SQLITE_FOR_TESTS or USE_SQLITE_FOR_DEV:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / ("test-db.sqlite3" if USE_SQLITE_FOR_TESTS else "dev-db.sqlite3"),
        }
    }
else:
    # PostgreSQL is the project's database (AGENTS.md) and what production
    # provisions. This defaulted to "mysql", so omitting one line from a
    # production .env sent Django to port 3306 instead -- and only the MySQL
    # branch needs a driver that isn't installed by default.
    DB_ENGINE = os.environ.get("DJANGO_DB_ENGINE", "postgresql").strip().lower()
    if DB_ENGINE == "postgresql":
        DATABASES = {
            "default": {
                "ENGINE": "django.db.backends.postgresql",
                "NAME": os.environ.get("DB_NAME", ""),
                "USER": os.environ.get("DB_USER", ""),
                "PASSWORD": os.environ.get("DB_PASSWORD", ""),
                "HOST": os.environ.get("DB_HOST", "127.0.0.1"),
                "PORT": os.environ.get("DB_PORT", "5432"),
            }
        }
    elif DB_ENGINE == "mysql":
        configure_mysql_driver()
        DATABASES = {
            "default": {
                "ENGINE": "django.db.backends.mysql",
                "NAME": os.environ.get("DB_NAME", ""),
                "USER": os.environ.get("DB_USER", ""),
                "PASSWORD": os.environ.get("DB_PASSWORD", ""),
                "HOST": os.environ.get("DB_HOST", "127.0.0.1"),
                "PORT": os.environ.get("DB_PORT", "3306"),
            }
        }
    else:
        raise ValueError("DJANGO_DB_ENGINE must be one of: mysql, postgresql")

CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.environ.get("CORS_ALLOWED_ORIGINS", "http://localhost:5173,http://localhost:8000").split(",")
    if origin.strip()
]

# The mobile app sends this on every request (mobile/lib/src/core/api/gawago_api.dart)
# to skip ngrok's interstitial warning page when testing against a tunneled backend.
# Native Android/iOS ignore CORS entirely, but Flutter web enforces it like any browser,
# so without this the preflight for every request fails before it reaches a view.
CORS_ALLOW_HEADERS = list(default_headers) + ["ngrok-skip-browser-warning"]

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator", "OPTIONS": {"min_length": 8}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "Asia/Manila"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
# Uploads that must never be reachable by URL (e.g. complaint evidence).
# Kept outside MEDIA_ROOT so neither DEBUG static serving nor a web server's
# /media/ alias can expose them.
PRIVATE_MEDIA_ROOT = BASE_DIR / "private_media"

# Cloudinary for PUBLIC uploads (profile photos, job images, portfolio work
# samples). Off by default: a host with a persistent disk does not need it. It
# matters where the filesystem is ephemeral (Render/Railway free tier), and
# uploads would otherwise be lost on every redeploy.
#
# This replaces the *default* storage only. Government IDs, worker
# certificates and complaint evidence pin PrivateMediaStorage on the field, so
# they stay on local disk behind permission-checked views whatever this is set
# to -- a Cloudinary delivery URL is public to anyone holding it.
#
# Never during tests, whatever the environment says: the suite saves a lot of
# images, and letting those reach the real account would make every run slow,
# dependent on the network, and quietly consume the plan's credits.
USE_CLOUDINARY = (
    os.environ.get("USE_CLOUDINARY", "False") == "True" and not USE_SQLITE_FOR_TESTS
)
CLOUDINARY_CLOUD_NAME = os.environ.get("CLOUDINARY_CLOUD_NAME", "")
CLOUDINARY_API_KEY = os.environ.get("CLOUDINARY_API_KEY", "")
CLOUDINARY_API_SECRET = os.environ.get("CLOUDINARY_API_SECRET", "")

# Cloudinary's dashboard offers one combined credential,
# `cloudinary://<api_key>:<api_secret>@<cloud_name>`, with a copy button.
# Accepting it means the secret is pasted rather than retyped -- the
# dashboard's font renders capital I and lowercase l identically, which is
# exactly how a hand-copied secret ends up failing with "Invalid Signature".
# The three separate variables still work and win if both are set.
CLOUDINARY_URL = os.environ.get("CLOUDINARY_URL", "").strip()
if CLOUDINARY_URL and not (CLOUDINARY_CLOUD_NAME and CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET):
    from urllib.parse import unquote, urlparse

    _parsed = urlparse(CLOUDINARY_URL)
    if _parsed.scheme != "cloudinary":
        raise ImproperlyConfigured(
            "CLOUDINARY_URL must start with 'cloudinary://' "
            "(cloudinary://<api_key>:<api_secret>@<cloud_name>)."
        )
    # The dashboard percent-encodes any reserved character in the secret.
    CLOUDINARY_CLOUD_NAME = CLOUDINARY_CLOUD_NAME or (_parsed.hostname or "")
    CLOUDINARY_API_KEY = CLOUDINARY_API_KEY or unquote(_parsed.username or "")
    CLOUDINARY_API_SECRET = CLOUDINARY_API_SECRET or unquote(_parsed.password or "")

if USE_CLOUDINARY:
    if not (CLOUDINARY_CLOUD_NAME and CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET):
        raise ImproperlyConfigured(
            "USE_CLOUDINARY=True requires either CLOUDINARY_URL, or all of "
            "CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET. "
            "Refusing to start rather than silently writing uploads to a disk "
            "that will not survive a redeploy."
        )
    _default_storage_backend = "apps.common.cloudinary_storage.CloudinaryMediaStorage"
else:
    _default_storage_backend = "django.core.files.storage.FileSystemStorage"

STORAGES = {
    "default": {"BACKEND": _default_storage_backend},
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

EMAIL_BACKEND = os.environ.get("EMAIL_BACKEND", "django.core.mail.backends.smtp.EmailBackend")
EMAIL_HOST = os.environ.get("EMAIL_HOST", "smtp.gmail.com")
EMAIL_PORT = int(os.environ.get("EMAIL_PORT", "587"))
EMAIL_USE_TLS = os.environ.get("EMAIL_USE_TLS", "True") == "True"
EMAIL_HOST_USER = os.environ.get("EMAIL_HOST_USER", "")
EMAIL_HOST_PASSWORD = os.environ.get("EMAIL_HOST_PASSWORD", "")
DEFAULT_FROM_EMAIL = os.environ.get("DEFAULT_FROM_EMAIL", EMAIL_HOST_USER or "no-reply@gawago.local")
# Without this, Django's SMTP backend falls back to the OS socket default
# (minutes, not seconds), so an unreachable mail host hangs whatever request
# triggered the email -- e.g. complete_job sends one inline per hired worker.
EMAIL_TIMEOUT = int(os.environ.get("EMAIL_TIMEOUT_SECONDS", "10"))
# Used only when EMAIL_BACKEND is apps.common.email_backends.BrevoAPIEmailBackend.
# That backend exists because Brevo's SMTP relay rejects unlisted IPs
# (525 Unauthorized IP address) and residential IPs here are dynamic.
BREVO_API_KEY = os.environ.get("BREVO_API_KEY", "")
PASSWORD_RESET_TOKEN_TTL_MINUTES = int(os.environ.get("PASSWORD_RESET_TOKEN_TTL_MINUTES", "10"))
OPENROUTESERVICE_API_KEY = os.environ.get("OPENROUTESERVICE_API_KEY") or os.environ.get(
    "VITE_OPENROUTESERVICE_API_KEY",
    "",
)
OPENROUTESERVICE_DIRECTIONS_URL = os.environ.get(
    "OPENROUTESERVICE_DIRECTIONS_URL",
    "https://api.openrouteservice.org/v2/directions/driving-car/geojson",
)
OPENROUTESERVICE_TIMEOUT_SECONDS = float(os.environ.get("OPENROUTESERVICE_TIMEOUT_SECONDS", "4"))
OSRM_DIRECTIONS_URL = os.environ.get(
    "OSRM_DIRECTIONS_URL",
    "https://router.project-osrm.org/route/v1/driving",
)
