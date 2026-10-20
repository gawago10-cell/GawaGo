from unittest.mock import patch

from django.contrib.auth.models import User
from django.core import mail
from django.test import override_settings
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from apps.accounts.models import UserProfile
from apps.common.authentication import create_jwt_token
from apps.jobs.models import JobApplication, JobPosting, JobStatusEvent
from apps.jobs.services import complete_job
from apps.matching.models import RouteDistanceCache
from apps.notifications.models import Notification
from apps.reviews.models import Review


class JobPermissionTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.household = User.objects.create_user(username="household1", email="household1@example.com", password="password")
        self.other_household = User.objects.create_user(username="household2", email="household2@example.com", password="password")
        self.worker = User.objects.create_user(username="worker1", email="worker1@example.com", password="password")
        UserProfile.objects.create(
            user=self.household,
            role=UserProfile.ROLE_HOUSEHOLD,
            verification_status="verified",
        )
        UserProfile.objects.create(
            user=self.other_household,
            role=UserProfile.ROLE_HOUSEHOLD,
            verification_status="verified",
        )
        UserProfile.objects.create(
            user=self.worker,
            role=UserProfile.ROLE_WORKER,
            verification_status="verified",
        )
        self.job = JobPosting.objects.create(
            household=self.household,
            title="Cleaning help",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-01 09:00",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
        )
        self.application = JobApplication.objects.create(job=self.job, worker=self.worker)

    def test_anonymous_user_cannot_create_job_by_household_username(self):
        response = self.client.post(
            reverse("job-list"),
            {
                "household_username": self.household.username,
                "title": "Impersonated job",
                "job_type": "House Cleaning",
                "required_skill": "House Cleaning",
                "schedule": "2026-06-02 09:00",
                "schedule_type": "One-Time",
                "location_label": "Isabang, Tayabas",
                "latitude": "13.9622745",
                "longitude": "121.5632841",
                "service_rate": "500.00",
                "worker_slots": 1,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 401)
        self.assertFalse(JobPosting.objects.filter(title="Impersonated job").exists())

    def test_anonymous_job_detail_hides_applications(self):
        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["applications"], [])
        self.assertIsNone(response.data["current_worker_application"])
        self.assertEqual(response.data["hired_count"], 0)
        self.assertEqual(response.data["workers_needed"], 1)
        self.assertFalse(response.data["can_apply"])
        self.assertFalse(response.data["can_accept_hire_request"])
        self.assertFalse(response.data["can_request_completion"])
        self.assertFalse(response.data["can_review"])
        self.assertIsNone(response.data["latitude"])
        self.assertIsNone(response.data["longitude"])
        self.assertEqual(response.data["route_points"], [])

    def test_anonymous_job_list_hides_applications(self):
        response = self.client.get(reverse("job-list"))

        self.assertEqual(response.status_code, 200)
        first_job = response.data["results"][0]
        self.assertEqual(first_job["applications"], [])
        self.assertIsNone(first_job["latitude"])
        self.assertIsNone(first_job["longitude"])

    def test_household_can_filter_job_list_to_own_posts(self):
        JobPosting.objects.create(
            household=self.other_household,
            title="Other household job",
            job_type="Laundry",
            required_skill="Laundry",
            schedule="2026-06-03 10:00",
            location_label="Calumpang, Tayabas",
            latitude="13.9500000",
            longitude="121.5900000",
            service_rate="300.00",
        )
        self.client.force_authenticate(user=self.household)

        response = self.client.get(reverse("job-list"), {"mine": "true"})

        self.assertEqual(response.status_code, 200)
        titles = [job["title"] for job in response.data["results"]]
        self.assertEqual(titles, ["Cleaning help"])

    def test_job_payload_carries_the_household_verification_status(self):
        """The worker job card badges a verified poster, so the status has to
        travel with each job rather than costing a request per row."""
        response = self.client.get(reverse("job-list"))

        self.assertEqual(response.status_code, 200)
        job = response.data["results"][0]
        self.assertEqual(job["household_verification_status"], "verified")

    def test_job_payload_reports_an_unverified_household_plainly(self):
        profile = self.household.profile
        profile.verification_status = "pending"
        profile.save(update_fields=["verification_status"])

        response = self.client.get(reverse("job-list"))

        self.assertEqual(response.status_code, 200)
        job = response.data["results"][0]
        self.assertEqual(job["household_verification_status"], "pending")

    def test_job_list_filtered_by_worker_returns_only_that_workers_jobs(self):
        """A household reads an applicant's employment history off this
        filter, so it must not leak jobs the worker never worked on."""
        other_worker = User.objects.create_user(
            username="worker2", email="worker2@example.com", password="password"
        )
        UserProfile.objects.create(
            user=other_worker,
            role=UserProfile.ROLE_WORKER,
            verification_status="verified",
        )
        other_job = JobPosting.objects.create(
            household=self.household,
            title="Someone else's job",
            job_type="Laundry",
            required_skill="Laundry",
            schedule="2026-06-04 10:00",
            location_label="Calumpang, Tayabas",
            latitude="13.9500000",
            longitude="121.5900000",
            service_rate="300.00",
        )
        JobApplication.objects.create(job=other_job, worker=other_worker)
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])

        response = self.client.get(reverse("job-list"), {"worker": self.worker.id})

        self.assertEqual(response.status_code, 200)
        titles = [job["title"] for job in response.data["results"]]
        self.assertEqual(titles, ["Cleaning help"])

    def test_job_list_worker_filter_excludes_jobs_only_applied_to(self):
        """Applying is not working: a pending or closed application must not
        show up in the employment history a household reads."""
        self.job.status = JobPosting.STATUS_COMPLETED
        self.job.save(update_fields=["status"])

        response = self.client.get(reverse("job-list"), {"worker": self.worker.id, "status": "completed"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["results"], [])

    def test_job_list_worker_filter_combines_with_status(self):
        JobPosting.objects.create(
            household=self.household,
            title="Unrelated completed job",
            job_type="Laundry",
            required_skill="Laundry",
            schedule="2026-06-05 10:00",
            location_label="Calumpang, Tayabas",
            latitude="13.9500000",
            longitude="121.5900000",
            service_rate="300.00",
            status=JobPosting.STATUS_COMPLETED,
        )
        self.job.status = JobPosting.STATUS_COMPLETED
        self.job.save(update_fields=["status"])
        self.application.status = JobApplication.STATUS_COMPLETED
        self.application.save(update_fields=["status"])

        response = self.client.get(
            reverse("job-list"), {"worker": self.worker.id, "status": "completed"}
        )

        self.assertEqual(response.status_code, 200)
        titles = [job["title"] for job in response.data["results"]]
        self.assertEqual(titles, ["Cleaning help"])

    def test_job_list_worker_filter_rejects_a_non_numeric_id(self):
        response = self.client.get(reverse("job-list"), {"worker": "not-an-id"})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["results"], [])

    def test_household_mine_list_includes_completed_and_cancelled_posts(self):
        completed_job = JobPosting.objects.create(
            household=self.household,
            title="Completed laundry",
            job_type="Laundry",
            required_skill="Laundry",
            schedule="2026-06-04 10:00",
            location_label="Calumpang, Tayabas",
            latitude="13.9500000",
            longitude="121.5900000",
            service_rate="300.00",
            status=JobPosting.STATUS_COMPLETED,
        )
        cancelled_job = JobPosting.objects.create(
            household=self.household,
            title="Cancelled cooking",
            job_type="Cooking",
            required_skill="Cooking",
            schedule="2026-06-05 10:00",
            location_label="Mainit, Tayabas",
            latitude="13.9500000",
            longitude="121.5900000",
            service_rate="450.00",
            status=JobPosting.STATUS_CANCELLED,
        )
        self.client.force_authenticate(user=self.household)

        response = self.client.get(reverse("job-list"), {"mine": "true"})

        self.assertEqual(response.status_code, 200)
        ids = {job["id"] for job in response.data["results"]}
        self.assertIn(self.job.id, ids)
        self.assertIn(completed_job.id, ids)
        self.assertIn(cancelled_job.id, ids)

    def test_job_owner_can_see_applications(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["applications"]), 1)
        self.assertEqual(response.data["applications"][0]["worker_username"], self.worker.username)
        self.assertIsNone(response.data["current_worker_application"])
        self.assertEqual(float(response.data["latitude"]), float(self.job.latitude))
        self.assertEqual(float(response.data["longitude"]), float(self.job.longitude))

    def _applicant_with_route(self):
        self.worker.profile.location_label = "Near Mayowe, Tayabas City"
        self.worker.profile.latitude = "13.9800000"
        self.worker.profile.longitude = "121.5800000"
        self.worker.profile.save(update_fields=["location_label", "latitude", "longitude"])
        route = {
            "distance_km": 6.94,
            "route_points": [
                [float(self.job.latitude), float(self.job.longitude)],
                [13.9700000, 121.5700000],
                [13.9800000, 121.5800000],
            ],
        }
        self.client.force_authenticate(user=self.household)
        with patch("apps.matching.services.fetch_road_route", return_value=route):
            response = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.assertEqual(response.status_code, 200)
        return response.data["applications"][0]

    def test_job_owner_sees_a_pending_applicants_location_and_route(self):
        """A household picks between applicants partly on where they are, so
        the distance map has to work before anyone is hired."""
        application = self._applicant_with_route()

        self.assertEqual(application["worker_location_label"], "Near Mayowe, Tayabas City")
        self.assertEqual(application["worker_latitude"], 13.98)
        self.assertEqual(application["worker_longitude"], 121.58)
        self.assertEqual(application["route_points"][1], [13.97, 121.57])
        self.assertEqual(application["route_distance_km"], 6.9)
        self.assertEqual(application["distance_label"], "6.9 km away")

    def test_a_pending_applicant_does_not_unlock_household_contact_details(self):
        """Locations opened up; contact details did not. Knowing where a job
        is doesn't require being able to phone whoever posted it."""
        self.job.household.profile.phone = "09171234567"
        self.job.household.profile.save(update_fields=["phone"])
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("job-application-list"), {"job_id": self.job.id})
        application = response.data[0] if isinstance(response.data, list) else response.data["results"][0]

        self.assertEqual(application["household_phone"], "")
        self.assertEqual(application["household_email"], "")

    def test_job_owner_receives_hired_worker_location_and_road_route(self):
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])

        application = self._applicant_with_route()

        self.assertEqual(application["worker_latitude"], 13.98)
        self.assertEqual(application["worker_longitude"], 121.58)
        self.assertEqual(application["route_distance_km"], 6.9)
        self.assertEqual(application["route_points"][1], [13.97, 121.57])

    def test_job_owner_receives_the_applicant_card_fields(self):
        self.worker.profile.rating_count = 3
        self.worker.profile.latitude = "13.9800000"
        self.worker.profile.longitude = "121.5800000"
        self.worker.profile.skills = ["House Cleaning"]
        self.worker.profile.save(
            update_fields=["rating_count", "latitude", "longitude", "skills"]
        )
        finished = JobPosting.objects.create(
            household=self.household,
            title="Earlier job",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="One-Time",
            location_label="Isabang, Tayabas",
            latitude=self.job.latitude,
            longitude=self.job.longitude,
            service_rate="500.00",
            status=JobPosting.STATUS_COMPLETED,
        )
        JobApplication.objects.create(
            job=finished,
            worker=self.worker,
            status=JobApplication.STATUS_COMPLETED,
        )

        self.client.force_authenticate(user=self.household)
        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        application = response.data["applications"][0]
        self.assertEqual(application["worker_rating_count"], 3)
        self.assertEqual(application["worker_completed_jobs"], 1)
        self.assertIsNotNone(application["worker_match_score"])

    def test_applicant_scoring_fields_are_household_only(self):
        """The worker's own application list shouldn't pay for a scoring pass
        and a count query it never renders."""
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("job-application-list"))

        self.assertEqual(response.status_code, 200)
        application = response.data[0] if isinstance(response.data, list) else response.data["results"][0]
        self.assertEqual(application["worker_completed_jobs"], 0)
        self.assertIsNone(application["worker_match_score"])

    def test_worker_job_payload_uses_cached_road_route_distance(self):
        self.worker.profile.latitude = "13.9800000"
        self.worker.profile.longitude = "121.5800000"
        self.worker.profile.save(update_fields=["latitude", "longitude"])
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])

        def fake_road_route(lat1, lon1, lat2, lon2):
            return {
                "distance_km": 6.9,
                "route_points": [[float(lat1), float(lon1)], [13.9700000, 121.5700000], [float(lat2), float(lon2)]],
            }

        self.client.force_authenticate(user=self.worker)
        with patch("apps.matching.services.fetch_road_route", side_effect=fake_road_route) as route_fetch:
            response = self.client.get(reverse("job-detail", args=[self.job.id]))
            second_response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(second_response.status_code, 200)
        self.assertEqual(response.data["route_distance_km"], 6.9)
        self.assertEqual(response.data["route_points"][1], [13.97, 121.57])
        self.assertEqual(route_fetch.call_count, 1)
        self.assertEqual(RouteDistanceCache.objects.count(), 1)

    def test_application_list_never_calls_the_external_routing_service(self):
        # One live route lookup per row means one sequential outbound HTTP
        # round-trip per application, so list serialization reads the cache
        # only. Detail serialization still resolves live (asserted above).
        self.worker.profile.latitude = "13.9800000"
        self.worker.profile.longitude = "121.5800000"
        self.worker.profile.save(update_fields=["latitude", "longitude"])

        self.client.force_authenticate(user=self.household)
        with patch("apps.matching.services.fetch_road_route") as route_fetch:
            response = self.client.get(reverse("job-application-list"), {"job_id": self.job.id})

        self.assertEqual(response.status_code, 200)
        route_fetch.assert_not_called()
        self.assertIsNone(response.data["results"][0]["route_distance_km"])

    def test_any_signed_in_worker_can_see_the_exact_job_location(self):
        """A worker decides whether a job is worth travelling to before
        applying, so the job's real location is not held back until hire."""
        unrelated_worker = User.objects.create_user(username="worker-location-private", password="password")
        UserProfile.objects.create(
            user=unrelated_worker,
            role=UserProfile.ROLE_WORKER,
            verification_status="verified",
            hourly_rate="120.00",
            location_label="Alitao, Tayabas City",
            latitude="14.0537324",
            longitude="121.5336725",
        )
        self.client.force_authenticate(user=unrelated_worker)

        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(float(response.data["latitude"]), float(self.job.latitude))
        self.assertEqual(float(response.data["longitude"]), float(self.job.longitude))
        self.assertEqual(response.data["location_label"], self.job.location_label)

    def test_a_signed_in_worker_gets_both_the_exact_and_approximate_points(self):
        """The browse map still pins neighbourhoods from the approximate
        point, so both are sent and the client picks per screen."""
        self.job.latitude = "14.0271234"
        self.job.longitude = "121.5928765"
        self.job.save(update_fields=["latitude", "longitude"])
        unrelated_worker = User.objects.create_user(username="worker-map-area", password="password")
        UserProfile.objects.create(user=unrelated_worker, role=UserProfile.ROLE_WORKER)
        self.client.force_authenticate(user=unrelated_worker)

        response = self.client.get(reverse("job-list"), {"status": "open"})

        job = next(item for item in response.data["results"] if item["id"] == self.job.id)
        self.assertEqual(float(job["latitude"]), 14.0271234)
        self.assertEqual(float(job["longitude"]), 121.5928765)
        # Snapped to the ~1 km grid, still used by the Find Jobs browse map.
        self.assertEqual(job["approximate_latitude"], 14.03)
        self.assertEqual(job["approximate_longitude"], 121.59)

    def test_a_signed_out_visitor_still_gets_only_the_approximate_area(self):
        """Job list and detail are public, so anything exact here would make
        every household's home address scrapable without an account."""
        self.job.latitude = "14.0271234"
        self.job.longitude = "121.5928765"
        self.job.location_label = "12 Real Street, Isabang, Tayabas"
        self.job.save(update_fields=["latitude", "longitude", "location_label"])

        listed = self.client.get(reverse("job-list"), {"status": "open"})
        detail = self.client.get(reverse("job-detail", args=[self.job.id]))

        job = next(item for item in listed.data["results"] if item["id"] == self.job.id)
        for payload in (job, detail.data):
            self.assertIsNone(payload["latitude"])
            self.assertIsNone(payload["longitude"])
            self.assertEqual(payload["approximate_latitude"], 14.03)
            self.assertEqual(payload["approximate_longitude"], 121.59)
            self.assertNotIn("Real Street", payload["location_label"])

    def test_hired_worker_can_see_exact_job_location(self):
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(float(response.data["latitude"]), float(self.job.latitude))
        self.assertEqual(float(response.data["longitude"]), float(self.job.longitude))

    def test_worker_only_sees_own_application_on_job_detail(self):
        second_worker = User.objects.create_user(username="worker-private-other", password="password")
        UserProfile.objects.create(user=second_worker, role=UserProfile.ROLE_WORKER)
        JobApplication.objects.create(job=self.job, worker=second_worker)
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["applications"]), 1)
        self.assertEqual(response.data["applications"][0]["worker_username"], self.worker.username)
        self.assertEqual(response.data["current_worker_application"]["id"], self.application.id)
        self.assertEqual(response.data["current_worker_application"]["status"], JobApplication.STATUS_PENDING)
        self.assertFalse(response.data["can_apply"])
        self.assertFalse(response.data["can_accept_hire_request"])
        self.assertFalse(response.data["can_request_completion"])

    def test_verified_worker_without_application_can_apply_to_open_job(self):
        available_worker = User.objects.create_user(username="worker-can-apply", password="password")
        UserProfile.objects.create(
            user=available_worker,
            role=UserProfile.ROLE_WORKER,
            verification_status="verified",
        )
        self.client.force_authenticate(user=available_worker)

        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["can_apply"])
        self.assertIsNone(response.data["current_worker_application"])

    def test_hire_request_flag_is_backend_owned(self):
        self.application.status = JobApplication.STATUS_HIRE_REQUESTED
        self.application.save(update_fields=["status"])
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data["can_apply"])
        self.assertTrue(response.data["can_accept_hire_request"])
        self.assertFalse(response.data["can_request_completion"])

    def test_hired_worker_can_request_completion_on_assigned_job(self):
        self.job.status = JobPosting.STATUS_ASSIGNED
        self.job.save(update_fields=["status"])
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["hired_count"], 1)
        self.assertFalse(response.data["can_apply"])
        self.assertFalse(response.data["can_accept_hire_request"])
        self.assertTrue(response.data["can_request_completion"])

    def test_completed_job_review_flags_clear_after_review(self):
        self.job.status = JobPosting.STATUS_COMPLETED
        self.job.save(update_fields=["status"])
        self.application.status = JobApplication.STATUS_COMPLETED
        self.application.save(update_fields=["status"])

        self.client.force_authenticate(user=self.household)
        household_response = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.client.force_authenticate(user=self.worker)
        worker_response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertTrue(household_response.data["can_review"])
        self.assertTrue(worker_response.data["can_review"])

        Review.objects.create(
            author=self.household,
            target=self.worker,
            author_role=Review.ROLE_HOUSEHOLD,
            target_role=Review.ROLE_WORKER,
            job=self.job,
            job_title=self.job.title,
            rating="5.0",
            feedback="Great work",
        )
        Review.objects.create(
            author=self.worker,
            target=self.household,
            author_role=Review.ROLE_WORKER,
            target_role=Review.ROLE_HOUSEHOLD,
            job=self.job,
            job_title=self.job.title,
            rating="5.0",
            feedback="Great household",
        )

        self.client.force_authenticate(user=self.household)
        household_reviewed_response = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.client.force_authenticate(user=self.worker)
        worker_reviewed_response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertFalse(household_reviewed_response.data["can_review"])
        self.assertFalse(worker_reviewed_response.data["can_review"])

    def test_unrelated_household_cannot_see_applications(self):
        self.client.force_authenticate(user=self.other_household)

        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["applications"], [])

    def test_worker_application_list_only_includes_own_applications(self):
        second_worker = User.objects.create_user(username="worker-list-other", password="password")
        UserProfile.objects.create(user=second_worker, role=UserProfile.ROLE_WORKER)
        JobApplication.objects.create(job=self.job, worker=second_worker)
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("job-application-list"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["results"]), 1)
        self.assertEqual(response.data["results"][0]["worker_username"], self.worker.username)
        self.assertEqual(response.data["results"][0]["job_id"], self.job.id)
        self.assertEqual(response.data["results"][0]["job_title"], self.job.title)

    def test_household_application_list_only_includes_owned_jobs(self):
        other_job = JobPosting.objects.create(
            household=self.other_household,
            title="Other household job",
            job_type="Laundry",
            required_skill="Laundry",
            schedule="2026-06-03 09:00",
            location_label="Alitao, Tayabas",
            latitude="14.0537324",
            longitude="121.5336725",
            service_rate="700.00",
        )
        JobApplication.objects.create(job=other_job, worker=self.worker)
        self.client.force_authenticate(user=self.household)

        response = self.client.get(reverse("job-application-list"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["results"]), 1)
        self.assertEqual(response.data["results"][0]["job_id"], self.job.id)

    def test_anonymous_user_cannot_apply_by_worker_username(self):
        response = self.client.post(
            reverse("job-apply", args=[self.job.id]),
            {"worker_username": self.worker.username},
            format="json",
        )

        self.assertEqual(response.status_code, 401)

    def test_household_cannot_apply_to_job(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.post(reverse("job-apply", args=[self.job.id]), {}, format="json")

        self.assertEqual(response.status_code, 403)

    def test_unverified_worker_cannot_apply_to_job(self):
        unverified_worker = User.objects.create_user(username="worker-unverified-apply", password="password")
        UserProfile.objects.create(
            user=unverified_worker,
            role=UserProfile.ROLE_WORKER,
            verification_status="pending",
        )
        self.client.force_authenticate(user=unverified_worker)

        response = self.client.post(reverse("job-apply", args=[self.job.id]), {}, format="json")

        self.assertEqual(response.status_code, 403)
        self.assertFalse(JobApplication.objects.filter(job=self.job, worker=unverified_worker).exists())

    def test_worker_cannot_apply_to_closed_job(self):
        self.job.status = JobPosting.STATUS_CANCELLED
        self.job.save(update_fields=["status"])
        new_worker = User.objects.create_user(username="worker-closed", password="password")
        UserProfile.objects.create(user=new_worker, role=UserProfile.ROLE_WORKER, verification_status="verified")
        self.client.force_authenticate(user=new_worker)

        response = self.client.post(reverse("job-apply", args=[self.job.id]), {}, format="json")

        self.assertEqual(response.status_code, 400)
        self.assertFalse(JobApplication.objects.filter(job=self.job, worker=new_worker).exists())

    def test_worker_application_creates_structured_household_notification(self):
        new_worker = User.objects.create_user(username="worker-apply-structured", password="password")
        UserProfile.objects.create(user=new_worker, role=UserProfile.ROLE_WORKER, verification_status="verified")
        self.client.force_authenticate(user=new_worker)

        response = self.client.post(reverse("job-apply", args=[self.job.id]), {}, format="json")

        self.assertEqual(response.status_code, 201)
        application = JobApplication.objects.get(job=self.job, worker=new_worker)
        notification = Notification.objects.get(
            recipient=self.household,
            notification_type=Notification.TYPE_APPLICATION,
            title="New worker application",
            message__contains=self.job.title,
        )
        self.assertEqual(notification.actor, new_worker)
        self.assertEqual(notification.related_job_id, self.job.id)
        self.assertEqual(notification.related_application_id, application.id)
        self.assertEqual(notification.action_type, Notification.ACTION_JOB_DETAIL)
        self.assertEqual(notification.action_url, f"/household/jobs/{self.job.id}/applications")
        self.assertTrue(notification.requires_action)

    def test_non_owner_cannot_edit_job(self):
        self.client.force_authenticate(user=self.other_household)

        response = self.client.patch(
            reverse("job-detail", args=[self.job.id]),
            {"title": "Changed by another household"},
            format="json",
        )

        self.assertEqual(response.status_code, 403)
        self.job.refresh_from_db()
        self.assertEqual(self.job.title, "Cleaning help")

    def test_non_owner_cannot_delete_job(self):
        self.client.force_authenticate(user=self.other_household)

        response = self.client.delete(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 403)
        self.assertTrue(JobPosting.objects.filter(pk=self.job.id).exists())

    def test_worker_cannot_create_job(self):
        self.client.force_authenticate(user=self.worker)

        response = self.client.post(
            reverse("job-list"),
            {
                "title": "Worker-created job",
                "job_type": "House Cleaning",
                "required_skill": "House Cleaning",
                "schedule": "2030-06-02 09:00",
                "location_label": "Isabang, Tayabas",
                "latitude": "13.9622745",
                "longitude": "121.5632841",
                "service_rate": "500.00",
                "worker_slots": 1,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 403)
        self.assertFalse(JobPosting.objects.filter(title="Worker-created job").exists())

    def test_household_can_create_job_with_structured_schedule_fields(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.post(
            reverse("job-list"),
            {
                "title": "Structured schedule job",
                "job_type": "House Cleaning",
                "required_skill": "House Cleaning",
                "schedule_type": "One-Time",
                "job_start_date": "2030-06-02",
                "location_label": "Isabang, Tayabas",
                "latitude": "13.9622745",
                "longitude": "121.5632841",
                "service_rate": "500.00",
                "worker_slots": 1,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data["schedule_type"], "One-Time")
        self.assertEqual(response.data["job_start_date"], "2030-06-02")
        self.assertEqual(response.data["schedule"], "One-Time starting 2030-06-02")
        job = JobPosting.objects.get(title="Structured schedule job")
        self.assertEqual(str(job.job_start_date), "2030-06-02")

    def test_job_rejects_negative_rate_and_nonsensical_numbers(self):
        self.client.force_authenticate(user=self.household)
        base = {
            "title": "Negative numbers job",
            "job_type": "House Cleaning",
            "required_skill": "House Cleaning",
            "schedule": "One-Time",
            "location_label": "Isabang, Tayabas",
            "latitude": "13.9622745",
            "longitude": "121.5632841",
            "service_rate": "500.00",
            "worker_slots": 1,
        }
        invalid_fields = [
            ("service_rate", "-500.00"),
            ("estimated_working_days", -3),
            ("max_distance_km", -1.0),
        ]

        for field, value in invalid_fields:
            response = self.client.post(
                reverse("job-list"), {**base, field: value}, format="json"
            )
            self.assertEqual(response.status_code, 400, f"{field}={value} should be rejected")
            self.assertIn(field, response.data)

        self.assertFalse(JobPosting.objects.filter(title="Negative numbers job").exists())

    def test_unverified_household_cannot_create_job(self):
        self.household.profile.verification_status = "pending"
        self.household.profile.save(update_fields=["verification_status"])
        self.client.force_authenticate(user=self.household)

        response = self.client.post(
            reverse("job-list"),
            {
                "title": "Blocked household job",
                "job_type": "House Cleaning",
                "required_skill": "House Cleaning",
                "schedule_type": "One-Time",
                "job_start_date": "2030-06-02",
                "location_label": "Isabang, Tayabas",
                "latitude": "13.9622745",
                "longitude": "121.5632841",
                "service_rate": "500.00",
                "worker_slots": 1,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 403)
        self.assertFalse(JobPosting.objects.filter(title="Blocked household job").exists())

    def test_household_token_repairs_stale_profile_role_when_creating_job(self):
        stale_household = User.objects.create_user(username="stalehousehold", password="password")
        UserProfile.objects.create(
            user=stale_household,
            role=UserProfile.ROLE_WORKER,
            verification_status="verified",
        )
        token = create_jwt_token(
            {
                "user_id": stale_household.id,
                "username": stale_household.username,
                "role": UserProfile.ROLE_HOUSEHOLD,
            }
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")

        response = self.client.post(
            reverse("job-list"),
            {
                "title": "Role repair job",
                "job_type": "Painting",
                "required_skill": "Painting",
                "schedule_type": "One-Time",
                "job_start_date": "2030-06-13",
                "location_label": "Lalo, Tayabas",
                "latitude": "13.9622745",
                "longitude": "121.5632841",
                "service_rate": "100.00",
                "worker_slots": 1,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        stale_household.profile.refresh_from_db()
        self.assertEqual(stale_household.profile.role, UserProfile.ROLE_HOUSEHOLD)
        self.assertTrue(JobPosting.objects.filter(title="Role repair job", household=stale_household).exists())

    def test_household_cannot_create_job_with_non_open_status(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.post(
            reverse("job-list"),
            {
                "title": "Pre-completed job",
                "job_type": "House Cleaning",
                "required_skill": "House Cleaning",
                "schedule": "2026-06-02 09:00",
                "location_label": "Isabang, Tayabas",
                "latitude": "13.9622745",
                "longitude": "121.5632841",
                "service_rate": "500.00",
                "worker_slots": 1,
                "status": JobPosting.STATUS_COMPLETED,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(JobPosting.objects.filter(title="Pre-completed job").exists())

    def test_open_job_can_be_cancelled_by_owner(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-detail", args=[self.job.id]),
            {"status": JobPosting.STATUS_CANCELLED},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_CANCELLED)

    def test_open_job_cannot_skip_to_completed(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-detail", args=[self.job.id]),
            {"status": JobPosting.STATUS_COMPLETED},
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_OPEN)

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
    def test_assigned_job_can_be_completed_by_owner(self):
        self.job.status = JobPosting.STATUS_ASSIGNED
        self.job.save(update_fields=["status"])
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-detail", args=[self.job.id]),
            {"status": JobPosting.STATUS_COMPLETED},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.job.refresh_from_db()
        self.application.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_COMPLETED)
        self.assertIsNotNone(self.job.completed_at)
        self.assertEqual(self.application.status, JobApplication.STATUS_COMPLETED)
        completion_notification = Notification.objects.get(
            recipient=self.worker,
            notification_type=Notification.TYPE_COMPLETION,
            title="Job completed",
            message__contains=self.job.title,
        )
        self.assertEqual(completion_notification.actor, self.household)
        self.assertEqual(completion_notification.related_job_id, self.job.id)
        self.assertEqual(completion_notification.related_application_id, self.application.id)
        self.assertEqual(completion_notification.action_type, Notification.ACTION_REVIEW)
        self.assertEqual(completion_notification.action_url, f"/worker/jobs/{self.job.id}/review")
        self.assertTrue(completion_notification.requires_action)
        reminder_notification = Notification.objects.get(
            recipient=self.household,
            notification_type=Notification.TYPE_REVIEW_REMINDER,
            message__contains=self.worker.username,
        )
        self.assertEqual(reminder_notification.actor, self.worker)
        self.assertEqual(reminder_notification.related_job_id, self.job.id)
        self.assertEqual(reminder_notification.related_application_id, self.application.id)
        self.assertEqual(reminder_notification.action_type, Notification.ACTION_REVIEW)
        self.assertEqual(reminder_notification.action_url, f"/household/jobs/{self.job.id}/review")
        self.assertTrue(reminder_notification.requires_action)
        subjects = [message.subject for message in mail.outbox]
        self.assertIn("GawaGo: Job completed", subjects)
        self.assertIn("GawaGo: Review worker service", subjects)

    def test_unverified_household_cannot_complete_job(self):
        self.job.status = JobPosting.STATUS_ASSIGNED
        self.job.save(update_fields=["status"])
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])
        self.household.profile.verification_status = "pending"
        self.household.profile.save(update_fields=["verification_status"])
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-detail", args=[self.job.id]),
            {"status": JobPosting.STATUS_COMPLETED},
            format="json",
        )

        self.assertEqual(response.status_code, 403)
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_ASSIGNED)

    def test_completion_creates_one_review_reminder_per_completed_worker(self):
        second_worker = User.objects.create_user(username="worker-reminder-2", password="password")
        UserProfile.objects.create(user=second_worker, role=UserProfile.ROLE_WORKER)
        self.job.worker_slots = 2
        self.job.status = JobPosting.STATUS_ASSIGNED
        self.job.save(update_fields=["worker_slots", "status"])
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])
        JobApplication.objects.create(job=self.job, worker=second_worker, status=JobApplication.STATUS_HIRED)

        complete_job(self.job)

        reminders = Notification.objects.filter(
            recipient=self.household,
            notification_type=Notification.TYPE_REVIEW_REMINDER,
        )
        self.assertEqual(reminders.count(), 2)
        self.assertTrue(reminders.filter(message__contains=self.worker.username).exists())
        self.assertTrue(reminders.filter(message__contains=second_worker.username).exists())

    def test_completion_review_reminders_are_not_duplicated(self):
        self.job.status = JobPosting.STATUS_ASSIGNED
        self.job.save(update_fields=["status"])
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])

        complete_job(self.job)
        complete_job(self.job)

        self.assertEqual(
            Notification.objects.filter(
                recipient=self.household,
                notification_type=Notification.TYPE_REVIEW_REMINDER,
            ).count(),
            1,
        )

    def test_completion_skips_review_reminder_when_worker_already_rated(self):
        self.job.status = JobPosting.STATUS_ASSIGNED
        self.job.save(update_fields=["status"])
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])
        Review.objects.create(
            author=self.household,
            target=self.worker,
            author_role=Review.ROLE_HOUSEHOLD,
            target_role=Review.ROLE_WORKER,
            job=self.job,
            job_title=self.job.title,
            rating="5.0",
            feedback="Already reviewed",
        )

        complete_job(self.job)

        self.assertFalse(
            Notification.objects.filter(
                recipient=self.household,
                notification_type=Notification.TYPE_REVIEW_REMINDER,
            ).exists()
        )

    def test_assigned_job_without_hired_workers_cannot_be_completed(self):
        self.job.status = JobPosting.STATUS_ASSIGNED
        self.job.save(update_fields=["status"])
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-detail", args=[self.job.id]),
            {"status": JobPosting.STATUS_COMPLETED},
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_ASSIGNED)
        self.assertIsNone(self.job.completed_at)

    def test_completed_job_cannot_be_reopened(self):
        self.job.status = JobPosting.STATUS_COMPLETED
        self.job.save(update_fields=["status"])
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-detail", args=[self.job.id]),
            {"status": JobPosting.STATUS_OPEN},
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_COMPLETED)

    def test_anonymous_user_cannot_update_application_status_by_household_username(self):
        response = self.client.patch(
            reverse("job-application-status", args=[self.application.id]),
            {"household_username": self.household.username, "status": JobApplication.STATUS_HIRED},
            format="json",
        )

        self.assertEqual(response.status_code, 401)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_PENDING)

    def test_only_job_owner_can_hire_or_reject(self):
        self.client.force_authenticate(user=self.other_household)

        response = self.client.patch(
            reverse("job-application-status", args=[self.application.id]),
            {"status": JobApplication.STATUS_HIRED},
            format="json",
        )

        self.assertEqual(response.status_code, 403)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_PENDING)

    def test_job_owner_can_directly_hire_pending_application_with_structured_notification(self):
        self.client.force_authenticate(user=self.household)

        with (
            patch(
                "apps.jobs.services.JobPosting.objects.select_for_update",
                wraps=JobPosting.objects.select_for_update,
            ) as job_lock,
            patch(
                "apps.jobs.services.JobApplication.objects.select_for_update",
                wraps=JobApplication.objects.select_for_update,
            ) as application_lock,
        ):
            response = self.client.patch(
                reverse("job-application-status", args=[self.application.id]),
                {"status": JobApplication.STATUS_HIRED},
                format="json",
            )

        self.assertEqual(response.status_code, 200)
        job_lock.assert_called_once_with()
        application_lock.assert_called_once_with()
        self.application.refresh_from_db()
        self.job.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_HIRED)
        self.assertEqual(self.job.status, JobPosting.STATUS_ASSIGNED)
        notification = Notification.objects.get(
            recipient=self.worker,
            notification_type=Notification.TYPE_ACCEPTED,
            title="Application accepted",
            message__contains=self.job.title,
        )
        self.assertEqual(notification.actor, self.household)
        self.assertEqual(notification.related_job_id, self.job.id)
        self.assertEqual(notification.related_application_id, self.application.id)
        self.assertEqual(notification.action_type, Notification.ACTION_JOB_DETAIL)
        self.assertEqual(notification.action_url, f"/worker/jobs/{self.job.id}")
        self.assertFalse(notification.requires_action)

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
    def test_job_owner_can_send_hire_request_for_pending_application(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-application-status", args=[self.application.id]),
            {"status": JobApplication.STATUS_HIRE_REQUESTED},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.application.refresh_from_db()
        self.job.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_HIRE_REQUESTED)
        self.assertEqual(self.job.status, JobPosting.STATUS_OPEN)
        notification = Notification.objects.get(
            recipient=self.worker,
            notification_type=Notification.TYPE_HIRING,
            title="Hire request",
            message__contains=self.job.title,
        )
        self.assertEqual(notification.actor, self.household)
        self.assertEqual(notification.related_job_id, self.job.id)
        self.assertEqual(notification.related_application_id, self.application.id)
        self.assertEqual(notification.action_type, Notification.ACTION_HIRE_REQUEST)
        self.assertEqual(notification.action_url, f"/worker/jobs/{self.job.id}")
        self.assertTrue(notification.requires_action)
        self.assertEqual(mail.outbox[-1].to, [self.worker.email])
        self.assertEqual(mail.outbox[-1].subject, "GawaGo: Hire request")
        self.assertIn(self.job.title, mail.outbox[-1].body)

    def test_unverified_household_cannot_send_hire_request(self):
        self.household.profile.verification_status = "pending"
        self.household.profile.save(update_fields=["verification_status"])
        self.client.force_authenticate(user=self.household)

        response = self.client.post(
            reverse("job-hire-request", args=[self.job.id]),
            {"worker_id": self.worker.id},
            format="json",
        )

        self.assertEqual(response.status_code, 403)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_PENDING)

    def test_unverified_household_cannot_manage_job_applications(self):
        self.household.profile.verification_status = "pending"
        self.household.profile.save(update_fields=["verification_status"])
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-application-status", args=[self.application.id]),
            {"status": JobApplication.STATUS_HIRE_REQUESTED},
            format="json",
        )

        self.assertEqual(response.status_code, 403)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_PENDING)

    def test_job_owner_cannot_hire_unverified_worker(self):
        self.worker.profile.verification_status = "pending"
        self.worker.profile.save(update_fields=["verification_status"])
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-application-status", args=[self.application.id]),
            {"status": JobApplication.STATUS_HIRED},
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.application.refresh_from_db()
        self.job.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_PENDING)
        self.assertEqual(self.job.status, JobPosting.STATUS_OPEN)

    def test_hiring_respects_worker_slots(self):
        second_worker = User.objects.create_user(username="worker2", password="password")
        UserProfile.objects.create(user=second_worker, role=UserProfile.ROLE_WORKER, verification_status="verified")
        second_application = JobApplication.objects.create(job=self.job, worker=second_worker)
        self.client.force_authenticate(user=self.household)
        self.client.patch(
            reverse("job-application-status", args=[self.application.id]),
            {"status": JobApplication.STATUS_HIRE_REQUESTED},
            format="json",
        )
        self.client.force_authenticate(user=self.worker)
        self.client.patch(
            reverse("job-application-decision", args=[self.application.id]),
            {"decision": "accept"},
            format="json",
        )
        accepted_notification = Notification.objects.get(
            recipient=self.household,
            notification_type=Notification.TYPE_ACCEPTED,
            title="Hire request accepted",
            message__contains=self.job.title,
        )
        self.assertEqual(accepted_notification.actor, self.worker)
        self.assertEqual(accepted_notification.related_job_id, self.job.id)
        self.assertEqual(accepted_notification.related_application_id, self.application.id)
        self.assertEqual(accepted_notification.action_type, Notification.ACTION_JOB_DETAIL)
        self.assertEqual(accepted_notification.action_url, f"/household/jobs/{self.job.id}")
        self.assertFalse(accepted_notification.requires_action)
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-application-status", args=[second_application.id]),
            {"status": JobApplication.STATUS_HIRE_REQUESTED},
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        second_application.refresh_from_db()
        self.assertEqual(second_application.status, JobApplication.STATUS_CLOSED)

    def test_finalized_application_cannot_be_changed(self):
        self.application.status = JobApplication.STATUS_REJECTED
        self.application.save(update_fields=["status"])
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-application-status", args=[self.application.id]),
            {"status": JobApplication.STATUS_HIRED},
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_REJECTED)

    @override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
    def test_owner_can_reject_pending_application(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-application-status", args=[self.application.id]),
            {"status": JobApplication.STATUS_REJECTED},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_REJECTED)
        notification = Notification.objects.get(
            recipient=self.worker,
            notification_type=Notification.TYPE_REJECTION,
            title="Application rejected",
            message__contains=self.job.title,
        )
        self.assertEqual(notification.actor, self.household)
        self.assertEqual(notification.related_job_id, self.job.id)
        self.assertEqual(notification.related_application_id, self.application.id)
        self.assertEqual(notification.action_type, Notification.ACTION_JOB_DETAIL)
        self.assertEqual(notification.action_url, f"/worker/jobs/{self.job.id}")
        self.assertFalse(notification.requires_action)
        self.assertEqual(mail.outbox[-1].to, [self.worker.email])
        self.assertEqual(mail.outbox[-1].subject, "GawaGo: Application rejected")
        self.assertIn(self.job.title, mail.outbox[-1].body)


