from datetime import timedelta
from decimal import Decimal

from django.contrib.auth.models import User
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.common.authentication import create_jwt_token
from apps.jobs.models import JobApplication, JobPosting
from apps.reports.services import _month_buckets, report_to_csv_rows, resolve_period


def authenticate(client, user):
    client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': user.id})}"


class ReportPeriodTests(TestCase):
    def test_reversed_bounds_are_swapped_rather_than_emptied(self):
        today = timezone.localdate()
        period = resolve_period(today, today - timedelta(days=30))

        self.assertEqual(period["start"], today - timedelta(days=30))
        self.assertEqual(period["end"], today)

    def test_missing_bounds_default_to_a_trailing_window(self):
        period = resolve_period()

        self.assertEqual(period["end"], timezone.localdate())
        self.assertLess(period["start"], period["end"])


class MonthlyBucketTests(TestCase):
    """roadmap audit LOW #33: the monthly chart was hard-capped at 6 buckets
    regardless of how wide the requested window actually was, so a custom
    range longer than 6 months silently dropped everything before the
    trailing 6 months."""

    def test_a_default_window_still_produces_around_six_buckets(self):
        period = resolve_period()
        # The trailing 180-day default spans 6 or 7 calendar months depending
        # on where "today" falls -- either is a correct "about 6 months" read.
        self.assertIn(len(_month_buckets(period)), (6, 7))

    def test_a_year_long_window_produces_a_full_years_worth_of_buckets(self):
        today = timezone.localdate()
        period = resolve_period(today.replace(year=today.year - 1), today)
        self.assertEqual(len(_month_buckets(period)), 13)

    def test_bucket_count_is_capped_for_an_extremely_wide_window(self):
        today = timezone.localdate()
        period = resolve_period(today.replace(year=today.year - 10), today)
        self.assertEqual(len(_month_buckets(period)), 24)


class CsvFormulaInjectionTests(TestCase):
    """A cell starting with =, +, -, @, tab or CR is interpreted as a formula
    by Excel/Google Sheets rather than literal text -- e.g. a worker or job
    title of `=cmd|'/c calc'!A1` would execute when the exported report is
    opened. Report fields are user-controlled free text, so every cell must
    be neutralized before it reaches the CSV writer."""

    def _report(self, dangerous_value):
        return {
            "title": "Household activity report",
            "period": {"start": "2026-01-01", "end": "2026-01-31"},
            "summary": {"jobsPosted": 1},
            "sections": [
                {
                    "title": "Workers you hired",
                    "columns": ["Worker", "Times hired"],
                    "rows": [[dangerous_value, 1]],
                }
            ],
        }

    def test_formula_trigger_characters_are_neutralized(self):
        for dangerous in ("=cmd|'/c calc'!A1", "+1+1", "-2+3", "@SUM(A1)", "\tHidden"):
            rows = report_to_csv_rows(self._report(dangerous))
            worker_row = next(row for row in rows if len(row) == 2 and row[0] == f"'{dangerous}")
            self.assertEqual(worker_row, [f"'{dangerous}", 1])

    def test_ordinary_text_and_numbers_pass_through_unchanged(self):
        rows = report_to_csv_rows(self._report("Maria Santos"))
        worker_row = next(row for row in rows if len(row) == 2 and row[0] == "Maria Santos")
        self.assertEqual(worker_row, ["Maria Santos", 1])
        summary_row = next(row for row in rows if row and row[0] == "Jobs posted")
        self.assertEqual(summary_row[1], 1)


