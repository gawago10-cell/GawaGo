# GawaGo - Product Objectives and Functional Scope

## App Name
`GawaGo`

## Mission
Build a centralized, responsive web and mobile application platform that helps households and workers connect, manage job opportunities, and complete services with trust, transparency, and clear communication.

## I. Employment Matching and Job Allocation

### A. Job Posting and Application
- Households can post job requests including:
  - Job type
  - Schedule, plus an optional job start date, end date, and estimated number of working days
  - Location
  - Service rate
  - A geographic search radius for matching (`1 km`, `2 km`, `5 km`, `10 km`, or `unlimited`; defaults to `1 km`)
- Workers can apply to available jobs based on:
  - Skills (a worker may list at most 3 skills on their profile)
  - Availability
- Households can review applicant profiles before confirming a worker.
- Application status uses three plain terms to avoid confusion with job completion: `Pending` (awaiting a decision), `Hired` (accepted), and `Rejected`. A job itself separately becomes `Completed` once both parties confirm the work is done.

### B. Smart Matching with Distance Indicator
- System ranks and suggests workers using, in priority order:
  1. Skill matching: workers with matching skills appear first.
  2. Verification status: verified workers are prioritized.
  3. Distance: workers are ranked by road-route distance (not straight-line), and any worker outside the job's geographic search radius is excluded outright rather than merely ranked lower.
  4. Rating and offered rate as tie-breakers.
- Distance is shown to households as a road-route estimate from the worker's registered location to the job site (for example, `2 km away`).
- Households retain final hiring choice regardless of ranking (can still choose based on price, ratings, experience, or preference).

