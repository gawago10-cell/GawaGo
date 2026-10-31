# Trust and Reputation (spec II)

Part of the GawaGo spec; [AGENTS.md](../../AGENTS.md) has the rules most changes need and the section index.

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
  - Individually listed skills with a proficiency level (beginner, intermediate, expert) and an aggregated household rating per skill. These are the same skills as the worker's (at most 3) profile skills that matching reads: adding, removing or renaming a portfolio skill changes the profile list, and saving profile skills gives each one a portfolio entry (with no proficiency until the worker sets one). A skill that has household ratings is unlisted rather than deleted when removed, so its rating history returns if it is listed again. Ratings belong to the skill they were given for: renaming a rated skill lists the new name as a fresh skill and leaves the ratings on the old one.
  - Certifications and credentials (TESDA certificate, professional license, credential, certification, or other), each uploaded with supporting files and subject to admin approval before showing a verified badge.
  - Work-sample images, including optional before/after pairs.
  - Employment history: completed jobs with the hiring household, location, and the skill ratings received.
- Identity verification supports multiple government ID types (national ID, passport, driver's license, voter ID, TIN, UMID, postal ID, or other); administrators review and approve or reject each submission. Households and workers share one Verification Queue, which admins filter with All / Households / Workers tabs (each with its count) on web and mobile.

### D. Dispute Resolution
- Households and workers can file a complaint tied to a specific job, at any job status (payment issue, quality of work, no-show, safety concern, inappropriate behavior, or other) &mdash; a live safety concern does not have to wait for the job to finish. The screens call these complaints throughout ("File a Complaint", "My Complaints", the superadmin "Complaints" queue; panel review, 2026-10-31). A household names which of the job's applicants the complaint is about; a worker's complaint always targets that job's household. Every complaint is traceable to a specific job/household/worker relationship the filer actually has, rather than an unverifiable free-floating accusation.
- A complaint may carry up to five photos as evidence, so an administrator can see what happened rather than judging from the written description alone.
- Superadmins track each complaint through `Submitted` &rarr; `Under Review` &rarr; `Resolved`/`Closed`, with resolution notes visible to the filer. Status only moves forward, a complaint must be under review before it is resolved or closed, and resolving or closing requires a resolution the filer can read; superadmins may also keep staff notes the filer never sees. Complaint review and account suspension are reserved to superadmin accounts; regular admin accounts (created from Admin Management) handle identity and credential verification and cannot open the complaints queue. The person named is not notified that a complaint exists &mdash; only the filer is notified when its status changes, keeping the case confidential while under review.
- Superadmins can export the complaints queue as CSV (`GET /api/complaints/admin/?export=csv`, same status filter as the screen) to keep on record. It carries each complaint's type, status, both parties, job, description and resolution, but not the internal staff notes.
- Having reviewed a report, a superadmin can act on the account it names: a timed suspension of 3 or 7 days that lifts itself automatically, or an indefinite block. Either is reversible, applies equally to a worker or a household, cannot be used against an administrator, and takes effect immediately on any session already signed in. The suspended user is notified with the superadmin's stated reason (a suspension without one is refused) and, for a timed suspension, the date it ends.
