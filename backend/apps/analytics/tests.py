from decimal import Decimal
from types import SimpleNamespace

from django.contrib.auth.models import User
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from apps.accounts.models import UserProfile
from apps.analytics.services import _build_rating_distribution, build_dashboard_metrics
from apps.common.models import VerificationRequest
from apps.jobs.models import JobApplication, JobPosting


class DashboardMetricsServiceTests(TestCase):
    def setUp(self):
        self.household = User.objects.create_user(username="household", password="password")
        UserProfile.objects.create(
            user=self.household,
            role=UserProfile.ROLE_HOUSEHOLD,
            location_label="Demo Street, Alitao, Tayabas City",
        )
        self.worker = User.objects.create_user(username="worker", password="password")
        UserProfile.objects.create(
            user=self.worker,
            role=UserProfile.ROLE_WORKER,
            verification_status="verified",
            average_rating=Decimal("4.50"),
            rating_count=2,
            location_label="Demo Street, Alupay, Tayabas City",
        )
        self.pending_worker = User.objects.create_user(username="pending-worker", password="password")
        UserProfile.objects.create(
            user=self.pending_worker,
            role=UserProfile.ROLE_WORKER,
            verification_status="pending",
            location_label="Demo Street, Alitao, Tayabas City",
        )
        self.rejected_worker = User.objects.create_user(username="rejected-worker", password="password")
        UserProfile.objects.create(
            user=self.rejected_worker,
            role=UserProfile.ROLE_WORKER,
            verification_status="rejected",
            location_label="Demo Street, Alupay, Tayabas City",
        )

        self.open_job = JobPosting.objects.create(
            household=self.household,
            title="Clean house",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Tomorrow morning",
            location_label="Demo Street, Alitao, Tayabas City",
            latitude=Decimal("14.0537324"),
            longitude=Decimal("121.5336724"),
            service_rate=Decimal("700.00"),
            worker_slots=2,
            status=JobPosting.STATUS_OPEN,
        )
        JobPosting.objects.create(
            household=self.household,
            title="Fix sink",
            job_type="Plumbing",
            required_skill="Plumbing",
            schedule="Today",
            location_label="Demo Street, Alupay, Tayabas City",
            latitude=Decimal("14.0580622"),
            longitude=Decimal("121.6089431"),
            service_rate=Decimal("900.00"),
            status=JobPosting.STATUS_COMPLETED,
        )
        JobApplication.objects.create(job=self.open_job, worker=self.worker, status=JobApplication.STATUS_PENDING)
        VerificationRequest.objects.create(
            worker=self.pending_worker,
            primary_id_name="id.png",
            secondary_doc_name="barangay-clearance.png",
            status=VerificationRequest.STATUS_PENDING,
        )
        VerificationRequest.objects.create(
            worker=self.rejected_worker,
            primary_id_name="id.png",
            secondary_doc_name="barangay-clearance.png",
            status=VerificationRequest.STATUS_REJECTED,
        )

    def test_dashboard_metrics_summary_comes_from_backend_models(self):
        metrics = build_dashboard_metrics()

        self.assertEqual(metrics["open_jobs"], 2)
        self.assertEqual(metrics["verified_workers"], 1)
        self.assertEqual(metrics["completed_jobs"], 1)
        self.assertEqual(metrics["active_applications"], 1)
        self.assertEqual(metrics["analytics"]["summary"]["totalUsers"], 4)
        self.assertEqual(metrics["analytics"]["summary"]["totalWorkers"], 3)
        self.assertEqual(metrics["analytics"]["summary"]["households"], 1)
        self.assertEqual(metrics["analytics"]["summary"]["totalJobPostings"], 2)
        self.assertEqual(metrics["analytics"]["summary"]["activeApplications"], 1)
        self.assertEqual(metrics["analytics"]["summary"]["completedServices"], 1)
        self.assertEqual(metrics["analytics"]["summary"]["cancelledRequests"], 0)
        self.assertEqual(metrics["analytics"]["summary"]["ongoingMatches"], 0)
        self.assertEqual(metrics["analytics"]["summary"]["verifiedUsers"], 1)
        # "Pending" is an account with an ID waiting in the queue -- the same
        # basis apps.reports.services uses. The household's profile defaults
        # to pending but it never submitted anything, so it is not counted.
        self.assertEqual(metrics["analytics"]["summary"]["pendingVerifications"], 1)
        self.assertEqual(metrics["analytics"]["summary"]["rejectedVerifications"], 1)
        # The admin queue's depth is a separate number: only one account has
        # actually submitted a request that is still waiting.
        self.assertEqual(metrics["analytics"]["summary"]["pendingVerificationRequests"], 1)
        self.assertEqual(metrics["analytics"]["summary"]["averageWorkerRating"], "4.50")

    def test_average_worker_rating_is_weighted_by_review_count(self):
        # A plain Avg("average_rating") across profiles would give this
        # worker (1 review) the same weight as self.worker (2 reviews at
        # 4.50), producing (4.50 + 2.00) / 2 = 3.25. Weighted by rating_count
        # instead: (4.50*2 + 2.00*1) / 3 = 3.666...
        heavily_reviewed_low_rated = User.objects.create_user(username="low-rated-worker", password="password")
        UserProfile.objects.create(
            user=heavily_reviewed_low_rated,
            role=UserProfile.ROLE_WORKER,
            verification_status="verified",
            average_rating=Decimal("2.00"),
            rating_count=1,
            location_label="Demo Street, Alitao, Tayabas City",
        )

        metrics = build_dashboard_metrics()

        self.assertEqual(metrics["analytics"]["summary"]["averageWorkerRating"], "3.67")

    def test_dashboard_metrics_include_chart_and_table_datasets(self):
        analytics = build_dashboard_metrics()["analytics"]

        geographic_analytics = analytics["geographicAnalytics"]
        rate_transparency = analytics["rateTransparency"]
        alitao_demand = next(item for item in geographic_analytics["barangayDemand"] if item["barangay"] == "Alitao")
        alupay_workers = next(item for item in geographic_analytics["workerAvailability"] if item["barangay"] == "Alupay")
        cleaning_rate = next(item for item in rate_transparency["averageRatesByCategory"] if item["skill"] == "House Cleaning")
        current_pricing_trend = rate_transparency["pricingTrends"][-1]
        heat_map_alitao = next(item for item in analytics["heatMapData"] if item["barangay"] == "Alitao")

        self.assertEqual(len(analytics["monthlyJobRequests"]), 6)
        self.assertEqual(len(rate_transparency["pricingTrends"]), 6)
        self.assertEqual(analytics["barangayJobAnalytics"], geographic_analytics["barangayDemand"])
        self.assertEqual(analytics["barangayWorkerAnalytics"], geographic_analytics["workerAvailability"])
        self.assertEqual(analytics["serviceRateSummary"], rate_transparency["averageRatesByCategory"][:5])
        self.assertEqual(alitao_demand["jobs"], 1)
        self.assertEqual(alupay_workers["workers"], 2)
        # The line chart's list carries both counts for each barangay, most
        # demand first, so a barangay never reads 0 workers just for missing
        # the separate worker ranking.
        demand_vs_supply = geographic_analytics["demandVsSupply"]
        self.assertLessEqual(len(demand_vs_supply), 10)
        by_barangay = {row["barangay"]: row for row in demand_vs_supply}
        self.assertEqual(by_barangay["Alitao"]["jobs"], 1)
        self.assertEqual(by_barangay["Alupay"]["workers"], 2)
        jobs_in_order = [row["jobs"] for row in demand_vs_supply]
        self.assertEqual(jobs_in_order, sorted(jobs_in_order, reverse=True))
        self.assertEqual(cleaning_rate["count"], 1)
        self.assertEqual(cleaning_rate["averageRate"], 700.0)
        self.assertEqual(current_pricing_trend["postings"], 2)
        self.assertEqual(current_pricing_trend["averageRate"], 800.0)
        self.assertEqual(heat_map_alitao["jobs"], 1)
        self.assertEqual(heat_map_alitao["pendingVerifications"], 1)
        # 4.50 rounds up (half-up, not Python's banker's rounding) into the
        # "5 stars" bucket at index 0.
        self.assertEqual(analytics["ratingDistribution"][0]["count"], 1)


