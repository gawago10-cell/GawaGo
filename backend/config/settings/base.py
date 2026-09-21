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
    "apps.accounts",
    "apps.jobs",
    "apps.matching",
    "apps.reviews",
    "apps.notifications",
    "apps.analytics",
    "apps.common",
    "apps.complaints",
    "apps.reports",
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
    },
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
    "apps.common.middleware.ContentSecurityPolicyMiddleware",
]

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

# Proactive AI job-match notifications (apps.matching.signals). Disabled during
# the test suite: every JobPosting created in tests would otherwise trigger a
# TF-IDF scoring pass plus a real road-distance network call per candidate
# worker, which is slow and flaky in CI.
ENABLE_JOB_MATCH_NOTIFICATIONS = "test" not in sys.argv
JOB_MATCH_NOTIFY_THRESHOLD = float(os.environ.get("JOB_MATCH_NOTIFY_THRESHOLD", "0.5"))
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
    DB_ENGINE = os.environ.get("DJANGO_DB_ENGINE", "mysql").strip().lower()
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
