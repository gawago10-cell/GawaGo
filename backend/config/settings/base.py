import os
import sys
from pathlib import Path

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

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "change-me-for-local-development")

DEBUG = os.environ.get("DJANGO_DEBUG", "False") == "True"
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

CORS_ALLOWED_ORIGINS = os.environ.get("CORS_ALLOWED_ORIGINS", "http://localhost:5173,http://localhost:8000").split(",")

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
