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
- Decimal values such as rates, latitude, and longitude may be returned as strings by Django REST Framework. Coerce before doing arithmetic — a value like `"5.00"` has no numeric methods.
- Common error shape:

```json
{
  "detail": "Human-readable error message."
}
```

### Pagination

List endpoints are paginated by DRF at **20 items per page**. Once a collection outgrows one page the response shape changes from a bare array to:

```json
{"count": 57, "next": "http://localhost:8000/api/jobs/?page=2", "previous": null, "results": [...]}
```

**Clients must follow `next` until it is `null`.** Reading only `results` silently drops every record past the first page, with no error to signal it — jobs and users simply start disappearing from lists once the platform passes 20 of them. Every record collection (jobs, applications, reviews, notifications, complaints, verification requests, admin certificate queue) is paginated; the matching endpoints (`/api/matching/recommended-workers/`, `/api/matching/recommended-jobs/`) return their full ranked result set unpaginated, so clients should accept both shapes.

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

### Worker Portfolio

| Method | Endpoint | Auth | Description |
| --- | --- | --- | --- |
| GET | `/api/accounts/profiles/{user_id}/portfolio/` | Bearer required | Public portfolio for one worker: `bio`, `years_experience`, `skills`, `certifications`, `portfolio_items`. |
| GET/POST | `/api/accounts/me/portfolio/skills/` | Bearer required, worker only | List or add portfolio skills. |
| PATCH/DELETE | `/api/accounts/me/portfolio/skills/{id}/` | Bearer required, owner only | Update or remove a skill. |
| GET/POST | `/api/accounts/me/portfolio/certifications/` | Bearer required, worker only | List or upload certificates (multipart). |
| PATCH/DELETE | `/api/accounts/me/portfolio/certifications/{id}/` | Bearer required, owner only | Update or remove a certificate. |
| GET/POST | `/api/accounts/me/portfolio/items/` | Bearer required, worker only | List or upload work samples (multipart). |
| PATCH/DELETE | `/api/accounts/me/portfolio/items/{id}/` | Bearer required, owner only | Update or remove a work sample. |

Note that decimal fields such as a skill's `average_rating` serialize as **strings** (`"5.00"`), so clients must coerce before doing arithmetic on them.

### Skill Ratings

`POST /api/accounts/jobs/{job_id}/skill-ratings/` — Auth: Bearer required, must be the job's household.

```json
{"skill": 3, "rating": 5, "feedback": "Spotless work."}
```

Supply either an existing `skill` id, or `skill_name` plus `worker_id` to rate work outside the posted scope (the `WorkerSkill` is created on the completed worker if needed). `rating` must be **1-5**; the value is averaged into the worker's skill standing, so out-of-range scores are rejected with 400. The job must be `completed`, and a `skill` belonging to a worker who never worked that job is rejected with 403.

### Certificate Verification (Admin)

| Method | Endpoint | Auth | Description |
| --- | --- | --- | --- |
| GET | `/api/accounts/admin/certificates/?status=pending` | Bearer required, `IsPlatformAdmin` | Lists worker certificates by `verification_status` (`pending`/`approved`/`rejected`). |
| PATCH | `/api/accounts/admin/certificates/{cert_id}/` | Bearer required, `IsPlatformAdmin` | Body: `{"verification_status": "approved"|"rejected", "verification_notes": "..."}`. |

Approving sets `is_verified` and stamps `verified_by`/`verified_at`; either decision notifies the worker (type `verification`). Each row carries `certificate_file_type` (`image`, `pdf`, `file` or empty) because `certificate_file_url` is an authenticated route with no extension. A worker who changes an already reviewed certificate's file, name, type, issuer or dates sends it back to `pending` (badge removed) and admins are alerted again. Any other `verification_status` value returns 400. Each row includes `worker_username` so the queue can show whose certificate it is.

### Identity Documents

