# GawaGo API Reference

This document describes the current REST API used by the web client and intended future mobile clients.

## Base URL

Local development:

```text
http://127.0.0.1:8000
```

Production clients should use the deployed HTTPS origin.

## Conventions

- Request and response bodies are JSON unless an endpoint explicitly accepts file uploads.
- Authenticated requests use a bearer token returned by `POST /api/accounts/login/`.
- Send the token as:

```http
Authorization: Bearer <access>
```

- Timestamps are ISO 8601 strings.
- Decimal values such as rates, latitude, and longitude may be returned as strings by Django REST Framework.
- Common error shape:

```json
{
  "detail": "Human-readable error message."
}
```

## Roles

- `household`: can create job postings, review applicants, hire workers, complete/cancel owned jobs, and review workers after completed jobs.
- `worker`: can apply to jobs, submit verification requests, and review households after completed jobs.
- `admin`: Django staff/superuser account. Can access admin-only analytics and approve/reject verification requests.

## Public System Endpoints

| Method | Endpoint | Auth | Description |
| --- | --- | --- | --- |
| GET | `/` | Public | Backend status message. |
| GET | `/health/` | Public | Health check. Returns `{"status":"ok"}`. |
| GET | `/admin/` | Staff session | Django admin UI. |

## Accounts

### Register

`POST /api/accounts/register/`

Auth: Public

Creates an active account that can log in immediately. Email verification is not required in the current development flow.

```json
{
  "username": "maria",
  "email": "maria@example.com",
  "password": "strong-password",
  "first_name": "Maria",
  "last_name": "Santos",
  "role": "household",
  "phone": "09170000000",
  "bio": "",
  "years_experience": 0,
  "skills": ["cleaning", "cooking"],
  "hourly_rate": "150.00",
  "daily_rate": "800.00",
  "location_label": "Tayabas City",
  "latitude": "14.0250000",
  "longitude": "121.5920000"
}
```

Response `201` includes `detail`, `user`, and `profile`.

### Verify Signup

`POST /api/accounts/verify-signup/`

Auth: Public

Legacy endpoint. The current registration flow does not require mobile or web clients to call this endpoint before login.

```json
{
  "email": "maria@example.com",
  "token": "123456"
}
```

Response `200`:

```json
{
  "detail": "Email verified and account activated."
}
```

### Login

`POST /api/accounts/login/`

Auth: Public

```json
{
  "username": "maria",
  "password": "strong-password"
}
```

Response `200`:

```json
{
  "detail": "Login successful.",
  "access": "<jwt>",
  "username": "maria",
  "email": "maria@example.com",
  "display_name": "Maria Santos",
  "role": "household",
  "is_staff": false,
  "profile": {}
}
```

The token currently expires after 60 minutes.

### Logout

`POST /api/accounts/logout/`

Auth: Bearer required

Flushes the Django session when present and returns:

```json
{
  "detail": "Logged out."
}
```

### Current Profile

| Method | Endpoint | Auth | Description |
| --- | --- | --- | --- |
| GET | `/api/accounts/me/` | Bearer required | Returns current user and profile. |
| PATCH | `/api/accounts/me/` | Bearer required | Updates current user/profile. Accepts JSON or multipart form data for `profile_photo`. |

Patchable fields:

```json
{
  "first_name": "Maria",
  "last_name": "Santos",
  "email": "maria@example.com",
  "phone": "09170000000",
  "bio": "Available weekdays",
  "years_experience": 3,
  "skills": ["cleaning", "childcare"],
  "hourly_rate": "150.00",
  "daily_rate": "800.00",
  "location_label": "Tayabas City",
  "latitude": "14.0250000",
  "longitude": "121.5920000"
}
```

### Profiles

`GET /api/accounts/profiles/`

Auth: Bearer required. Staff users receive the full profile serializer; non-staff users receive the public serializer.

Returns user profiles. Non-staff clients do not receive email, phone, verification request details, latitude, or longitude.

### Worker Availability

| Method | Endpoint | Auth | Description |
| --- | --- | --- | --- |
| GET | `/api/accounts/me/availability/` | Bearer required, worker only | Lists the current worker's available windows. |
| PUT | `/api/accounts/me/availability/` | Bearer required, worker only | Replaces the current worker's availability windows. |

PUT body:

```json
{
  "availability_windows": [
    {
      "date": "2026-06-01",
      "start_time": "09:00",
      "end_time": "17:00",
      "is_available": true
    }
  ]
}
```

### Password Reset

| Method | Endpoint | Auth | Body | Description |
| --- | --- | --- | --- | --- |
| POST | `/api/accounts/forgot-password/` | Public | `{"email":"maria@example.com"}` | Sends reset code if the email exists. |
| POST | `/api/accounts/verify-reset-token/` | Public | `{"email":"maria@example.com","token":"123456"}` | Checks reset code validity. |
| POST | `/api/accounts/reset-password/` | Public | `{"email":"maria@example.com","token":"123456","new_password":"new-strong-password"}` | Sets a new password. |

