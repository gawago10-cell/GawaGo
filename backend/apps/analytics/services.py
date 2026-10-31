import calendar
import math
from collections import Counter
from decimal import Decimal

from django.db.models import Avg, Count, F, Q, Sum
from django.db.models.functions import TruncMonth
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.common.models import VerificationRequest
from apps.common.barangays import (
    BARANGAY_CENTERS,
    BARANGAYS,
    barangay_from_location_label as _barangay_from_location_label,
    normalize_barangay_name as _normalize_barangay_name,
)
from apps.common.skills import SKILL_CATALOG, canonical_skill_label
from apps.jobs.models import JobApplication, JobPosting


# The barangay table and label parser are shared with reports and the job
# serializer's label masking -- see apps.common.barangays. The service
# categories are the skill catalog the clients offer (apps.common.skills).
SERVICE_CATEGORIES = list(SKILL_CATALOG)


def _decimal_to_float(value):
    if value is None:
        return None
    if isinstance(value, Decimal):
        return float(value)
    return value


def _last_six_months():
    today = timezone.localdate()
    return [
        (today.year + ((today.month - offset - 1) // 12), ((today.month - offset - 1) % 12) + 1)
        for offset in range(5, -1, -1)
    ]


def _build_monthly_job_requests():
    monthly_counts = {
        (row["month"].year, row["month"].month): row["requests"]
        for row in JobPosting.objects.annotate(month=TruncMonth("created_at"))
        .values("month")
        .annotate(requests=Count("id"))
    }
    return [
        {
            "month": calendar.month_abbr[month],
            "requests": monthly_counts.get((year, month), 0),
        }
        for year, month in _last_six_months()
    ]


def _build_application_trend():
    monthly_counts = {
        (row["month"].year, row["month"].month): row["applications"]
        for row in JobApplication.objects.annotate(month=TruncMonth("applied_at"))
        .values("month")
        .annotate(applications=Count("id"))
    }
    return [
        {
            "month": calendar.month_abbr[month],
            "applications": monthly_counts.get((year, month), 0),
        }
        for year, month in _last_six_months()
    ]


def _percent(part, whole):
    return round((part / whole) * 100, 1) if whole else 0.0


def _build_enhanced_analytics(jobs, total_workers):
    """Hiring performance (AGENTS.md IV.A).

    These used to be computed in the web client's offline fallback only, so
    the dashboard showed 0% whenever the API call *succeeded*. The formulas
    deliberately match apps.reports.services so the dashboard and the
    platform report cannot disagree on the same data.
    """
    applications = list(JobApplication.objects.all().values("id", "job_id", "worker_id", "status"))
    hired = [
        application
        for application in applications
        if application["status"] in (JobApplication.STATUS_HIRED, JobApplication.STATUS_COMPLETED)
    ]
    hires_per_worker = Counter(application["worker_id"] for application in hired)
    job_ids = {job.id for job in jobs}
    matched_job_ids = {
        application["job_id"] for application in hired if application["job_id"] in job_ids
    }
    return {
        "hiringSuccessRate": _percent(len(hired), len(applications)),
        "jobMatchRate": _percent(len(matched_job_ids), len(jobs)),
        "workerHiringStats": {
            "hiredWorkers": len(hires_per_worker),
            "hirePercentage": _percent(len(hires_per_worker), total_workers),
            "repeatHires": sum(1 for count in hires_per_worker.values() if count > 1),
        },
        "applicationTrends": _build_application_trend(),
    }


def _build_service_analytics(jobs):
    # Counted under the catalog name, so "Electrician" and "Electrical Work"
    # are one bar rather than two.
    counts = Counter(canonical_skill_label(job.required_skill) for job in jobs if job.required_skill)
    categories = [*SERVICE_CATEGORIES, *[skill for skill in counts if skill not in SERVICE_CATEGORIES]]
    return [
        {
            "service": category.replace("House ", ""),
            "requests": counts.get(category, 0),
        }
        for category in categories
        if counts.get(category, 0) > 0 or category in SERVICE_CATEGORIES
    ]


def _build_barangay_analytics(counter, value_key):
    return sorted(
        [
            {
                "barangay": barangay,
                value_key: count,
            }
            for barangay, count in counter.items()
            if count > 0
        ],
        key=lambda item: item[value_key],
        reverse=True,
    )[:8]


def _build_barangay_demand_vs_supply(job_counts, worker_counts, limit=10):
    """Job requests and available workers side by side for the barangays with
    the most demand -- one list for the Geographic Analytics line chart. The
    two top-8 lists above rank separately, so a barangay in one would read 0
    in the other even when it has some."""
    rows = [
        {
            "barangay": barangay,
            "jobs": job_counts.get(barangay, 0),
            "workers": worker_counts.get(barangay, 0),
        }
        for barangay in set(job_counts) | set(worker_counts)
        if barangay and (job_counts.get(barangay, 0) or worker_counts.get(barangay, 0))
    ]
    rows.sort(key=lambda row: (-row["jobs"], -row["workers"], row["barangay"]))
    return rows[:limit]


def _round_half_up(value):
    """Python's round() rounds half-to-even (4.5 -> 4, 2.5 -> 2), which
    bucket a rating distribution's boundary values the wrong way. Clamped to
    [1, 5] so a sub-0.5 average -- a data anomaly, since ratings are 1-5 --
    still lands in a bucket instead of vanishing from the chart entirely.
    """
    return max(1, min(5, math.floor(value + 0.5)))


def _build_rating_distribution(worker_profiles):
    ratings = [
        float(profile.average_rating)
        for profile in worker_profiles
        if profile.rating_count and profile.average_rating is not None
    ]
    return [
        {
            "stars": f"{stars} star{'s' if stars > 1 else ''}",
            "count": sum(1 for rating in ratings if _round_half_up(rating) == stars),
        }
        for stars in [5, 4, 3, 2, 1]
    ]


def _build_average_rates_by_category():
    # A cancelled job's rate was never actually agreed to or paid, so it must
    # not drag down what households are told to expect for a category
    # (AGENTS.md IV.A: pricing exists "to support fair pricing"; averaging in
    # cancelled postings misrepresents live market rates).
    rows = (
        JobPosting.objects.exclude(status=JobPosting.STATUS_CANCELLED)
        .values("required_skill")
        .annotate(count=Count("id"), average_rate=Avg("service_rate"))
        .order_by("-count", "required_skill")
    )
    return [
        {
            "skill": row["required_skill"],
            "count": row["count"],
            "averageRate": _decimal_to_float(row["average_rate"]) or 0,
        }
        for row in rows
        if row["required_skill"]
    ]


def _build_pricing_trends():
    monthly_rates = {
        (row["month"].year, row["month"].month): {
            "averageRate": _decimal_to_float(row["average_rate"]) or 0,
            "postings": row["postings"],
        }
        for row in JobPosting.objects.exclude(status=JobPosting.STATUS_CANCELLED)
        .annotate(month=TruncMonth("created_at"))
        .values("month")
        .annotate(average_rate=Avg("service_rate"), postings=Count("id"))
    }
    return [
        {
            "month": calendar.month_abbr[month],
            "averageRate": monthly_rates.get((year, month), {}).get("averageRate", 0),
            "postings": monthly_rates.get((year, month), {}).get("postings", 0),
        }
        for year, month in _last_six_months()
    ]


def pending_account_verifications():
    """Household and worker accounts with an ID waiting in the review queue."""
    return (
        UserProfile.objects.filter(user__is_staff=False)
        .exclude(verification_status="verified")
        .filter(user__in=VerificationRequest.objects.filter(status=VerificationRequest.STATUS_PENDING).values("worker"))
        .count()
    )


def active_application_count():
    """Applications still awaiting a decision on a job that is still live."""
    return (
        JobApplication.objects.filter(status=JobApplication.STATUS_PENDING)
        .exclude(job__status__in=[JobPosting.STATUS_COMPLETED, JobPosting.STATUS_CANCELLED])
        .count()
    )


def ongoing_match_count():
    """Jobs whose hired worker is on the job right now."""
    return (
        JobPosting.objects.filter(
            status__in=[JobPosting.STATUS_ASSIGNED, JobPosting.STATUS_COMPLETION_REQUESTED],
            applications__status=JobApplication.STATUS_HIRED,
        )
        .distinct()
        .count()
    )


def build_dashboard_metrics():
    jobs = list(JobPosting.objects.all())
    # Admin accounts can carry a UserProfile (role defaults to worker), so
    # every head count here is limited to real households and workers.
    member_profiles = UserProfile.objects.filter(user__is_staff=False)
    worker_profiles = list(member_profiles.filter(role=UserProfile.ROLE_WORKER))
    household_profiles = list(member_profiles.filter(role=UserProfile.ROLE_HOUSEHOLD))

    job_barangay_counts = Counter(_barangay_from_location_label(job.location_label) for job in jobs)
    worker_barangay_counts = Counter(_barangay_from_location_label(profile.location_label) for profile in worker_profiles)

    completed_by_barangay = Counter(
        _barangay_from_location_label(job.location_label)
        for job in jobs
        if job.status == JobPosting.STATUS_COMPLETED
    )
    pending_verification_workers = set(
        VerificationRequest.objects.filter(
            status=VerificationRequest.STATUS_PENDING, worker__is_staff=False
        ).values_list("worker_id", flat=True)
    )
    pending_verifications_by_barangay = Counter(
        _barangay_from_location_label(profile.location_label)
        for profile in worker_profiles
        if profile.user_id in pending_verification_workers
    )
    barangay_demand = _build_barangay_analytics(job_barangay_counts, "jobs")
    worker_availability = _build_barangay_analytics(worker_barangay_counts, "workers")
    demand_vs_supply = _build_barangay_demand_vs_supply(job_barangay_counts, worker_barangay_counts)

    average_rates_by_category = _build_average_rates_by_category()
    pricing_trends = _build_pricing_trends()

    # A plain Avg("average_rating") weighs a worker with 1 review the same
    # as one with 200 -- weighting each worker's mean by their own
    # rating_count instead recovers the true mean across every individual
    # rating (sum(rating_i * count_i) / sum(count_i) == mean of all rating_i).
    rating_stats = member_profiles.filter(
        role=UserProfile.ROLE_WORKER,
        rating_count__gt=0,
        average_rating__isnull=False,
    ).aggregate(
        weighted_total=Sum(F("average_rating") * F("rating_count")),
        total_count=Sum("rating_count"),
    )
    rating_avg = (
        rating_stats["weighted_total"] / rating_stats["total_count"]
        if rating_stats["total_count"]
        else None
    )
    rated_worker_count = sum(1 for profile in worker_profiles if profile.rating_count and profile.average_rating is not None)

    open_job_slots = JobPosting.objects.filter(status=JobPosting.STATUS_OPEN).aggregate(total=Sum("worker_slots"))["total"] or 0
    total_workers = len(worker_profiles)
    verified_workers = sum(1 for profile in worker_profiles if profile.verification_status == "verified")
    rejected_workers = sum(1 for profile in worker_profiles if profile.verification_status == "rejected")
    # "Verified users" covers households too, and is counted off the profile's
    # own verification status -- the same basis apps.reports.services uses, so
    # the dashboard and the platform report cannot report different totals for
    # the same data. "Pending" means an account with an ID actually waiting in
    # the queue: every new profile starts as "pending" before submitting
    # anything, so the profile status alone counted every unverified account.
    account_verification = member_profiles.aggregate(
        verified=Count("id", filter=Q(verification_status="verified")),
        rejected=Count("id", filter=Q(verification_status="rejected")),
    )
    verified_users = account_verification["verified"]
    pending_verifications = pending_account_verifications()
    rejected_verifications = account_verification["rejected"]
    pending_verification_requests = VerificationRequest.objects.filter(
        status=VerificationRequest.STATUS_PENDING, worker__is_staff=False
    ).count()
    total_accounts_with_profiles = len(worker_profiles) + len(household_profiles)

    heat_map_data = []
    for barangay, center in BARANGAY_CENTERS.items():
        heat_map_data.append(
            {
                "barangay": barangay,
                "value": job_barangay_counts.get(barangay, 0),
                "jobs": job_barangay_counts.get(barangay, 0),
                "workers": worker_barangay_counts.get(barangay, 0),
                "completed": completed_by_barangay.get(barangay, 0),
                "pendingVerifications": pending_verifications_by_barangay.get(barangay, 0),
                **center,
            }
        )

    return {
        "open_jobs": open_job_slots,
        "verified_workers": verified_workers,
        "completed_jobs": JobPosting.objects.filter(status=JobPosting.STATUS_COMPLETED).count(),
        "cancelled_jobs": JobPosting.objects.filter(status=JobPosting.STATUS_CANCELLED).count(),
        "active_applications": active_application_count(),
        "total_accounts": total_accounts_with_profiles,
        "avg_rating": _decimal_to_float(rating_avg),
        "analytics": {
            "summary": {
                "totalUsers": total_workers + len(household_profiles),
                "totalWorkers": total_workers,
                "households": len(household_profiles),
                "totalJobPostings": len(jobs),
                "activeJobs": sum(1 for job in jobs if job.status == JobPosting.STATUS_OPEN),
                "activeApplications": active_application_count(),
                "completedServices": sum(1 for job in jobs if job.status == JobPosting.STATUS_COMPLETED),
                "cancelledRequests": sum(1 for job in jobs if job.status == JobPosting.STATUS_CANCELLED),
                "ongoingMatches": ongoing_match_count(),
                "verifiedUsers": verified_users,
                "verifiedWorkers": verified_workers,
                "pendingVerifications": pending_verifications,
                "pendingVerificationRequests": pending_verification_requests,
                "rejectedVerifications": rejected_verifications,
                "rejectedWorkers": rejected_workers,
                "verifiedPercent": (
                    round((verified_users / total_accounts_with_profiles) * 100)
                    if total_accounts_with_profiles
                    else 0
                ),
                "averageWorkerRating": f"{float(rating_avg):.2f}" if rating_avg is not None else "No ratings yet",
                "ratedWorkerCount": rated_worker_count,
            },
            "monthlyJobRequests": _build_monthly_job_requests(),
            "serviceAnalytics": _build_service_analytics(jobs),
            "geographicAnalytics": {
                "barangayDemand": barangay_demand,
                "workerAvailability": worker_availability,
                "demandVsSupply": demand_vs_supply,
            },
            "barangayJobAnalytics": barangay_demand,
            "barangayWorkerAnalytics": worker_availability,
            "heatMapData": heat_map_data,
            "ratingDistribution": _build_rating_distribution(worker_profiles),
            "rateTransparency": {
                "averageRatesByCategory": average_rates_by_category,
                "pricingTrends": pricing_trends,
            },
            "serviceRateSummary": average_rates_by_category[:5],
            "enhancedAnalytics": _build_enhanced_analytics(jobs, total_workers),
        },
    }
