# GawaGo

A responsive web app (React + Bootstrap 5) and a Flutter mobile app on one Django + PostgreSQL backend. It connects households in Tayabas City with domestic helpers and skilled workers: post a job, match, apply or invite, hire, complete, review, report.

## Rules most changes need

- **The backend decides; clients render.** Business logic lives in backend services so web and mobile behave the same. Application and job status words come from `apps/jobs/statuses.py` (`status_stage`/`status_label`); clients never word statuses themselves.
- **Two matchers, kept separate, both advisory.** Smart Matching ranks workers for a job by rule: skill match, then verification, then road-route distance, then rating and rate. The AI score is `0.7 × TF-IDF skill similarity + 0.3 × 1/(1 + km)` and runs both ways (jobs for a worker, workers for a job). A job's search radius (1, 2, 5, 10 km or unlimited; default 1 km) is a hard boundary for both. The household always makes the final choice.
- **Trust gates.** Approving a `common/verification-requests/` entry sets `profile.verification_status`, which gates posting, applying and hiring. Only the household marks a job done (`can_mark_done`), never before its start date, and reviews need a completed job. With metric ratings, the overall rating is their average. Workers list 1 to 3 skills from the shared catalog (`apps/common/skills.py`); `Other` opens a text box and is never saved as a skill.
- **Tayabas City only.** Every location is checked against the city boundary polygon (`apps/common/tayabas_boundary.py`, mirrored in `frontend/src/data/tayabasCityBoundary.js`). Workers and job sites need a map pin or GPS fix; nothing falls back to the town centre. Signed-out visitors see only a ~1 km approximate job pin, and a household's phone and email stay hidden until that worker is hired (`apps/jobs/privacy.py`).
- **Complaints are confidential.** Screens call them complaints (the code's `complaints` app); the admin "Reports" tab is the separate activity report. Only superadmins review complaints and suspend accounts. The person named is never notified. Status moves forward only: Submitted, Under Review, then Resolved or Closed, with a resolution the filer can read. A suspension needs a reason.
- **Notifications.** Every notification except the job-match alert is mirrored by email; admins get their alerts by email only.
- **Lists.** Collection endpoints return 20 per page; clients follow `next`. The two matching endpoints return one unpaginated ranked list.
- **Reference data has one copy per layer** (66 barangays, the skill catalog, the city boundary). `apps/common/test_reference_data.py` fails when the web or mobile copy drifts from the backend's.
- **Background work runs after commit.** The job-match notification pass is queued with `transaction.on_commit` through `apps.common.background.enqueue()`, never inside the request.

## Stack and direction

- Frontend: HTML5, JavaScript (React), CSS with Bootstrap 5. Mobile: Flutter. Backend: Python Django. Database: PostgreSQL.
- One shared Django backend serves both clients; API endpoints and authentication are designed for web and mobile alike.

## Spec index

Code comments cite sections as "AGENTS.md II.D". Each section now lives in its own file:

| Section | Topic | File |
| --- | --- | --- |
| I.A | Job posting, application and job statuses | [docs/spec/jobs-and-matching.md](docs/spec/jobs-and-matching.md) |
| I.B | Smart Matching and the distance indicator | [docs/spec/jobs-and-matching.md](docs/spec/jobs-and-matching.md) |
| I.C | AI job recommendations (pull, push, household view, explainability) | [docs/spec/jobs-and-matching.md](docs/spec/jobs-and-matching.md) |
| II.A | Reviews, metric ratings, tiers, default 3.5 rating | [docs/spec/trust-and-reputation.md](docs/spec/trust-and-reputation.md) |
| II.B | Price transparency | [docs/spec/trust-and-reputation.md](docs/spec/trust-and-reputation.md) |
| II.C | Worker portfolio, certificates, identity verification | [docs/spec/trust-and-reputation.md](docs/spec/trust-and-reputation.md) |
| II.D | Reports and suspensions | [docs/spec/trust-and-reputation.md](docs/spec/trust-and-reputation.md) |
| III.A | Notifications and admin alerts | [docs/spec/notifications-and-analytics.md](docs/spec/notifications-and-analytics.md) |
| IV.A | Admin dashboard metrics | [docs/spec/notifications-and-analytics.md](docs/spec/notifications-and-analytics.md) |
| IV.B | Admin activity reports and CSV | [docs/spec/notifications-and-analytics.md](docs/spec/notifications-and-analytics.md) |
| V | Scope: worker types, skill catalog, Tayabas area, matching approach | [docs/spec/scope-and-terms.md](docs/spec/scope-and-terms.md) |
| Terms | Definition of terms | [docs/spec/scope-and-terms.md](docs/spec/scope-and-terms.md) |
| Implementation notes | Verification flow, pagination, location visibility and capture, reference data, background tasks | [docs/implementation-notes.md](docs/implementation-notes.md) |
