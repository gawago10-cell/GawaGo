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
  - Skills (a worker may list at most 4 skills on their profile)
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
- Households and workers can file a complaint after a job (payment issue, quality of work, no-show, safety concern, inappropriate behavior, or other).
- Administrators track each complaint through `Submitted` &rarr; `Under Review` &rarr; `Resolved`/`Closed`, with resolution notes visible to the filer.

## III. Communication and Notification System

### A. Notification and Alerts
- In-system notifications, each mirrored by an automated email, cover: job application submitted, application hired, application rejected, job completion, rating/review submitted, verification status change, review reminders, account activity, and admin alerts.
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

## V. Scope and Limitations

- Worker types: registered workers fall into two categories — domestic helpers (cleaning, cooking, laundry, childcare, elder care, and similar home-based tasks) and skilled workers (electrical, plumbing, carpentry, painting, aircon repair, welding, and similar trade services). A worker profile lists at most 4 skills to keep listings scannable and matching meaningful.
- Geographic area: the platform targets households and workers within Tayabas City and its barangays; job locations and worker registrations are expected to fall within this area, and the smart matching distance boundary (1-10 km, or unlimited) is calibrated for a single-city service area rather than nationwide reach.
- Matching approach: smart matching is a deterministic, rule-based ranking (skill match, verification, road-route distance, rating, and rate) rather than a machine-learning model. An AI-based matching model that learns from historical hiring outcomes has been identified as a future enhancement once enough completed-job data has accumulated to train and validate one.
- Proximity range justification: domestic and skilled-trade work in this study is assumed to be commuted to on foot, by bicycle, or by short tricycle/jeepney rides rather than long-distance travel, so a 1 km default radius (configurable up to unlimited per job) keeps recommended workers realistically reachable for same-day or recurring work.

## Implementation Notes

- Platform type: centralized web-based and mobile application system.
- UX requirement: responsive on desktop and mobile.
- Matching assistance is advisory; user autonomy in final selection must remain intact.
- Trust mechanisms (verification + reviews + pricing disclosure) are core, not optional.

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
