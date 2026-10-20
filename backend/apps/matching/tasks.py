"""Proactive AI job-match notifications, run in the background.

When a household posts an open job, the job-create view schedules
run_job_match_notifications(job.id) with transaction.on_commit + enqueue()
(apps.common.background). It scores the job against every eligible worker
with the same content-based algorithm as get_recommended_jobs() and notifies
anyone at or above JOB_MATCH_NOTIFY_THRESHOLD (or with an exact skill match).

Safe to run more than once for the same job: a worker already notified about
this job is skipped, and a database constraint backs that up if two runs
overlap.
"""

import logging
import time

from django.conf import settings
from django.db import IntegrityError, transaction

from apps.accounts.models import UserProfile
from apps.jobs.models import JobPosting
from apps.matching.recommendations import _within_radius, score_pair_with_distance
from apps.matching.services import get_road_route_for_match, straight_line_distance_km
from apps.notifications.models import Notification
from apps.notifications.services import create_notification

logger = logging.getLogger(__name__)

# Django-Q2 kills a task that runs longer than this. Each routing call is
# capped at OPENROUTESERVICE_TIMEOUT_SECONDS, so this bounds a large pass.
JOB_MATCH_TASK_TIMEOUT_SECONDS = 600


def eligible_workers():
    return (
        UserProfile.objects.select_related("user")
        .filter(role=UserProfile.ROLE_WORKER, user__is_staff=False, user__is_active=True)
        .not_suspended()
    )


def _distance_km(job, profile):
    """Road distance, falling back to straight-line when routing fails.

    Straight-line is never longer than the road route, so the fallback can
    only admit a borderline worker, never wrongly exclude one."""
    try:
        distance_km = get_road_route_for_match(job, profile)["distance_km"]
    except Exception:
        logger.warning("job-match: routing raised for job=%s worker=%s", job.id, profile.user_id, exc_info=True)
        distance_km = None
    if distance_km is None:
        distance_km = straight_line_distance_km(job.latitude, job.longitude, profile.latitude, profile.longitude)
        return distance_km, True
    return distance_km, False


def _notify(job, profile, result):
    """Create the notification; False if this worker already has one for this
    job (the conditional unique constraint catches an overlapping run)."""
    try:
        with transaction.atomic():
            create_notification(
                recipient=profile.user,
                notification_type=Notification.TYPE_JOB_MATCH,
                title="New job matches your profile",
                message=f"{job.title} — {round(result['ai_score'] * 100)}% match",
                related_job_id=job.id,
                action_type=Notification.ACTION_JOB_DETAIL,
                send_email=False,
            )
    except IntegrityError:
        return False
    return True


def run_job_match_notifications(job_id):
    """Returns the number of notifications sent (0 if the job is gone/closed)."""
    started = time.monotonic()
    job = JobPosting.objects.filter(pk=job_id).first()
    if job is None or job.status != JobPosting.STATUS_OPEN:
        logger.info("job-match: skipped job=%s (%s)", job_id, "deleted" if job is None else f"status={job.status}")
        return 0

    logger.info("job-match: start job=%s", job_id)
    threshold = getattr(settings, "JOB_MATCH_NOTIFY_THRESHOLD", 0.5)
    already_notified = set(
        Notification.objects.filter(
            notification_type=Notification.TYPE_JOB_MATCH, related_job_id=job.id
        ).values_list("recipient_id", flat=True)
    )
    scored = sent = fallbacks = failed = 0

    for profile in eligible_workers():
        if profile.user_id in already_notified or not profile.has_location:
            continue
        # The road is never shorter than the straight line, so a worker
        # already outside the radius as the crow flies is skipped without a
        # routing call -- one call per worker in the city is what pushed a
        # large pass past its timeout.
        straight_km = straight_line_distance_km(job.latitude, job.longitude, profile.latitude, profile.longitude)
        if straight_km is not None and not _within_radius(job, straight_km):
            continue
        try:
            distance_km, used_fallback = _distance_km(job, profile)
            fallbacks += used_fallback
            if not _within_radius(job, distance_km):
                continue
            result = score_pair_with_distance(job, profile, distance_km)
            scored += 1
        except Exception:
            # One worker's bad data must never stop everyone else's.
            failed += 1
            logger.exception("job-match: scoring failed for job=%s worker=%s", job.id, profile.user_id)
            continue

        # An exact skill match always clears the bar, regardless of how the
        # cosine-similarity score got diluted by the worker's *other* listed
        # skills (a worker with 3 skills scores lower on any one of them than
        # a worker with just 1). The radius filter has already run above, so
        # this only bypasses the dilution artifact, not distance.
        if result and (result["ai_score"] >= threshold or result["exact_skill_match"]):
            sent += _notify(job, profile, result)

    logger.info(
        "job-match: finish job=%s scored=%s notified=%s routing_fallbacks=%s failed=%s duration=%.2fs",
        job_id, scored, sent, fallbacks, failed, time.monotonic() - started,
    )
    return sent