class MyReportTests(TestCase):
    def setUp(self):
        self.household = User.objects.create_user(username="report-household", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.worker = User.objects.create_user(username="report-worker", password="password")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER, skills=["House Cleaning"])

        self.job = JobPosting.objects.create(
            household=self.household,
            title="Weekly clean",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Flexible schedule",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            status=JobPosting.STATUS_COMPLETED,
        )
        JobApplication.objects.create(
            job=self.job, worker=self.worker, status=JobApplication.STATUS_COMPLETED
        )

    def test_household_gets_a_household_scoped_report(self):
        authenticate(self.client, self.household)

        response = self.client.get(reverse("my-report"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["scope"], "household")
        self.assertEqual(response.data["summary"]["jobsPosted"], 1)
        self.assertEqual(response.data["summary"]["completedJobs"], 1)
        self.assertEqual(response.data["summary"]["totalSpend"], 500.0)
        self.assertEqual(response.data["summary"]["workersHired"], 1)

    def test_worker_gets_a_worker_scoped_report(self):
        authenticate(self.client, self.worker)

        response = self.client.get(reverse("my-report"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["scope"], "worker")
        self.assertEqual(response.data["summary"]["applicationsSubmitted"], 1)
        self.assertEqual(response.data["summary"]["jobsCompleted"], 1)
        self.assertEqual(response.data["summary"]["totalEarnings"], 500.0)

    def test_report_requires_authentication(self):
        response = self.client.get(reverse("my-report"))

        self.assertEqual(response.status_code, 401)

    def test_csv_export_escapes_a_worker_name_that_looks_like_a_formula(self):
        self.worker.first_name = "=cmd|'/c calc'!A1"
        self.worker.save(update_fields=["first_name"])
        authenticate(self.client, self.household)

        response = self.client.get(reverse("my-report"), {"export": "csv"})

        self.assertEqual(response.status_code, 200)
        content = response.content.decode()
        # The raw formula-triggering value must never appear un-prefixed --
        # only the quote-escaped, inert form.
        self.assertNotIn("\n=cmd|", content)
        self.assertNotIn(",=cmd|", content)
        self.assertIn("'=cmd|'/c calc'!A1", content)

    def test_csv_export_returns_a_downloadable_file(self):
        authenticate(self.client, self.household)

        response = self.client.get(reverse("my-report"), {"export": "csv"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "text/csv")
        self.assertIn("attachment;", response["Content-Disposition"])
        self.assertIn("Household activity report", response.content.decode())

    def test_period_filter_excludes_jobs_outside_the_window(self):
        authenticate(self.client, self.household)
        long_ago = timezone.localdate() - timedelta(days=900)

        response = self.client.get(
            reverse("my-report"),
            {"start": long_ago.isoformat(), "end": (long_ago + timedelta(days=5)).isoformat()},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["summary"]["jobsPosted"], 0)


class PlatformReportTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create_user(username="report-admin", password="password", is_staff=True)
        UserProfile.objects.create(user=self.admin, role=UserProfile.ROLE_HOUSEHOLD)
        self.member = User.objects.create_user(username="report-member", password="password")
        UserProfile.objects.create(user=self.member, role=UserProfile.ROLE_WORKER)

    def test_admin_can_read_the_platform_report(self):
        authenticate(self.client, self.admin)

        response = self.client.get(reverse("platform-report"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["scope"], "platform")
        # The admin's own profile is not a platform member.
        self.assertEqual(response.data["summary"]["totalAccounts"], 1)
        self.assertEqual(response.data["summary"]["totalWorkers"], 1)

    def test_average_worker_rating_is_weighted_by_review_count(self):
        # A plain Avg("average_rating") would give self.member (0 reviews,
        # excluded by rating_count__gt=0) no weight either way here, so add
        # two rated workers with different counts: a plain per-worker mean
        # gives (5.00 + 1.00) / 2 = 3.00, but weighted by rating_count it's
        # (5.00*4 + 1.00*1) / 5 = 4.20.
        heavily_reviewed = User.objects.create_user(username="report-heavily-reviewed", password="password")
        UserProfile.objects.create(
            user=heavily_reviewed,
            role=UserProfile.ROLE_WORKER,
            average_rating=Decimal("5.00"),
            rating_count=4,
        )
        barely_reviewed = User.objects.create_user(username="report-barely-reviewed", password="password")
        UserProfile.objects.create(
            user=barely_reviewed,
            role=UserProfile.ROLE_WORKER,
            average_rating=Decimal("1.00"),
            rating_count=1,
        )
        authenticate(self.client, self.admin)

        response = self.client.get(reverse("platform-report"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["summary"]["averageWorkerRating"], 4.2)

    def test_job_match_rate_cannot_exceed_100_percent(self):
        # A job posted long before this period gets hired *within* it. That
        # hire must not inflate jobMatchRate's numerator, since the job
        # itself isn't one of the jobs "posted in this period" the rate's
        # denominator (job_list) counts.
        old_job = JobPosting.objects.create(
            household=self.admin,
            title="Old job",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Flexible",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            status=JobPosting.STATUS_ASSIGNED,
        )
        JobPosting.objects.filter(pk=old_job.pk).update(
            created_at=timezone.now() - timedelta(days=900)
        )
        JobApplication.objects.create(
            job=old_job, worker=self.member, status=JobApplication.STATUS_HIRED
        )
        new_job = JobPosting.objects.create(
            household=self.admin,
            title="New job",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Flexible",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            status=JobPosting.STATUS_ASSIGNED,
        )
        JobApplication.objects.create(
            job=new_job, worker=self.member, status=JobApplication.STATUS_HIRED
        )
        authenticate(self.client, self.admin)

        response = self.client.get(reverse("platform-report"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["summary"]["jobMatchRate"], 100.0)

    def test_non_admin_is_refused(self):
        authenticate(self.client, self.member)

        response = self.client.get(reverse("platform-report"))

        self.assertEqual(response.status_code, 403)
