from django.contrib.auth.models import User
from django.db import IntegrityError
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.jobs.models import JobApplication, JobPosting
from apps.reviews.models import Review
from apps.reviews.serializers import ReviewCreateSerializer, ReviewSerializer
from apps.reviews.services import assign_due_default_worker_ratings, update_worker_reputation
from apps.notifications.models import Notification
from apps.notifications.services import create_notification


class ReviewListCreateView(APIView):
    def get_permissions(self):
        if self.request.method == "GET":
            return [AllowAny()]
        return [IsAuthenticated()]

    def get(self, request):
        assign_due_default_worker_ratings()
        target_username = request.query_params.get("username") or request.query_params.get("target_username")
        author_username = request.query_params.get("author_username")
        reviews = Review.objects.select_related("author", "target", "job")
        if target_username:
            reviews = reviews.filter(target__username=target_username)
        if author_username:
            author_user = User.objects.filter(username=author_username).select_related("profile").first()
            author_profile = getattr(author_user, "profile", None)
            is_anonymous_feedback_author = author_profile and author_profile.role == Review.ROLE_WORKER
            if is_anonymous_feedback_author and request.user != author_user:
                reviews = reviews.none()
            else:
                reviews = reviews.filter(author=author_user)
        if not target_username and not author_username:
            if request.user.is_authenticated:
                reviews = reviews.filter(target=request.user)
            else:
                return Response({"detail": "username or author_username is required."}, status=status.HTTP_400_BAD_REQUEST)
        return Response(ReviewSerializer(reviews, many=True).data)

    def post(self, request):
        serializer = ReviewCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        target_user = serializer.validated_data["target_username"]
        author_user = request.user

        author_profile = getattr(author_user, "profile", None)
        target_profile = getattr(target_user, "profile", None)

        if not author_profile or not target_profile:
            return Response({"detail": "Both users must have profiles."}, status=status.HTTP_400_BAD_REQUEST)

        author_role = author_profile.role
        target_role = target_profile.role
        if author_role == target_role:
            return Response({"detail": "Reviews are only allowed between workers and households."}, status=status.HTTP_400_BAD_REQUEST)

        if author_role == "worker" and target_role != "household":
            return Response({"detail": "Workers can only review households."}, status=status.HTTP_400_BAD_REQUEST)
        if author_role == "household" and target_role != "worker":
            return Response({"detail": "Households can only review workers."}, status=status.HTTP_400_BAD_REQUEST)
        job = JobPosting.objects.filter(pk=serializer.validated_data["job_id"]).first()
        if not job:
            return Response({"detail": "Completed job is required before submitting a review."}, status=status.HTTP_400_BAD_REQUEST)
        if job.status != JobPosting.STATUS_COMPLETED:
            return Response({"detail": "Reviews are only allowed after the job is completed."}, status=status.HTTP_400_BAD_REQUEST)
        if author_role == "household":
            eligible = (
                job.household == author_user
                and JobApplication.objects.filter(
                    job=job,
                    worker=target_user,
                    status=JobApplication.STATUS_COMPLETED,
                ).exists()
            )
        else:
            eligible = (
                job.household == target_user
                and JobApplication.objects.filter(
                    job=job,
                    worker=author_user,
                    status=JobApplication.STATUS_COMPLETED,
                ).exists()
            )
        if not eligible:
            return Response({"detail": "Users can only review each other after a completed job relationship."}, status=status.HTTP_400_BAD_REQUEST)

        if Review.objects.filter(job=job, author=author_user, target=target_user).exists():
            return Response({"detail": "This user has already been reviewed for this completed job."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            review = Review.objects.create(
                author=author_user,
                target=target_user,
                author_role=author_role,
                target_role=target_role,
                job=job,
                job_title=serializer.validated_data.get("job_title") or job.title,
                rating=serializer.validated_data.get("rating"),
                feedback=serializer.validated_data.get("feedback", ""),
                quality_of_work=serializer.validated_data.get("quality_of_work"),
                punctuality=serializer.validated_data.get("punctuality"),
                communication=serializer.validated_data.get("communication"),
                professionalism=serializer.validated_data.get("professionalism"),
            )
        except IntegrityError:
            return Response({"detail": "This user has already been reviewed for this completed job."}, status=status.HTTP_400_BAD_REQUEST)
        notification_message = (
            "You received anonymous feedback from a worker."
            if author_role == "worker"
            else f"You received a new review from {author_user.username}."
        )
        create_notification(
            recipient=target_user,
            notification_type=Notification.TYPE_ANALYTICS,
            title="New feedback received" if author_role == "worker" else "New review received",
            message=notification_message,
            actor=author_user,
            related_job_id=job.id,
            action_type=Notification.ACTION_REVIEW,
            action_url=f"/reviews/jobs/{job.id}",
        )
        # Update reputation tier and trend after new review
        update_worker_reputation(target_user)
        return Response(ReviewSerializer(review).data, status=status.HTTP_201_CREATED)