## Jobs And Applications

### Job Object

Representative fields:

```json
{
  "id": 12,
  "household_username": "maria",
  "household_name": "Maria Santos",
  "title": "Weekend house cleaning",
  "job_type": "Domestic Helper",
  "required_skill": "cleaning",
  "schedule": "Weekend on 2026-06-01 at 09:00",
  "schedule_type": "Weekend",
  "preferred_date": "2026-06-01",
  "preferred_time": "09:00:00",
  "description": "General cleaning",
  "location_label": "Barangay Wakas, Tayabas City",
  "latitude": "14.0250000",
  "longitude": "121.5920000",
  "service_rate": "800.00",
  "worker_slots": 1,
  "status": "open",
  "created_at": "2026-05-26T12:00:00Z",
  "completed_at": null,
  "applications": [],
  "images": []
}
```

Job statuses: `open`, `assigned`, `completed`, `cancelled`.

Application statuses: `pending`, `hired`, `rejected`, `closed`, `completed`.

### List Jobs

`GET /api/jobs/`

Auth: Public

Optional filters:

- `status`
- `job_type`
- `location`
- `required_skill`
- `min_rate`
- `max_rate`

Example:

```text
GET /api/jobs/?status=open&required_skill=cleaning&location=Tayabas
```

### Create Job

`POST /api/jobs/`

Auth: Bearer required, household only.

Accepts JSON or multipart form data. Multipart field `images` accepts up to 5 images, each JPG, PNG, or WebP and up to 5 MB.

```json
{
  "title": "Weekend house cleaning",
  "job_type": "Domestic Helper",
  "required_skill": "cleaning",
  "schedule_type": "Weekend",
  "preferred_date": "2026-06-01",
  "preferred_time": "09:00",
  "description": "General cleaning",
  "location_label": "Barangay Wakas, Tayabas City",
  "latitude": "14.0250000",
  "longitude": "121.5920000",
  "service_rate": "800.00",
  "worker_slots": 1
}
```

Either `schedule` or both `preferred_date` and `preferred_time` are required. New jobs must start as `open`.

### Job Detail

| Method | Endpoint | Auth | Description |
| --- | --- | --- | --- |
| GET | `/api/jobs/{id}/` | Public | Returns one job with applications and images. |
| PATCH | `/api/jobs/{id}/` | Bearer required, job owner or staff | Updates a job. |
| PUT | `/api/jobs/{id}/` | Bearer required, job owner or staff | Replaces a job. |
| DELETE | `/api/jobs/{id}/` | Bearer required, job owner or staff | Deletes a job. |

Allowed job status transitions:

- `open` to `open` or `cancelled`
- `assigned` to `assigned`, `completed`, or `cancelled`
- `completed` stays `completed`
- `cancelled` stays `cancelled`

A job can be completed only when it has at least one hired worker. Completion also updates related application/review workflow through backend services.

### Apply To Job

`POST /api/jobs/{job_id}/apply/`

Auth: Bearer required, worker only.

```json
{
  "note": "I am available at the requested time."
}
```

Response `201` returns the created application.

### Update Application Status

`PATCH /api/jobs/applications/{id}/status/`

Auth: Bearer required, job owner or staff.

```json
{
  "status": "hired"
}
```

Allowed requested statuses are `hired` and `rejected`.

Hiring a worker moves the job to `assigned`. When all worker slots are filled, other pending applications are closed.

## Smart Matching

`GET /api/matching/recommended-workers/?job_id=12`

`POST /api/matching/recommended-workers/`

Auth: Bearer required, job owner or staff only.

POST body:

```json
{
  "job_id": 12
}
```

Response:

```json
{
  "job_id": 12,
  "job_title": "Weekend house cleaning",
  "required_skill": "cleaning",
  "results": [
    {
      "worker_id": 7,
      "worker_username": "juan",
      "skills": ["cleaning", "laundry"],
      "matches_skill": true,
      "verification_status": "verified",
      "distance_km": 2.4,
      "distance_label": "2.4 km away",
      "match_score": 92.5,
      "rating_label": "4.80",
      "rating_score": 4.8,
      "available_at_requested_time": true,
      "rate_score": 1.0,
      "worker_rate": "800.00 daily"
    }
  ]
}
```

Matching is advisory. Households still choose the final worker.

## AI-Based Job Recommendations

`GET /api/matching/recommended-jobs/`

Auth: Bearer required, worker role only.

Returns open jobs ranked for the logged-in worker by a content-based algorithm (TF-IDF skill similarity blended with road-route proximity; see `AGENTS.md` I.C for the full explanation). Jobs outside their own configured search radius are excluded, not merely ranked lower.

Response:

```json
{
  "results": [
    {
      "job": { "...": "job posting fields" },
      "ai_score": 0.82,
      "skill_similarity": 0.9,
      "distance_km": 1.4,
      "skill_contribution": 0.63,
      "proximity_contribution": 0.19,
      "exact_skill_match": true
    }
  ]
}
```

