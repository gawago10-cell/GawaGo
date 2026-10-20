import json

from datetime import timedelta
from urllib import error

from django.contrib.auth.models import User
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from decimal import Decimal
from unittest.mock import patch

from apps.accounts.models import UserProfile, WorkerAvailability
from apps.common.authentication import create_jwt_token
from apps.jobs.models import JobApplication, JobPosting
from apps.matching.models import RouteDistanceCache
from apps.matching.services import (
    fetch_osrm_route,
    fetch_road_route,
    normalize_skill_label,
    skill_matches,
)
from apps.notifications.models import Notification


class SkillNormalizationTests(TestCase):
    def test_skill_matching_is_case_insensitive(self):
        self.assertTrue(skill_matches("house cleaning", ["HOUSE CLEANING"]))

    def test_skill_matching_uses_aliases(self):
        self.assertTrue(skill_matches("House Cleaning", ["cleaning"]))
        self.assertTrue(skill_matches("Plumbing", ["plumber"]))
        self.assertTrue(skill_matches("Electrical Work", ["electrician"]))
        self.assertTrue(skill_matches("Aircon Repair/Cleaning", ["aircon repair"]))

    def test_unknown_skill_normalizes_consistently(self):
        self.assertEqual(normalize_skill_label("Pet Care"), "pet_care")


class RoadRoutingProviderTests(TestCase):
    @override_settings(OSRM_DIRECTIONS_URL="https://router.example/route/v1/driving")
    def test_osrm_route_returns_driving_distance_and_geometry(self):
        payload = {
            "code": "Ok",
            "routes": [
                {
                    "distance": 2450.5,
                    "geometry": {
                        "coordinates": [
                            [121.5632841, 13.9622745],
                            [121.5812345, 13.9787654],
                        ]
                    },
                }
            ],
        }

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return json.dumps(payload).encode("utf-8")

        with patch("apps.matching.services.request.urlopen", return_value=FakeResponse()) as urlopen:
            route = fetch_osrm_route(13.9622745, 121.5632841, 13.9787654, 121.5812345)

        self.assertEqual(route["distance_km"], 2.4505)
        self.assertEqual(
            route["route_points"],
            [
                [13.9622745, 121.5632841],
                [13.9787654, 121.5812345],
            ],
        )
        self.assertIn("geometries=geojson", urlopen.call_args.args[0].full_url)

    OSRM_RESULT = {"distance_km": 3.58, "route_points": [[13.96, 121.56], [13.98, 121.58]]}

    @override_settings(OPENROUTESERVICE_API_KEY="a-configured-key")
    def test_a_failing_openrouteservice_falls_back_to_osrm(self):
        """A configured key that stops working -- daily quota spent, the
        40/min rate limit tripped by a job-match pass, an expired key, an
        outage -- used to return nothing at all, so every distance on both
        clients read "Road distance unavailable". An unset key already
        degraded to OSRM, so a broken one must not be worse than no key."""
        failures = [
            error.HTTPError("https://ors.example", 403, "Quota exceeded", {}, None),
            error.HTTPError("https://ors.example", 401, "Invalid key", {}, None),
            error.URLError("connection refused"),
            TimeoutError("timed out"),
            ValueError("not json"),
        ]
        for failure in failures:
            with self.subTest(failure=type(failure).__name__):
                with patch("apps.matching.services.request.urlopen", side_effect=failure), patch(
                    "apps.matching.services.fetch_osrm_route", return_value=self.OSRM_RESULT
                ) as osrm:
                    route = fetch_road_route(13.9622745, 121.5632841, 13.9787654, 121.5812345)

                self.assertEqual(route, self.OSRM_RESULT)
                osrm.assert_called_once()

    @override_settings(OPENROUTESERVICE_API_KEY="a-configured-key")
    def test_a_200_with_no_usable_distance_falls_back_to_osrm(self):
        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return json.dumps({"features": []}).encode("utf-8")

        with patch("apps.matching.services.request.urlopen", return_value=FakeResponse()), patch(
            "apps.matching.services.fetch_osrm_route", return_value=self.OSRM_RESULT
        ) as osrm:
            route = fetch_road_route(13.9622745, 121.5632841, 13.9787654, 121.5812345)

        self.assertEqual(route, self.OSRM_RESULT)
        osrm.assert_called_once()

    @override_settings(OPENROUTESERVICE_API_KEY="a-configured-key")
    def test_a_working_openrouteservice_is_not_sent_to_osrm(self):
        payload = {
            "features": [
                {
                    "properties": {"summary": {"distance": 4380.0}},
                    "geometry": {"coordinates": [[121.5632841, 13.9622745], [121.5812345, 13.9787654]]},
                }
            ]
        }

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return json.dumps(payload).encode("utf-8")

        with patch("apps.matching.services.request.urlopen", return_value=FakeResponse()), patch(
            "apps.matching.services.fetch_osrm_route"
        ) as osrm:
            route = fetch_road_route(13.9622745, 121.5632841, 13.9787654, 121.5812345)

        self.assertEqual(route["distance_km"], 4.38)
        osrm.assert_not_called()

    def test_an_unset_key_still_goes_straight_to_osrm(self):
        with override_settings(OPENROUTESERVICE_API_KEY=""):
            with patch(
                "apps.matching.services.fetch_osrm_route", return_value=self.OSRM_RESULT
            ) as osrm, patch("apps.matching.services.request.urlopen") as urlopen:
                route = fetch_road_route(13.9622745, 121.5632841, 13.9787654, 121.5812345)

        self.assertEqual(route, self.OSRM_RESULT)
        osrm.assert_called_once()
        urlopen.assert_not_called()


