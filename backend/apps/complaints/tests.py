from django.test import TestCase
from django.contrib.auth import get_user_model

from apps.accounts.models import UserProfile
from apps.complaints.models import Complaint

User = get_user_model()


class ComplaintModelTest(TestCase):
    def setUp(self):
        self.complainant = User.objects.create_user(username="worker", password="testpass")
        self.respondent = User.objects.create_user(username="household", password="testpass")
        UserProfile.objects.create(user=self.complainant, role=UserProfile.ROLE_WORKER)
        UserProfile.objects.create(user=self.respondent, role=UserProfile.ROLE_HOUSEHOLD)

    def test_create_complaint(self):
        complaint = Complaint.objects.create(
            complainant=self.complainant,
            respondent=self.respondent,
            complaint_type=Complaint.TYPE_PAYMENT_ISSUE,
            description="Payment was not made after job completion",
            status=Complaint.STATUS_SUBMITTED,
        )
        self.assertEqual(complaint.complainant.username, "worker")
        self.assertEqual(complaint.status, Complaint.STATUS_SUBMITTED)
