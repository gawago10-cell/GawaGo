"""Report aggregation for the three GawaGo audiences.

Each build_*_report() returns the same envelope -- {"scope", "period",
"summary", "sections"} -- so one serializer, one CSV writer, and one set of
client-side renderers cover all three. A "section" is a titled table of
{"label", "value"} style rows, which is what both the web and mobile report
screens draw.

Money figures are sums of a job's offered service_rate over the jobs counted,
not a payment ledger -- GawaGo does not process payments, so this is the
agreed rate for work that reached `completed`, and it is labelled as such.
"""

from collections import OrderedDict
from datetime import timedelta
from decimal import Decimal

from django.contrib.auth.models import User
from django.db.models import Avg, Count, F, Q, Sum
from django.utils import timezone

from apps.accounts.models import UserProfile
from apps.analytics.services import pending_account_verifications
from apps.common.barangays import barangay_from_location_label
from apps.jobs.models import JobApplication, JobPosting
from apps.reviews.models import Review

SCOPE_HOUSEHOLD = "household"
SCOPE_WORKER = "worker"
SCOPE_PLATFORM = "platform"

DEFAULT_PERIOD_DAYS = 180
MONTHLY_BUCKETS_MIN = 6
MONTHLY_BUCKETS_MAX = 24


def resolve_period(start=None, end=None):
    """Normalize an optional start/end pair into a concrete reporting window.

    Defaults to the trailing DEFAULT_PERIOD_DAYS so a report is never
    unbounded, and swaps reversed bounds rather than returning an empty
    window, which reads as "no activity" and hides real data.
    """
    today = timezone.localdate()
    end_date = end or today
    start_date = start or (end_date - timedelta(days=DEFAULT_PERIOD_DAYS))
    if start_date > end_date:
        start_date, end_date = end_date, start_date
    return {"start": start_date, "end": end_date}


def _within(period):
    """Filter kwargs for models timestamped with `created_at`."""
    return {"created_at__date__gte": period["start"], "created_at__date__lte": period["end"]}


def _float(value):
    if value is None:
        return 0.0
    if isinstance(value, Decimal):
        return float(value)
    return float(value)


def _percent(part, whole):
    if not whole:
        return 0.0
    return round((part / whole) * 100, 1)


def _month_buckets(period):
    """Ordered 'Mon YYYY' keys covering the requested window, newest last so
    charts read left-to-right.

    Bucket count follows the actual start/end span (clamped to
    [MONTHLY_BUCKETS_MIN, MONTHLY_BUCKETS_MAX]) instead of a fixed 6, so a
    custom range wider than 6 months no longer silently drops everything
    before the trailing 6 months from the monthly chart.
    """
    start, end = period["start"], period["end"]
    span_months = (end.year - start.year) * 12 + (end.month - start.month) + 1
    bucket_count = max(MONTHLY_BUCKETS_MIN, min(span_months, MONTHLY_BUCKETS_MAX))
    buckets = OrderedDict()
    cursor = end.replace(day=1)
    months = []
    for _ in range(bucket_count):
        months.append(cursor)
        cursor = (cursor - timedelta(days=1)).replace(day=1)
    for month in reversed(months):
        buckets[month.strftime("%b %Y")] = month
    return buckets


def _monthly_counts(period, queryset, date_field="created_at"):
    buckets = _month_buckets(period)
    counts = OrderedDict((label, 0) for label in buckets)
    for record in queryset:
        stamp = getattr(record, date_field, None)
        if stamp is None:
            continue
        label = timezone.localtime(stamp).strftime("%b %Y") if timezone.is_aware(stamp) else stamp.strftime("%b %Y")
        if label in counts:
            counts[label] += 1
    return counts


def _section(title, description, columns, rows):
    return {"title": title, "description": description, "columns": columns, "rows": rows}


