from decimal import ROUND_HALF_UP, Decimal

from django.contrib.auth.models import User
from rest_framework import serializers

from apps.common.sanitize import sanitize_text
from apps.reviews.models import Review


METRIC_FIELDS = ("quality_of_work", "punctuality", "communication", "professionalism")


def average_metric_rating(values):
    """The average of the metrics present in `values`, to one decimal place,
    or None when none was rated."""
    metrics = [values.get(field) for field in METRIC_FIELDS]
    metrics = [metric for metric in metrics if metric is not None]
    if not metrics:
        return None
    return (Decimal(sum(metrics)) / Decimal(len(metrics))).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)


def mask_name_part(value):
    name_part = str(value or "").strip()
    if not name_part:
        return ""
    return f"{name_part[0].lower()}{'*' * (len(name_part) - 1)}"


def get_masked_user_name(user):
    if user is None:
        return "Masked worker"
    name_parts = [user.first_name.strip(), user.last_name.strip()]
    visible_parts = [mask_name_part(part) for part in name_parts if part]
    if visible_parts:
        return " ".join(visible_parts)
    username_parts = [part for part in user.username.replace("_", " ").replace("-", " ").split() if part]
    return " ".join(mask_name_part(part) for part in username_parts) or "Masked worker"


class ReviewSerializer(serializers.ModelSerializer):
    author_username = serializers.CharField(source="author_label", read_only=True)
    target_username = serializers.CharField(source="target.username", read_only=True)
    author_name = serializers.SerializerMethodField()
    target_name = serializers.SerializerMethodField()
    overall_rating = serializers.SerializerMethodField()

    class Meta:
        model = Review
        fields = [
            "id",
            "author",
            "author_username",
            "author_name",
            "author_role",
            "target",
            "target_username",
            "target_name",
            "target_role",
            "job",
            "job_title",
            "rating",
            "feedback",
            "quality_of_work",
            "punctuality",
            "communication",
            "professionalism",
            "overall_rating",
            "created_at",
        ]
        read_only_fields = ["id", "author", "author_username", "target_username", "overall_rating", "created_at"]

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if self.is_anonymous_worker_feedback(instance):
            data["author"] = None
            data["author_username"] = ""
            data["author_name"] = get_masked_user_name(instance.author)
        return data

    @staticmethod
    def is_anonymous_worker_feedback(obj):
        return obj.author_role == Review.ROLE_WORKER and obj.target_role == Review.ROLE_HOUSEHOLD

    def get_author_name(self, obj):
        if not obj.author_id:
            return obj.author_username or "Deleted account"
        return obj.author.get_full_name().strip() or obj.author.username

    def get_target_name(self, obj):
        return obj.target.get_full_name().strip() or obj.target.username

    def get_overall_rating(self, obj):
        metrics = [obj.quality_of_work, obj.punctuality, obj.communication, obj.professionalism]
        valid_metrics = [m for m in metrics if m is not None]
        if not valid_metrics:
            return obj.rating
        return round(sum(valid_metrics) / len(valid_metrics), 1)


class ReviewCreateSerializer(serializers.Serializer):
    author_username = serializers.CharField(max_length=150, required=False, allow_blank=True)
    target_username = serializers.CharField(max_length=150)
    job_id = serializers.IntegerField()
    job_title = serializers.CharField(max_length=255, required=False, allow_blank=True)
    rating = serializers.DecimalField(
        max_digits=2,
        decimal_places=1,
        required=False,
        min_value=1,
        max_value=5,
        allow_null=True,
    )
    feedback = serializers.CharField(required=False, allow_blank=True)
    quality_of_work = serializers.IntegerField(required=False, min_value=1, max_value=5, allow_null=True)
    punctuality = serializers.IntegerField(required=False, min_value=1, max_value=5, allow_null=True)
    communication = serializers.IntegerField(required=False, min_value=1, max_value=5, allow_null=True)
    professionalism = serializers.IntegerField(required=False, min_value=1, max_value=5, allow_null=True)

    def validate_feedback(self, value):
        return sanitize_text(value)

    def validate_author_username(self, value):
        if not value:
            return None
        try:
            return User.objects.get(username=value)
        except User.DoesNotExist as exc:
            raise serializers.ValidationError("Author user not found.") from exc

    def validate_target_username(self, value):
        try:
            return User.objects.get(username=value)
        except User.DoesNotExist as exc:
            raise serializers.ValidationError("Target user not found.") from exc

    def validate(self, attrs):
        scores = ["rating", "quality_of_work", "punctuality", "communication", "professionalism"]
        if all(attrs.get(field) is None for field in scores):
            raise serializers.ValidationError({"rating": "Give an overall rating or rate at least one metric."})
        # AGENTS.md II.A: when the metrics are given, the overall rating is
        # their average. The star picker's value used to be stored beside
        # them, so one review read 5.0 in `rating` and 4.5 in
        # `overall_rating`, and screens disagreed depending on which they used.
        metric_average = average_metric_rating(attrs)
        if metric_average is not None:
            attrs["rating"] = metric_average
        return attrs
