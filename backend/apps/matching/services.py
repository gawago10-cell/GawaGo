import json
from datetime import timedelta
from decimal import Decimal
from urllib import error, request

from django.conf import settings
from django.db import models

from apps.matching.models import RouteDistanceCache

# Shared with recommendations.py so both rankers agree on what "no distance
# limit" means for a job -- they used to disagree, since only the AI path
# checked this.
DISTANCE_UNLIMITED = "unlimited"


SKILL_ALIASES = {
    "aircon": "aircon_repair",
    "aircon cleaning": "aircon_repair",
    "aircon repair": "aircon_repair",
    "aircon repair cleaning": "aircon_repair",
    "aircon repair/cleaning": "aircon_repair",
    "babysitting": "childcare",
    "baby sitting": "childcare",
    "carpenter": "carpentry",
    "cleaning": "house_cleaning",
    "cooking": "cooking",
    "cook": "cooking",
    "domestic helper": "house_cleaning",
    "driver": "driving",
    "driving": "driving",
    "elder care": "elder_care",
    "eldercare": "elder_care",
    "electrical": "electrical_work",
    "electrical work": "electrical_work",
    "electrician": "electrical_work",
    "garden cleanup": "gardening",
    "gardener": "gardening",
    "gardening": "gardening",
    "house cleaning": "house_cleaning",
    "housekeeping": "house_cleaning",
    "laundry": "laundry",
    "painting": "painting",
    "painter": "painting",
    "plumber": "plumbing",
    "plumbing": "plumbing",
    "welding": "welding",
    "welder": "welding",
}


def normalize_skill_label(value):
    normalized = " ".join(str(value or "").strip().lower().replace("&", " and ").replace("-", " ").split())
    normalized = normalized.replace(" / ", "/").replace(" /", "/").replace("/ ", "/")
    return SKILL_ALIASES.get(normalized, normalized.replace("/", " ").replace(" ", "_"))


def skill_matches(required_skill, worker_skills):
    required_key = normalize_skill_label(required_skill)
    worker_keys = {normalize_skill_label(skill) for skill in worker_skills or []}
    return required_key in worker_keys


def normalize_coordinate(value):
    if value is None:
        return None
    return Decimal(str(value)).quantize(Decimal("0.0000001"))


def cached_coordinates_match(cache_record, job, profile):
    return (
        cache_record.job_latitude == normalize_coordinate(job.latitude)
        and cache_record.job_longitude == normalize_coordinate(job.longitude)
        and cache_record.worker_latitude == normalize_coordinate(profile.latitude)
        and cache_record.worker_longitude == normalize_coordinate(profile.longitude)
    )


def fetch_road_route(lat1, lon1, lat2, lon2):
    if None in (lat1, lon1, lat2, lon2):
        return None
    coordinates = [float(lat1), float(lon1), float(lat2), float(lon2)]
    if any(value == 0.0 for value in coordinates):
        return None
    if not settings.OPENROUTESERVICE_API_KEY:
        return fetch_osrm_route(lat1, lon1, lat2, lon2)
    payload = json.dumps(
        {
            "coordinates": [
                [float(lon1), float(lat1)],
                [float(lon2), float(lat2)],
            ]
        }
    ).encode("utf-8")
    route_request = request.Request(
        settings.OPENROUTESERVICE_DIRECTIONS_URL,
        data=payload,
        method="POST",
        headers={
            "Authorization": settings.OPENROUTESERVICE_API_KEY,
            "Content-Type": "application/json",
            "Accept": "application/json, application/geo+json",
        },
    )
    try:
        with request.urlopen(route_request, timeout=settings.OPENROUTESERVICE_TIMEOUT_SECONDS) as response:
            data = json.loads(response.read().decode("utf-8"))
    except (OSError, ValueError, error.URLError, error.HTTPError):
        return None
    feature = (data.get("features") or [None])[0] or {}
    distance_meters = feature.get("properties", {}).get("summary", {}).get("distance")
    raw_coordinates = feature.get("geometry", {}).get("coordinates") or []
    route_points = [
        [float(coordinate[1]), float(coordinate[0])]
        for coordinate in raw_coordinates
        if isinstance(coordinate, list)
        and len(coordinate) >= 2
        and isinstance(coordinate[0], (int, float))
        and isinstance(coordinate[1], (int, float))
    ]
    try:
        return {
            "distance_km": float(distance_meters) / 1000,
            "route_points": route_points,
        }
    except (TypeError, ValueError):
        return None