def build_household_report(user: User, period):
    """What a household has spent, posted, and who they hired."""
    jobs = list(JobPosting.objects.filter(household=user, **_within(period)))
    job_ids = [job.id for job in jobs]
    completed = [job for job in jobs if job.status == JobPosting.STATUS_COMPLETED]
    cancelled = [job for job in jobs if job.status == JobPosting.STATUS_CANCELLED]
    open_jobs = [job for job in jobs if job.status == JobPosting.STATUS_OPEN]

    applications = JobApplication.objects.filter(job_id__in=job_ids).select_related("worker")
    pending = [app for app in applications if app.status == JobApplication.STATUS_PENDING]
    hired = [
        app
        for app in applications
        if app.status in (JobApplication.STATUS_HIRED, JobApplication.STATUS_COMPLETED)
    ]

    hires_per_worker = OrderedDict()
    for application in hired:
        hires_per_worker.setdefault(application.worker, 0)
        hires_per_worker[application.worker] += 1
    repeat_hires = sum(1 for count in hires_per_worker.values() if count > 1)

    total_spend = sum(_float(job.service_rate) for job in completed)
    reviews_given = Review.objects.filter(author=user, **_within(period))
    average_given = reviews_given.aggregate(value=Avg("rating"))["value"]

    by_service = OrderedDict()
    for job in jobs:
        key = job.required_skill or job.job_type or "Unspecified"
        by_service[key] = by_service.get(key, 0) + 1

    monthly = _monthly_counts(period, jobs)

    summary = {
        "jobsPosted": len(jobs),
        "openJobs": len(open_jobs),
        "completedJobs": len(completed),
        "cancelledJobs": len(cancelled),
        "applicationsReceived": len(applications),
        "pendingApplications": len(pending),
        "workersHired": len(hires_per_worker),
        "repeatHires": repeat_hires,
        "completionRate": _percent(len(completed), len(jobs)),
        "totalSpend": round(total_spend, 2),
        "averageJobRate": round(total_spend / len(completed), 2) if completed else 0.0,
        "reviewsGiven": reviews_given.count(),
        "averageRatingGiven": round(_float(average_given), 2) if average_given is not None else None,
    }

    sections = [
        _section(
            "Jobs by service type",
            "Which services you post most often.",
            ["Service", "Jobs posted"],
            [[service, count] for service, count in sorted(by_service.items(), key=lambda item: -item[1])],
        ),
        _section(
            "Monthly posting activity",
            "Jobs you posted each month in this period.",
            ["Month", "Jobs posted"],
            [[month, count] for month, count in monthly.items()],
        ),
        _section(
            "Workers you hired",
            "Hire counts per worker, highest first. More than one hire is a repeat hire.",
            ["Worker", "Times hired"],
            [
                [worker.get_full_name() or worker.username, count]
                for worker, count in sorted(hires_per_worker.items(), key=lambda item: -item[1])
            ],
        ),
    ]

    return {
        "scope": SCOPE_HOUSEHOLD,
        "title": "Household activity report",
        "period": period,
        "summary": summary,
        "sections": sections,
    }


def build_worker_report(user: User, period):
    """What a worker applied to, won, earned, and how they were rated."""
    applications = list(
        JobApplication.objects.filter(worker=user, applied_at__date__gte=period["start"], applied_at__date__lte=period["end"])
        .select_related("job")
    )
    hired = [
        app
        for app in applications
        if app.status in (JobApplication.STATUS_HIRED, JobApplication.STATUS_COMPLETED)
    ]
    completed = [app for app in applications if app.status == JobApplication.STATUS_COMPLETED]
    rejected = [app for app in applications if app.status == JobApplication.STATUS_REJECTED]
    pending = [
        app
        for app in applications
        if app.status in (JobApplication.STATUS_PENDING, JobApplication.STATUS_HIRE_REQUESTED)
    ]

    total_earnings = sum(_float(app.job.service_rate) for app in completed if app.job_id)

    reviews = Review.objects.filter(target=user, **_within(period))
    metric_averages = reviews.aggregate(
        quality=Avg("quality_of_work"),
        punctuality=Avg("punctuality"),
        communication=Avg("communication"),
        professionalism=Avg("professionalism"),
        overall=Avg("rating"),
    )

    profile = getattr(user, "profile", None)

    by_skill = OrderedDict()
    for application in completed:
        job = application.job
        if job is None:
            continue
        key = job.required_skill or job.job_type or "Unspecified"
        by_skill[key] = by_skill.get(key, 0) + 1

    monthly = _monthly_counts(period, applications, date_field="applied_at")

    summary = {
        "applicationsSubmitted": len(applications),
        "pendingApplications": len(pending),
        "timesHired": len(hired),
        "jobsCompleted": len(completed),
        "applicationsRejected": len(rejected),
        "hireRate": _percent(len(hired), len(applications)),
        "completionRate": _percent(len(completed), len(hired)),
        "totalEarnings": round(total_earnings, 2),
        "averageJobRate": round(total_earnings / len(completed), 2) if completed else 0.0,
        "reviewsReceived": reviews.count(),
        "averageRating": round(_float(metric_averages["overall"]), 2) if metric_averages["overall"] is not None else None,
        "reputationTier": getattr(profile, "reputation_tier", None),
        "ratingTrend": getattr(profile, "rating_trend", None),
    }

    rating_rows = [
        ["Quality of work", round(_float(metric_averages["quality"]), 2) if metric_averages["quality"] is not None else "No ratings yet"],
        ["Punctuality", round(_float(metric_averages["punctuality"]), 2) if metric_averages["punctuality"] is not None else "No ratings yet"],
        ["Communication", round(_float(metric_averages["communication"]), 2) if metric_averages["communication"] is not None else "No ratings yet"],
        ["Professionalism", round(_float(metric_averages["professionalism"]), 2) if metric_averages["professionalism"] is not None else "No ratings yet"],
    ]

    sections = [
        _section(
            "Rating breakdown",
            "Your average score on each review metric, out of 5.",
            ["Metric", "Average"],
            rating_rows,
        ),
        _section(
            "Completed jobs by skill",
            "Which of your skills actually win work.",
            ["Skill", "Jobs completed"],
            [[skill, count] for skill, count in sorted(by_skill.items(), key=lambda item: -item[1])],
        ),
        _section(
            "Monthly application activity",
            "Applications you submitted each month in this period.",
            ["Month", "Applications"],
            [[month, count] for month, count in monthly.items()],
        ),
    ]

    return {
        "scope": SCOPE_WORKER,
        "title": "Worker activity report",
        "period": period,
        "summary": summary,
        "sections": sections,
    }


