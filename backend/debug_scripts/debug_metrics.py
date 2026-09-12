#!/usr/bin/env python
import os
import sys
import django
import json
from django.test import Client
from django.contrib.auth import get_user_model

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

django.setup()

from rest_framework.test import APIClient
from apps.common.authentication import create_jwt_token
from apps.jobs.models import JobPosting, JobApplication
from apps.reviews.models import Review

User = get_user_model()
client = APIClient()

# Get test users
user1 = User.objects.first()
if not user1:
    print("No users found")
    sys.exit(1)

# Create household and worker for testing
household = User.objects.filter(profile__role='household').first()
worker = User.objects.filter(profile__role='worker').first()

if not household or not worker:
    print("Need household and worker users")
    sys.exit(1)

print(f"Test: Household: {household.username}, Worker: {worker.username}")

# Create test job
from datetime import date
job = JobPosting.objects.create(
    household=household,
    title="Test Job",
    job_type="Test Service",
    required_skill="Testing",
    schedule="One-time",
    location_label="Test Location",
    latitude=14.05,
    longitude=121.53,
    service_rate=500,
    status=JobPosting.STATUS_COMPLETED
)

# Create completed application
app, _ = JobApplication.objects.get_or_create(
    job=job,
    worker=worker,
    defaults={'status': JobApplication.STATUS_COMPLETED}
)

app.status = JobApplication.STATUS_COMPLETED
app.save()

print(f"Created job #{job.id} and application")

# Create JWT token
token = create_jwt_token({'user_id': household.id, 'username': household.username})
client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

# Test review with metrics
print("\n[TEST] Creating review with detailed metrics...")
response = client.post('/api/reviews/', {
    'target_username': worker.username,
    'job_id': job.id,
    'job_title': job.title,
    'rating': 5,
    'feedback': 'Excellent work! Very impressed with the quality and professionalism.',
    'quality_of_work': 5,
    'punctuality': 4,
    'communication': 5,
    'professionalism': 5,
}, format='json')

print(f"Status: {response.status_code}")
if response.status_code == 201:
    print("Success! Review created:")
    data = response.data
    print(f"  ID: {data.get('id')}")
    print(f"  Overall Rating: {data.get('overall_rating')}")
    print(f"  Quality: {data.get('quality_of_work')}")
    print(f"  Punctuality: {data.get('punctuality')}")
    print(f"  Communication: {data.get('communication')}")
    print(f"  Professionalism: {data.get('professionalism')}")
else:
    print(f"Error: {response.data}")

# Verify database
print("\n[TEST] Verifying review in database...")
review = Review.objects.filter(job=job).last()
if review:
    print(f"Review found:")
    print(f"  Quality: {review.quality_of_work}")
    print(f"  Punctuality: {review.punctuality}")
    print(f"  Communication: {review.communication}")
    print(f"  Professionalism: {review.professionalism}")