class ApplicationHouseholdContactDetailTests(TestCase):
    """roadmap audit LOW #35: normalizeProfileRecord read phone/email off
    PublicUserProfileSerializer, which strips both for every non-staff
    caller -- so "contact details become available after you are hired" had
    nothing behind it. household_phone/household_email on
    JobApplicationSerializer close that gap instead, gated to the hired
    worker viewing their own application."""

    def setUp(self):
        self.client = APIClient()
        self.household = User.objects.create_user(
            username="contact-household", email="household@example.com", password="password"
        )
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD, phone="09123456789")
        self.worker = User.objects.create_user(username="contact-worker", password="password")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.other_worker = User.objects.create_user(username="other-worker", password="password")
        UserProfile.objects.create(user=self.other_worker, role=UserProfile.ROLE_WORKER)
        self.job = JobPosting.objects.create(
            household=self.household,
            title="Cleaning help",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-01 09:00",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
        )
        self.application = JobApplication.objects.create(job=self.job, worker=self.worker)

    def test_contact_details_hidden_before_the_worker_is_hired(self):
        self.client.force_authenticate(user=self.worker)
        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        application_data = response.data["current_worker_application"]
        self.assertEqual(application_data["household_phone"], "")
        self.assertEqual(application_data["household_email"], "")

    def test_contact_details_visible_once_hired(self):
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        application_data = response.data["current_worker_application"]
        self.assertEqual(application_data["household_phone"], "09123456789")
        self.assertEqual(application_data["household_email"], "household@example.com")

    def test_contact_details_never_leak_to_a_worker_who_was_not_hired(self):
        self.application.status = JobApplication.STATUS_HIRED
        self.application.save(update_fields=["status"])
        rejected = JobApplication.objects.create(
            job=self.job, worker=self.other_worker, status=JobApplication.STATUS_REJECTED
        )
        self.client.force_authenticate(user=self.other_worker)

        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        application_data = response.data["current_worker_application"]
        self.assertEqual(application_data["id"], rejected.id)
        self.assertEqual(application_data["household_phone"], "")
        self.assertEqual(application_data["household_email"], "")


class JobLifecycleTransitionTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.household = User.objects.create_user(username="lifecycle-household", password="password")
        self.worker = User.objects.create_user(username="lifecycle-worker", password="password")
        self.reject_worker = User.objects.create_user(username="lifecycle-reject-worker", password="password")
        UserProfile.objects.create(
            user=self.household,
            role=UserProfile.ROLE_HOUSEHOLD,
            verification_status="verified",
        )
        UserProfile.objects.create(
            user=self.worker,
            role=UserProfile.ROLE_WORKER,
            verification_status="verified",
        )
        UserProfile.objects.create(
            user=self.reject_worker,
            role=UserProfile.ROLE_WORKER,
            verification_status="verified",
        )
        self.job = JobPosting.objects.create(
            household=self.household,
            title="Lifecycle cleaning",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-04 10:00",
            schedule_type="One-Time",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            worker_slots=1,
        )

    def apply_as_worker(self, worker=None):
        worker = worker or self.worker
        self.client.force_authenticate(user=worker)
        return self.client.post(reverse("job-apply", args=[self.job.id]), {}, format="json")

    def send_hire_request(self, application):
        self.client.force_authenticate(user=self.household)
        return self.client.patch(
            reverse("job-application-status", args=[application.id]),
            {"status": JobApplication.STATUS_HIRE_REQUESTED},
            format="json",
        )

    def decide_hire_request(self, application, decision, worker=None):
        self.client.force_authenticate(user=worker or application.worker)
        return self.client.patch(
            reverse("job-application-decision", args=[application.id]),
            {"decision": decision},
            format="json",
        )

    def complete_job_from_household(self):
        self.client.force_authenticate(user=self.household)
        return self.client.patch(
            reverse("job-detail", args=[self.job.id]),
            {"status": JobPosting.STATUS_COMPLETED},
            format="json",
        )

    def submit_review(self, author, target, rating="5.0"):
        self.client.force_authenticate(user=author)
        return self.client.post(
            reverse("review-list-create"),
            {
                "target_username": target.username,
                "job_id": self.job.id,
                "job_title": self.job.title,
                "rating": rating,
                "feedback": "Lifecycle review",
            },
            format="json",
        )

    def test_worker_applies_transition_creates_pending_application(self):
        response = self.apply_as_worker()

        self.assertEqual(response.status_code, 201)
        application = JobApplication.objects.get(job=self.job, worker=self.worker)
        self.assertEqual(application.status, JobApplication.STATUS_PENDING)
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_OPEN)
        self.client.force_authenticate(user=self.worker)
        detail_response = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.assertFalse(detail_response.data["can_apply"])
        self.assertFalse(detail_response.data["can_accept_hire_request"])

    def test_household_sends_hire_request_transition(self):
        self.apply_as_worker()
        application = JobApplication.objects.get(job=self.job, worker=self.worker)

        response = self.send_hire_request(application)

        self.assertEqual(response.status_code, 200)
        application.refresh_from_db()
        self.job.refresh_from_db()
        self.assertEqual(application.status, JobApplication.STATUS_HIRE_REQUESTED)
        self.assertEqual(self.job.status, JobPosting.STATUS_OPEN)
        self.client.force_authenticate(user=self.worker)
        detail_response = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.assertTrue(detail_response.data["can_accept_hire_request"])
        self.assertFalse(detail_response.data["can_apply"])

    def test_worker_accepts_hire_request_transition(self):
        self.apply_as_worker()
        application = JobApplication.objects.get(job=self.job, worker=self.worker)
        self.send_hire_request(application)

        with (
            patch(
                "apps.jobs.services.JobPosting.objects.select_for_update",
                wraps=JobPosting.objects.select_for_update,
            ) as job_lock,
            patch(
                "apps.jobs.services.JobApplication.objects.select_for_update",
                wraps=JobApplication.objects.select_for_update,
            ) as application_lock,
        ):
            response = self.decide_hire_request(application, "accept")

        self.assertEqual(response.status_code, 200)
        job_lock.assert_called_once_with()
        application_lock.assert_called_once_with()
        application.refresh_from_db()
        self.job.refresh_from_db()
        self.assertEqual(application.status, JobApplication.STATUS_HIRED)
        self.assertEqual(self.job.status, JobPosting.STATUS_ASSIGNED)
        self.client.force_authenticate(user=self.worker)
        detail_response = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.assertEqual(detail_response.data["hired_count"], 1)
        self.assertFalse(detail_response.data["can_accept_hire_request"])
        self.assertTrue(detail_response.data["can_request_completion"])

    def test_worker_rejects_hire_request_transition(self):
        self.apply_as_worker(self.reject_worker)
        application = JobApplication.objects.get(job=self.job, worker=self.reject_worker)
        self.send_hire_request(application)

        response = self.decide_hire_request(application, "reject", worker=self.reject_worker)

        self.assertEqual(response.status_code, 200)
        application.refresh_from_db()
        self.job.refresh_from_db()
        self.assertEqual(application.status, JobApplication.STATUS_REJECTED)
        self.assertEqual(self.job.status, JobPosting.STATUS_OPEN)
        self.client.force_authenticate(user=self.reject_worker)
        detail_response = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.assertFalse(detail_response.data["can_apply"])
        self.assertFalse(detail_response.data["can_accept_hire_request"])
        self.assertFalse(detail_response.data["can_request_completion"])

    def test_worker_requests_completion_transition(self):
        self.apply_as_worker()
        application = JobApplication.objects.get(job=self.job, worker=self.worker)
        self.send_hire_request(application)
        self.decide_hire_request(application, "accept")

        self.client.force_authenticate(user=self.worker)
        response = self.client.post(
            reverse("job-request-completion", args=[self.job.id]),
            {"note": "Service completed."},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        application.refresh_from_db()
        self.job.refresh_from_db()
        self.assertEqual(application.status, JobApplication.STATUS_HIRED)
        self.assertEqual(application.note, "Service completed.")
        self.assertEqual(self.job.status, JobPosting.STATUS_COMPLETION_REQUESTED)
        self.assertFalse(response.data["can_request_completion"])
        notification = Notification.objects.get(
            recipient=self.household,
            notification_type=Notification.TYPE_COMPLETION,
            title="Worker requested completion",
        )
        self.assertEqual(notification.related_job_id, self.job.id)
        self.assertEqual(notification.related_application_id, application.id)
        self.assertTrue(notification.requires_action)

    def test_household_confirms_completion_transition(self):
        self.apply_as_worker()
        application = JobApplication.objects.get(job=self.job, worker=self.worker)
        self.send_hire_request(application)
        self.decide_hire_request(application, "accept")
        self.client.force_authenticate(user=self.worker)
        self.client.post(reverse("job-request-completion", args=[self.job.id]), {}, format="json")

        response = self.complete_job_from_household()

        self.assertEqual(response.status_code, 200)
        application.refresh_from_db()
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_COMPLETED)
        self.assertEqual(application.status, JobApplication.STATUS_COMPLETED)
        self.assertIsNotNone(self.job.completed_at)
        self.assertEqual(response.data["hired_count"], 1)
        self.assertTrue(response.data["can_review"])

    def test_reviews_are_blocked_before_completion_and_allowed_after_completion(self):
        self.apply_as_worker()
        application = JobApplication.objects.get(job=self.job, worker=self.worker)
        self.send_hire_request(application)
        self.decide_hire_request(application, "accept")

        household_review_before = self.submit_review(self.household, self.worker)
        worker_review_before = self.submit_review(self.worker, self.household)

        self.assertEqual(household_review_before.status_code, 400)
        self.assertEqual(worker_review_before.status_code, 400)
        self.assertFalse(Review.objects.exists())

        self.client.force_authenticate(user=self.worker)
        self.client.post(reverse("job-request-completion", args=[self.job.id]), {}, format="json")
        self.complete_job_from_household()

        self.client.force_authenticate(user=self.household)
        household_detail = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.client.force_authenticate(user=self.worker)
        worker_detail = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.assertTrue(household_detail.data["can_review"])
        self.assertTrue(worker_detail.data["can_review"])

        household_review_after = self.submit_review(self.household, self.worker)
        worker_review_after = self.submit_review(self.worker, self.household, rating="4.0")

        self.assertEqual(household_review_after.status_code, 201)
        self.assertEqual(worker_review_after.status_code, 201)
        self.assertEqual(Review.objects.count(), 2)

        self.client.force_authenticate(user=self.household)
        household_reviewed_detail = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.client.force_authenticate(user=self.worker)
        worker_reviewed_detail = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.assertFalse(household_reviewed_detail.data["can_review"])
        self.assertFalse(worker_reviewed_detail.data["can_review"])