class RecommendedWorkersAvailabilityTests(TestCase):
    def setUp(self):
        self.household = User.objects.create_user(username="household-match", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.available_worker = User.objects.create_user(username="available-worker", password="password")
        self.unavailable_worker = User.objects.create_user(username="unavailable-worker", password="password")
        UserProfile.objects.create(
            user=self.available_worker,
            role=UserProfile.ROLE_WORKER,
            skills=["House Cleaning"],
            latitude="13.9622745",
            longitude="121.5632841",
            verification_status="verified",
        )
        UserProfile.objects.create(
            user=self.unavailable_worker,
            role=UserProfile.ROLE_WORKER,
            skills=["House Cleaning"],
            latitude="13.9622745",
            longitude="121.5632841",
            verification_status="verified",
        )
        self.job = JobPosting.objects.create(
            household=self.household,
            title="Structured cleaning",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="One-Time on 2026-06-02 at 09:30",
            schedule_type="One-Time",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
        )
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': self.household.id})}"

    def test_anonymous_user_cannot_fetch_recommended_workers(self):
        self.client.defaults.pop("HTTP_AUTHORIZATION", None)

        response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 401)

    def test_unrelated_household_cannot_fetch_recommended_workers(self):
        other_household = User.objects.create_user(username="other-household-match", password="password")
        UserProfile.objects.create(user=other_household, role=UserProfile.ROLE_HOUSEHOLD)
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': other_household.id})}"

        response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 403)

    def test_worker_cannot_fetch_recommended_workers_for_household_job(self):
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': self.available_worker.id})}"

        response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 403)

    def test_staff_can_fetch_recommended_workers_for_any_job(self):
        admin = User.objects.create_superuser(username="matching-admin", password="password")
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': admin.id})}"

        response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 200)

    def test_matching_keeps_workers_regardless_of_requested_datetime(self):
        WorkerAvailability.objects.create(
            worker=self.available_worker,
            date="2026-06-02",
            start_time="09:00",
            end_time="10:00",
        )
        WorkerAvailability.objects.create(
            worker=self.unavailable_worker,
            date="2026-06-02",
            start_time="13:00",
            end_time="14:00",
        )

        response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 200)
        usernames = [item["worker_username"] for item in response.data["results"]]
        self.assertEqual(set(usernames), {"available-worker", "unavailable-worker"})
        self.assertTrue(all(item["available_at_requested_time"] for item in response.data["results"]))

    def test_matching_keeps_workers_without_availability(self):
        response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            {item["worker_username"] for item in response.data["results"]},
            {"available-worker", "unavailable-worker"},
        )

    def test_matching_does_not_filter_date_specific_availability(self):
        WorkerAvailability.objects.create(
            worker=self.available_worker,
            date="2026-06-02",
            start_time="00:00",
            end_time="23:59",
            is_available=False,
        )

        response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            {item["worker_username"] for item in response.data["results"]},
            {"available-worker", "unavailable-worker"},
        )

    def test_match_results_carry_the_profile_fields_the_cards_render(self):
        profile = self.available_worker.profile
        profile.bio = "Five years of deep cleaning."
        profile.location_label = "Poblacion, Tayabas"
        profile.rating_count = 4
        profile.save(update_fields=["bio", "location_label", "rating_count"])
        self.available_worker.first_name = "Ava"
        self.available_worker.last_name = "Lopez"
        self.available_worker.save(update_fields=["first_name", "last_name"])
        finished = JobPosting.objects.create(
            household=self.household,
            title="Past job",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="One-Time",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            status=JobPosting.STATUS_COMPLETED,
        )
        JobApplication.objects.create(
            job=finished,
            worker=self.available_worker,
            status=JobApplication.STATUS_COMPLETED,
        )

        response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 200)
        result = next(
            item for item in response.data["results"] if item["worker_username"] == "available-worker"
        )
        self.assertEqual(result["worker_name"], "Ava Lopez")
        self.assertEqual(result["worker_bio"], "Five years of deep cleaning.")
        self.assertEqual(result["worker_location_label"], "Poblacion, Tayabas")
        self.assertEqual(result["worker_rating_count"], 4)
        self.assertEqual(result["worker_completed_jobs"], 1)
        self.assertEqual(result["worker_profile_photo_url"], "")

    def test_matching_ranks_alias_skill_matches_first(self):
        self.job.required_skill = "house cleaning"
        self.job.save(update_fields=["required_skill"])
        alias_worker = User.objects.create_user(username="alias-worker", password="password")
        UserProfile.objects.create(
            user=alias_worker,
            role=UserProfile.ROLE_WORKER,
            skills=["cleaning"],
            latitude="13.9622745",
            longitude="121.5632841",
        )

        response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 200)
        alias_result = next(item for item in response.data["results"] if item["worker_username"] == "alias-worker")
        self.assertTrue(alias_result["matches_skill"])

    @override_settings(OPENROUTESERVICE_API_KEY="")
    def test_matching_does_not_fall_back_to_straight_line_distance(self):
        WorkerAvailability.objects.create(
            worker=self.available_worker,
            date="2026-06-02",
            start_time="09:00",
            end_time="10:00",
        )
        with patch("apps.matching.services.fetch_osrm_route", return_value=None):
            response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["results"]), 2)
        self.assertTrue(all(item["distance_km"] is None for item in response.data["results"]))
        self.assertTrue(all(item["distance_label"] == "Road distance unavailable" for item in response.data["results"]))


