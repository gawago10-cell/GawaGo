# Jobs and Matching (spec I)

Part of the GawaGo spec; [AGENTS.md](../../AGENTS.md) has the rules most changes need and the section index.

## I. Employment Matching and Job Allocation

### A. Job Posting and Application
- Households can post job requests including:
  - Job type
  - Schedule, plus an optional job start date, end date, and estimated number of working days. Both sides see them the same way on My Jobs and the household dashboard: a Start and an End with the day of the week ("Fri, Oct 30, 2026"), worded Starts/Started and Ends/Ended, and the working days under them; a one-day job with no end date ends the day it starts (panel review, 2026-10-31)
  - Location
  - Service rate
  - A geographic search radius for matching (`1 km`, `2 km`, `5 km`, `10 km`, or `unlimited`; defaults to `1 km`)
- Workers can apply to available jobs based on:
  - Skills (a worker may list at most 3 skills on their profile)
  - Availability
- Households can review applicant profiles before confirming a worker.
- Application status is shown as a stage the backend owns (`apps/jobs/statuses.py`, sent as `status_stage`/`status_label`), so web and mobile always use the same words: `Pending` (applied, awaiting a decision), `Awaiting worker response` (the household invited a worker who has not answered), `In progress` (hired), `Completed` (the household marked the hired worker's job done), `Rejected`, `Closed` (the job filled or finished without this applicant), and `Cancelled` (the job was cancelled). A worker who applied is hired as soon as the household accepts; only an invited worker has to confirm first. Only the household marks a job done: once a worker is hired the household gets "Mark as done" (the backend's `can_mark_done`, with `mark_done_note` saying why when it isn't available yet), the job becomes `Completed`, and only the hired worker's application follows it to `Completed`, with the worker notified. Workers do not mark jobs done (panel review, 2026-10-31); the old worker request endpoint now refuses with a message, and a job left `Awaiting confirmation` by that older flow can still be marked done by its household. Marking done is not allowed before the job's start date or by an unverified household, so a review always follows work that could have happened; anyone still pending reads `Closed`. Cancelling a job likewise closes every application still undecided.

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
- Push delivery: when a household posts a new open job, the system scores it against every candidate worker in the background and sends a job-match notification to any worker scoring above a configurable threshold (`JOB_MATCH_NOTIFY_THRESHOLD`), or with an exact skill match, instead of waiting for the worker to check manually. The job-create request only saves the job; see "Background tasks" under Implementation Notes for how the pass runs.
- Household delivery: the same content-based score also runs in the opposite direction, ranking *workers for a job*. Immediately after a household posts a job they land on a recommended-workers screen showing each candidate's `% match` and the same skill-versus-proximity breakdown a worker sees. This does not replace Smart Matching: the job detail screen still lists candidates in Smart Matching's rule order (which prioritises verification), and both scores are returned on every result so the two remain complementary rather than competing.
- Explainability: each recommendation also reports how much of the score came from skill fit versus proximity (and whether the match was an exact skill match, not just a related one), shown to the worker as a breakdown (for example, "70% skill fit, 30% proximity") rather than a single opaque number.
- Future enhancement: once enough completed-job/hire outcome data exists, this can be extended with a collaborative-filtering signal ("workers with similar hire histories were chosen for jobs like this") layered on top of the content-based score. That requires a worker-job interaction dataset that does not yet exist, so it is out of scope for now.
