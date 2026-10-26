from datetime import timedelta
from decimal import Decimal
from io import StringIO

from django.contrib.auth.models import User
from django.core.cache import cache
from django.core.management import call_command
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import UserProfile
from apps.jobs.models import JobApplication, JobPosting
from apps.notifications.models import Notification
from apps.reviews.models import Review
from apps.reviews.services import update_worker_reputation


class ReviewPermissionTests(TestCase):
    def setUp(self):
        # GET /reviews/ throttles its auto-assign sweep via the cache; clear
        # it so one test's trigger doesn't suppress another's.
        cache.clear()
        self.client = APIClient()
        self.household = User.objects.create_user(username="household-reviewer", password="password")
        self.worker = User.objects.create_user(
            username="worker-target",
            first_name="John",
            last_name="Israel",
            password="password",
        )
        self.other_worker = User.objects.create_user(username="worker-other", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        UserProfile.objects.create(user=self.other_worker, role=UserProfile.ROLE_WORKER)
        self.completed_job = JobPosting.objects.create(
            household=self.household,
            title="Completed cleaning",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-01 09:00",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            status=JobPosting.STATUS_COMPLETED,
            completed_at=timezone.now() - timezone.timedelta(hours=73),
        )
        self.completed_application = JobApplication.objects.create(
            job=self.completed_job,
            worker=self.worker,
            status=JobApplication.STATUS_COMPLETED,
        )
        self.open_job = JobPosting.objects.create(
            household=self.household,
            title="Open cleaning",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-02 09:00",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            status=JobPosting.STATUS_OPEN,
        )

    def create_completed_job_for_worker(self, title):
        job = JobPosting.objects.create(
            household=self.household,
            title=title,
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="2026-06-03 09:00",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            status=JobPosting.STATUS_COMPLETED,
            completed_at=timezone.now() - timezone.timedelta(hours=73),
        )
        JobApplication.objects.create(
            job=job,
            worker=self.worker,
            status=JobApplication.STATUS_COMPLETED,
        )
        return job

    def test_anonymous_user_cannot_create_review_by_author_username(self):
        response = self.client.post(
            reverse("review-list-create"),
            {
                "author_username": self.household.username,
                "target_username": self.worker.username,
                "job_id": self.completed_job.id,
                "rating": "5.0",
                "feedback": "Fake review",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 401)
        self.assertFalse(Review.objects.exists())

    def test_authenticated_household_can_review_worker(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.post(
            reverse("review-list-create"),
            {
                "target_username": self.worker.username,
                "job_id": self.completed_job.id,
                "rating": "5.0",
                "feedback": "Good service",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        review = Review.objects.get()
        self.assertEqual(review.author, self.household)
        self.assertEqual(review.target, self.worker)
        self.assertEqual(review.job, self.completed_job)
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.average_rating, Decimal("5.00"))
        self.assertEqual(self.worker.profile.rating_count, 1)
        notification = Notification.objects.get(
            recipient=self.worker,
            notification_type=Notification.TYPE_REVIEW,
            title="New review received",
        )
        self.assertEqual(notification.actor, self.household)
        self.assertEqual(notification.related_job_id, self.completed_job.id)
        self.assertEqual(notification.action_type, Notification.ACTION_REVIEW)
        self.assertEqual(notification.action_url, f"/reviews/jobs/{self.completed_job.id}")
        self.assertFalse(notification.requires_action)

    def test_rating_is_the_metric_average_when_metrics_are_given(self):
        # AGENTS.md II.A: with the metrics provided, the overall rating is
        # their average. The star picker's 5.0 used to be stored beside a
        # 4.5 average, so screens disagreed on the same review.
        self.client.force_authenticate(user=self.household)

        response = self.client.post(
            reverse("review-list-create"),
            {
                "target_username": self.worker.username,
                "job_id": self.completed_job.id,
                "rating": "5.0",
                "quality_of_work": 4,
                "punctuality": 5,
                "communication": 4,
                "professionalism": 5,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(Decimal(str(response.json()["rating"])), Decimal("4.5"))
        self.assertEqual(Decimal(str(response.json()["overall_rating"])), Decimal("4.5"))
        self.assertEqual(Review.objects.get().rating, Decimal("4.5"))
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.average_rating, Decimal("4.50"))

    def test_worker_rating_stats_recalculate_when_ratings_change(self):
        self.client.force_authenticate(user=self.household)
        second_job = self.create_completed_job_for_worker("Completed laundry")

        response = self.client.post(
            reverse("review-list-create"),
            {
                "target_username": self.worker.username,
                "job_id": self.completed_job.id,
                "rating": "5.0",
                "feedback": "Good service",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201)
        second_review = Review.objects.create(
            author=self.household,
            target=self.worker,
            author_role=Review.ROLE_HOUSEHOLD,
            target_role=Review.ROLE_WORKER,
            job=second_job,
            job_title=second_job.title,
            rating="3.0",
            feedback="Okay service",
        )

        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.average_rating, Decimal("4.00"))
        self.assertEqual(self.worker.profile.rating_count, 2)

        second_review.rating = "1.0"
        second_review.save(update_fields=["rating"])
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.average_rating, Decimal("3.00"))
        self.assertEqual(self.worker.profile.rating_count, 2)

        second_review.delete()
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.average_rating, Decimal("5.00"))
        self.assertEqual(self.worker.profile.rating_count, 1)

    def test_review_without_any_rating_is_rejected(self):
        self.client.force_authenticate(user=self.worker)

        response = self.client.post(
            reverse("review-list-create"),
            {"target_username": self.household.username, "job_id": self.completed_job.id, "feedback": "ok"},
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(Review.objects.exists())

    def test_worker_can_review_household_after_completed_job(self):
        self.client.force_authenticate(user=self.worker)

        response = self.client.post(
            reverse("review-list-create"),
            {
                "target_username": self.household.username,
                "job_id": self.completed_job.id,
                "rating": "4.0",
                "feedback": "Fair household",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        review = Review.objects.get()
        self.assertEqual(review.author, self.worker)
        self.assertEqual(review.target, self.household)
        self.assertEqual(review.rating, Decimal("4.0"))
        self.household.profile.refresh_from_db()
        self.assertEqual(self.household.profile.average_rating, Decimal("4.00"))
        self.assertEqual(self.household.profile.rating_count, 1)
        self.assertIsNone(response.data["author"])
        self.assertEqual(response.data["author_username"], "")
        self.assertEqual(response.data["author_name"], "j*** i*****")
        notification = Notification.objects.get(
            recipient=self.household,
            notification_type=Notification.TYPE_REVIEW,
            title="New feedback received",
        )
        # The feedback is anonymous, so the notification must not name its author.
        self.assertIsNone(notification.actor)
        self.assertEqual(notification.related_job_id, self.completed_job.id)
        self.assertEqual(notification.action_type, Notification.ACTION_REVIEW)
        self.assertEqual(notification.action_url, f"/reviews/jobs/{self.completed_job.id}")
        self.assertFalse(notification.requires_action)

    def test_worker_feedback_author_is_hidden_when_household_fetches_reviews(self):
        Review.objects.create(
            author=self.worker,
            target=self.household,
            author_role=Review.ROLE_WORKER,
            target_role=Review.ROLE_HOUSEHOLD,
            job=self.completed_job,
            job_title=self.completed_job.title,
            feedback="Fair household",
        )

        response = self.client.get(reverse("review-list-create"), {"username": self.household.username})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["results"]), 1)
        self.assertIsNone(response.data["results"][0]["author"])
        self.assertEqual(response.data["results"][0]["author_username"], "")
        self.assertEqual(response.data["results"][0]["author_name"], "j*** i*****")
        self.assertEqual(response.data["results"][0]["feedback"], "Fair household")

    def test_public_author_filter_does_not_expose_worker_feedback(self):
        Review.objects.create(
            author=self.worker,
            target=self.household,
            author_role=Review.ROLE_WORKER,
            target_role=Review.ROLE_HOUSEHOLD,
            job=self.completed_job,
            job_title=self.completed_job.title,
            feedback="Fair household",
        )

        response = self.client.get(reverse("review-list-create"), {"author_username": self.worker.username})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["results"], [])

    def test_worker_can_fetch_own_given_feedback_without_author_identity(self):
        Review.objects.create(
            author=self.worker,
            target=self.household,
            author_role=Review.ROLE_WORKER,
            target_role=Review.ROLE_HOUSEHOLD,
            job=self.completed_job,
            job_title=self.completed_job.title,
            feedback="Fair household",
        )
        self.client.force_authenticate(user=self.worker)

        response = self.client.get(reverse("review-list-create"), {"author_username": self.worker.username})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data["results"]), 1)
        self.assertIsNone(response.data["results"][0]["author"])
        self.assertEqual(response.data["results"][0]["author_username"], "")
        self.assertEqual(response.data["results"][0]["author_name"], "j*** i*****")

    def test_household_review_author_identity_is_still_visible(self):
        Review.objects.create(
            author=self.household,
            target=self.worker,
            author_role=Review.ROLE_HOUSEHOLD,
            target_role=Review.ROLE_WORKER,
            job=self.completed_job,
            job_title=self.completed_job.title,
            rating="5.0",
            feedback="Good service",
        )

        response = self.client.get(reverse("review-list-create"), {"username": self.worker.username})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["results"][0]["author"], self.household.id)
        self.assertEqual(response.data["results"][0]["author_username"], self.household.username)

    def test_household_cannot_review_same_worker_twice_for_completed_job(self):
        self.client.force_authenticate(user=self.household)
        payload = {
            "target_username": self.worker.username,
            "job_id": self.completed_job.id,
            "rating": "5.0",
            "feedback": "Good service",
        }

        first_response = self.client.post(reverse("review-list-create"), payload, format="json")
        second_response = self.client.post(
            reverse("review-list-create"),
            {**payload, "feedback": "Trying again"},
            format="json",
        )

        self.assertEqual(first_response.status_code, 201)
        self.assertEqual(second_response.status_code, 400)
        self.assertEqual(Review.objects.count(), 1)

    def test_review_requires_completed_job(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.post(
            reverse("review-list-create"),
            {
                "target_username": self.worker.username,
                "job_id": self.open_job.id,
                "rating": "5.0",
                "feedback": "Too early",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(Review.objects.exists())

    def test_review_requires_completed_relationship_between_users(self):
        self.client.force_authenticate(user=self.household)

        response = self.client.post(
            reverse("review-list-create"),
            {
                "target_username": self.other_worker.username,
                "job_id": self.completed_job.id,
                "rating": "5.0",
                "feedback": "No completed application",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(Review.objects.exists())

    def test_same_role_review_is_rejected(self):
        self.client.force_authenticate(user=self.worker)

        response = self.client.post(
            reverse("review-list-create"),
            {
                "target_username": self.other_worker.username,
                "job_id": self.completed_job.id,
                "feedback": "Same role feedback",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400)
        self.assertFalse(Review.objects.exists())

    def test_worker_cannot_review_same_household_twice_for_completed_job(self):
        self.client.force_authenticate(user=self.worker)
        payload = {
            "target_username": self.household.username,
            "job_id": self.completed_job.id,
            "rating": "5.0",
            "feedback": "Good household",
        }

        first_response = self.client.post(reverse("review-list-create"), payload, format="json")
        second_response = self.client.post(
            reverse("review-list-create"),
            {**payload, "feedback": "Trying again"},
            format="json",
        )

        self.assertEqual(first_response.status_code, 201)
        self.assertEqual(second_response.status_code, 400)
        self.assertEqual(Review.objects.count(), 1)

    def test_review_scored_only_on_metrics_still_counts_toward_the_average(self):
        # No overall `rating` at all -- only the four detail metrics. This
        # still has a real effective_review_rating (their average of 4.0)
        # and must not be silently dropped from the worker's aggregate.
        Review.objects.create(
            author=self.household,
            target=self.worker,
            author_role=Review.ROLE_HOUSEHOLD,
            target_role=Review.ROLE_WORKER,
            job=self.completed_job,
            job_title=self.completed_job.title,
            rating=None,
            quality_of_work=4,
            punctuality=4,
            communication=4,
            professionalism=4,
        )

        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.rating_count, 1)
        self.assertEqual(self.worker.profile.average_rating, Decimal("4.00"))

    def test_default_rating_command_assigns_no_feedback_rating_after_window(self):
        output = StringIO()

        call_command("assign_default_worker_ratings", stdout=output)

        review = Review.objects.get()
        self.assertEqual(review.author, self.household)
        self.assertEqual(review.target, self.worker)
        self.assertEqual(review.job, self.completed_job)
        self.assertEqual(review.rating, Decimal("3.5"))
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.average_rating, Decimal("3.50"))
        self.assertEqual(self.worker.profile.rating_count, 1)
        self.assertIn("1 default worker rating(s) assigned", output.getvalue())

    def test_household_can_still_submit_a_real_review_after_the_default_was_assigned(self):
        call_command("assign_default_worker_ratings", stdout=StringIO())
        default_review = Review.objects.get()
        self.assertTrue(default_review.is_system_generated)

        self.client.force_authenticate(user=self.household)
        response = self.client.post(
            reverse("review-list-create"),
            {
                "target_username": self.worker.username,
                "job_id": self.completed_job.id,
                "rating": "5.0",
                "feedback": "Actually excellent work.",
            },
            format="json",
        )

        # Replaces the placeholder in place rather than rejecting as a
        # duplicate -- the household never actually gave the 3.5 rating.
        self.assertEqual(response.status_code, 200)
        self.assertEqual(Review.objects.count(), 1)
        review = Review.objects.get()
        self.assertEqual(review.id, default_review.id)
        self.assertEqual(review.rating, Decimal("5.0"))
        self.assertEqual(review.feedback, "Actually excellent work.")
        self.assertFalse(review.is_system_generated)
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.average_rating, Decimal("5.00"))

    def test_default_rating_sweep_on_read_is_throttled(self):
        # Without the cooldown, a looped anonymous GET would re-run the sweep
        # (and its DB writes) on every single request.
        self.client.get(reverse("review-list-create"), {"username": self.worker.username})
        self.assertEqual(Review.objects.count(), 1)
        Review.objects.all().delete()

        self.client.get(reverse("review-list-create"), {"username": self.worker.username})

        self.assertEqual(Review.objects.count(), 0)

    def test_default_rating_is_assigned_automatically_when_reviews_are_loaded(self):
        response = self.client.get(reverse("review-list-create"), {"username": self.worker.username})

        self.assertEqual(response.status_code, 200)
        self.assertEqual(Review.objects.count(), 1)
        self.assertEqual(Review.objects.get().rating, Decimal("3.5"))
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.average_rating, Decimal("3.50"))
        self.assertEqual(response.data["results"][0]["rating"], "3.5")

    def test_default_rating_command_skips_recent_completed_jobs(self):
        self.completed_job.completed_at = timezone.now() - timezone.timedelta(hours=47)
        self.completed_job.save(update_fields=["completed_at"])

        call_command("assign_default_worker_ratings", stdout=StringIO())

        self.assertFalse(Review.objects.exists())

    def test_default_rating_command_skips_existing_household_rating(self):
        Review.objects.create(
            author=self.household,
            target=self.worker,
            author_role=Review.ROLE_HOUSEHOLD,
            target_role=Review.ROLE_WORKER,
            job=self.completed_job,
            job_title=self.completed_job.title,
            rating="4.0",
            feedback="Manual rating",
        )

        call_command("assign_default_worker_ratings", stdout=StringIO())

        self.assertEqual(Review.objects.count(), 1)
        self.assertEqual(Review.objects.get().rating, Decimal("4.0"))

    def test_default_rating_command_dry_run_does_not_create_reviews(self):
        output = StringIO()

        call_command("assign_default_worker_ratings", "--dry-run", stdout=output)

        self.assertFalse(Review.objects.exists())
        self.assertIn("1 default worker rating(s) would be assigned", output.getvalue())


class RatingTrendTests(TestCase):
    """calculate_rating_trend (roadmap audit MEDIUM #14): must not flip on a
    single review per window, and a stale stored trend must self-heal when
    that worker's reviews are next read."""

    def setUp(self):
        cache.clear()
        self.household = User.objects.create_user(username="trend-household", password="password")
        self.worker = User.objects.create_user(username="trend-worker", password="password")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)

    def _review(self, rating, days_ago):
        review = Review.objects.create(
            author=self.household,
            target=self.worker,
            author_role=Review.ROLE_HOUSEHOLD,
            target_role=Review.ROLE_WORKER,
            rating=rating,
        )
        Review.objects.filter(pk=review.pk).update(created_at=timezone.now() - timedelta(days=days_ago))
        return review

    def test_trend_does_not_flip_on_a_single_review_per_window(self):
        # One old review and one new, higher-rated review -- not enough
        # samples in either window to call this an actual trend.
        self._review(4.0, days_ago=40)
        self._review(5.0, days_ago=1)

        update_worker_reputation(self.worker)
        self.worker.profile.refresh_from_db()

        self.assertEqual(self.worker.profile.rating_trend, "neutral")

    def test_trend_improves_with_enough_samples_in_each_window(self):
        self._review(3.0, days_ago=40)
        self._review(3.0, days_ago=35)
        self._review(5.0, days_ago=2)
        self._review(5.0, days_ago=1)

        update_worker_reputation(self.worker)
        self.worker.profile.refresh_from_db()

        self.assertEqual(self.worker.profile.rating_trend, "improving")

    def test_stale_trend_self_heals_when_reviews_are_read(self):
        # Both reviews are now more than 30 days old, so a fresh computation
        # finds zero "recent" reviews and returns neutral -- but the profile
        # still carries whatever was last computed for it.
        self._review(3.0, days_ago=60)
        self._review(3.0, days_ago=55)
        self.worker.profile.rating_trend = "improving"
        self.worker.profile.save(update_fields=["rating_trend"])

        response = self.client.get(reverse("review-list-create"), {"username": self.worker.username})

        self.assertEqual(response.status_code, 200)
        self.worker.profile.refresh_from_db()
        self.assertEqual(self.worker.profile.rating_trend, "neutral")


class ReputationTierTests(TestCase):
    """AGENTS.md II.A: tiers above New need 5+ reviews."""

    def _tier(self, rating, count):
        from apps.accounts.models import UserProfile
        from apps.reviews.services import calculate_reputation_tier

        user = User.objects.create_user(username=f"tier-{rating}-{count}", password="password")
        UserProfile.objects.create(
            user=user, role=UserProfile.ROLE_WORKER, average_rating=Decimal(rating), rating_count=count
        )
        return calculate_reputation_tier(user)

    def test_few_reviews_stay_new_even_at_five_stars(self):
        self.assertEqual(self._tier("5.00", 2), "new")
        self.assertEqual(self._tier("5.00", 4), "new")

    def test_tiers_with_five_reviews(self):
        self.assertEqual(self._tier("4.60", 5), "elite")
        self.assertEqual(self._tier("4.10", 5), "trusted")
        self.assertEqual(self._tier("3.60", 5), "established")
        self.assertEqual(self._tier("3.00", 5), "new")