class RecommendedWorkersRankingTests(TestCase):
    def setUp(self):
        self.household = User.objects.create_user(username="ranking-household", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.job = JobPosting.objects.create(
            household=self.household,
            title="Ranking job",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Flexible schedule",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            max_distance_km=10.0,
        )
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': self.household.id})}"

    def create_worker_profile(
        self,
        username,
        skills,
        verification_status="pending",
        latitude="13.9622745",
        longitude="121.5632841",
        average_rating=None,
        daily_rate=None,
    ):
        user = User.objects.create_user(username=username, password="password")
        return UserProfile.objects.create(
            user=user,
            role=UserProfile.ROLE_WORKER,
            skills=skills,
            verification_status=verification_status,
            latitude=latitude,
            longitude=longitude,
            average_rating=average_rating,
            rating_count=1 if average_rating is not None else 0,
            daily_rate=daily_rate,
        )

    def fake_road_route(self, lat1, lon1, lat2, lon2):
        if str(lat2) == "13.9622745" and str(lon2) == "121.5632841":
            distance_km = 0.1
        elif str(lat2) == "13.9800000" and str(lon2) == "121.5800000":
            distance_km = 7.5
        else:
            distance_km = 3.0
        return {
            "distance_km": distance_km,
            "route_points": [[float(lat1), float(lon1)], [float(lat2), float(lon2)]],
        }

    def get_ranked_usernames(self):
        with patch("apps.matching.services.fetch_road_route", self.fake_road_route):
            response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})
        self.assertEqual(response.status_code, 200)
        return [item["worker_username"] for item in response.data["results"]]

    def test_matching_caches_backend_route_distance_and_points(self):
        self.create_worker_profile("cached-worker", ["House Cleaning"], verification_status="verified")

        with patch("apps.matching.services.fetch_road_route", side_effect=self.fake_road_route) as route_fetch:
            first_response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})
            second_response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(first_response.status_code, 200)
        self.assertEqual(second_response.status_code, 200)
        self.assertEqual(route_fetch.call_count, 1)
        cached_result = first_response.data["results"][0]
        self.assertEqual(cached_result["distance_km"], 0.1)
        # The route is cached server-side for later (post-hire) use, but a
        # candidate's route line is never sent -- its far end is their home.
        self.assertNotIn("route_points", cached_result)
        self.assertEqual(RouteDistanceCache.objects.get().route_points[0], [13.9622745, 121.5632841])

    def test_unlimited_boundary_bypasses_max_distance_km_in_smart_matching(self):
        # A job can end up with geographic_boundary='unlimited' while
        # max_distance_km still holds a small number (the two fields are
        # written independently, with nothing keeping them in sync). The AI
        # ranker already treats 'unlimited' as no limit regardless of
        # max_distance_km; Smart Matching's build_match_results must agree,
        # or the same job produces different candidate pools on the two
        # screens.
        self.job.max_distance_km = 1.0
        self.job.geographic_boundary = "unlimited"
        self.job.save(update_fields=["max_distance_km", "geographic_boundary"])
        self.create_worker_profile(
            "far-worker", ["House Cleaning"], verification_status="verified",
            latitude="13.9800000", longitude="121.5800000",
        )

        self.assertIn("far-worker", self.get_ranked_usernames())

    def test_skill_match_ranks_before_other_factors(self):
        self.create_worker_profile("skilled-worker", ["cleaning"], verification_status="pending")
        self.create_worker_profile("near-verified-worker", ["Plumbing"], verification_status="verified")

        self.assertEqual(self.get_ranked_usernames()[0], "skilled-worker")

    def test_verification_ranks_before_distance_when_skill_matches(self):
        self.create_worker_profile(
            "verified-far-worker",
            ["House Cleaning"],
            verification_status="verified",
            latitude="13.9800000",
            longitude="121.5800000",
        )
        self.create_worker_profile(
            "unverified-near-worker",
            ["House Cleaning"],
            verification_status="pending",
        )

        self.assertEqual(self.get_ranked_usernames()[0], "verified-far-worker")

    def test_distance_ranks_before_rating_when_skill_and_verification_match(self):
        self.create_worker_profile(
            "near-lower-rated-worker",
            ["House Cleaning"],
            verification_status="verified",
            average_rating=Decimal("3.00"),
        )
        self.create_worker_profile(
            "far-higher-rated-worker",
            ["House Cleaning"],
            verification_status="verified",
            latitude="13.9800000",
            longitude="121.5800000",
            average_rating=Decimal("5.00"),
        )

        self.assertEqual(self.get_ranked_usernames()[0], "near-lower-rated-worker")

    def test_rating_ranks_before_rate_when_skill_verification_and_distance_match(self):
        self.create_worker_profile(
            "higher-rated-expensive-worker",
            ["House Cleaning"],
            verification_status="verified",
            average_rating=Decimal("5.00"),
            daily_rate=Decimal("900.00"),
        )
        self.create_worker_profile(
            "lower-rated-rate-fit-worker",
            ["House Cleaning"],
            verification_status="verified",
            average_rating=Decimal("4.00"),
            daily_rate=Decimal("500.00"),
        )

        self.assertEqual(self.get_ranked_usernames()[0], "higher-rated-expensive-worker")

    def test_rate_fit_breaks_otherwise_equal_ties(self):
        self.create_worker_profile(
            "rate-fit-worker",
            ["House Cleaning"],
            verification_status="verified",
            average_rating=Decimal("5.00"),
            daily_rate=Decimal("500.00"),
        )
        self.create_worker_profile(
            "over-budget-worker",
            ["House Cleaning"],
            verification_status="verified",
            average_rating=Decimal("5.00"),
            daily_rate=Decimal("900.00"),
        )

        self.assertEqual(self.get_ranked_usernames()[0], "rate-fit-worker")