def fetch_osrm_route(lat1, lon1, lat2, lon2):
    coordinates = f"{float(lon1)},{float(lat1)};{float(lon2)},{float(lat2)}"
    route_url = (
        f"{settings.OSRM_DIRECTIONS_URL.rstrip('/')}/{coordinates}"
        "?overview=full&geometries=geojson&steps=false"
    )
    route_request = request.Request(
        route_url,
        method="GET",
        headers={
            "Accept": "application/json",
            "User-Agent": "GawaGo/1.0",
        },
    )
    try:
        with request.urlopen(
            route_request,
            timeout=settings.OPENROUTESERVICE_TIMEOUT_SECONDS,
        ) as response:
            data = json.loads(response.read().decode("utf-8"))
    except (OSError, ValueError, error.URLError, error.HTTPError):
        return None
    if data.get("code") != "Ok":
        return None
    route = (data.get("routes") or [None])[0] or {}
    distance_meters = route.get("distance")
    raw_coordinates = route.get("geometry", {}).get("coordinates") or []
    route_points = [
        [float(coordinate[1]), float(coordinate[0])]
        for coordinate in raw_coordinates
        if isinstance(coordinate, list)
        and len(coordinate) >= 2
        and isinstance(coordinate[0], (int, float))
        and isinstance(coordinate[1], (int, float))
    ]
    try:
        return {
            "distance_km": float(distance_meters) / 1000,
            "route_points": route_points,
        }
    except (TypeError, ValueError):
        return None


def get_cached_road_route(job, profile):
    """Cache-only lookup -- never calls the external routing service.

    For list serialization, where doing a live lookup per row means one
    sequential outbound HTTP round-trip per item. Pairs that aren't cached
    yet simply report no distance until the matching endpoints populate
    them; a slow list is worse than a missing distance label.
    """
    if None in (job.latitude, job.longitude, profile.latitude, profile.longitude):
        return {"distance_km": None, "route_points": []}
    cache_record = RouteDistanceCache.objects.filter(job=job, worker_profile=profile).first()
    if cache_record and cached_coordinates_match(cache_record, job, profile):
        return {
            "distance_km": float(cache_record.distance_km),
            "route_points": cache_record.route_points or [],
        }
    return {"distance_km": None, "route_points": []}


def get_road_route_for_match(job, profile):
    if None in (job.latitude, job.longitude, profile.latitude, profile.longitude):
        return {"distance_km": None, "route_points": []}
    cache_record = RouteDistanceCache.objects.filter(job=job, worker_profile=profile).first()
    if cache_record and cached_coordinates_match(cache_record, job, profile):
        return {
            "distance_km": float(cache_record.distance_km),
            "route_points": cache_record.route_points or [],
        }
    route = fetch_road_route(job.latitude, job.longitude, profile.latitude, profile.longitude)
    if not route or route["distance_km"] is None:
        return {"distance_km": None, "route_points": []}
    cache_values = {
        "job_latitude": normalize_coordinate(job.latitude),
        "job_longitude": normalize_coordinate(job.longitude),
        "worker_latitude": normalize_coordinate(profile.latitude),
        "worker_longitude": normalize_coordinate(profile.longitude),
        "distance_km": Decimal(str(route["distance_km"])).quantize(Decimal("0.001")),
        "route_points": route.get("route_points") or [],
    }
    RouteDistanceCache.objects.update_or_create(
        job=job,
        worker_profile=profile,
        defaults=cache_values,
    )
    return route


def time_in_window(target_time, start_time, end_time):
    if start_time <= end_time:
        return start_time <= target_time <= end_time
    return target_time >= start_time or target_time <= end_time


def windows_cover_time(windows, target_time, include_overnight_start=True, include_overnight_end=False):
    for window in windows:
        if window.start_time <= window.end_time:
            if window.start_time <= target_time <= window.end_time:
                return True
            continue
        if include_overnight_start and target_time >= window.start_time:
            return True
        if include_overnight_end and target_time <= window.end_time:
            return True
    return False


