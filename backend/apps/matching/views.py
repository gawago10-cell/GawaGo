from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import UserProfile
from apps.jobs.models import JobPosting
from apps.matching.recommendations import get_recommended_jobs, get_recommended_workers
from apps.matching.serializers import (
    MatchRequestSerializer,
    MatchResultSerializer,
    RecommendedJobSerializer,
)
from apps.matching.services import build_match_results

# Ranking modes for RecommendedWorkersView. The two are complementary, not
# alternatives to each other: "smart" is the deterministic rule ordering
# (skill, then verification, then distance, then rating/rate) that households
# browse a job's candidates with, while "ai" is the content-based score used
# to surface strong matches right after a job is posted.
RANK_SMART = "smart"
RANK_AI = "ai"


class RecommendedJobsView(APIView):
    """GET /api/matching/recommended-jobs/

    Returns open job postings ranked for the logged-in worker by the
    content-based AI recommendation engine. See
    apps.matching.recommendations.get_recommended_jobs for the algorithm.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        profile = getattr(request.user, "profile", None)
        if profile is None or profile.role != UserProfile.ROLE_WORKER:
            return Response(
                {"detail": "Only workers can view job recommendations."},
                status=status.HTTP_403_FORBIDDEN,
            )

        recommendations = get_recommended_jobs(request.user)
        serializer = RecommendedJobSerializer(
            recommendations, many=True, context={"request": request}
        )
        return Response({"results": serializer.data})


class RecommendedWorkersView(APIView):
    """GET|POST /api/matching/recommended-workers/?job_id=N[&rank=ai]

    Returns candidate workers for a household's job. Every result carries
    both the rule-based Smart Matching signals (verification, rating, rate,
    road distance) and the content-based AI score with the same
    explainability breakdown the worker-facing recommendations expose.

    `rank` selects the ordering: the default "smart" preserves the
    documented Smart Matching priority order, and "ai" re-ranks by ai_score
    for the post-a-job recommendation screen. The AI view leaves out
    workers with no skill fit at all: AGENTS.md I.C weights skill over
    distance, and an electrician listed as an "AI match" for a cleaning job
    because he lives nearby read as a recommendation. They stay in the
    Smart Matching list, which ranks everyone inside the radius.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        serializer = MatchRequestSerializer(data=request.query_params)
        serializer.is_valid(raise_exception=True)
        return self._build_response(
            request, serializer.validated_data["job_id"], request.query_params.get("rank")
        )

    def post(self, request):
        serializer = MatchRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return self._build_response(
            request, serializer.validated_data["job_id"], request.data.get("rank")
        )

    def _build_response(self, request, job_id, rank):
        try:
            job = JobPosting.objects.get(pk=job_id)
        except JobPosting.DoesNotExist:
            return Response(
                {
                    "detail": "Job posting not found.",
                    "job_id": job_id,
                    "results": [],
                },
                status=status.HTTP_404_NOT_FOUND,
            )
        if job.household != request.user and not request.user.is_staff:
            return Response(
                {"detail": "Only the job owner or staff can view recommended workers for this job."},
                status=status.HTTP_403_FORBIDDEN,
            )
        workers = list(
            UserProfile.objects.select_related("user")
            .prefetch_related("user__availability_windows")
            .filter(role=UserProfile.ROLE_WORKER, user__is_staff=False)
            .not_suspended()
        )
        match_results = build_match_results(job, workers)
        # Both scores on every result (AGENTS.md I.C), whichever order was
        # asked for. The Smart order used to carry placeholder zeros to skip
        # this pass, which read as "0% match"; the routes it needs are the
        # ones build_match_results just resolved, so it is now cheap.
        results = _merge_ai_scores(job, workers, match_results)
        if rank == RANK_AI:
            # Drop only real skill mismatches. A worker whose skill matches
            # but who can't be scored (no saved location) stays, at 0 and
            # last, so the household still sees them.
            results = [
                result for result in results
                if result["skill_similarity"] > 0 or result["matches_skill"]
            ]
            results.sort(key=lambda result: result["_ai_sort"], reverse=True)
        return Response(
            {
                "job_id": job.id,
                "job_title": job.title,
                "required_skill": job.required_skill,
                "rank": rank if rank == RANK_AI else RANK_SMART,
                "results": MatchResultSerializer(results, many=True, context={"request": request}).data,
            }
        )


def _merge_ai_scores(job, worker_profiles, match_results):
    """Attach the AI score + explainability breakdown to each Smart Matching
    result, without changing their order.

    Workers the content-based scorer cannot rank (no location, no listed
    skills, or outside the job's radius) keep their Smart Matching fields
    but score 0, so they still appear -- the household keeps the final
    hiring choice either way.
    """
    ai_by_worker = {
        result["profile"].user_id: result
        for result in get_recommended_workers(job, worker_profiles, limit=len(worker_profiles))
    }

    # Two decimals (the UI shows whole percentages): proximity_contribution
    # is 0.3 / (1 + distance_km), so at 4 decimals it -- or ai_score minus
    # skill_contribution -- gives back the worker's distance to within a few
    # metres, undoing the rounding of distance_km.
    # ai_score is the whole score rounded once, exactly as the applicant
    # card and "Find Jobs for Me" round it. It used to be the sum of the two
    # rounded parts (0.41 + 0.20 = 0.61 for a 0.6012 pair), so one pair read
    # 61% here and 60% elsewhere. The proximity part takes the remainder so
    # the breakdown still adds up. The unrounded score is kept
    # (unserialized) so rounding never reorders candidates.
    for result in match_results:
        scored = ai_by_worker.get(result["worker_id"])
        ai_score = round(scored["ai_score"], 2) if scored else 0.0
        skill_contribution = round(scored["skill_contribution"], 2) if scored else 0.0
        proximity_contribution = round(ai_score - skill_contribution, 2) if scored else 0.0
        result["_ai_sort"] = scored["ai_score"] if scored else 0.0
        result["ai_score"] = ai_score
        result["skill_similarity"] = round(scored["skill_similarity"], 2) if scored else 0.0
        result["skill_contribution"] = skill_contribution
        result["proximity_contribution"] = proximity_contribution
        result["exact_skill_match"] = scored["exact_skill_match"] if scored else False

    return match_results
