from unittest.mock import patch

from django.contrib.auth.models import User
from django.core import mail
from django.test import override_settings
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient

from apps.accounts.models import UserProfile
from apps.common.authentication import create_jwt_token
from apps.jobs.models import JobApplication, JobPosting
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
                "preferred_date": "2026-06-02",
                "preferred_time": "09:00",
                "location_label": "Isabang, Tayabas",
                "latitude": "13.9622745",
                "longitude": "121.5632841",
                "service_rate": "500.00",
                "worker_slots": 1,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 403)
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

    def test_job_owner_receives_applicant_location_and_road_route(self):
        self.worker.profile.location_label = "Near Mayowe, Tayabas City"
        self.worker.profile.latitude = "13.9800000"
        self.worker.profile.longitude = "121.5800000"
        self.worker.profile.save(update_fields=["location_label", "latitude", "longitude"])
        route = {
            "distance_km": 6.9,
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
        application = response.data["applications"][0]
        self.assertEqual(application["worker_location_label"], "Near Mayowe, Tayabas City")
        self.assertEqual(application["worker_latitude"], 13.98)
        self.assertEqual(application["worker_longitude"], 121.58)
        self.assertEqual(application["route_distance_km"], 6.9)
        self.assertEqual(application["route_points"][1], [13.97, 121.57])

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

    def test_unrelated_authenticated_worker_cannot_see_exact_job_location(self):
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
        self.assertIsNone(response.data["latitude"])
        self.assertIsNone(response.data["longitude"])
        self.assertEqual(response.data["route_points"], [])

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
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["worker_username"], self.worker.username)
        self.assertEqual(response.data[0]["job_id"], self.job.id)
        self.assertEqual(response.data[0]["job_title"], self.job.title)

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
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["job_id"], self.job.id)

    def test_anonymous_user_cannot_apply_by_worker_username(self):
        response = self.client.post(
            reverse("job-apply", args=[self.job.id]),
            {"worker_username": self.worker.username},
            format="json",
        )

        self.assertEqual(response.status_code, 403)

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
                "schedule": "2026-06-02 09:00",
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
                "preferred_date": "2026-06-02",
                "preferred_time": "09:30",
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
        self.assertEqual(response.data["preferred_date"], "2026-06-02")
        self.assertEqual(response.data["preferred_time"], "09:30:00")
        self.assertEqual(response.data["schedule"], "One-Time on 2026-06-02 at 09:30")
        job = JobPosting.objects.get(title="Structured schedule job")
        self.assertEqual(str(job.preferred_date), "2026-06-02")
        self.assertEqual(job.preferred_time.strftime("%H:%M"), "09:30")

    def test_unverified_household_can_create_job(self):
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
                "preferred_date": "2026-06-02",
                "preferred_time": "09:30",
                "location_label": "Isabang, Tayabas",
                "latitude": "13.9622745",
                "longitude": "121.5632841",
                "service_rate": "500.00",
                "worker_slots": 1,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertTrue(JobPosting.objects.filter(title="Blocked household job").exists())

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
                "preferred_date": "2026-06-13",
                "preferred_time": "09:09",
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

        self.assertEqual(response.status_code, 403)
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

    def test_unverified_household_can_manage_job_applications(self):
        self.household.profile.verification_status = "pending"
        self.household.profile.save(update_fields=["verification_status"])
        self.client.force_authenticate(user=self.household)

        response = self.client.patch(
            reverse("job-application-status", args=[self.application.id]),
            {"status": JobApplication.STATUS_HIRE_REQUESTED},
            format="json",
        )

        self.assertEqual(response.status_code, 200)
        self.application.refresh_from_db()
        self.assertEqual(self.application.status, JobApplication.STATUS_HIRE_REQUESTED)

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
            preferred_date="2026-06-04",
            preferred_time="10:00",
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