def build_platform_report(period):
    """Platform-wide totals for administrators.

    Mirrors the metrics AGENTS.md section IV.A requires of the employment
    analytics dashboard, in the exportable report shape.
    """
    jobs = JobPosting.objects.filter(**_within(period))
    job_list = list(jobs)
    completed = [job for job in job_list if job.status == JobPosting.STATUS_COMPLETED]
    cancelled = [job for job in job_list if job.status == JobPosting.STATUS_CANCELLED]

    applications = JobApplication.objects.filter(
        applied_at__date__gte=period["start"], applied_at__date__lte=period["end"]
    )
    application_list = list(applications)
    hired = [
        app
        for app in application_list
        if app.status in (JobApplication.STATUS_HIRED, JobApplication.STATUS_COMPLETED)
    ]
    # jobMatchRate's denominator (job_list) is jobs *posted* in this period,
    # so the numerator has to be restricted to those same jobs -- otherwise a
    # hire this period against a job posted in an earlier period inflates the
    # count without being one of the jobs the rate is supposed to be "out
    # of", letting the rate exceed 100%.
    job_list_ids = {job.id for job in job_list}
    matched_job_ids = {app.job_id for app in hired if app.job_id in job_list_ids}
    finished_job_ids = set(
        JobPosting.objects.filter(
            id__in={app.job_id for app in application_list},
            status__in=[JobPosting.STATUS_COMPLETED, JobPosting.STATUS_CANCELLED],
        ).values_list("id", flat=True)
    )

    # Admin accounts can carry a UserProfile; only households and workers
    # are platform members (the same basis as the analytics dashboard).
    profiles = UserProfile.objects.filter(user__is_staff=False)
    workers = profiles.filter(role=UserProfile.ROLE_WORKER)
    households = profiles.filter(role=UserProfile.ROLE_HOUSEHOLD)

    verification_counts = profiles.aggregate(
        verified=Count("id", filter=Q(verification_status="verified")),
        rejected=Count("id", filter=Q(verification_status="rejected")),
    )

    # A plain Avg("average_rating") weighs a worker with 1 review the same
    # as one with 200 -- weighting each worker's mean by their own
    # rating_count instead recovers the true mean across every individual
    # rating (sum(rating_i * count_i) / sum(count_i) == mean of all rating_i).
    rated = workers.filter(rating_count__gt=0)
    rating_stats = rated.aggregate(
        weighted_total=Sum(F("average_rating") * F("rating_count")),
        total_count=Sum("rating_count"),
    )
    average_rating = (
        rating_stats["weighted_total"] / rating_stats["total_count"]
        if rating_stats["total_count"]
        else None
    )

    by_service = OrderedDict()
    by_barangay = OrderedDict()
    for job in job_list:
        service = job.required_skill or job.job_type or "Unspecified"
        by_service[service] = by_service.get(service, 0) + 1
        barangay = barangay_from_location_label(job.location_label) or "Unspecified"
        by_barangay[barangay] = by_barangay.get(barangay, 0) + 1

    monthly = _monthly_counts(period, job_list)

    tier_counts = OrderedDict()
    for tier, _label in UserProfile._meta.get_field("reputation_tier").choices or []:
        tier_counts[tier] = workers.filter(reputation_tier=tier).count()

    summary = {
        "totalAccounts": profiles.count(),
        "totalWorkers": workers.count(),
        "totalHouseholds": households.count(),
        "jobsPosted": len(job_list),
        "completedJobs": len(completed),
        "cancelledJobs": len(cancelled),
        "activeApplications": sum(
            1
            for app in application_list
            if app.status == JobApplication.STATUS_PENDING and app.job_id not in finished_job_ids
        ),
        "hiringSuccessRate": _percent(len(hired), len(application_list)),
        "jobMatchRate": _percent(len(matched_job_ids), len(job_list)),
        "verifiedUsers": verification_counts["verified"],
        "pendingVerifications": pending_account_verifications(),
        "rejectedVerifications": verification_counts["rejected"],
        "averageWorkerRating": round(_float(average_rating), 2) if average_rating is not None else None,
        # Agreed rates for work that reached Completed (AGENTS.md IV.B), not
        # a payment ledger: GawaGo does not process payments.
        "completedJobValue": round(sum(_float(job.service_rate) for job in completed), 2),
    }

    sections = [
        _section(
            "Jobs by service type",
            "Demand across service categories.",
            ["Service", "Jobs posted"],
            [[service, count] for service, count in sorted(by_service.items(), key=lambda item: -item[1])],
        ),
        _section(
            "Jobs by barangay",
            "Geographic distribution of job demand.",
            ["Barangay", "Jobs posted"],
            [[barangay, count] for barangay, count in sorted(by_barangay.items(), key=lambda item: -item[1])],
        ),
        _section(
            "Monthly job postings",
            "Posting volume each month in this period.",
            ["Month", "Jobs posted"],
            [[month, count] for month, count in monthly.items()],
        ),
        _section(
            "Worker reputation tiers",
            "How the worker base is distributed across reputation tiers.",
            ["Tier", "Workers"],
            [[tier.title(), count] for tier, count in tier_counts.items()],
        ),
    ]

    return {
        "scope": SCOPE_PLATFORM,
        "title": "Platform activity report",
        "period": period,
        "summary": summary,
        "sections": sections,
    }


