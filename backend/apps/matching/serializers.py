from rest_framework import serializers

from apps.jobs.serializers import JobPostingSerializer


class RecommendedJobSerializer(serializers.Serializer):
    """Serializes one ranked recommendation dict from
    apps.matching.recommendations.get_recommended_jobs().
    """

    job = JobPostingSerializer()
    ai_score = serializers.FloatField()
    skill_similarity = serializers.FloatField()
    distance_km = serializers.FloatField(allow_null=True)
    skill_contribution = serializers.FloatField()
    proximity_contribution = serializers.FloatField()
    exact_skill_match = serializers.BooleanField()


class MatchRequestSerializer(serializers.Serializer):
    job_id = serializers.IntegerField()


class MatchResultSerializer(serializers.Serializer):
    worker_id = serializers.IntegerField()
    worker_username = serializers.CharField()
    skills = serializers.ListField(child=serializers.CharField())
    matches_skill = serializers.BooleanField()
    verification_status = serializers.CharField()
    worker_latitude = serializers.FloatField(allow_null=True)
    worker_longitude = serializers.FloatField(allow_null=True)
    distance_km = serializers.FloatField(allow_null=True)
    distance_label = serializers.CharField()
    route_points = serializers.ListField(child=serializers.ListField(child=serializers.FloatField()), required=False)
    match_score = serializers.FloatField()
    rating_label = serializers.CharField()
    rating_score = serializers.FloatField()
    available_at_requested_time = serializers.BooleanField()
    rate_score = serializers.FloatField()
    worker_rate = serializers.CharField(allow_blank=True)