class ApplicantInstantAcceptTests(TestCase):
    """A worker who applied has already opted in, so the household hires them
    outright; a worker the household invited out of the blue still confirms.
    """

    def setUp(self):
        self.client = APIClient()
        self.household = User.objects.create_user(username="stage-household", password="password")
        self.applicant = User.objects.create_user(username="stage-applicant", password="password")
        self.invitee = User.objects.create_user(username="stage-invitee", password="password")
        UserProfile.objects.create(
            user=self.household, role=UserProfile.ROLE_HOUSEHOLD, verification_status="verified"
        )
        for worker in (self.applicant, self.invitee):
            UserProfile.objects.create(
                user=worker, role=UserProfile.ROLE_WORKER, verification_status="verified"
            )
        self.job = JobPosting.objects.create(
            household=self.household,
            title="Stage cleaning",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-04 10:00",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            worker_slots=2,
        )

    def set_status(self, application, new_status):
        self.client.force_authenticate(user=self.household)
        return self.client.patch(
            reverse("job-application-status", args=[application.id]),
            {"status": new_status},
            format="json",
        )

    def test_household_hires_applicant_without_a_second_handshake(self):
        application = JobApplication.objects.create(
            job=self.job, worker=self.applicant, status=JobApplication.STATUS_PENDING
        )

        response = self.set_status(application, JobApplication.STATUS_HIRED)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["status"], JobApplication.STATUS_HIRED)
        self.assertEqual(response.data["status_stage"], "in_progress")
        self.assertEqual(response.data["status_label"], "In progress")
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, JobPosting.STATUS_ASSIGNED)

    def test_invited_worker_cannot_be_hired_before_they_confirm(self):
        application = JobApplication.objects.create(
            job=self.job, worker=self.invitee, status=JobApplication.STATUS_HIRE_REQUESTED
        )

        response = self.set_status(application, JobApplication.STATUS_HIRED)

        self.assertEqual(response.status_code, 400)
        application.refresh_from_db()
        self.assertEqual(application.status, JobApplication.STATUS_HIRE_REQUESTED)

    def test_invited_worker_reaches_in_progress_by_confirming(self):
        application = JobApplication.objects.create(
            job=self.job, worker=self.invitee, status=JobApplication.STATUS_HIRE_REQUESTED
        )

        self.client.force_authenticate(user=self.invitee)
        response = self.client.patch(
            reverse("job-application-decision", args=[application.id]),
            {"decision": "accept"},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["status_stage"], "in_progress")

    def test_stage_tracks_the_completion_handshake(self):
        application = JobApplication.objects.create(
            job=self.job, worker=self.applicant, status=JobApplication.STATUS_PENDING
        )
        self.set_status(application, JobApplication.STATUS_HIRED)

        self.client.force_authenticate(user=self.applicant)
        self.client.post(reverse("job-request-completion", args=[self.job.id]), {}, format="json")
        awaiting = self.client.get(reverse("job-detail", args=[self.job.id]))
        self.assertEqual(awaiting.data["status_stage"], "awaiting_confirmation")
        self.assertEqual(awaiting.data["status_label"], "Awaiting confirmation")

        self.client.force_authenticate(user=self.household)
        confirmed = self.client.patch(
            reverse("job-detail", args=[self.job.id]),
            {"status": JobPosting.STATUS_COMPLETED},
            format="json",
        )
        self.assertEqual(confirmed.data["status_stage"], "completed")
        self.assertEqual(confirmed.data["status_label"], "Completed")


class JobStatusEventTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.household = User.objects.create_user(username="audit-household", password="password")
        self.worker = User.objects.create_user(username="audit-worker", password="password")
        UserProfile.objects.create(
            user=self.household, role=UserProfile.ROLE_HOUSEHOLD, verification_status="verified"
        )
        UserProfile.objects.create(
            user=self.worker, role=UserProfile.ROLE_WORKER, verification_status="verified"
        )
        self.job = JobPosting.objects.create(
            household=self.household,
            title="Audit cleaning",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-04 10:00",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            worker_slots=1,
        )

    def test_each_transition_is_recorded_with_its_actor(self):
        application = JobApplication.objects.create(
            job=self.job, worker=self.worker, status=JobApplication.STATUS_PENDING
        )

        self.client.force_authenticate(user=self.household)
        self.client.patch(
            reverse("job-application-status", args=[application.id]),
            {"status": JobApplication.STATUS_HIRED},
            format="json",
        )
        self.client.force_authenticate(user=self.worker)
        self.client.post(reverse("job-request-completion", args=[self.job.id]), {}, format="json")
        self.client.force_authenticate(user=self.household)
        self.client.patch(
            reverse("job-detail", args=[self.job.id]),
            {"status": JobPosting.STATUS_COMPLETED},
            format="json",
        )

        events = list(JobStatusEvent.objects.filter(job=self.job))
        transitions = [(event.entity, event.from_status, event.to_status) for event in events]

        self.assertIn(("application", "pending", "hired"), transitions)
        self.assertIn(("job", "open", "assigned"), transitions)
        self.assertIn(("job", "assigned", "completion_requested"), transitions)
        self.assertIn(("job", "completion_requested", "completed"), transitions)
        self.assertIn(("application", "hired", "completed"), transitions)

        hire_event = next(event for event in events if event.to_status == "hired")
        completion_request = next(
            event for event in events if event.to_status == "completion_requested"
        )
        self.assertEqual(hire_event.actor, self.household)
        self.assertEqual(completion_request.actor, self.worker)

    def test_no_event_is_written_when_the_status_does_not_move(self):
        JobApplication.objects.create(
            job=self.job, worker=self.worker, status=JobApplication.STATUS_HIRED
        )
        self.job.status = JobPosting.STATUS_ASSIGNED
        self.job.save(update_fields=["status"])
        JobStatusEvent.objects.all().delete()

        self.client.force_authenticate(user=self.household)
        self.client.patch(
            reverse("job-detail", args=[self.job.id]),
            {"status": JobPosting.STATUS_ASSIGNED},
            format="json",
        )

        self.assertEqual(JobStatusEvent.objects.count(), 0)


