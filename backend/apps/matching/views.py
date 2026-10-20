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

    `rank` selects the ordering only: the default "smart" preserves the
    documented Smart Matching priority order, and "ai" re-ranks by ai_score
    for the post-a-job recommendation screen.
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
        if rank == RANK_AI:
            # Only Smart Matching's "AI Matched Workers" view reads the score
            # breakdown, so the (expensive, content-based) scoring pass only
            # runs when that view actually asked for it.
            results = _merge_ai_scores(job, workers, match_results)
            results.sort(key=lambda result: result["_ai_sort"], reverse=True)
        else:
            results = _default_ai_fields(match_results)
        return Response(
            {
                "job_id": job.id,
                "job_title": job.title,
                "required_skill": job.required_skill,
                "rank": rank if rank == RANK_AI else RANK_SMART,
                "results": MatchResultSerializer(results, many=True, context={"request": request}).data,
            }
        )


def _default_ai_fields(match_results):
    """The zero-score defaults _merge_ai_scores() gives an unrankable worker,
    applied to every result -- for rank=smart, where nothing reads the AI
    breakdown, so there's no reason to pay for the scoring pass at all.
    """
    for result in match_results:
        result["ai_score"] = 0.0
        result["skill_similarity"] = 0.0
        result["skill_contribution"] = 0.0
        result["proximity_contribution"] = 0.0
        result["exact_skill_match"] = False
    return match_results


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
    # The displayed ai_score is the sum of the two rounded terms so the
    # breakdown still adds up; the unrounded score is kept (unserialized)
    # so rounding never reorders candidates.
    for result in match_results:
        scored = ai_by_worker.get(result["worker_id"])
        skill_contribution = round(scored["skill_contribution"], 2) if scored else 0.0
        proximity_contribution = round(scored["proximity_contribution"], 2) if scored else 0.0
        result["_ai_sort"] = scored["ai_score"] if scored else 0.0
        result["ai_score"] = round(skill_contribution + proximity_contribution, 2)
        result["skill_similarity"] = round(scored["skill_similarity"], 2) if scored else 0.0
        result["skill_contribution"] = skill_contribution
        result["proximity_contribution"] = proximity_contribution
        result["exact_skill_match"] = scored["exact_skill_match"] if scored else False

    return match_results
