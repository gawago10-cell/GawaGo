# Notifications and Analytics (spec III, IV)

Part of the GawaGo spec; [AGENTS.md](../../AGENTS.md) has the rules most changes need and the section index.

## III. Communication and Notification System

### A. Notification and Alerts
- In-system notifications, each mirrored by an automated email, cover: job application submitted, application hired, application rejected, job completion, rating/review submitted, verification status change, review reminders, account activity, and admin alerts.
- The mirrored emails go out in the background once the change is saved (`transaction.on_commit` + `enqueue`), the same way admin alerts and match alerts do, so a household cancelling a job with many applicants isn't kept waiting and no email goes out for an action that rolled back (second scan, 2026-11-01).
- Admin alerts tell administrators that something is waiting in a review queue: every active admin is alerted when a verification request or a certificate is submitted, and only superadmins are alerted when a report is filed (the alert names no one, keeping the report confidential). Admin dashboards have no notification inbox, so admins receive these through the mirrored email; the queues themselves show what is pending.
- A separate, email-less notification alerts a worker when a newly posted job scores above the AI recommendation match threshold (see I.C), so a strong match reaches the worker without them having to check manually.
- Notifications carry read/unread state and, where relevant, an action link back to the job, hire request, or review that triggered them. They name people by display name, not login username (fourth scan, 2026-11-01).
- A household is told when a worker withdraws an application or backs out of a hire (with the worker's reason), and is reminded once, the day after a hired job's last day, to mark it done or cancel it (fourth scan, 2026-11-01).

## IV. Employment Analytics and Monitoring

### A. Dashboard and Reports
- Employment activity dashboard with real-time counts of:
  - Total job postings
  - Active applications
  - Completed services
  - Cancelled requests
  - Ongoing matches
- Hiring performance metrics:
  - Hiring success rate (share of applications resulting in a hire)
  - Job match rate (share of jobs successfully matched)
  - Hired worker count and repeat-hire count
  - Application volume trend over time and monthly job posting volume, each charted
  - Job distribution by service type, charted
- Verification and trust metrics:
  - Verified users
  - Pending verifications
  - Reputation score distribution
- Geographic service distribution:
  - One line chart of job requests against available workers in the 10 barangays with the most demand (`geographicAnalytics.demandVsSupply`), so a barangay short of workers shows where the job line runs above the worker line
- Service rate transparency summary:
  - Disclosed rates by job category, averaged separately for day, hourly and fixed rates and counted under catalog service names (a day rate and an hourly rate can't share an average; fourth scan, 2026-11-01)
  - Service rate trends (the average day rate offered on new per-day job posts each month; a month with no posts has no rate and is left as a gap, not plotted as PHP 0); named for service rates rather than "pricing", since workers are not products (panel review, 2026-10-31)
  - Purpose: support fair pricing and protect both workers and households from underpricing or overpricing
- Every chart and summary carries a one-line description under its title saying what it shows, on web and mobile.

### B. Admin Reports

- Separate from the admin dashboard above, administrators can pull a date-bounded, platform-wide activity report (accounts, employment, verification, and reputation totals, plus breakdowns by service type, barangay, month, and reputation tier), exportable as CSV. This is admin-only — households and workers do not have an activity-report screen; `GET /api/reports/me/` exists on the backend but nothing in either client calls it.
- The completed-job value is estimated per job from its agreed rate: a day rate times its working days times the workers who did it, a fixed rate times those workers. Hourly jobs are counted (`completedHourlyJobs`) but not valued, since hours aren't recorded (fourth scan, 2026-11-01). GawaGo does not process payments, so these represent agreed rates for work that reached `Completed`, not a payment ledger.
- Dashboard versus reports: the dashboard answers "what is happening right now" with live counts and hiring performance; reports answer "what happened over this period" for one role, and are exportable. Metrics that are point-in-time counts belong on the dashboard, not the analytics charts.
