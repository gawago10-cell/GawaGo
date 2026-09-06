# GawaGo Mobile Architecture

## Goal

Build the Flutter mobile app on top of the same Django API used by the web app. Core workflow rules should remain backend-owned so web and mobile screens show the same states.

## Folder Structure

```text
mobile/
  lib/
    src/
      app/
      core/
        api/
        config/
        errors/
        network/
        router/
        storage/
        theme/
      features/
        auth/
        dashboard/
        jobs/
        applications/
        notifications/
        profile/
        reviews/
        verification/
      shared/
        models/
        widgets/
        utils/
  assets/
    images/
    icons/
  test/
    features/
```

## Current Foundation

- `lib/main.dart` is now only the Flutter entry point.
- `lib/src/app/gawago_app.dart` owns app startup, session restoration, and the
  existing UI shell.
- `lib/src/core/api/` contains the shared Django API client.
- `lib/src/core/config/` contains environment-driven API configuration.
- `lib/src/core/errors/` contains reusable API error handling.
- `lib/src/core/storage/` securely persists the JWT and account role.
- `lib/src/core/theme/` contains shared visual tokens.
- `lib/src/shared/constants/` contains shared GawaGo form options.

Feature screens will move from the current app shell into `features/` as each
worker and household workflow is connected to its backend repository. This
keeps the initial refactor behavior-preserving instead of rewriting every UI
screen at once.

## Feature Rules

- `core` contains app-wide infrastructure such as API client, secure token storage, routing, theme, and network handling.
- `features` contains screen-specific modules.
- `data` contains API DTOs, repositories, and remote data sources.
- `domain` contains app models and use cases when needed.
- `presentation` contains screens, controllers, and widgets for the feature.
- `shared` contains reusable widgets and helper utilities.

## First Mobile MVP

The first mobile build focuses on the worker flow:

1. Login - connected
2. Worker dashboard - connected
3. Find jobs - connected
4. Job details and road route - connected
5. Apply to job - connected
6. Notifications - connected
7. Accept or reject hire request from job detail - connected
8. My applications - connected
9. Profile, rates, skills, and weekly availability - connected
10. Verification document submission - connected
11. Completion requests and household reviews - connected

Registration now saves a Tayabas coordinate selected from the map or device
location for both household and worker accounts.

## Household Flow

- Household dashboard and current profile are connected.
- Verification submission and pending/approved locking are connected.
- Verified households can post jobs with a real Tayabas map coordinate.
- My Jobs loads the authenticated household's backend jobs.
- Applicant details use backend road distance and route geometry.
- Pending applicants can be accepted or rejected.
- Smart matching displays strict-availability recommendations ranked by the
  backend and allows the household to send a hire request.
- Households can confirm completion and review completed workers.
- Household notifications support details, mark-as-read, and delete actions.

## Backend API Source of Truth

Mobile should display backend-provided fields such as:

- `job.status`
- `current_worker_application.status`
- `hired_count`
- `workers_needed`
- `can_apply`
- `can_accept_hire_request`
- `can_request_completion`
- `can_review`
- `route_distance_km`
- `route_points`

The Flutter app should not recalculate workflow rules that Django already provides.
