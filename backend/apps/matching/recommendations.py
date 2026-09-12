"""
AI-based Job Recommendation Engine (content-based filtering).

Recommends OPEN job postings to a WORKER by comparing the worker's
skill profile against each job's required skill using TF-IDF +
cosine similarity, then blending that with a proximity score computed
from real road distance (reusing the existing Smart Matching distance
pipeline in apps.matching.services). See get_recommended_jobs() below
for the full algorithm writeup.
"""

from django.contrib.auth.models import User
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

from apps.jobs.models import JobPosting
from apps.matching.services import get_road_route_for_match, normalize_skill_label

# Relative importance of skill fit vs. proximity in the final score.
# A skill mismatch makes a job irrelevant regardless of distance, so
# skill similarity is weighted more heavily than proximity.
SKILL_WEIGHT = 0.7
PROXIMITY_WEIGHT = 0.3

DISTANCE_UNLIMITED = "unlimited"


def _worker_skill_document(profile):
    """Flatten a worker's skill list into one TF-IDF text document.

    Skills are normalized with the same normalize_skill_label() used by
    the existing rule-based Smart Matching feature, so both algorithms
    agree on what counts as "the same skill" (aliases, casing, etc).
    A worker has at most 4 skills, so this document is always short.
    """
    skills = profile.skills or []
    return " ".join(normalize_skill_label(skill) for skill in skills)


def _job_skill_document(job):
    """Turn a job's single required skill into a TF-IDF text document."""
    return normalize_skill_label(job.required_skill)


def _has_exact_skill_match(profile, job):
    """True if one of the worker's skills is exactly the job's required skill
    (after normalization), as opposed to a partial/related TF-IDF match.

    Used to explain *why* a job matched -- an exact match is a stronger,
    easier-to-state reason than "62% skill similarity".
    """
    required = normalize_skill_label(job.required_skill)
    worker_skills = {normalize_skill_label(skill) for skill in (profile.skills or [])}
    return required in worker_skills


def _within_radius(job, distance_km):
    """Hard scope filter: True only if the job accepts workers this far away.

    Applied BEFORE ranking/scoring, not as a ranking penalty -- jobs
    outside their configured search radius are excluded entirely, not
    merely ranked lower.
    """
    if job.geographic_boundary == DISTANCE_UNLIMITED:
        return True
    if distance_km is None:
        return False
    return distance_km <= job.max_distance_km


def _proximity_score(distance_km):
    """proximity_score = 1 / (1 + distance_km).

    0km -> 1.0, 1km -> 0.5, 4km -> 0.2, approaching 0 as distance grows.
    Bounded, monotonically decreasing, never negative -- no arbitrary
    "max distance" normalization constant required.
    """
    if distance_km is None:
        return 0.0
    return 1.0 / (1.0 + distance_km)


def score_job_for_worker(job, profile):
    """Score a single (job, worker profile) pair using the same content-based
    algorithm as get_recommended_jobs(): TF-IDF skill similarity blended with
    road-distance proximity, gated by the job's hard radius filter.

    Shared by both the pull-based get_recommended_jobs() endpoint and the
    push-based apps.matching.signals notification hook, so both agree on
    what counts as a match.

    Returns:
        dict with "ai_score", "skill_similarity", "distance_km", plus an
        explainability breakdown ("skill_contribution",
        "proximity_contribution", "exact_skill_match" -- see
        _build_score_result()), or None if the worker has no
        location/skills or the job is outside their radius.
    """
    if profile is None or not profile.has_location:
        return None

    worker_document = _worker_skill_document(profile)
    if not worker_document.strip():
        return None

    job_document = _job_skill_document(job)
    vectorizer = TfidfVectorizer()
    tfidf_matrix = vectorizer.fit_transform([worker_document, job_document])
    skill_similarity = cosine_similarity(tfidf_matrix[0:1], tfidf_matrix[1:2])[0][0]

    route = get_road_route_for_match(job, profile)
    distance_km = route["distance_km"]
    if not _within_radius(job, distance_km):
        return None

    return _build_score_result(job, profile, float(skill_similarity), distance_km)


