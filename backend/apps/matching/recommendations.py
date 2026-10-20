"""
AI-based recommendation engine (content-based filtering), used in both
directions:

  * get_recommended_jobs()    -- ranks OPEN jobs for a WORKER (pull).
  * get_recommended_workers() -- ranks WORKERS for a household's JOB (push).

Both compare a worker's skill profile against a job's required skill using
TF-IDF + cosine similarity, then blend that with a proximity score computed
from real road distance (reusing the existing Smart Matching distance
pipeline in apps.matching.services). Because the score is symmetric in
(job, worker), both directions share the same weights and the same
explainability breakdown via _build_score_result().
"""

from django.contrib.auth.models import User

from apps.accounts.models import currently_suspended_q
from apps.jobs.models import JobPosting
from apps.jobs.privacy import rounded_distance_km
from apps.matching.services import (
    DISTANCE_UNLIMITED,
    get_road_route_for_match,
    normalize_skill_label,
    scope_distance_km,
)

# Relative importance of skill fit vs. proximity in the final score.
# A skill mismatch makes a job irrelevant regardless of distance, so
# skill similarity is weighted more heavily than proximity.
SKILL_WEIGHT = 0.7
PROXIMITY_WEIGHT = 0.3


def _tfidf():
    """Import scikit-learn on first use rather than at module import.

    Serializers and the job-match task import this module, so a module-level
    sklearn import made *every* management command -- runserver included --
    sit through a ~20s import before doing anything. Only a call that
    actually scores something should pay that.
    """
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.metrics.pairwise import cosine_similarity

    return TfidfVectorizer, cosine_similarity


def _worker_skill_document(profile):
    """Flatten a worker's skill list into one TF-IDF text document.

    Skills are normalized with the same normalize_skill_label() used by
    the existing rule-based Smart Matching feature, so both algorithms
    agree on what counts as "the same skill" (aliases, casing, etc).
    A worker has at most 3 skills, so this document is always short.
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

    Shares its scoring (score_pair_with_distance) with the push-based
    background task in apps.matching.tasks, so both agree on what counts as
    a match.

    Returns:
        dict with "ai_score", "skill_similarity", "distance_km", plus an
        explainability breakdown ("skill_contribution",
        "proximity_contribution", "exact_skill_match" -- see
        _build_score_result()), or None if the worker has no
        location/skills or the job is outside their radius.
    """
    if profile is None or not profile.has_location:
        return None

    route = get_road_route_for_match(job, profile)
    distance_km = scope_distance_km(job, profile, route["distance_km"])
    if not _within_radius(job, distance_km):
        return None

    return score_pair_with_distance(job, profile, distance_km)


def score_pair_with_distance(job, profile, distance_km):
    """The scoring half of score_job_for_worker(), for callers that already
    resolved the road distance themselves.

    Serializers resolve a route once per row (and may be restricted to the
    cache-only lookup on collection endpoints); routing them back through
    score_job_for_worker() would silently re-resolve it live, one outbound
    request per row.
    """
    if profile is None:
        return None

    worker_document = _worker_skill_document(profile)
    if not worker_document.strip():
        return None

    TfidfVectorizer, cosine_similarity = _tfidf()
    vectorizer = TfidfVectorizer()
    tfidf_matrix = vectorizer.fit_transform([worker_document, _job_skill_document(job)])
    skill_similarity = float(cosine_similarity(tfidf_matrix[0:1], tfidf_matrix[1:2])[0][0])

    return _build_score_result(job, profile, skill_similarity, distance_km)


