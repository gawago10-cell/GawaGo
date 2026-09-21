import calendar
import math
from collections import Counter
from decimal import Decimal

from django.contrib.auth.models import User
from django.db.models import Avg, Count, F, Sum
from django.db.models.functions import TruncMonth
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.common.models import VerificationRequest
from apps.jobs.models import JobApplication, JobPosting


BARANGAY_CENTERS = {
    "Alitao": {"latitude": 14.053732435726491, "longitude": 121.53367247279074},
    "Alupay": {"latitude": 14.058062231209304, "longitude": 121.60894317598026},
    "Anos": {"latitude": 13.99232619250926, "longitude": 121.5687256763307},
    "Ayaas": {"latitude": 14.033228404082344, "longitude": 121.61280358513223},
    "Baguio": {"latitude": 14.021320928095191, "longitude": 121.58003973115441},
    "Banilad": {"latitude": 14.04366598567965, "longitude": 121.60287713844916},
    "Calumpang": {"latitude": 13.976661577650393, "longitude": 121.55620698162966},
    "Camaysa": {"latitude": 14.061311651286287, "longitude": 121.55211748652624},
    "Dapdap": {"latitude": 14.059836954143305, "longitude": 121.56928155311572},
    "Gibanga": {"latitude": 14.02426437684045, "longitude": 121.52448299373229},
    "Ibas": {"latitude": 14.056263954528147, "longitude": 121.5858639459556},
    "Ilasan Ilaya": {"latitude": 14.076395444822706, "longitude": 121.62660976250517},
    "Ilasan Ibaba": {"latitude": 14.076395444822706, "longitude": 121.62660976250517},
    "Isabang": {"latitude": 13.962274547948905, "longitude": 121.56328409695064},
    "Ipilan": {"latitude": 14.033357570914804, "longitude": 121.56833532099283},
    "Katigan Kanluran": {"latitude": 14.046025691828351, "longitude": 121.6202812396619},
    "Katigan Silangan": {"latitude": 14.060227861113688, "longitude": 121.62154538337464},
    "Lalo": {"latitude": 14.050261202405046, "longitude": 121.55717481490423},
    "Lakawan": {"latitude": 14.009582881492914, "longitude": 121.62560074991586},
    "Lita": {"latitude": 14.017699813459267, "longitude": 121.59813443683436},
    "Mateuna": {"latitude": 14.023782235513432, "longitude": 121.6406},
    "Mayowe": {"latitude": 13.97392868959356, "longitude": 121.5783335732242},
    "Opias": {"latitude": 14.036073743242486, "longitude": 121.59254781007984},
    "Palale Ilaya": {"latitude": 14.054262032583141, "longitude": 121.6530714222272},
    "Palale Kanluran": {"latitude": 14.041216405063171, "longitude": 121.6540020663721},
    "Palale Ibaba": {"latitude": 14.061429877540817, "longitude": 121.70714387691235},
    "Palale Silangan": {"latitude": 14.089421743230861, "longitude": 121.68915654043055},
    "Tamlong": {"latitude": 14.069116148209835, "longitude": 121.60191813524901},
    "Talolong": {"latitude": 14.077712524215334, "longitude": 121.61401135611793},
    "Tongko": {"latitude": 13.987459902846487, "longitude": 121.60973707319776},
    "Wakas": {"latitude": 14.006911431929879, "longitude": 121.60872288744254},
}

BARANGAYS = list(BARANGAY_CENTERS.keys())
SERVICE_CATEGORIES = [
    "House Cleaning",
    "Cooking",
    "Laundry",
    "Childcare",
    "Elder Care",
    "Gardening",
    "Electrical Work",
    "Plumbing",
    "Carpentry",
    "Painting",
    "Aircon Repair/Cleaning",
    "Welding",
    "Driving",
]


def _decimal_to_float(value):
    if value is None:
        return None
    if isinstance(value, Decimal):
        return float(value)
    return value


def _normalize_barangay_name(value):
    normalized = str(value or "").strip()
    if normalized.lower().startswith("barangay "):
        normalized = normalized[9:].strip()
    for barangay in BARANGAYS:
        if barangay.lower() == normalized.lower():
            return barangay
    return normalized


