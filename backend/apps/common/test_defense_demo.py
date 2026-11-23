"""The capstone-defense demo seed (seed_defense_demo)."""

import io
import tempfile

from django.contrib.auth.models import User
from django.core.management import CommandError, call_command
from django.test import TestCase, override_settings
from django.urls import reverse

from apps.common.test_flow_fixes import client_for
from apps.jobs.models import JobApplication, JobPosting
from apps.reviews.models import Review

MEDIA = tempfile.mkdtemp(prefix="gawago-demo-media-")
PRIVATE = tempfile.mkdtemp(prefix="gawago-demo-private-")


@override_settings(MEDIA_ROOT=MEDIA, PRIVATE_MEDIA_ROOT=PRIVATE, USE_CLOUDINARY=False)
class DefenseDemoSeedTests(TestCase):
    def seed(self, *args):
        call_command("seed_defense_demo", *args, password="DemoPass2026", stdout=io.StringIO())

    def test_it_needs_a_password(self):
        with self.assertRaises(CommandError):
            call_command("seed_defense_demo", password="", stdout=io.StringIO())

    def test_it_builds_the_demo_and_can_run_again(self):
        self.seed()
        counts = (User.objects.count(), JobPosting.objects.count(), JobApplication.objects.count(), Review.objects.count())
        self.seed()
        self.assertEqual(
            (User.objects.count(), JobPosting.objects.count(), JobApplication.objects.count(), Review.objects.count()),
            counts,
        )
        self.assertEqual(counts[:2], (16, 15))
        self.assertTrue(all(user.email.startswith("gawago10+demo.") for user in User.objects.all()))

    def test_the_stories_hold_together(self):
        self.seed()
        fernando = User.objects.get(username="fernando.cruz")
        status = client_for(fernando).get(reverse("job-posting-status")).json()
        self.assertFalse(status["can_post"])
        liza = User.objects.get(username="liza.mendoza")
        self.assertTrue(client_for(liza).get(reverse("job-posting-status")).json()["can_post"])

        rosa = User.objects.get(username="rosa.lim")
        rows = client_for(rosa).get(reverse("job-application-list")).json()
        rows = rows.get("results", rows)
        labels = {row["job_title"]: row["status_label"] for row in rows}
        self.assertEqual(labels["Fiesta cooking helpers"], "Hire request received")
        self.assertEqual(rosa.profile.display_rating, "4.5")

        joy = User.objects.get(username="joy.fernandez")
        jobs = client_for(joy).get(reverse("job-list"), {"accepting": "true"}).json()
        jobs = jobs.get("results", jobs)
        self.assertTrue(jobs)
        self.assertTrue(all(job["apply_blocked_title"] == "Your ID is being reviewed." for job in jobs))

    def test_reset_rebuilds_without_touching_other_accounts(self):
        other = User.objects.create_user("someone-else", "someone@example.com", "pass-12345")
        self.seed()
        self.seed("--reset")
        self.assertTrue(User.objects.filter(pk=other.pk).exists())
        self.assertEqual(JobPosting.objects.count(), 15)