### C. AI-Based Job Recommendations
- Separate from Smart Matching (which ranks *workers for a household's job*), this feature ranks *open jobs for a worker* using a content-based recommendation algorithm rather than the fixed rule ordering above.
- Scoring: each worker-skill list and each job's required skill are compared with TF-IDF cosine similarity to produce a skill-similarity score; a road-route proximity score (`1 / (1 + distance_km)`) is computed the same way Smart Matching computes distance. The final score blends the two as `0.7 × skill similarity + 0.3 × proximity`, so a skill mismatch outweighs being nearby. Jobs outside their own configured search radius are excluded before scoring, the same hard-boundary rule Smart Matching applies.
- Pull delivery: a worker can request "Find Jobs for Me" to see their open jobs ranked by this score, each shown with a `% match` badge and distance.
- Push delivery: when a household posts a new open job, the system scores it against every candidate worker in the background and sends a job-match notification to any worker scoring above a configurable threshold, instead of waiting for the worker to check manually.
- Household delivery: the same content-based score also runs in the opposite direction, ranking *workers for a job*. Immediately after a household posts a job they land on a recommended-workers screen showing each candidate's `% match` and the same skill-versus-proximity breakdown a worker sees. This does not replace Smart Matching: the job detail screen still lists candidates in Smart Matching's rule order (which prioritises verification), and both scores are returned on every result so the two remain complementary rather than competing.
- Explainability: each recommendation also reports how much of the score came from skill fit versus proximity (and whether the match was an exact skill match, not just a related one), shown to the worker as a breakdown (for example, "70% skill fit, 30% proximity") rather than a single opaque number.
- Future enhancement: once enough completed-job/hire outcome data exists, this can be extended with a collaborative-filtering signal ("workers with similar hire histories were chosen for jobs like this") layered on top of the content-based score. That requires a worker-job interaction dataset that does not yet exist, so it is out of scope for now.

## II. Reputation and Trust Management System

### A. Reputation Scoring and Reviews
- Households can rate workers after completed jobs; workers can rate households to support fairness on both sides.
- A review can only be submitted once the job is marked `Completed` and the reviewer's hire relationship for that job is also completed, preventing ratings for work that never happened.
- Reviews carry an overall 1-5 rating plus four optional e-commerce-style metrics — quality of work, punctuality, communication, and professionalism — each rated 1-5; when the metrics are provided, the overall rating is their average.
- Workers are additionally assigned a reputation tier based on their average rating and review count: `New` (default), `Established` (3.5+ with 5+ reviews), `Trusted` (4.0+ with 5+ reviews), and `Elite` (4.5+ with 5+ reviews). A rating trend (`Improving`, `Declining`, or `Neutral`) compares a worker's last 30 days of reviews against older ones.
- Households may also rate a worker's individual portfolio skills (see II.C) after a completed job; these per-skill ratings roll up into the average shown on that skill.
- System sends reminders to submit feedback after job completion.
- Neutral no-feedback policy:
  - If no household rating is submitted within 72 hours of job completion, system assigns a default 3.5-star rating to the worker.
- New users display `No ratings yet` instead of `0` or empty numeric score.

### B. Price Transparency
- Workers must disclose service rates on profiles (hourly and/or daily).
- Households must see agreed rates before worker confirmation.

### C. Worker Portfolio and Credibility
- Workers can build a public portfolio with:
  - A bio and years of experience.
  - Individually listed skills with a proficiency level (beginner, intermediate, expert) and an aggregated household rating per skill.
  - Certifications and credentials (TESDA certificate, professional license, credential, certification, or other), each uploaded with supporting files and subject to admin approval before showing a verified badge.
  - Work-sample images, including optional before/after pairs.
  - Employment history: completed jobs with the hiring household, location, and the skill ratings received.
- Identity verification supports multiple government ID types (national ID, passport, driver's license, voter ID, TIN, UMID, postal ID, or other); administrators review and approve or reject each submission.

### D. Dispute Resolution
- Households and workers can file a complaint tied to a specific job, at any job status (payment issue, quality of work, no-show, safety concern, inappropriate behavior, or other) &mdash; a live safety concern does not have to wait for the job to finish. A household names which of the job's applicants the report is about; a worker's report always targets that job's household. Every report is traceable to a specific job/household/worker relationship the filer actually has, rather than an unverifiable free-floating accusation.
- A report may carry up to five photos as evidence, so an administrator can see what happened rather than judging from the written description alone.
- Administrators track each complaint through `Submitted` &rarr; `Under Review` &rarr; `Resolved`/`Closed`, with resolution notes visible to the filer. The person reported is not notified that a report exists &mdash; only the filer is notified when its status changes, keeping the case confidential while under review.
- Having reviewed a report, an administrator can act on the account it names: a timed suspension of 3 or 7 days that lifts itself automatically, or an indefinite block. Either is reversible, applies equally to a worker or a household, cannot be used against another administrator, and takes effect immediately on any session already signed in. The suspended user is notified with the administrator's stated reason and, for a timed suspension, the date it ends.

## III. Communication and Notification System

### A. Notification and Alerts
- In-system notifications, each mirrored by an automated email, cover: job application submitted, application hired, application rejected, job completion, rating/review submitted, verification status change, review reminders, account activity, and admin alerts.
- A separate, email-less notification alerts a worker when a newly posted job scores above the AI recommendation match threshold (see I.C), so a strong match reaches the worker without them having to check manually.
- Notifications carry read/unread state and, where relevant, an action link back to the job, hire request, or review that triggered them.

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
  - Barangays with high job demand
  - Areas with higher worker availability
- Service rate transparency summary:
  - Disclosed rates by job category
  - Average pricing trends
  - Purpose: support fair pricing and protect both workers and households from underpricing or overpricing

### B. Admin Reports

- Separate from the admin dashboard above, administrators can pull a date-bounded, platform-wide activity report (accounts, employment, verification, and reputation totals, plus breakdowns by service type, barangay, month, and reputation tier), exportable as CSV. This is admin-only — households and workers do not have an activity-report screen; `GET /api/reports/me/` exists on the backend but nothing in either client calls it.
- Money figures are the sum of the offered service rate across completed jobs. GawaGo does not process payments, so these represent agreed rates for work that reached `Completed`, not a payment ledger.
- Dashboard versus reports: the dashboard answers "what is happening right now" with live counts and hiring performance; reports answer "what happened over this period" for one role, and are exportable. Metrics that are point-in-time counts belong on the dashboard, not the analytics charts.

## V. Scope and Limitations

- Worker types: registered workers fall into two categories — domestic helpers (cleaning, cooking, laundry, childcare, elder care, and similar home-based tasks) and skilled workers (electrical, plumbing, carpentry, painting, aircon repair, welding, and similar trade services). A worker profile lists at most 3 skills to keep listings scannable and matching meaningful.
- Geographic area: the platform targets households and workers within Tayabas City and its barangays; job locations and worker registrations are expected to fall within this area, and the smart matching distance boundary (1-10 km, or unlimited) is calibrated for a single-city service area rather than nationwide reach.
- Matching approach: the platform uses two complementary matching features. Smart Matching (household-facing) is a deterministic, rule-based ranking of workers for a job (skill match, verification, road-route distance, rating, and rate). AI-Based Job Recommendations (worker-facing, see I.C) is a content-based model that scores open jobs for a worker from TF-IDF skill similarity and road-route proximity, with an explainability breakdown shown to the worker. Neither model currently learns from historical hiring outcomes; a collaborative-filtering layer that does has been identified as a future enhancement once enough completed-job/hire data has accumulated to train and validate one.
- Proximity range justification: domestic and skilled-trade work in this study is assumed to be commuted to on foot, by bicycle, or by short tricycle/jeepney rides rather than long-distance travel, so a 1 km default radius (configurable up to unlimited per job) keeps recommended workers realistically reachable for same-day or recurring work.

## Implementation Notes

- Platform type: centralized web-based and mobile application system.
- UX requirement: responsive on desktop and mobile.
- Matching assistance is advisory; user autonomy in final selection must remain intact.
- Trust mechanisms (verification + reviews + pricing disclosure) are core, not optional.
- Identity verification currently has **two** backend implementations: the `common/verification-requests/` flow (primary ID plus a supporting document), which is what both shipped clients actually use, and a separate multi-ID-type system (`accounts/*/verification-documents/`) that matches the eight ID types described in II.C but has no worker-facing upload screen. These should be consolidated onto one before the system is presented as final; documenting it here so the duplication is not mistaken for a single coherent flow.
- Collection endpoints are paginated at 20 records per page, and clients must follow the `next` link. Reading only the first page silently loses data rather than failing loudly.

## Required Technology Stack
- Frontend structure and markup: `HTML5`
- Frontend scripting: `JavaScript (React)`
- Frontend styling framework: `CSS` with `Bootstrap 5`
- Backend framework: `Python Django`
- Database style: `MySQL`

## Development Direction
- Build a shared backend in Django to serve both web and mobile clients.
- Keep core business logic centralized in backend services to ensure consistent behavior across platforms.
- Design API endpoints and authentication flows to support both web frontend and mobile applications.

## Definition of Terms

### Technical Terms
- Distance Indicator: A measurement that shows the geographic distance between two locations. In this study, it refers to the system feature that displays the approximate road-route distance between a worker's registered location and the household's job site to help households assess worker proximity.
- Employment Analytics Dashboard: A digital interface that visually presents employment-related data and statistics. In this study, it refers to the administrative dashboard that displays information such as job activity, hiring performance, verified users, geographic service distribution across barangays, and service rate summaries to support monitoring and decision-making.
- Smart Matching: An automated process that recommends or pairs users based on predefined criteria. In this study, it refers to the system feature that suggests suitable workers to households based on factors such as skills, verification status, and geographic proximity to the job location, applying the job's search radius as a hard boundary rather than a soft preference.
- AI-Based Job Recommendations: A content-based recommendation feature that ranks open jobs for a worker, as opposed to Smart Matching's ranking of workers for a job. In this study, it refers to the system feature that scores each open job against a worker's skills and location using TF-IDF skill similarity blended with road-route proximity, surfaces the result as a percentage match with a skill-fit-versus-proximity breakdown, and proactively notifies workers of strong matches when a household posts a new job.
- Verification: The process of confirming the authenticity or validity of a person's identity or credentials. In this study, it refers to the administrative procedure where system administrators review and approve identification documents and worker certifications, allowing verified workers to receive a verification badge and higher priority in smart matching results.
- Web-Based Employment System: A software application that can be accessed through a web browser using an internet connection. In this study, it refers to the proposed platform that allows households, domestic helpers, and skilled workers in Tayabas City to interact, post jobs, apply for work, and manage employment activities online.
- Worker Portfolio: A worker-maintained profile section that showcases qualifications beyond a basic listing. In this study, it refers to the platform feature combining a bio, individually rated skills, uploaded certifications, and work-sample images that households can review before hiring.

### Non-Technical Terms
- Application Status: The current stage of a worker's job application. In this study, it refers to one of three states — Pending, Hired, or Rejected — kept separate from a job's own Completed status to avoid confusing an undecided application with finished work.
- Complaint: A formal report of a problem encountered during or after a job. In this study, it refers to the dispute report a household or worker can file against the other party (for example, a payment issue or a no-show), which an administrator reviews and resolves.
- Default Rating: A system-assigned rating automatically given when a household does not submit a rating within 72 hours after job completion. In such cases, the system assigns a 3.5-star rating to prevent workers from being unfairly penalized due to missing rating and feedback.
- Domestic Helper: An individual employed to perform household-related tasks and services within a residence. In this study, it refers to a registered platform user who offers services such as cleaning, cooking, laundry, childcare, and other home-based tasks to households in Tayabas City.
- Household: A group of individuals living together in a residence. In this study, it refers to a registered user representing a family or individual residing in Tayabas City who can post job requests and hire domestic helpers or skilled workers through the system.
- Job Posting: An announcement or listing of available work opportunities. In this study, it refers to a job listing created by a household on the platform specifying the type of service needed, required skills, schedule, job dates, location, geographic search radius, and offered service rate.
- Reputation Scoring System: A method used to evaluate credibility or performance based on ratings and feedback. In this study, it refers to the platform feature that allows households to rate workers after job completion and enables both parties to provide feedback, which is aggregated into an average rating, a reputation tier (New, Established, Trusted, or Elite), and a rating trend, then displayed on worker profiles to promote trust and accountability.
- Skilled Worker: An individual who possesses specialized knowledge or technical expertise in a particular field. In this study, it refers to a registered user of the platform who provides technical services such as electrical work, plumbing, carpentry, or other repair services to households in Tayabas City.
