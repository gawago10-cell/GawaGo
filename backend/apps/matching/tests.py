import json

from django.contrib.auth.models import User
from django.test import TestCase, override_settings
from django.urls import reverse
from decimal import Decimal
from unittest.mock import patch

from apps.accounts.models import UserProfile, WorkerAvailability
from apps.common.authentication import create_jwt_token
from apps.jobs.models import JobPosting
from apps.matching.models import RouteDistanceCache
from apps.matching.services import fetch_osrm_route, normalize_skill_label, skill_matches


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
            preferred_date="2026-06-02",
            preferred_time="09:30",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
        )
        self.client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': self.household.id})}"

    def test_anonymous_user_cannot_fetch_recommended_workers(self):
        self.client.defaults.pop("HTTP_AUTHORIZATION", None)

        response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 403)

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

    def test_matching_keeps_legacy_jobs_without_structured_datetime_compatible(self):
        self.job.preferred_date = None
        self.job.preferred_time = None
        self.job.save(update_fields=["preferred_date", "preferred_time"])

        response = self.client.get(reverse("recommended-workers"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 200)
        usernames = {item["worker_username"] for item in response.data["results"]}
        self.assertEqual(usernames, {"available-worker", "unavailable-worker"})

    def test_matching_ranks_alias_skill_matches_first(self):
        self.job.preferred_date = None
        self.job.preferred_time = None
        self.job.required_skill = "house cleaning"
        self.job.save(update_fields=["preferred_date", "preferred_time", "required_skill"])
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
        self.assertEqual(cached_result["route_points"][0], [13.9622745, 121.5632841])
        self.assertEqual(RouteDistanceCache.objects.count(), 1)

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