class RecommendedWorkersAiRankingTests(TestCase):
    """Household-facing AI matching: ?rank=ai scores the same candidates with
    the content-based recommender instead of the Smart Matching rule order.
    """

    def setUp(self):
        self.household = User.objects.create_user(username="ai-household", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.job = JobPosting.objects.create(
            household=self.household,
            title="AI ranking job",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Flexible schedule",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            max_distance_km=10.0,
        )
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': self.household.id})}"

    def create_worker_profile(self, username, skills, verification_status="pending", latitude="13.9622745", longitude="121.5632841"):
        user = User.objects.create_user(username=username, password="password")
        return UserProfile.objects.create(
            user=user,
            role=UserProfile.ROLE_WORKER,
            skills=skills,
            verification_status=verification_status,
            latitude=latitude,
            longitude=longitude,
        )

    def fake_road_route(self, lat1, lon1, lat2, lon2):
        distance_km = 0.1 if str(lat2) == "13.9622745" else 7.5
        return {
            "distance_km": distance_km,
            "route_points": [[float(lat1), float(lon1)], [float(lat2), float(lon2)]],
        }

    def fetch_results(self, **params):
        with patch("apps.matching.services.fetch_road_route", self.fake_road_route):
            response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id, **params})
        self.assertEqual(response.status_code, 200)
        return response.data

    def test_ai_rank_prefers_skill_and_proximity_over_verification(self):
        self.create_worker_profile(
            "verified-far-worker",
            ["House Cleaning"],
            verification_status="verified",
            latitude="13.9800000",
            longitude="121.5800000",
        )
        self.create_worker_profile("unverified-near-worker", ["House Cleaning"])

        data = self.fetch_results(rank="ai")

        self.assertEqual(data["rank"], "ai")
        self.assertEqual(data["results"][0]["worker_username"], "unverified-near-worker")

    def test_default_rank_keeps_smart_matching_order(self):
        self.create_worker_profile(
            "verified-far-worker",
            ["House Cleaning"],
            verification_status="verified",
            latitude="13.9800000",
            longitude="121.5800000",
        )
        self.create_worker_profile("unverified-near-worker", ["House Cleaning"])

        data = self.fetch_results()

        self.assertEqual(data["rank"], "smart")
        self.assertEqual(data["results"][0]["worker_username"], "verified-far-worker")

    def test_every_result_carries_the_explainability_breakdown(self):
        self.create_worker_profile("skilled-worker", ["House Cleaning"])

        result = self.fetch_results(rank="ai")["results"][0]

        self.assertTrue(result["exact_skill_match"])
        self.assertGreater(result["ai_score"], 0)
        self.assertAlmostEqual(
            result["skill_contribution"] + result["proximity_contribution"],
            result["ai_score"],
            places=3,
        )

    def test_worker_without_location_is_kept_but_scores_zero(self):
        self.create_worker_profile("skilled-worker", ["House Cleaning"])
        self.create_worker_profile("no-location-worker", ["House Cleaning"], latitude=None, longitude=None)

        results = self.fetch_results(rank="ai")["results"]
        scores = {item["worker_username"]: item["ai_score"] for item in results}

        self.assertEqual(scores["no-location-worker"], 0.0)
        self.assertEqual(results[-1]["worker_username"], "no-location-worker")

    def test_smart_rank_skips_the_ai_scoring_pass_entirely(self):
        """roadmap audit LOW #38: rank=smart never reads the AI score
        breakdown, so the (expensive, content-based) scoring pass shouldn't
        run at all for it -- only for rank=ai, which actually uses it."""
        self.create_worker_profile("smart-only-worker", ["House Cleaning"])

        with patch("apps.matching.views.get_recommended_workers") as mocked:
            mocked.return_value = []
            results = self.fetch_results()["results"]
        mocked.assert_not_called()
        self.assertEqual(results[0]["ai_score"], 0.0)
        self.assertFalse(results[0]["exact_skill_match"])

        with patch("apps.matching.views.get_recommended_workers") as mocked:
            mocked.return_value = []
            self.fetch_results(rank="ai")
        mocked.assert_called_once()