class WorkerLocationPrivacyTests(TestCase):
    """Where the line sits now: a household sees any applicant's exact
    location and route, because that is what the distance map is for. The
    *recommended workers* browse list is different -- it scores every
    candidate in range, most of whom never apply, so it stays on an
    approximate point. Contact details still need a real hire."""

    COORDINATE_KEYS = {"worker_latitude", "worker_longitude", "route_points"}

    def setUp(self):
        self.client = APIClient()
        self.household = User.objects.create_user(username="loc-household", password="password")
        self.other_household = User.objects.create_user(username="loc-other-household", password="password")
        for user in (self.household, self.other_household):
            UserProfile.objects.create(user=user, role=UserProfile.ROLE_HOUSEHOLD, verification_status="verified")
        self.worker = User.objects.create_user(username="loc-worker", password="password")
        self.other_worker = User.objects.create_user(username="loc-other-worker", password="password")
        for index, user in enumerate((self.worker, self.other_worker)):
            UserProfile.objects.create(
                user=user,
                role=UserProfile.ROLE_WORKER,
                verification_status="verified",
                skills=["House Cleaning"],
                latitude=f"13.98{index}0000",
                longitude="121.5800000",
                location_label="Near Mayowe, Tayabas City",
            )
        self.job_a = self._job(self.household, "Job A")
        self.job_b = self._job(self.household, "Job B")
        self.other_job = self._job(self.other_household, "Other household job")

    def _job(self, household, title, boundary="unlimited"):
        return JobPosting.objects.create(
            household=household,
            title=title,
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Saturday",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            geographic_boundary=boundary,
            max_distance_km=999999 if boundary == "unlimited" else 1.0,
        )

    def _route(self, lat1, lon1, lat2, lon2):
        return {
            "distance_km": 2.3456,
            "route_points": [[float(lat1), float(lon1)], [13.97, 121.57], [float(lat2), float(lon2)]],
        }

    def _get(self, user, url, params=None):
        self.client.force_authenticate(user=user)
        with patch("apps.matching.services.fetch_road_route", self._route):
            response = self.client.get(url, params or {})
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def _applications(self, user, job):
        return self._get(user, reverse("job-application-list"), {"job_id": job.id})["results"]

    def _assert_location_shared(self, item):
        self.assertIsNotNone(item.get("worker_latitude"))
        self.assertIsNotNone(item.get("worker_longitude"))
        self.assertTrue(item.get("route_points"))
        self.assertEqual(item.get("route_distance_km", item.get("distance_km")), 2.3)
        self.assertEqual(item["distance_label"], "2.3 km away")

    def test_recommended_workers_still_carry_distance_but_no_coordinates(self):
        for boundary in ("unlimited", "5km"):
            job = self._job(self.household, f"Rec {boundary}", boundary=boundary)
            if boundary == "5km":
                job.max_distance_km = 5.0
                job.save(update_fields=["max_distance_km"])
            for params in ({}, {"rank": "ai"}):
                data = self._get(self.household, reverse("recommended-workers"), {"job_id": job.id, **params})
                self.assertEqual(len(data["results"]), 2, (boundary, params))
                for candidate in data["results"]:
                    self.assertFalse(self.COORDINATE_KEYS & set(candidate), (boundary, params, candidate))
                    self.assertEqual(candidate["distance_km"], 2.3)
                    self.assertEqual(candidate["distance_label"], "2.3 km away")

    def test_recommended_workers_never_include_a_hired_workers_coordinates(self):
        JobApplication.objects.create(job=self.job_a, worker=self.worker, status=JobApplication.STATUS_HIRED)
        data = self._get(self.household, reverse("recommended-workers"), {"job_id": self.job_a.id, "rank": "ai"})
        for candidate in data["results"]:
            self.assertFalse(self.COORDINATE_KEYS & set(candidate))

    def test_recommended_workers_carry_a_grid_snapped_point_for_the_map(self):
        """The matches map pins a candidate's neighbourhood, so the payload
        carries an approximate point -- snapped away from the real house, and
        never alongside the exact coordinates."""
        profile = self.worker.profile
        profile.latitude = "13.9871234"
        profile.longitude = "121.5834567"
        profile.save(update_fields=["latitude", "longitude"])

        data = self._get(self.household, reverse("recommended-workers"), {"job_id": self.job_a.id})
        candidate = next(item for item in data["results"] if item["worker_username"] == self.worker.username)

        self.assertEqual(candidate["worker_approximate_latitude"], 13.99)
        self.assertEqual(candidate["worker_approximate_longitude"], 121.58)
        self.assertFalse(self.COORDINATE_KEYS & set(candidate))

    def test_ai_breakdown_is_too_coarse_to_recover_the_exact_distance(self):
        data = self._get(self.household, reverse("recommended-workers"), {"job_id": self.job_a.id, "rank": "ai"})
        for candidate in data["results"]:
            for key in ("ai_score", "skill_contribution", "proximity_contribution", "skill_similarity"):
                self.assertEqual(candidate[key], round(candidate[key], 2), key)
            self.assertAlmostEqual(
                candidate["skill_contribution"] + candidate["proximity_contribution"], candidate["ai_score"], places=6
            )

    def test_household_sees_location_for_applicants_at_any_status(self):
        for status in (
            JobApplication.STATUS_PENDING,
            JobApplication.STATUS_HIRE_REQUESTED,
            JobApplication.STATUS_REJECTED,
            JobApplication.STATUS_CLOSED,
        ):
            JobApplication.objects.filter(job=self.job_a).delete()
            JobApplication.objects.create(job=self.job_a, worker=self.worker, status=status)
            # Detail resolves the route live (and caches it); the list is
            # cache-only, so read it second.
            detail = self._get(self.household, reverse("job-detail", args=[self.job_a.id]))["applications"][0]
            listed = self._applications(self.household, self.job_a)[0]
            for item in (listed, detail):
                with self.subTest(status=status):
                    self._assert_location_shared(item)

    def test_contact_details_still_need_a_real_hire(self):
        self.household.profile.phone = "09171234567"
        self.household.profile.save(update_fields=["phone"])
        JobApplication.objects.create(job=self.job_a, worker=self.worker)

        pending = self._applications(self.worker, self.job_a)[0]
        self.assertEqual(pending["household_phone"], "")
        self.assertEqual(pending["household_email"], "")

        JobApplication.objects.filter(job=self.job_a).update(status=JobApplication.STATUS_HIRED)
        hired = self._applications(self.worker, self.job_a)[0]
        self.assertEqual(hired["household_phone"], "09171234567")

    def test_household_sees_coordinates_and_route_once_worker_is_hired(self):
        for status in (JobApplication.STATUS_HIRED, JobApplication.STATUS_COMPLETED):
            JobApplication.objects.filter(job=self.job_a).delete()
            JobApplication.objects.create(job=self.job_a, worker=self.worker, status=status)
            detail = self._get(self.household, reverse("job-detail", args=[self.job_a.id]))["applications"][0]
            listed = self._applications(self.household, self.job_a)[0]
            for item in (listed, detail):
                with self.subTest(status=status):
                    self.assertEqual(item["worker_latitude"], 13.98)
                    self.assertEqual(item["worker_longitude"], 121.58)
                    self.assertEqual(item["route_points"][-1], [13.98, 121.58])

    def test_a_household_still_only_sees_its_own_jobs_applicants(self):
        """Opening locations up did not widen *which* applications a
        household can read -- that scoping is what keeps one household out
        of another's applicant list."""
        JobApplication.objects.create(job=self.job_a, worker=self.worker, status=JobApplication.STATUS_HIRED)
        JobApplication.objects.create(job=self.other_job, worker=self.worker)
        self._get(self.other_household, reverse("job-detail", args=[self.other_job.id]))

        self.assertEqual(self._applications(self.other_household, self.job_a), [])
        self.assertEqual(self._get(self.other_household, reverse("job-detail", args=[self.job_a.id]))["applications"], [])

    def test_pending_worker_gets_the_route_to_the_job_site(self):
        """This is the worker-side distance map: it used to render empty for
        anyone not yet hired, which is when they most need it."""
        JobApplication.objects.create(job=self.job_a, worker=self.worker)

        # Job detail resolves the route live (and caches it); the application
        # list is cache-only, so it has to be read second.
        job = self._get(self.worker, reverse("job-detail", args=[self.job_a.id]))
        self.assertTrue(job["route_points"])
        self.assertEqual(float(job["latitude"]), float(self.job_a.latitude))

        own = self._applications(self.worker, self.job_a)[0]
        self.assertTrue(own["route_points"])
        # Still not the household's phone number, though.
        self.assertEqual(own["household_phone"], "")