def _build_score_result(job, profile, skill_similarity, distance_km):
    """Assemble the score + explainability breakdown shared by
    score_job_for_worker() and get_recommended_jobs().

    "skill_contribution" and "proximity_contribution" are the two weighted
    terms that sum to ai_score -- exposing them lets the UI explain *why*
    a job matched (e.g. "mostly skill fit" vs. "mostly proximity") instead
    of showing only the combined score.
    """
    # The proximity score itself is computed from the precise distance --
    # only the *displayed* distance_km is coarsened. A worker controls their
    # own registered location, so a precise reading here would let repeated
    # self-reported moves trilaterate the job's ~1 km-masked pin before
    # they're hired (SEC-13); 0.1 km resolution is enough to compare
    # candidates without that.
    proximity_score = _proximity_score(distance_km)
    skill_contribution = skill_similarity * SKILL_WEIGHT
    proximity_contribution = proximity_score * PROXIMITY_WEIGHT
    ai_score = skill_contribution + proximity_contribution
    return {
        "ai_score": round(ai_score, 4),
        "skill_similarity": round(skill_similarity, 4),
        "distance_km": rounded_distance_km(distance_km),
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

    # Same market the job list shows: a suspended household's jobs can't be
    # applied to, so they must not be recommended either.
    open_jobs = list(
        JobPosting.objects.filter(status=JobPosting.STATUS_OPEN)
        .exclude(household_id=worker.id)
        .exclude(currently_suspended_q("household__profile__"))
        .select_related("household")
    )
    if not open_jobs:
        return []

    job_documents = [_job_skill_document(job) for job in open_jobs]

    TfidfVectorizer, cosine_similarity = _tfidf()
    vectorizer = TfidfVectorizer()
    tfidf_matrix = vectorizer.fit_transform([worker_document] + job_documents)
    worker_vector = tfidf_matrix[0:1]
    job_vectors = tfidf_matrix[1:]
    similarities = cosine_similarity(worker_vector, job_vectors)[0]

    results = []
    for job, skill_similarity in zip(open_jobs, similarities):
        route = get_road_route_for_match(job, profile)
        distance_km = scope_distance_km(job, profile, route["distance_km"])

        if not _within_radius(job, distance_km):
            continue

        results.append({
            "job": job,
            **_build_score_result(job, profile, float(skill_similarity), distance_km),
        })

    results.sort(key=lambda r: r["ai_score"], reverse=True)
    return results[:limit]


def get_recommended_workers(job, worker_profiles, limit: int = 20):
    """Return workers ranked for `job` by the same content-based score
    get_recommended_jobs() applies in the opposite direction.

    This is the household-facing half of AI matching: after a household
    posts a job, it sees candidate workers ranked by TF-IDF skill
    similarity blended with road-route proximity, each carrying the same
    explainability breakdown a worker sees on a recommended job.

    The single TfidfVectorizer is fit across the job's document plus every
    candidate worker's document, so IDF weighting reflects how common a
    skill is across the current candidate pool -- a worker whose skill is
    rare among candidates scores higher on it than one whose skill
    everybody lists.

    Workers with no location or no listed skills cannot be scored and are
    dropped, as are workers outside the job's configured search radius
    (the same hard filter, not a ranking penalty, that _within_radius
    applies on the pull side).

    Args:
        job: the JobPosting to rank workers for.
        worker_profiles: candidate UserProfile instances (the caller owns
            the queryset so it can apply its own role/staff filtering).
        limit: max number of recommendations to return.

    Returns:
        list[dict]: {"profile", "ai_score", "skill_similarity",
        "distance_km", "skill_contribution", "proximity_contribution",
        "exact_skill_match"} sorted by ai_score descending.
    """
    job_document = _job_skill_document(job)
    if not job_document.strip():
        return []

    candidates = [
        profile
        for profile in worker_profiles
        if profile.has_location and _worker_skill_document(profile).strip()
    ]
    if not candidates:
        return []

    worker_documents = [_worker_skill_document(profile) for profile in candidates]

    TfidfVectorizer, cosine_similarity = _tfidf()
    vectorizer = TfidfVectorizer()
    tfidf_matrix = vectorizer.fit_transform([job_document] + worker_documents)
    similarities = cosine_similarity(tfidf_matrix[0:1], tfidf_matrix[1:])[0]

    results = []
    for profile, skill_similarity in zip(candidates, similarities):
        route = get_road_route_for_match(job, profile)
        distance_km = scope_distance_km(job, profile, route["distance_km"])

        if not _within_radius(job, distance_km):
            continue

        results.append({
            "profile": profile,
            **_build_score_result(job, profile, float(skill_similarity), distance_km),
        })

    results.sort(key=lambda r: r["ai_score"], reverse=True)
    return results[:limit]
