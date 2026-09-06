# GawaGo - Product Objectives and Functional Scope

## App Name
`GawaGo`

## Mission
Build a centralized, responsive web and mobile application platform that helps households and workers connect, manage job opportunities, and complete services with trust, transparency, and clear communication.

## I. Employment Matching and Job Allocation

### A. Job Posting and Application
- Households can post job requests including:
  - Job type
  - Schedule
  - Location
  - Service rate
- Workers can apply to available jobs based on:
  - Skills
  - Availability
- Households can review applicant profiles before confirming a worker.

### B. Smart Matching with Distance Indicator
- System ranks and suggests workers using:
  - Skill matching: workers with matching skills appear first.
  - Availability check: only workers available at requested date/time are shown.
  - Verification status: verified workers are prioritized.
  - Distance calculation: show straight-line distance from worker registered location to job site (for example, `2 km away`).
- Households retain final hiring choice regardless of ranking (can still choose based on price, ratings, experience, or preference).

## II. Reputation and Trust Management System

### A. Reputation Scoring and Reviews
- Households can rate workers after completed jobs.
- Workers can rate households to support fairness on both sides.
- System sends reminders to submit feedback after job completion.
- Neutral no-feedback policy:
  - If no household rating is submitted within 48 to 72 hours, system assigns default 4-star rating to the worker.
- New users display `No ratings yet` instead of `0` or empty numeric score.

### B. Price Transparency
- Workers must disclose service rates on profiles (hourly and/or daily).
- Households must see agreed rates before worker confirmation.

## III. Communication and Notification System

### A. Notification and Alerts
- Email notifications for:
  - Job status updates
  - Account activity updates
  - Longer or detailed messages
- In-system notifications for real-time updates when applications are:
  - Accepted
  - Rejected
  - Completed

## IV. Employment Analytics and Monitoring

### A. Dashboard and Reports
- Employment activity dashboard with real-time counts of:
  - Total job postings
  - Active applications
  - Completed services
  - Cancelled requests
  - Ongoing matches
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
## Implementation Notes
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
- Distance Indicator: A measurement that shows the geographic distance between two locations. In this study, it refers to the system feature that displays the approximate straight-line distance between a worker's registered location and the household's job site to help households assess worker proximity.
- Employment Analytics Dashboard: A digital interface that visually presents employment-related data and statistics. In this study, it refers to the administrative dashboard that displays information such as job activity, verified users, geographic service distribution across barangays, and service rate summaries to support monitoring and decision-making.
- Smart Matching: An automated process that recommends or pairs users based on predefined criteria. In this study, it refers to the system feature that suggests suitable workers to households based on factors such as skills, availability, verification status, and geographic proximity to the job location.
- Verification: The process of confirming the authenticity or validity of a person's identity or credentials. In this study, it refers to the administrative procedure where system administrators review and approve worker identification documents, allowing verified workers to receive a verification badge and higher priority in smart matching results.
- Web-Based Employment System: A software application that can be accessed through a web browser using an internet connection. In this study, it refers to the proposed platform that allows households, domestic helpers, and skilled workers in Tayabas City to interact, post jobs, apply for work, and manage employment activities online.

### Non-Technical Terms
- Default Rating: A system-assigned rating automatically given when a household does not submit a rating within 48 to 72 hours after job completion. In such cases, the system assigns a 3.5-star rating to prevent workers from being unfairly penalized due to missing rating and feedback.
- Domestic Helper: An individual employed to perform household-related tasks and services within a residence. In this study, it refers to a registered platform user who offers services such as cleaning, cooking, laundry, childcare, and other home-based tasks to households in Tayabas City.
- Household: A group of individuals living together in a residence. In this study, it refers to a registered user representing a family or individual residing in Tayabas City who can post job requests and hire domestic helpers or skilled workers through the system.
- Job Posting: An announcement or listing of available work opportunities. In this study, it refers to a job listing created by a household on the platform specifying the type of service needed, required skills, schedule, location, and offered service rate.
- Reputation Scoring System: A method used to evaluate credibility or performance based on ratings and feedback. In this study, it refers to the platform feature that allows households to rate workers after job completion and enables both parties to provide feedback, which is then aggregated and displayed on worker profiles to promote trust and accountability.
- Skilled Worker: An individual who possesses specialized knowledge or technical expertise in a particular field. In this study, it refers to a registered user of the platform who provides technical services such as electrical work, plumbing, carpentry, or other repair services to households in Tayabas City.