class JobLifecycleSafeguardTests(TestCase):
    """Regressions from the 2026-09 QA pass: job terms, deletion and the
    applications left behind when a job fills, completes or is cancelled."""

    def setUp(self):
        JobPermissionTests.setUp(self)
        self.client.force_authenticate(user=self.household)

    def _hire(self, application=None):
        application = application or self.application
        response = self.client.patch(
            reverse("job-application-status", args=[application.id]), {"status": "hired"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)

    def test_job_with_applicants_cannot_be_deleted(self):
        response = self.client.delete(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 400)
        self.assertTrue(JobPosting.objects.filter(pk=self.job.pk).exists())

    def test_open_job_without_applicants_can_be_deleted(self):
        self.application.delete()

        response = self.client.delete(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 204)

    def test_edit_rejects_values_that_create_would_reject(self):
        for field, value in [("service_rate", "-100.00"), ("worker_slots", 0), ("max_distance_km", -5)]:
            with self.subTest(field=field):
                response = self.client.patch(reverse("job-detail", args=[self.job.id]), {field: value}, format="json")
                self.assertEqual(response.status_code, 400)

    def test_edit_rejects_end_date_before_existing_start_date(self):
        self.job.job_start_date = "2026-10-10"
        self.job.save(update_fields=["job_start_date"])

        response = self.client.patch(
            reverse("job-detail", args=[self.job.id]), {"job_end_date": "2026-10-01"}, format="json"
        )

        self.assertEqual(response.status_code, 400)

    def test_rate_is_locked_once_a_worker_is_hired(self):
        self._hire()

        response = self.client.patch(reverse("job-detail", args=[self.job.id]), {"service_rate": "50.00"}, format="json")

        self.assertEqual(response.status_code, 400)
        self.job.refresh_from_db()
        self.assertEqual(str(self.job.service_rate), "500.00")

    def test_status_change_still_allowed_after_hiring(self):
        self._hire()

        response = self.client.patch(reverse("job-detail", args=[self.job.id]), {"status": "cancelled"}, format="json")

        self.assertEqual(response.status_code, 200)

    def test_crowded_out_applicant_is_closed_and_notified(self):
        other = User.objects.create_user(username="worker-late", email="late@example.com", password="password")
        UserProfile.objects.create(user=other, role=UserProfile.ROLE_WORKER, verification_status="verified")
        late = JobApplication.objects.create(job=self.job, worker=other)

        self._hire()

        late.refresh_from_db()
        self.assertEqual(late.status, JobApplication.STATUS_CLOSED)
        self.assertTrue(Notification.objects.filter(recipient=other, title="Position filled").exists())

    def test_unhired_applicant_reads_closed_not_completed_when_job_completes(self):
        self.job.worker_slots = 2
        self.job.save(update_fields=["worker_slots"])
        other = User.objects.create_user(username="worker-pending", email="pending@example.com", password="password")
        UserProfile.objects.create(user=other, role=UserProfile.ROLE_WORKER, verification_status="verified")
        pending = JobApplication.objects.create(job=self.job, worker=other)
        self._hire()

        response = self.client.patch(reverse("job-detail", args=[self.job.id]), {"status": "completed"}, format="json")

        self.assertEqual(response.status_code, 200)
        pending.refresh_from_db()
        self.assertEqual(pending.status, JobApplication.STATUS_CLOSED)
        self.client.force_authenticate(user=other)
        rows = self.client.get(reverse("job-application-list"), {"job_id": self.job.id}).data["results"]
        self.assertEqual(rows[0]["status_label"], "Closed")

    def test_hired_worker_is_notified_when_job_is_cancelled(self):
        self._hire()

        self.client.patch(reverse("job-detail", args=[self.job.id]), {"status": "cancelled"}, format="json")

        self.assertTrue(Notification.objects.filter(recipient=self.worker, title="Job cancelled").exists())


class JobRateTypeTests(TestCase):
    """The rate type both clients ask for must be stored and returned, not
    dropped (every rate used to display as "per day")."""

    def test_rate_type_round_trips(self):
        JobPermissionTests.setUp(self)
        self.client.force_authenticate(user=self.household)
        response = self.client.post(reverse("job-list"), {
            "title": "Hourly help", "job_type": "Laundry", "required_skill": "Laundry", "schedule": "Mon",
            "location_label": "Isabang", "latitude": "13.96", "longitude": "121.56",
            "service_rate": "120", "rate_type": "per_hour",
        }, format="json")

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["rate_type"], "per_hour")
        self.assertEqual(response.data["rate_type_label"], "Per Hour")

    def test_unknown_rate_type_rejected(self):
        JobPermissionTests.setUp(self)
        self.client.force_authenticate(user=self.household)
        response = self.client.post(reverse("job-list"), {
            "title": "x", "job_type": "Laundry", "required_skill": "Laundry", "schedule": "Mon",
            "location_label": "Isabang", "latitude": "13.96", "longitude": "121.56",
            "service_rate": "120", "rate_type": "per_lifetime",
        }, format="json")

        self.assertEqual(response.status_code, 400)


