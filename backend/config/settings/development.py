from .base import *  # noqa

DEBUG = True
ALLOWED_HOSTS = ["*"]

# Use SQLite locally when MySQL is not available.
USE_SQLITE_FOR_DEV = os.environ.get("DJANGO_USE_SQLITE_FOR_DEV", "True") == "True"
HAS_MYSQL_CONFIG = all(
    os.environ.get(key)
    for key in ("DB_NAME", "DB_USER", "DB_PASSWORD", "DB_HOST", "DB_PORT")
)

if USE_SQLITE_FOR_DEV or not HAS_MYSQL_CONFIG:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "dev-db.sqlite3",
        }
    }

if os.environ.get("CORS_ALLOWED_ORIGINS"):
    CORS_ALLOWED_ORIGINS = [origin.strip() for origin in os.environ["CORS_ALLOWED_ORIGINS"].split(",") if origin.strip()]
else:
    CORS_ALLOWED_ORIGINS = [
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ]

CORS_ALLOWED_ORIGIN_REGEXES = [
    r"^http://localhost:\d+$",
    r"^http://127\.0\.0\.1:\d+$",
]

CORS_ALLOW_CREDENTIALS = True

# Locally, run background tasks in a thread so `runserver` alone works; set
# BACKGROUND_TASK_BACKEND=django_q (and run `manage.py qcluster`) to exercise
# the production queue.
if not RUNNING_TESTS:
    BACKGROUND_TASK_BACKEND = os.environ.get("BACKGROUND_TASK_BACKEND", "thread").strip().lower()

USE_CONSOLE_EMAIL = os.environ.get("DJANGO_USE_CONSOLE_EMAIL", "True") == "True"

if USE_CONSOLE_EMAIL or not os.environ.get("EMAIL_HOST_USER") or not os.environ.get("EMAIL_HOST_PASSWORD"):
    EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"