def _build_score_result(job, profile, skill_similarity, distance_km):
    """Assemble the score + explainability breakdown shared by
    score_job_for_worker() and get_recommended_jobs().

    "skill_contribution" and "proximity_contribution" are the two weighted
    terms that sum to ai_score -- exposing them lets the UI explain *why*
    a job matched (e.g. "mostly skill fit" vs. "mostly proximity") instead
    of showing only the combined score.
    """
    proximity_score = _proximity_score(distance_km)
    skill_contribution = skill_similarity * SKILL_WEIGHT
    proximity_contribution = proximity_score * PROXIMITY_WEIGHT
    ai_score = skill_contribution + proximity_contribution
    return {
        "ai_score": round(ai_score, 4),
        "skill_similarity": round(skill_similarity, 4),
        "distance_km": round(distance_km, 2) if distance_km is not None else None,
        "skill_contribution": round(skill_contribution, 4),
        "proximity_contribution": round(proximity_contribution, 4),
        "exact_skill_match": _has_exact_skill_match(profile, job),
    }


def get_recommended_jobs(worker: User, limit: int = 20):
    """Return open jobs ranked for `worker` by AI recommendation score.

    Algorithm (content-based filtering):
      1. Build one text document from the worker's skill list, and one
         per open job from its required skill.
      2. Fit a single TfidfVectorizer across the worker's document plus
         every open job's document, so IDF weighting reflects how
         common/rare each skill term is across the current pool of open
         jobs -- a skill almost every job needs contributes less to
         similarity than a rare, specific one.
      3. cosine_similarity(worker_vector, job_vectors) -> skill_similarity
         in [0, 1] per job.
      4. distance_km comes from get_road_route_for_match(), the same
         OSRM-backed, cached road-distance lookup the rule-based Smart
         Matching feature already uses -- "distance" means the same
         thing in both algorithms.
      5. ai_score = skill_similarity * 0.7 + proximity_score * 0.3.
      6. Jobs outside their own configured search radius are dropped
         BEFORE scoring/ranking (see _within_radius) -- a hard filter,
         not a ranking penalty.

    FUTURE ENHANCEMENT (not built now): once enough historical
    hire/application/rating data exists, extend this into a hybrid
    recommender by blending in collaborative filtering -- e.g. "workers
    with similar skill/hire profiles to you were hired for jobs like X"
    -- as an additional signal on top of this content-based score. That
    needs a worker-job interaction dataset that doesn't exist yet, so it
    is intentionally left out of this version.

    Args:
        worker: the logged-in worker's User instance.
        limit: max number of recommendations to return.

    Returns:
        list[dict]: {"job", "ai_score", "skill_similarity", "distance_km"}
        sorted by ai_score descending.
    """
    profile = getattr(worker, "profile", None)
    if profile is None or not profile.has_location:
        return []

    worker_document = _worker_skill_document(profile)
    if not worker_document.strip():
        return []

    open_jobs = list(
        JobPosting.objects.filter(status=JobPosting.STATUS_OPEN)
        .exclude(household_id=worker.id)
        .select_related("household")
    )
    if not open_jobs:
        return []

    job_documents = [_job_skill_document(job) for job in open_jobs]

    vectorizer = TfidfVectorizer()
    tfidf_matrix = vectorizer.fit_transform([worker_document] + job_documents)
    worker_vector = tfidf_matrix[0:1]
    job_vectors = tfidf_matrix[1:]
    similarities = cosine_similarity(worker_vector, job_vectors)[0]

    results = []
    for job, skill_similarity in zip(open_jobs, similarities):
        route = get_road_route_for_match(job, profile)
        distance_km = route["distance_km"]

        if not _within_radius(job, distance_km):
            continue

        results.append({
            "job": job,
            **_build_score_result(job, profile, float(skill_similarity), distance_km),
        })

    results.sort(key=lambda r: r["ai_score"], reverse=True)
    return results[:limit]
