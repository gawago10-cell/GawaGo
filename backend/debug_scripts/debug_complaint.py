#!/usr/bin/env python
import os
import sys
import django
import json

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

django.setup()

from apps.complaints.models import Complaint
from apps.complaints.serializers import ComplaintSerializer

complaint = Complaint.objects.filter(id=1).first()
if complaint:
    serializer = ComplaintSerializer(complaint)
    print('Test complaint retrieved:')
    print(json.dumps(serializer.data, indent=2, default=str))
else:
    print('Complaint not found')

print('\nAll complaints in database:')
for c in Complaint.objects.all():
    print(f"  ID: {c.id}, Type: {c.complaint_type}, Status: {c.status}")