JOB_SITE = ("13.9622745", "121.5632841")


def _route_for(distances):
    """Fake fetch_road_route: distance keyed by the worker's latitude string;
    an Exception value is raised instead (routing service failure)."""

    def fake(lat1, lon1, lat2, lon2):
        outcome = distances.get(str(lat2), 1.0)
        if isinstance(outcome, Exception):
            raise outcome
        return {"distance_km": outcome, "route_points": []}

    return fake


@override_settings(
    ENABLE_JOB_MATCH_NOTIFICATIONS=True, JOB_MATCH_NOTIFY_THRESHOLD=0.5, BACKGROUND_TASK_BACKEND="sync"
)
class JobMatchNotificationTaskTests(TestCase):
    """The job-match pass runs after the job commits, outside the request,
    and is safe to run more than once."""

    def setUp(self):
        self.household = User.objects.create_user(username="notify-household", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD, verification_status="verified")
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': self.household.id})}"

    def make_worker(self, username, skills=("House Cleaning",), latitude=JOB_SITE[0], longitude=JOB_SITE[1], **extra):
        user = User.objects.create_user(username=username, password="password")
        UserProfile.objects.create(
            user=user, role=UserProfile.ROLE_WORKER, skills=list(skills), latitude=latitude, longitude=longitude, **extra
        )
        return user

    def make_job(self, **extra):
        values = dict(
            household=self.household, title="Cleaning job", job_type="House Cleaning", required_skill="House Cleaning",
            schedule="Flexible", location_label="Isabang, Tayabas", latitude=JOB_SITE[0], longitude=JOB_SITE[1],
            service_rate="500.00", status=JobPosting.STATUS_OPEN, max_distance_km=10.0, geographic_boundary="10km",
        )
        values.update(extra)
        return JobPosting.objects.create(**values)

    def post_job(self):
        return self.client.post(
            reverse("job-list"),
            {
                "title": "Cleaning job", "job_type": "House Cleaning", "required_skill": "House Cleaning",
                "schedule": "Saturday", "location_label": "Isabang, Tayabas", "latitude": JOB_SITE[0],
                "longitude": JOB_SITE[1], "service_rate": "500.00", "geographic_boundary": "10km", "max_distance_km": 10,
            },
            content_type="application/json",
        )

    def notified(self, job=None):
        rows = Notification.objects.filter(notification_type=Notification.TYPE_JOB_MATCH)
        if job is not None:
            rows = rows.filter(related_job_id=job.id)
        return sorted(rows.values_list("recipient__username", flat=True))

    def run_pass(self, job, distances=None):
        from apps.matching.tasks import run_job_match_notifications

        with patch("apps.matching.services.fetch_road_route", side_effect=_route_for(distances or {})):
            return run_job_match_notifications(job.id)

    # --- request / commit behaviour --------------------------------------

    def test_post_does_no_scoring_routing_or_notifying_during_the_request(self):
        self.make_worker("cleaner")
        with patch("apps.matching.services.fetch_road_route") as route, patch(
            "apps.matching.tasks.score_pair_with_distance"
        ) as score, patch("apps.matching.tasks.create_notification") as notify, self.captureOnCommitCallbacks(
            execute=False
        ) as callbacks:
            response = self.post_job()

        self.assertEqual(response.status_code, 201)
        route.assert_not_called()
        score.assert_not_called()
        notify.assert_not_called()
        self.assertEqual(len(callbacks), 1, "exactly one on_commit callback is scheduled")
        self.assertEqual(self.notified(), [])

    def test_after_commit_the_pass_is_enqueued_with_the_job_id(self):
        from apps.matching.tasks import JOB_MATCH_TASK_TIMEOUT_SECONDS, run_job_match_notifications

        with patch("apps.jobs.views.enqueue") as enqueue, self.captureOnCommitCallbacks(execute=True):
            response = self.post_job()

        enqueue.assert_called_once_with(
            run_job_match_notifications, response.data["id"], timeout=JOB_MATCH_TASK_TIMEOUT_SECONDS
        )

    def test_rolled_back_create_enqueues_nothing(self):
        from django.db import transaction

        with patch("apps.jobs.views.enqueue") as enqueue, self.captureOnCommitCallbacks(execute=True) as callbacks:
            with self.assertRaises(RuntimeError):
                with transaction.atomic():
                    self.assertEqual(self.post_job().status_code, 201)
                    raise RuntimeError("roll the job back")

        enqueue.assert_not_called()
        self.assertEqual(callbacks, [])
        self.assertFalse(JobPosting.objects.exists())

    def test_post_end_to_end_with_sync_backend_notifies_after_commit(self):
        self.make_worker("cleaner")
        with patch("apps.matching.services.fetch_road_route", side_effect=_route_for({})), \
                self.captureOnCommitCallbacks(execute=True):
            self.post_job()
        self.assertEqual(self.notified(), ["cleaner"])

    def test_disabled_setting_schedules_nothing(self):
        with override_settings(ENABLE_JOB_MATCH_NOTIFICATIONS=False), patch("apps.jobs.views.enqueue") as enqueue, \
                self.captureOnCommitCallbacks(execute=True):
            self.post_job()
        enqueue.assert_not_called()

    # --- the pass itself --------------------------------------------------

    def test_pass_notifies_matching_workers_only(self):
        self.make_worker("cleaner")
        self.make_worker("far-cleaner", latitude="14.0500000")
        self.make_worker("plumber", skills=["Plumbing"])
        job = self.make_job()

        sent = self.run_pass(job, {"14.0500000": 25.0})

        self.assertEqual(sent, 1)
        self.assertEqual(self.notified(job), ["cleaner"])
        note = Notification.objects.get(notification_type=Notification.TYPE_JOB_MATCH)
        self.assertEqual(note.related_job_id, job.id)
        self.assertEqual(note.action_type, Notification.ACTION_JOB_DETAIL)

    def test_running_twice_creates_no_duplicate_notifications(self):
        self.make_worker("cleaner")
        self.make_worker("cleaner-2", latitude="13.9630000")
        job = self.make_job()

        self.assertEqual(self.run_pass(job), 2)
        self.assertEqual(self.run_pass(job), 0)
        self.assertEqual(self.notified(job), ["cleaner", "cleaner-2"])

    def test_overlapping_runs_are_stopped_by_the_database_constraint(self):
        from apps.matching import tasks

        worker = self.make_worker("cleaner")
        job = self.make_job()
        Notification.objects.create(
            recipient=worker, notification_type=Notification.TYPE_JOB_MATCH, title="x", message="x", related_job_id=job.id
        )
        profile = UserProfile.objects.get(user=worker)

        self.assertFalse(tasks._notify(job, profile, {"ai_score": 0.9}))
        self.assertEqual(self.notified(job), ["cleaner"])

    def test_routing_failure_for_one_worker_does_not_stop_the_others(self):
        self.make_worker("unroutable", latitude="13.9630000")
        self.make_worker("routable", latitude="13.9640000")
        job = self.make_job()

        self.run_pass(job, {"13.9630000": OSError("routing service down")})

        # The unroutable worker falls back to straight-line distance (~0.1 km).
        self.assertEqual(self.notified(job), ["routable", "unroutable"])

    def test_routing_returning_nothing_falls_back_to_straight_line(self):
        from apps.matching import tasks

        self.make_worker("cleaner", latitude="13.9630000")
        job = self.make_job()
        with patch("apps.matching.services.fetch_road_route", return_value=None), \
                self.assertLogs("apps.matching.tasks", level="INFO") as logs:
            sent = tasks.run_job_match_notifications(job.id)

        self.assertEqual(sent, 1)
        self.assertTrue(any("routing_fallbacks=1" in line for line in logs.output), logs.output)
        self.assertTrue(any("job-match: start" in line for line in logs.output))

    def test_one_workers_scoring_error_does_not_stop_the_others(self):
        from apps.matching import tasks

        self.make_worker("cleaner")
        self.make_worker("broken", latitude="13.9630000")
        job = self.make_job()
        real_score = tasks.score_pair_with_distance

        def flaky(job_, profile, distance_km):
            if profile.user.username == "broken":
                raise ValueError("bad worker data")
            return real_score(job_, profile, distance_km)

        with patch("apps.matching.tasks.score_pair_with_distance", side_effect=flaky):
            self.run_pass(job)
        self.assertEqual(self.notified(job), ["cleaner"])

    def test_deleted_or_closed_job_exits_quietly(self):
        from apps.matching.tasks import run_job_match_notifications

        self.make_worker("cleaner")
        closed = self.make_job(status=JobPosting.STATUS_CANCELLED)
        deleted = self.make_job()
        deleted_id = deleted.id
        deleted.delete()

        with patch("apps.matching.services.fetch_road_route") as route:
            self.assertEqual(run_job_match_notifications(closed.id), 0)
            self.assertEqual(run_job_match_notifications(deleted_id), 0)
        route.assert_not_called()
        self.assertEqual(self.notified(), [])

    def test_exact_skill_match_is_notified_despite_score_dilution_from_other_skills(self):
        self.make_worker("multi-skill", skills=["House Cleaning", "Cooking", "Laundry", "Gardening"])
        job = self.make_job()
        self.run_pass(job, {JOB_SITE[0]: 5.0})
        self.assertEqual(self.notified(job), ["multi-skill"])

    def test_suspended_or_inactive_workers_are_never_notified(self):
        self.make_worker("blocked-permanent", is_blocked=True)
        self.make_worker("blocked-timed", is_blocked=True, blocked_until=timezone.now() + timedelta(days=1))
        self.make_worker("blocked-expired", is_blocked=True, blocked_until=timezone.now() - timedelta(days=1))
        self.make_worker("eligible-worker")
        inactive = self.make_worker("inactive-worker")
        inactive.is_active = False
        inactive.save(update_fields=["is_active"])
        job = self.make_job()

        self.run_pass(job)
        self.assertEqual(self.notified(job), ["blocked-expired", "eligible-worker"])


