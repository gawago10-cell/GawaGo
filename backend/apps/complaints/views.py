from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.complaints.models import Complaint
from apps.complaints.serializers import ComplaintSerializer
from apps.common.permissions import IsPlatformSuperAdmin


class ComplaintCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        data = request.data.copy()
        data["complainant"] = request.user.id

        serializer = ComplaintSerializer(data=data)
        if serializer.is_valid():
            complaint = serializer.save()
            return Response(serializer.data, status=status.HTTP_201_CREATED)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class ComplaintListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        queryset = Complaint.objects.select_related("complainant", "respondent", "job").filter(
            complainant=user
        ) | Complaint.objects.select_related("complainant", "respondent", "job").filter(respondent=user)
        queryset = queryset.distinct()

        status_filter = request.query_params.get("status")
        if status_filter:
            queryset = queryset.filter(status=status_filter)

        return Response(ComplaintSerializer(queryset, many=True).data)


class ComplaintDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, pk):
        complaint = get_object_or_404(Complaint, pk=pk)
        if complaint.complainant != request.user and complaint.respondent != request.user:
            return Response({"error": "Permission denied"}, status=status.HTTP_403_FORBIDDEN)
        return Response(ComplaintSerializer(complaint).data)


class ComplaintListAdminView(APIView):
    permission_classes = [IsAuthenticated, IsPlatformSuperAdmin]

    def get(self, request):
        queryset = Complaint.objects.select_related("complainant", "respondent", "job").all()

        status_filter = request.query_params.get("status")
        if status_filter:
            queryset = queryset.filter(status=status_filter)

        complaint_type_filter = request.query_params.get("type")
        if complaint_type_filter:
            queryset = queryset.filter(complaint_type=complaint_type_filter)

        return Response(ComplaintSerializer(queryset, many=True).data)


class ComplaintUpdateAdminView(APIView):
    permission_classes = [IsAuthenticated, IsPlatformSuperAdmin]

    def patch(self, request, pk):
        complaint = get_object_or_404(Complaint, pk=pk)

        if "status" in request.data:
            complaint.status = request.data["status"]

        if "resolution" in request.data:
            complaint.resolution = request.data["resolution"]

        if "admin_notes" in request.data:
            complaint.admin_notes = request.data["admin_notes"]

        complaint.save()
        return Response(ComplaintSerializer(complaint).data)