def build_report_for_user(user: User, period):
    """Pick the report matching the caller's own role."""
    profile = getattr(user, "profile", None)
    if profile is not None and profile.role == UserProfile.ROLE_HOUSEHOLD:
        return build_household_report(user, period)
    return build_worker_report(user, period)



# A cell that opens with any of these is interpreted as a formula by Excel
# and Google Sheets, not literal text -- e.g. a worker or job title of
# `=cmd|'/c calc'!A1` executes when the exported report is opened. Free-text
# report fields (names, job titles, locations) are user-controlled, so every
# cell has to be checked before it reaches the writer.
_FORMULA_TRIGGER_CHARS = ("=", "+", "-", "@", "\t", "\r")


def _csv_safe(value):
    if isinstance(value, str) and value.startswith(_FORMULA_TRIGGER_CHARS):
        return f"'{value}"
    return value


def report_to_csv_rows(report):
    """Flatten a report envelope into CSV rows.

    Summary first as label/value pairs, then each section under its own
    heading, so one CSV carries the whole report rather than forcing a
    separate download per section.
    """
    rows = [[report["title"]], ["Period", f"{report['period']['start']} to {report['period']['end']}"], []]

    rows.append(["Summary"])
    rows.append(["Metric", "Value"])
    for key, value in report["summary"].items():
        rows.append([_humanize(key), "" if value is None else value])

    for section in report["sections"]:
        rows.append([])
        rows.append([section["title"]])
        rows.append(list(section["columns"]))
        rows.extend([list(row) for row in section["rows"]])

    return [[_csv_safe(cell) for cell in row] for row in rows]


def _humanize(key):
    """jobsPosted -> Jobs posted."""
    spaced = "".join(f" {char.lower()}" if char.isupper() else char for char in key)
    return spaced.strip().capitalize()