class BackgroundDispatchTests(TestCase):
    def test_sync_backend_runs_inline(self):
        from apps.common.background import enqueue

        calls = []
        with override_settings(BACKGROUND_TASK_BACKEND="sync"):
            enqueue(calls.append, 7)
        self.assertEqual(calls, [7])

    def test_thread_backend_runs_in_a_daemon_thread(self):
        import threading

        from apps.common.background import enqueue

        seen = []
        with override_settings(BACKGROUND_TASK_BACKEND="thread"):
            thread = enqueue(lambda value: seen.append((value, threading.current_thread().name)), 3)
        thread.join(timeout=5)
        self.assertTrue(thread.daemon)
        self.assertEqual(seen[0][0], 3)
        self.assertNotEqual(seen[0][1], threading.current_thread().name)

    def test_django_q_backend_queues_by_dotted_path(self):
        from apps.common.background import enqueue
        from apps.matching.tasks import run_job_match_notifications

        with override_settings(BACKGROUND_TASK_BACKEND="django_q"), patch("django_q.tasks.async_task") as async_task:
            enqueue(run_job_match_notifications, 42, timeout=600)
        args, kwargs = async_task.call_args
        self.assertEqual(args, ("apps.matching.tasks.run_job_match_notifications", 42))
        self.assertEqual(kwargs["timeout"], 600)

    def test_unknown_backend_is_rejected(self):
        from apps.common.background import enqueue

        with override_settings(BACKGROUND_TASK_BACKEND="celery"), self.assertRaises(ValueError):
            enqueue(print, 1)