class HiringIsHouseholdOnlyTests(TestCase):
    """Hiring belongs to the household that posted the job. Staff accounts
    (the administrators who review IDs and verification documents) previously
    bypassed the owner check on both hiring endpoints, which let an
    administrator hire or reject on a job they had nothing to do with."""

    def setUp(self):
        self.client = APIClient()
        self.household = User.objects.create_user(username="hire-household", password="password")
        self.other_household = User.objects.create_user(username="hire-other-household", password="password")
        self.staff = User.objects.create_user(username="hire-staff", password="password", is_staff=True)
        self.worker = User.objects.create_user(username="hire-worker", password="password")
        for user, role in (
            (self.household, UserProfile.ROLE_HOUSEHOLD),
            (self.other_household, UserProfile.ROLE_HOUSEHOLD),
            (self.staff, UserProfile.ROLE_HOUSEHOLD),
            (self.worker, UserProfile.ROLE_WORKER),
        ):
            UserProfile.objects.create(user=user, role=role, verification_status="verified")
        self.job = JobPosting.objects.create(
            household=self.household,
            title="Owner-only hiring",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Saturday",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            worker_slots=1,
        )
        self.application = JobApplication.objects.create(job=self.job, worker=self.worker)

    def _patch_status(self, user, new_status):
        self.client.force_authenticate(user=user)
        return self.client.patch(
            reverse("job-application-status", args=[self.application.id]),
            {"status": new_status},
            format="json",
        )

    def test_staff_cannot_hire_or_reject_on_someone_elses_job(self):
        for new_status in (JobApplication.STATUS_HIRED, JobApplication.STATUS_REJECTED):
            with self.subTest(status=new_status):
                response = self._patch_status(self.staff, new_status)
                self.assertEqual(response.status_code, 403, response.data)
                self.application.refresh_from_db()
                self.assertEqual(self.application.status, JobApplication.STATUS_PENDING)

    def test_staff_cannot_send_a_hire_request_on_someone_elses_job(self):
        self.client.force_authenticate(user=self.staff)

        response = self.client.post(
            reverse("job-hire-request", args=[self.job.id]),
            {"worker_username": self.worker.username},
            format="json",
        )

        self.assertEqual(response.status_code, 403, response.data)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_PENDING)

    def test_another_household_still_cannot_hire(self):
        response = self._patch_status(self.other_household, JobApplication.STATUS_HIRED)

        self.assertEqual(response.status_code, 403, response.data)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_PENDING)

    def test_the_owning_household_can_still_hire(self):
        response = self._patch_status(self.household, JobApplication.STATUS_HIRED)

        self.assertEqual(response.status_code, 200, response.data)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_HIRED)

    def test_an_unverified_owner_is_still_blocked(self):
        self.household.profile.verification_status = "pending"
        self.household.profile.save(update_fields=["verification_status"])

        response = self._patch_status(self.household, JobApplication.STATUS_HIRED)

        self.assertEqual(response.status_code, 403, response.data)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_PENDING)

    def test_a_staff_account_can_still_hire_on_its_own_job(self):
        """Removing the bypass must not stop a staff member who genuinely
        posted a job from managing their own applicants."""
        own_job = JobPosting.objects.create(
            household=self.staff,
            title="Staff member's own job",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Sunday",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            worker_slots=1,
        )
        own_application = JobApplication.objects.create(job=own_job, worker=self.worker)
        self.client.force_authenticate(user=self.staff)

        response = self.client.patch(
            reverse("job-application-status", args=[own_application.id]),
            {"status": JobApplication.STATUS_HIRED},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        own_application.refresh_from_db()
        self.assertEqual(own_application.status, JobApplication.STATUS_HIRED)


class JobDateValidationTests(TestCase):
    def test_past_job_start_date_rejected(self):
        JobPermissionTests.setUp(self)
        self.client.force_authenticate(user=self.household)
        response = self.client.post(reverse("job-list"), {
            "title": "Past", "job_type": "Laundry", "required_skill": "Laundry", "schedule_type": "One-Time",
            "job_start_date": "2025-01-01",
            "location_label": "Isabang", "latitude": "13.96", "longitude": "121.56", "service_rate": "100",
        }, format="json")
        self.assertEqual(response.status_code, 400)
        self.assertIn("job_start_date", response.data)


class DuplicateJobPostingTests(TestCase):
    """The same posting twice (a double tap, or a retry after a timeout the
    server had actually finished) created a second job and notified every
    matching worker again."""

    def setUp(self):
        self.client = APIClient()
        self.household = User.objects.create_user(username="dup-household", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD, verification_status="verified")
        self.client.force_authenticate(user=self.household)

    def payload(self, **overrides):
        data = {
            "title": "Clean the house",
            "job_type": "House Cleaning",
            "required_skill": "House Cleaning",
            "schedule": "Saturday",
            "location_label": "Alitao, Tayabas City",
            "latitude": "13.9622745",
            "longitude": "121.5632841",
            "service_rate": "500.00",
            "worker_slots": 1,
        }
        data.update(overrides)
        return data

    def post(self, **overrides):
        with patch("apps.jobs.views.enqueue"):
            return self.client.post(reverse("job-list"), self.payload(**overrides), format="json")

    def test_an_identical_open_posting_is_refused(self):
        first = self.post()
        second = self.post()

        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(second.status_code, 409)
        self.assertEqual(JobPosting.objects.filter(household=self.household).count(), 1)

    def test_a_different_posting_is_allowed(self):
        self.post()
        different = self.post(title="Clean the garage")

        self.assertEqual(different.status_code, 201, different.data)

    def test_the_same_job_can_be_reposted_once_the_first_is_closed(self):
        self.post()
        JobPosting.objects.filter(household=self.household).update(status=JobPosting.STATUS_CANCELLED)

        again = self.post()

        self.assertEqual(again.status_code, 201, again.data)


class ApplicantSmartMatchingOrderTests(TestCase):
    """The household reviews applicants in Smart Matching's rule order
    (AGENTS.md I.B): skill match, then verification, then road distance --
    not by who applied last."""

    def setUp(self):
        self.client = APIClient()
        self.household = User.objects.create_user(username="orderhome", password="password")
        UserProfile.objects.create(
            user=self.household, role=UserProfile.ROLE_HOUSEHOLD, verification_status="verified"
        )
        self.job = JobPosting.objects.create(
            household=self.household,
            title="Cleaning help",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-01 09:00",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            geographic_boundary="unlimited",
        )

    def _applicant(self, username, *, skills, verified, distance_km):
        worker = User.objects.create_user(username=username, password="password")
        profile = UserProfile.objects.create(
            user=worker,
            role=UserProfile.ROLE_WORKER,
            verification_status="verified" if verified else "pending",
            skills=skills,
            latitude="13.9700000",
            longitude="121.5700000",
        )
        RouteDistanceCache.objects.create(
            job=self.job,
            worker_profile=profile,
            job_latitude=self.job.latitude,
            job_longitude=self.job.longitude,
            worker_latitude=profile.latitude,
            worker_longitude=profile.longitude,
            distance_km=distance_km,
        )
        JobApplication.objects.create(job=self.job, worker=worker)
        return worker

    def test_job_detail_lists_applicants_in_smart_matching_order(self):
        # Created in the reverse of the expected order, so the old
        # most-recent-first ordering would put them exactly backwards.
        self._applicant("no_skill_near", skills=["Cooking"], verified=True, distance_km="0.5")
        self._applicant("match_unverified", skills=["House Cleaning"], verified=False, distance_km="0.8")
        self._applicant("match_verified_far", skills=["House Cleaning"], verified=True, distance_km="6.0")
        self._applicant("match_verified_near", skills=["House Cleaning"], verified=True, distance_km="1.2")

        self.client.force_authenticate(user=self.household)
        response = self.client.get(reverse("job-detail", args=[self.job.id]))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            [application["worker_username"] for application in response.data["applications"]],
            ["match_verified_near", "match_verified_far", "match_unverified", "no_skill_near"],
        )


class EmploymentHistorySkillRatingTests(TestCase):
    """A worker's employment history carries the per-skill ratings they
    received on each completed job (AGENTS.md II.C)."""

    def test_worker_history_includes_that_workers_skill_ratings_only(self):
        from apps.accounts.models import SkillRating, WorkerSkill

        household = User.objects.create_user(username="historyhome", password="password")
        UserProfile.objects.create(user=household, role=UserProfile.ROLE_HOUSEHOLD, verification_status="verified")
        worker = User.objects.create_user(username="historyworker", password="password")
        UserProfile.objects.create(user=worker, role=UserProfile.ROLE_WORKER, verification_status="verified")
        other = User.objects.create_user(username="otherworker", password="password")
        UserProfile.objects.create(user=other, role=UserProfile.ROLE_WORKER, verification_status="verified")
        job = JobPosting.objects.create(
            household=household,
            title="Two-person cleaning",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-01 09:00",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            worker_slots=2,
            status=JobPosting.STATUS_COMPLETED,
        )
        for each in (worker, other):
            JobApplication.objects.create(job=job, worker=each, status=JobApplication.STATUS_COMPLETED)
        worker_skill = WorkerSkill.objects.create(worker=worker, skill_name="House Cleaning")
        other_skill = WorkerSkill.objects.create(worker=other, skill_name="House Cleaning")
        SkillRating.objects.create(job=job, household=household, worker=worker, skill=worker_skill, rating="4.5")
        SkillRating.objects.create(job=job, household=household, worker=other, skill=other_skill, rating="2.0")

        response = self.client.get(reverse("job-list"), {"worker": worker.id, "status": "completed"})

        self.assertEqual(response.status_code, 200)
        history = response.data["results"]
        self.assertEqual(len(history), 1)
        self.assertEqual(history[0]["skill_ratings"], [{"skill_name": "House Cleaning", "rating": 4.5}])

    def test_skill_ratings_are_empty_outside_a_worker_history(self):
        household = User.objects.create_user(username="browsehome", password="password")
        UserProfile.objects.create(user=household, role=UserProfile.ROLE_HOUSEHOLD, verification_status="verified")
        JobPosting.objects.create(
            household=household,
            title="Open job",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-01 09:00",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
        )

        response = self.client.get(reverse("job-list"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["results"][0]["skill_ratings"], [])