def _barangay_from_location_label(value):
    parts = [part.strip() for part in str(value or "").split(",") if part.strip()]
    for part in parts:
        normalized = _normalize_barangay_name(part)
        if normalized in BARANGAYS:
            return normalized
    return _normalize_barangay_name(parts[0]) if parts else ""


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


def _build_service_analytics(jobs):
    counts = Counter(job.required_skill for job in jobs if job.required_skill)
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
    rows = (
        JobPosting.objects.values("required_skill")
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
        for row in JobPosting.objects.annotate(month=TruncMonth("created_at"))
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


def build_dashboard_metrics():
    jobs = list(JobPosting.objects.all())
    worker_profiles = list(UserProfile.objects.filter(role=UserProfile.ROLE_WORKER))
    household_profiles = list(UserProfile.objects.filter(role=UserProfile.ROLE_HOUSEHOLD))

    job_barangay_counts = Counter(_barangay_from_location_label(job.location_label) for job in jobs)
    worker_barangay_counts = Counter(_barangay_from_location_label(profile.location_label) for profile in worker_profiles)

    completed_by_barangay = Counter(
        _barangay_from_location_label(job.location_label)
        for job in jobs
        if job.status == JobPosting.STATUS_COMPLETED
    )
    pending_verification_workers = set(
        VerificationRequest.objects.filter(status=VerificationRequest.STATUS_PENDING).values_list("worker_id", flat=True)
    )
    pending_verifications_by_barangay = Counter(
        _barangay_from_location_label(profile.location_label)
        for profile in worker_profiles
        if profile.user_id in pending_verification_workers
    )
    barangay_demand = _build_barangay_analytics(job_barangay_counts, "jobs")
    worker_availability = _build_barangay_analytics(worker_barangay_counts, "workers")

    average_rates_by_category = _build_average_rates_by_category()
    pricing_trends = _build_pricing_trends()

    # A plain Avg("average_rating") weighs a worker with 1 review the same
    # as one with 200 -- weighting each worker's mean by their own
    # rating_count instead recovers the true mean across every individual
    # rating (sum(rating_i * count_i) / sum(count_i) == mean of all rating_i).
    rating_stats = UserProfile.objects.filter(
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
    pending_verifications = VerificationRequest.objects.filter(status=VerificationRequest.STATUS_PENDING).count()
    rejected_verifications = VerificationRequest.objects.filter(status=VerificationRequest.STATUS_REJECTED).count()

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
        "active_applications": JobApplication.objects.filter(status=JobApplication.STATUS_PENDING).count(),
        "total_accounts": User.objects.count(),
        "avg_rating": _decimal_to_float(rating_avg),
        "analytics": {
            "summary": {
                "totalUsers": total_workers + len(household_profiles),
                "totalWorkers": total_workers,
                "households": len(household_profiles),
                "totalJobPostings": len(jobs),
                "activeJobs": sum(1 for job in jobs if job.status == JobPosting.STATUS_OPEN),
                "activeApplications": JobApplication.objects.filter(status=JobApplication.STATUS_PENDING).count(),
                "completedServices": sum(1 for job in jobs if job.status == JobPosting.STATUS_COMPLETED),
                "cancelledRequests": sum(1 for job in jobs if job.status == JobPosting.STATUS_CANCELLED),
                "ongoingMatches": JobPosting.objects.filter(applications__status=JobApplication.STATUS_HIRED).distinct().count(),
                "verifiedUsers": verified_workers,
                "verifiedWorkers": verified_workers,
                "pendingVerifications": pending_verifications,
                "rejectedVerifications": rejected_verifications,
                "rejectedWorkers": rejected_workers,
                "verifiedPercent": round((verified_workers / total_workers) * 100) if total_workers else 0,
                "averageWorkerRating": f"{float(rating_avg):.2f}" if rating_avg is not None else "No ratings yet",
                "ratedWorkerCount": rated_worker_count,
            },
            "monthlyJobRequests": _build_monthly_job_requests(),
            "serviceAnalytics": _build_service_analytics(jobs),
            "geographicAnalytics": {
                "barangayDemand": barangay_demand,
                "workerAvailability": worker_availability,
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
        },
    }
