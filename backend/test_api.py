#!/usr/bin/env python
import os
import sys
import django
import json
from django.test import Client
from django.contrib.auth import get_user_model

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings.development')
sys.path.insert(0, os.path.dirname(__file__))

django.setup()

from rest_framework.test import APIClient

User = get_user_model()
client = APIClient()

# Get a test user
user = User.objects.first()
if not user:
    print("No users found")
    sys.exit(1)

print(f"Test user: {user.username}")

# Create a JWT token for the user
from apps.common.authentication import create_jwt_token
token = create_jwt_token({'user_id': user.id, 'username': user.username})
client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

# Test 1: Create a complaint via API
print("\n[TEST 1] Creating complaint via API...")
response = client.post('/api/complaints/create/', {
    'complaint_type': 'payment_issue',
    'description': 'Payment was not made after job completion',
    'job': None
}, format='json')
print(f"Status: {response.status_code}")
if response.status_code == 201:
    print(f"Success! Created complaint ID: {response.data.get('id')}")
    print(f"Data: {json.dumps(response.data, indent=2, default=str)}")
else:
    print(f"Error: {response.data}")

# Test 2: List complaints
print("\n[TEST 2] Listing complaints...")
response = client.get('/api/complaints/', format='json')
print(f"Status: {response.status_code}")
print(f"Count: {len(response.data)}")
for complaint in response.data[:2]:
    print(f"  - ID {complaint['id']}: {complaint['complaint_type']} ({complaint['status']})")

# Test 3: Get complaint detail
print("\n[TEST 3] Getting complaint detail...")
response = client.get('/api/complaints/1/', format='json')
print(f"Status: {response.status_code}")
if response.status_code == 200:
    print(f"Complaint: {response.data.get('complaint_type')}")
else:
    print(f"Error: {response.data}")