class RadiusWithoutRoutingTests(TestCase):
    """When the routing service is down the radius must still hold (AGENTS.md
    I.B): straight-line distance stands in for the missing road distance."""

    def setUp(self):
        RecommendedWorkersRankingTests.setUp(self)
        self.near = RecommendedWorkersRankingTests.create_worker_profile(
            self, "near-worker", ["House Cleaning"], verification_status="verified"
        )
        self.far = RecommendedWorkersRankingTests.create_worker_profile(
            self, "far-worker", ["House Cleaning"], verification_status="verified",
            latitude="14.3000000", longitude="121.9000000",
        )
        self.no_route = {"distance_km": None, "route_points": []}

    def test_smart_matching_excludes_workers_beyond_radius_without_routing(self):
        with patch("apps.matching.services.get_road_route_for_match", return_value=self.no_route):
            response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        usernames = [row["worker_username"] for row in response.json()["results"]]
        self.assertIn("near-worker", usernames)
        self.assertNotIn("far-worker", usernames)

    def test_ai_recommendation_keeps_nearby_job_without_routing(self):
        from apps.matching.recommendations import get_recommended_jobs

        with patch("apps.matching.recommendations.get_road_route_for_match", return_value=self.no_route):
            near_jobs = [row["job"].id for row in get_recommended_jobs(self.near.user)]
            far_jobs = [row["job"].id for row in get_recommended_jobs(self.far.user)]

        self.assertIn(self.job.id, near_jobs)
        self.assertNotIn(self.job.id, far_jobs)