`ai_score` is `skill_contribution + proximity_contribution` (weighted 0.7/0.3). The frontend uses `skill_contribution`/`proximity_contribution` to show a "why this match" breakdown rather than the score alone.

Recommendations are advisory, same as Smart Matching. When a household posts a new open job, this same scoring also runs in the background against every candidate worker; workers scoring above `JOB_MATCH_NOTIFY_THRESHOLD` (default `0.5`, see `backend/config/settings/base.py`) get a `job_match` notification without needing to call this endpoint themselves.

## Reviews

### List Reviews

`GET /api/reviews/`

Auth: Public

Query options:

- `username` or `target_username`: reviews received by a user.
- `author_username`: reviews written by a user.

If no query parameter is provided, authenticated users receive reviews targeting themselves. Anonymous requests without a username return `400`.

Worker-to-household feedback is anonymous in API responses. For anonymous worker feedback, `author` is `null`, `author_username` is empty, and `author_name` is `Anonymous worker`. Public `author_username` queries do not expose worker-authored anonymous feedback.

### Create Review

`POST /api/reviews/`

Auth: Bearer required.

```json
{
  "target_username": "juan",
  "job_id": 12,
  "job_title": "Weekend house cleaning",
  "rating": "5.0",
  "feedback": "Arrived on time and completed the work well."
}
```

Rules:

- Reviews are only allowed between households and workers.
- Reviews require a completed job relationship.
- Households may rate workers from `1.0` to `5.0`.
- Workers may submit feedback for households, but cannot assign a numeric rating.
- A household can review the same worker only once per completed job.

## Notifications

| Method | Endpoint | Auth | Description |
| --- | --- | --- | --- |
| GET | `/api/notifications/` | Bearer required | Lists current user's notifications. |
| PATCH | `/api/notifications/{id}/read/` | Bearer required | Marks one notification as read. |

Notification types:

- `application`
- `account_activity`
- `accepted`
- `hiring`
- `rejection`
- `verification`
- `analytics`
- `completion`
- `review_reminder`

Notification object:

```json
{
  "id": 30,
  "recipient": 7,
  "recipient_username": "juan",
  "notification_type": "accepted",
  "title": "Application accepted",
  "message": "Your application for Weekend house cleaning was accepted.",
  "is_read": false,
  "created_at": "2026-05-26T12:00:00Z"
}
```

## Verification Requests

### List Verification Requests

`GET /api/common/verification-requests/`

Auth: Bearer required.

Staff users receive all verification requests ordered by latest submission. Worker users receive only their own requests. Household users are rejected with `403`.

### Submit Verification Request

`POST /api/common/verification-requests/`

Auth: Bearer required, worker only.

```json
{
  "primary_id_name": "National ID",
  "secondary_doc_name": "Barangay clearance",
  "primary_id_file": "<file>",
  "secondary_doc_file": "<file>",
  "notes": "Available for admin review."
}
```

If the worker already has a non-rejected request, it is updated and reset to `pending`.

Verification document uploads accept JPG, PNG, WebP, or PDF files up to 5 MB each. The API response returns protected document URLs in `primary_id_preview` and `secondary_doc_preview`; these URLs require bearer authentication and are only available to the worker owner or staff users.

### Verification Documents

| Method | Endpoint | Auth | Description |
| --- | --- | --- | --- |
| GET | `/api/common/verification-requests/{id}/documents/primary/` | Bearer required, request owner or staff only | Streams the submitted primary ID file. |
| GET | `/api/common/verification-requests/{id}/documents/secondary/` | Bearer required, request owner or staff only | Streams the submitted supporting document file. |

### Verification Request Detail

`GET /api/common/verification-requests/{id}/`

Auth: Bearer required, request owner or staff only.

Returns `verification_request` and associated `worker`.

### Review Verification Request

`POST /api/common/verification-requests/{id}/review/`

Auth: Staff/admin required.

Approve:

```json
{
  "action": "approve"
}
```

Reject:

```json
{
  "action": "reject",
  "review_note": "Document is unreadable."
}
```

Approval sets the worker profile `verification_status` to `verified`. Rejection sets it to `rejected`.

## Analytics

`GET /api/analytics/dashboard-metrics/`

Auth: Staff/admin required.

Response:

```json
{
  "open_jobs": 10,
  "verified_workers": 6,
  "completed_jobs": 18,
  "cancelled_jobs": 2,
  "active_applications": 14,
  "total_accounts": 42,
  "avg_rating": 4.7,
  "analytics": {}
}
```

The nested `analytics` object contains dashboard summaries such as job activity, verification/trust metrics, geographic distribution, and service rate transparency data.

## Mobile Client Notes

- Store the bearer token securely using platform secure storage.
- Refresh/login again when an API call returns token-expired authentication errors.
- Use multipart form data for profile photos, job images, and verification documents.
- Treat matching order and `match_score` as recommendation data only; final hiring choice remains user-controlled.
- Use `display_rating` for new users because unrated users are intentionally shown as `No ratings yet`.
