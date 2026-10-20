from rest_framework import serializers


class DashboardMetricsSerializer(serializers.Serializer):
    open_jobs = serializers.IntegerField()
    verified_workers = serializers.IntegerField()
    completed_jobs = serializers.IntegerField()
    cancelled_jobs = serializers.IntegerField()
    active_applications = serializers.IntegerField()
    total_accounts = serializers.IntegerField()
    avg_rating = serializers.FloatField(allow_null=True)
    analytics = serializers.JSONField()
