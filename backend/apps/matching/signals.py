"""
Proactive AI job-match notifications.

When a household posts a new open job, score it against every candidate
worker using the same content-based algorithm as the pull-based
get_recommended_jobs() endpoint (see apps.matching.recommendations), and
notify anyone who scores above JOB_MATCH_NOTIFY_THRESHOLD — instead of
waiting for the worker to click "Find Jobs for Me".

FUTURE ENHANCEMENT: this loop runs synchronously in the request that
creates the job. For a job pool much larger than this capstone's, move it
to a background task (e.g. Celery) so posting a job doesn't wait on
scoring every candidate worker.
"""

from django.conf import settings
from django.db.models import Q
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.jobs.models import JobPosting
from apps.matching.recommendations import score_job_for_worker
from apps.notifications.models import Notification
from apps.notifications.services import create_notification


@receiver(post_save, sender=JobPosting)
def notify_matching_workers(sender, instance, created, **kwargs):
    if not getattr(settings, "ENABLE_JOB_MATCH_NOTIFICATIONS", True):
        return
    if not created or instance.status != JobPosting.STATUS_OPEN:
        return

    threshold = getattr(settings, "JOB_MATCH_NOTIFY_THRESHOLD", 0.5)
    # Excludes a currently suspended worker (permanent, or a timed suspension
    # that hasn't lifted yet) -- a plain is_blocked=True filter would also
    # skip a worker whose timed block already expired but hasn't been lazily
    # cleared by refresh_block_status() yet.
    candidates = UserProfile.objects.select_related("user").filter(
        role=UserProfile.ROLE_WORKER,
        user__is_staff=False,
        user__is_active=True,
    ).exclude(
        Q(is_blocked=True) & (Q(blocked_until__isnull=True) | Q(blocked_until__gt=timezone.now()))
    )

    for profile in candidates:
        try:
            result = score_job_for_worker(instance, profile)
        except Exception:
            # A single worker's scoring failing (e.g. a distance-service
            # network error) should never block notifying everyone else.
            continue

        # An exact skill match always clears the bar, regardless of how the
        # cosine-similarity score got diluted by the worker's *other* listed
        # skills (a worker with 3 skills scores lower on any one of them
        # than a worker with just 1) -- score_job_for_worker() has already
        # enforced the job's hard radius filter by this point, so this
        # isn't bypassing distance, only the skill-dilution artifact.
        if result and (result["ai_score"] >= threshold or result["exact_skill_match"]):
            create_notification(
                recipient=profile.user,
                notification_type=Notification.TYPE_JOB_MATCH,
                title="New job matches your profile",
                message=f"{instance.title} — {round(result['ai_score'] * 100)}% match",
                related_job_id=instance.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                send_email=False,
            )