def get_worker_rate(profile):
    return profile.daily_rate or profile.hourly_rate


def calculate_rate_score(job, profile):
    worker_rate = get_worker_rate(profile)
    if worker_rate is None or job.service_rate is None:
        return 0
    offered_rate = float(job.service_rate)
    if offered_rate <= 0:
        return 0
    ratio = float(worker_rate) / offered_rate
    if ratio <= 1:
        return 1.0
    if ratio <= 1.2:
        return 0.5
    return 0


def calculate_distance_score(distance_km):
    if distance_km is None:
        return 0
    return max(0, 10 - distance_km) / 10


def calculate_match_score(matches_skill, verified, distance_km, rating, rate_score):
    return (
        (50 if matches_skill else 0)
        + (20 if verified else 0)
        + (calculate_distance_score(distance_km) * 15)
        + (min(float(rating or 0), 5) * 2)
        + (rate_score * 5)
    )


def completed_job_counts(worker_ids):
    """How many jobs each worker has finished, in one grouped query rather
    than one per candidate -- the match list renders this for every card."""
    from apps.jobs.models import JobApplication

    rows = (
        JobApplication.objects.filter(worker_id__in=worker_ids, status=JobApplication.STATUS_COMPLETED)
        .values("worker_id")
        .annotate(total=models.Count("id"))
    )
    return {row["worker_id"]: row["total"] for row in rows}


def build_match_results(job, worker_profiles):
    # geographic_boundary='unlimited' must bypass the distance filter here
    # the same way recommendations._within_radius() does for the AI path --
    # otherwise the two rankers can disagree about the same job whenever
    # max_distance_km wasn't (or couldn't be) kept in sync with the boundary
    # label.
    is_unlimited = job.geographic_boundary == DISTANCE_UNLIMITED
    max_distance_km = None if is_unlimited else (float(job.max_distance_km) if job.max_distance_km else None)
    finished_jobs = completed_job_counts([profile.user_id for profile in worker_profiles])
    results = []
    for profile in worker_profiles:
        skills = profile.skills or []
        matches_skill = skill_matches(job.required_skill, skills)
        route = get_road_route_for_match(job, profile)
        distance_km = route["distance_km"]

        if max_distance_km is not None and distance_km is not None and distance_km > max_distance_km:
            continue

        is_verified = profile.verification_status == "verified"
        rating_score = float(profile.average_rating or 0)
        rate_score = calculate_rate_score(job, profile)
        match_score = calculate_match_score(
            matches_skill=matches_skill,
            verified=is_verified,
            distance_km=distance_km,
            rating=rating_score,
            rate_score=rate_score,
        )
        results.append(
            {
                "worker_id": profile.user_id,
                "worker_username": profile.user.username,
                "worker_name": profile.user.get_full_name().strip() or profile.user.username,
                "worker_location_label": profile.location_label or "",
                "worker_bio": profile.bio or "",
                "worker_profile_photo_url": profile.profile_photo.url if profile.profile_photo else "",
                "worker_rating_count": profile.rating_count or 0,
                "worker_completed_jobs": finished_jobs.get(profile.user_id, 0),
                "skills": skills,
                "matches_skill": matches_skill,
                "verification_status": profile.verification_status,
                "worker_latitude": float(profile.latitude) if profile.latitude is not None else None,
                "worker_longitude": float(profile.longitude) if profile.longitude is not None else None,
                "distance_km": round(distance_km, 3) if distance_km is not None else None,
                "distance_label": (
                    f"{round(distance_km, 3)} km away" if distance_km is not None else "Road distance unavailable"
                ),
                "route_points": route.get("route_points") or [],
                "match_score": round(match_score, 2),
                "rating_label": profile.display_rating,
                "rating_score": round(rating_score, 2),
                "available_at_requested_time": True,
                "rate_score": round(rate_score, 2),
                "worker_rate": str(get_worker_rate(profile) or ""),
            }
        )
    return sorted(
        results,
        key=lambda item: (
            0 if item["matches_skill"] else 1,
            0 if item["verification_status"] == "verified" else 1,
            0 if item["distance_km"] is not None else 1,
            item["distance_km"] if item["distance_km"] is not None else float("inf"),
            -item["rating_score"],
            -item["rate_score"],
            -item["match_score"],
        ),
    )