class RatingDistributionRoundingTests(TestCase):
    """roadmap audit LOW #31: Python's round() rounds half-to-even, so 4.5
    and 2.5 bucketed down and a sub-0.5 rating vanished from the chart
    entirely."""

    @staticmethod
    def _profile(rating, count=1):
        return SimpleNamespace(average_rating=Decimal(str(rating)), rating_count=count)

    def _counts_by_stars(self, ratings):
        distribution = _build_rating_distribution([self._profile(rating) for rating in ratings])
        return {int(item["stars"].split()[0]): item["count"] for item in distribution}

    def test_half_point_ratings_round_up_not_to_even(self):
        counts = self._counts_by_stars([4.5, 2.5])
        self.assertEqual(counts[5], 1)
        self.assertEqual(counts[3], 1)
        self.assertEqual(counts[4], 0)
        self.assertEqual(counts[2], 0)

    def test_a_sub_half_star_rating_is_clamped_into_the_1_star_bucket_instead_of_vanishing(self):
        counts = self._counts_by_stars([0.3])
        self.assertEqual(counts[1], 1)
        self.assertEqual(sum(counts.values()), 1)


class DashboardMetricsPermissionTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.url = reverse("dashboard-metrics")
        self.user = User.objects.create_user(username="regular", password="password")
        self.admin = User.objects.create_user(username="staff-admin", password="password", is_staff=True)

    def test_dashboard_metrics_requires_authentication(self):
        response = self.client.get(self.url)

        self.assertEqual(response.status_code, 401)

    def test_dashboard_metrics_rejects_non_staff_users(self):
        self.client.force_authenticate(user=self.user)

        response = self.client.get(self.url)

        self.assertEqual(response.status_code, 403)

    def test_dashboard_metrics_allows_staff_admins(self):
        self.client.force_authenticate(user=self.admin)

        response = self.client.get(self.url)

        self.assertEqual(response.status_code, 200)