The former second identity system (`/api/accounts/me/verification-documents/` and its admin queue) has been removed: its approval never reached `profile.verification_status`. Identity verification runs only through [Verification Requests](#verification-requests), whose `primary_id_type` takes the same 8 ID types: `national_id`, `passport`, `drivers_license`, `voter_id`, `tin`, `umid`, `postal_id`, `other`.

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
  "schedule": "Weekend starting 2026-06-01",
  "schedule_type": "Weekend",
  "job_start_date": "2026-06-01",
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

For the job's household (or staff), `applications` is ordered by Smart Matching's rule order -- skill match, then verification, then road distance, then rating and rate -- rather than by application time. Each application's `worker_match_score` is the separate AI content-based score (0-1). Live applications come before rejected/closed ones, and `GET /api/jobs/applications/?job_id=` returns the household the same order. `household_can_review` says whether the household can still review that particular worker (several workers can be hired on one job).

`skill_ratings` (`[{"skill_name": "House Cleaning", "rating": 4.5}]`) lists the per-skill ratings a worker received on that job. It is only filled on a worker's employment history (`GET /api/jobs/?worker=<user_id>&status=completed`) and is an empty list everywhere else.

The search radius is set with `geographic_boundary` (`1km`, `2km`, `5km`, `10km`, `unlimited`); `max_distance_km` always follows from it, on create and on edit, and a PATCH that sends `max_distance_km` alone is rejected with 400.

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
  "job_start_date": "2026-06-01",
  "description": "General cleaning",
  "location_label": "Barangay Wakas, Tayabas City",
  "latitude": "14.0250000",
  "longitude": "121.5920000",
  "service_rate": "800.00",
  "worker_slots": 1
}
```

Either `schedule` or `job_start_date` is required. New jobs must start as `open`.

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

## Smart Matching And Household AI Matching

`GET /api/matching/recommended-workers/?job_id=12&rank=ai`

`POST /api/matching/recommended-workers/`

Auth: Bearer required, job owner or staff only.

`rank` selects the ordering only; every result carries both scoring systems either way.

| `rank` | Ordering |
| --- | --- |
| omitted / `smart` (default) | Smart Matching's documented priority order: skill match, then verification, then road distance, then rating and rate. |
| `ai` | The content-based `ai_score`, highest first. Used by the post-a-job recommendation screen on web and mobile. |

POST body:

```json
{
  "job_id": 12,
  "rank": "ai"
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
      "worker_rate": "800.00 daily",
      "ai_score": 0.62,
      "skill_similarity": 0.88,
      "skill_contribution": 0.47,
      "proximity_contribution": 0.15,
      "exact_skill_match": true
    }
  ]
}
```

`match_score` is the rule-based Smart Matching score (roughly 0-100). `ai_score` is the content-based score in `[0, 1]`, equal to `skill_contribution + proximity_contribution`, and is the same algorithm the worker-facing recommendations use — so a household sees the same "why this match" breakdown a worker sees.

Workers the content-based scorer cannot rank — no saved location, no listed skills, or outside the job's search radius — are still returned with their Smart Matching fields, scoring `ai_score: 0.0`.

Matching is advisory under either ranking. Households still choose the final worker.

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

If no query parameter is provided, authenticated users receive reviews targeting themselves. Anonymous requests without a username return `400`. The list is paginated (newest first).

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
| GET | `/api/notifications/unread-count/` | Bearer required | `{"unread": n}` -- the badge number, without paging through every notification. |

Notification types:

- `application`
- `account_activity`
- `accepted`
- `hiring`
- `rejection`
- `verification`
- `completion`
- `review_reminder`
- `review` — a rating/feedback was submitted about the recipient
- `job_match` — a newly posted job scored above the AI match threshold (no email)
- `admin_alert` — sent to admins when a verification request or certificate is submitted, and to superadmins only when a report is filed
- `analytics` — legacy, no longer sent

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

Staff users receive all verification requests ordered by latest submission. Worker and household users receive only their own requests. Paginated.

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

## Reports

Exportable activity reports for the three audiences described in `AGENTS.md` IV.A.

`GET /api/reports/me/` — the signed-in user's own report. Auth: Bearer required. The backend picks the household or worker report from the caller's profile role, so clients do not choose.

`GET /api/reports/platform/` — platform-wide report. Auth: Staff/admin required. Head counts cover household and worker accounts only (admins excluded); `pendingVerifications` counts accounts with an ID waiting in the queue; `completedJobValue` is the sum of the agreed service rate of jobs completed in the period (not a payment ledger).

Both accept the same query parameters:

| Parameter | Meaning |
| --- | --- |
| `start`, `end` | `YYYY-MM-DD` bounds. Defaults to the trailing 180 days. Reversed bounds are swapped rather than returning an empty window. |
| `export=csv` | Returns the report as a CSV attachment instead of JSON. |

Note the CSV switch is `export`, not `format` — DRF reserves `format` for content negotiation.

Response:

```json
{
  "scope": "household",
  "title": "Household activity report",
  "period": { "start": "2026-03-17", "end": "2026-09-13" },
  "summary": {
    "jobsPosted": 9,
    "completedJobs": 9,
    "totalSpend": 4500.0,
    "averageRatingGiven": 5.0
  },
  "sections": [
    {
      "title": "Jobs by service type",
      "description": "Which services you post most often.",
      "columns": ["Service", "Jobs posted"],
      "rows": [["House Cleaning", 5]]
    }
  ]
}
```

All three scopes share this envelope, so one client renderer covers every role. `summary` values may be `null`, meaning "no data yet" rather than zero. Money figures are the sum of offered `service_rate` across completed jobs — GawaGo does not process payments, so this is agreed rate, not a payment ledger.

## Complaints ("Report an Issue")

An incident report against a specific job's other party — a household reporting a worker, or a worker reporting a household (payment issue, quality of work, no-show, safety concern, inappropriate behavior, other) — reviewed and resolved by admin. Distinct from Reports above: this is a case to investigate, not a personal activity summary.

Every report must be tied to a job the filer has a real stake in, at **any** job status (not only completed) — a live safety concern doesn't have to wait for the job to finish. The respondent is derived by the server, never accepted from the client:

- A household names which of the job's applicants the report is about (`respondent` = that worker's user id, validated to actually have an application on the job).
- A worker's report always targets that job's household — supplying a different `respondent` is ignored.

`GET /api/complaints/` — Auth: Bearer required. Reports the caller filed, plus reports naming them as respondent (both sides can see status; only the filer's own description is meant to be shown by clients — see confidentiality note below).

`POST /api/complaints/create/` — Auth: Bearer required.

```json
{
  "job": 19,
  "respondent": 1,
  "complaint_type": "no_show",
  "description": "Worker never showed up for the scheduled cleaning."
}
```
`respondent` is required when the filer is the job's household; omit it as a worker (it's derived). Returns 403 if the filer has no relationship to the job (not its household, no application on it), 400 if `job` is missing or the named `respondent` has no application on that job.

`GET /api/complaints/admin/?status=&type=` — Auth: `IsPlatformSuperAdmin`. Lists every report, optionally filtered.

`PATCH /api/complaints/admin/<id>/` — Auth: `IsPlatformSuperAdmin`. Body: any of `status` (`submitted|under_review|resolved|closed`), `resolution`, `admin_notes`. Rejects an unrecognized `status` with 400. On a real status change, sends the complainant (not the respondent) a notification that their report was updated — confidentiality is preserved by never telling the respondent a report exists. The notification is typed `account_activity`.

### Photo Evidence

`POST /api/complaints/create/` also accepts `multipart/form-data` with up to **5** `evidence` image files (extension-validated like job images). The plain JSON body above still works unchanged when no photo is attached. Each report returns its photos as an `evidence` array of `{id, image_url, uploaded_at, order}`.

### Suspend Or Restore The Reported Account

`POST /api/complaints/admin/<id>/block/` — Auth: `IsPlatformSuperAdmin`.

```json
{
  "blocked": true,
  "reason": "Repeated no-shows.",
  "duration_days": 3
}
```

| Field | Meaning |
| --- | --- |
| `blocked` | `true` suspends, `false` restores. Defaults to `true`. |
| `reason` | Shown to the suspended user in their notification. Cleared on restore. |
| `duration_days` | Optional, **3 or 7**. A timed suspension that lifts itself. Omit (or send `null`) for a permanent block. Any other value returns 400. |

Works identically whether the respondent is a worker or a household — the view only ever acts on the report's `respondent`. Admin accounts cannot be suspended from this queue (403), and a report with no respondent returns 400.

Suspension sets `UserProfile.is_blocked` rather than `auth_user.is_active`, because login reactivates any inactive account that supplies the correct password and would silently undo the block. It is enforced per-request in `JWTAuthentication`, so it takes effect **immediately on sessions that are already signed in**, not just at next login; `LoginView` refuses a blocked account with 403. A timed suspension expires lazily on the next login, authenticated request, or admin read, so no scheduled job is needed.

Response shape (all endpoints):
```json
{
  "id": 11,
  "complainant": 25,
  "complainant_username": "john",
  "respondent": 1,
  "respondent_username": "gawago",
  "respondent_is_blocked": true,
  "respondent_blocked_until": "2026-09-19T22:40:32+08:00",
  "job": 19,
  "job_title": "Test Job at Test Location",
  "job_service_type": "Test Service",
  "job_status": "completed",
  "complaint_type": "no_show",
  "description": "Worker never showed up for the scheduled cleaning.",
  "evidence": [
    {"id": 4, "image_url": "http://localhost:8000/media/complaint_evidence/11/sink.jpg", "uploaded_at": "2026-09-15T09:02:11+08:00", "order": 0}
  ],
  "status": "submitted",
  "resolution": null,
  "admin_notes": null,
  "created_at": "2026-09-13T16:10:54+08:00",
  "updated_at": "2026-09-13T16:10:54+08:00"
}
```

`respondent_is_blocked` reflects the account's *current* state (an expired timed suspension already reads as `false`). `respondent_blocked_until` is `null` when the account is unblocked **or** when the block is permanent.

## Mobile Client Notes

- Store the bearer token securely using platform secure storage.
- Refresh/login again when an API call returns token-expired authentication errors.
- Use multipart form data for profile photos, job images, and verification documents.
- Treat matching order and `match_score` as recommendation data only; final hiring choice remains user-controlled.
- Use `display_rating` for new users because unrated users are intentionally shown as `No ratings yet`.
