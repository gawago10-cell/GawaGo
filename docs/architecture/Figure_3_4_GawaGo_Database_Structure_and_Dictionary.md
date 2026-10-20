# GawaGo Database Structure and Dictionary

This section presents the full database structure and dictionary of the GawaGo Employment Platform. The structure follows the current Django backend implementation and includes both Django framework tables and GawaGo application tables — 28 in total: 8 Django framework tables and 20 GawaGo application tables.

Last reconciled against the Django models on 2026-09-16.

## Table 1: `django_content_type`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | INTEGER | 1 | NULL | 1 |
| 1 | app_label | VARCHAR(100) | 1 | NULL | 0 |
| 2 | model | VARCHAR(100) | 1 | NULL | 0 |

This table stores Django model metadata used by the permission and admin systems.

## Table 2: `auth_permission`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | INTEGER | 1 | NULL | 1 |
| 1 | name | VARCHAR(255) | 1 | NULL | 0 |
| 2 | content_type_id | INTEGER | 1 | NULL | 0 |
| 3 | codename | VARCHAR(100) | 1 | NULL | 0 |

This table stores Django permissions. Each permission belongs to one content type.

## Table 3: `auth_group`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | INTEGER | 1 | NULL | 1 |
| 1 | name | VARCHAR(150) | 1 | NULL | 0 |

This table stores Django user groups for permission assignment.

## Table 4: `auth_group_permissions`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | group_id | INTEGER | 1 | NULL | 0 |
| 2 | permission_id | INTEGER | 1 | NULL | 0 |

This table connects groups to permissions and supports many-to-many group permission assignment.

## Table 5: `auth_user`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | INTEGER | 1 | NULL | 1 |
| 1 | password | VARCHAR(128) | 1 | NULL | 0 |
| 2 | last_login | DATETIME | 0 | NULL | 0 |
| 3 | is_superuser | BOOLEAN | 1 | FALSE | 0 |
| 4 | username | VARCHAR(150) | 1 | NULL | 0 |
| 5 | first_name | VARCHAR(150) | 1 | '' | 0 |
| 6 | last_name | VARCHAR(150) | 1 | '' | 0 |
| 7 | email | VARCHAR(254) | 1 | '' | 0 |
| 8 | is_staff | BOOLEAN | 1 | FALSE | 0 |
| 9 | is_active | BOOLEAN | 1 | TRUE | 0 |
| 10 | date_joined | DATETIME | 1 | NULL | 0 |

This table stores the base login and account information for registered users. Household and worker-specific details are stored in `accounts_userprofile`.

## Table 6: `auth_user_groups`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | user_id | INTEGER | 1 | NULL | 0 |
| 2 | group_id | INTEGER | 1 | NULL | 0 |

This table connects users to groups and supports many-to-many user group membership.

## Table 7: `auth_user_user_permissions`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | user_id | INTEGER | 1 | NULL | 0 |
| 2 | permission_id | INTEGER | 1 | NULL | 0 |

This table connects users directly to permissions and supports many-to-many user permission assignment.

## Table 8: `django_admin_log`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | INTEGER | 1 | NULL | 1 |
| 1 | action_time | DATETIME | 1 | NULL | 0 |
| 2 | object_id | TEXT | 0 | NULL | 0 |
| 3 | object_repr | VARCHAR(200) | 1 | NULL | 0 |
| 4 | action_flag | SMALLINT UNSIGNED | 1 | NULL | 0 |
| 5 | change_message | TEXT | 1 | NULL | 0 |
| 6 | content_type_id | INTEGER | 0 | NULL | 0 |
| 7 | user_id | INTEGER | 1 | NULL | 0 |

This table stores Django admin activity logs, including the admin user, affected object, action type, and change message.

## Table 9: `accounts_userprofile`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | user_id | INTEGER | 1 | NULL | 0 |
| 2 | role | VARCHAR(20) | 1 | worker | 0 |
| 3 | phone | VARCHAR(30) | 1 | '' | 0 |
| 4 | bio | TEXT | 1 | '' | 0 |
| 5 | years_experience | INTEGER UNSIGNED | 1 | 0 | 0 |
| 6 | skills | JSON | 1 | [] | 0 |
| 7 | hourly_rate | DECIMAL(10,2) | 0 | NULL | 0 |
| 8 | daily_rate | DECIMAL(10,2) | 0 | NULL | 0 |
| 9 | verification_status | VARCHAR(20) | 1 | pending | 0 |
| 10 | primary_id_type | VARCHAR(50) | 1 | national_id | 0 |
| 11 | location_label | VARCHAR(255) | 1 | '' | 0 |
| 12 | latitude | DECIMAL(10,7) | 0 | NULL | 0 |
| 13 | longitude | DECIMAL(10,7) | 0 | NULL | 0 |
| 14 | profile_photo | VARCHAR(100) | 0 | NULL | 0 |
| 15 | average_rating | DECIMAL(3,2) | 0 | NULL | 0 |
| 16 | rating_count | INTEGER UNSIGNED | 1 | 0 | 0 |
| 17 | reputation_tier | VARCHAR(20) | 1 | new | 0 |
| 18 | rating_trend | VARCHAR(20) | 1 | neutral | 0 |
| 19 | credentials_updated_at | DATETIME | 0 | NULL | 0 |
| 20 | is_blocked | BOOL | 1 | 0 | 0 |
| 21 | blocked_at | DATETIME | 0 | NULL | 0 |
| 22 | blocked_reason | TEXT | 1 | '' | 0 |
| 23 | blocked_until | DATETIME | 0 | NULL | 0 |

This table stores profile information for household and worker users. It includes skills (capped at 4 per worker), service rates, verification status, the worker's chosen government ID type, location coordinates, profile image, and rating/reputation summary. `reputation_tier` (`new`/`established`/`trusted`/`elite`) and `rating_trend` (`improving`/`declining`/`neutral`) are recalculated after every new review.

**Account security and suspension.** `credentials_updated_at` is bumped whenever the user's credentials change (for example a password reset), so every JWT issued before that moment — each token carries an `iat` claim — is rejected at once without needing a per-token blacklist entry.

Suspension deliberately uses `is_blocked` rather than `auth_user.is_active`: login reactivates any inactive account that supplies the correct password (kept for legacy accounts), which would silently undo every block. `blocked_until` distinguishes the two kinds of suspension — `NULL` while blocked means a permanent block, while a future datetime is a timed suspension (3 or 7 days from the admin queue) that lifts itself. The expiry is applied lazily on the next login, authenticated request, or admin read, so no scheduled job is required. A block is enforced per-request in `JWTAuthentication`, so it takes effect immediately on sessions that are already signed in.

## Table 10: `accounts_workeravailability`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | worker_id | INTEGER | 1 | NULL | 0 |
| 2 | date | DATE | 1 | NULL | 0 |
| 3 | start_time | TIME | 1 | NULL | 0 |
| 4 | end_time | TIME | 1 | NULL | 0 |
| 5 | is_available | BOOLEAN | 1 | TRUE | 0 |

This table stores date-specific availability windows for workers.

## Table 11: `accounts_passwordresetrequest`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | user_id | INTEGER | 1 | NULL | 0 |
| 2 | email | VARCHAR(254) | 1 | NULL | 0 |
| 3 | token_hash | VARCHAR(128) | 1 | NULL | 0 |
| 4 | created_at | DATETIME | 1 | NULL | 0 |
| 5 | expires_at | DATETIME | 1 | NULL | 0 |
| 6 | used_at | DATETIME | 0 | NULL | 0 |
| 7 | attempts | INTEGER UNSIGNED | 1 | 0 | 0 |

This table stores secure password reset requests.

## Table 12: `accounts_signupverificationrequest`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | user_id | INTEGER | 1 | NULL | 0 |
| 2 | email | VARCHAR(254) | 1 | NULL | 0 |
| 3 | token_hash | VARCHAR(128) | 1 | NULL | 0 |
| 4 | created_at | DATETIME | 1 | NULL | 0 |
| 5 | expires_at | DATETIME | 1 | NULL | 0 |
| 6 | verified_at | DATETIME | 0 | NULL | 0 |

This table stores email verification requests created during registration.

## Table 13: `accounts_workerportfolio`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | worker_id | INTEGER | 1 | NULL | 0 |
| 2 | bio | TEXT | 1 | '' | 0 |
| 3 | years_experience | INTEGER UNSIGNED | 1 | 0 | 0 |
| 4 | created_at | DATETIME | 1 | NULL | 0 |
| 5 | updated_at | DATETIME | 1 | NULL | 0 |

This table stores the one-to-one worker portfolio record shown on a worker's public profile (bio and years of experience). Skills, certifications, and work samples are stored in the related tables below.

## Table 14: `accounts_workerskill`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | worker_id | INTEGER | 1 | NULL | 0 |
| 2 | skill_name | VARCHAR(120) | 1 | NULL | 0 |
| 3 | proficiency | VARCHAR(20) | 1 | beginner | 0 |
| 4 | average_rating | DECIMAL(3,2) | 0 | NULL | 0 |
| 5 | rating_count | INTEGER UNSIGNED | 1 | 0 | 0 |
| 6 | created_at | DATETIME | 1 | NULL | 0 |
| 7 | updated_at | DATETIME | 1 | NULL | 0 |

This table stores individually-listed portfolio skills (beginner/intermediate/expert) with a per-skill rating aggregated from household feedback. This is distinct from the short skill list on `accounts_userprofile` used for job matching.

## Table 15: `accounts_workercertification`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | worker_id | INTEGER | 1 | NULL | 0 |
| 2 | certificate_type | VARCHAR(50) | 1 | certification | 0 |
| 3 | certificate_name | VARCHAR(255) | 1 | NULL | 0 |
| 4 | issuer | VARCHAR(255) | 1 | '' | 0 |
| 5 | issue_date | DATE | 0 | NULL | 0 |
| 6 | expiry_date | DATE | 0 | NULL | 0 |
| 7 | certificate_file | VARCHAR(100) | 0 | NULL | 0 |
| 8 | is_verified | BOOLEAN | 1 | FALSE | 0 |
| 9 | verification_status | VARCHAR(20) | 1 | pending | 0 |
| 10 | verified_by_id | INTEGER | 0 | NULL | 0 |
| 11 | verification_notes | TEXT | 1 | '' | 0 |
| 12 | verified_at | DATETIME | 0 | NULL | 0 |
| 13 | created_at | DATETIME | 1 | NULL | 0 |
| 14 | updated_at | DATETIME | 1 | NULL | 0 |

This table stores uploaded worker credentials (TESDA certificate, professional license, credential, certification, or other) and the admin approval workflow (`verification_status`, reviewing admin, notes, timestamp) used to grant the verified badge.

## Table 16: `accounts_workerportfolioitem`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | worker_id | INTEGER | 1 | NULL | 0 |
| 2 | title | VARCHAR(255) | 1 | '' | 0 |
| 3 | description | TEXT | 1 | '' | 0 |
| 4 | image | VARCHAR(100) | 1 | NULL | 0 |
| 5 | before_image | VARCHAR(100) | 0 | NULL | 0 |
| 6 | after_image | VARCHAR(100) | 0 | NULL | 0 |
| 7 | created_at | DATETIME | 1 | NULL | 0 |

This table stores work-sample images on a worker's portfolio, including optional before/after image pairs.

## Table 17: `accounts_skillrating`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | job_id | BIGINT | 1 | NULL | 0 |
| 2 | household_id | INTEGER | 1 | NULL | 0 |
| 3 | worker_id | INTEGER | 1 | NULL | 0 |
| 4 | skill_id | BIGINT | 1 | NULL | 0 |
| 5 | rating | DECIMAL(2,1) | 1 | NULL | 0 |
| 6 | feedback | TEXT | 1 | '' | 0 |
| 7 | created_at | DATETIME | 1 | NULL | 0 |

This table stores a household's per-skill rating of a worker for one completed job, feeding the average rating shown on each `accounts_workerskill` entry. `rating` is constrained to 1-5 by `SkillRatingSerializer`; because the value is averaged into `accounts_workerskill.average_rating`, an out-of-range score would permanently skew the worker's displayed standing. The rated `skill` is also checked against the job, so a household cannot attach a rating to a worker who never worked it.

## Table 18: `accounts_verificationdocument`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | user_id | INTEGER | 1 | NULL | 0 |
| 2 | id_type | VARCHAR(50) | 1 | national_id | 0 |
| 3 | id_number | VARCHAR(255) | 1 | '' | 0 |
| 4 | document_file | VARCHAR(100) | 1 | NULL | 0 |
| 5 | is_primary | BOOLEAN | 1 | TRUE | 0 |
| 6 | verification_status | VARCHAR(20) | 1 | pending | 0 |
| 7 | verified_by_id | INTEGER | 0 | NULL | 0 |
| 8 | verification_notes | TEXT | 1 | '' | 0 |
| 9 | verified_at | DATETIME | 0 | NULL | 0 |
| 10 | created_at | DATETIME | 1 | NULL | 0 |
| 11 | updated_at | DATETIME | 1 | NULL | 0 |

This table stores multiple-ID-type identity documents (national ID, passport, driver's license, voter ID, TIN, UMID, postal ID, or other) submitted by any user, with the same admin approval workflow as certifications. It supersedes the older single-document `common_verificationrequest` table below, which is retained for existing records.

## Table 19: `jobs_jobposting`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | household_id | INTEGER | 1 | NULL | 0 |
| 2 | title | VARCHAR(255) | 1 | NULL | 0 |
| 3 | job_type | VARCHAR(120) | 1 | NULL | 0 |
| 4 | required_skill | VARCHAR(120) | 1 | NULL | 0 |
| 5 | schedule | VARCHAR(255) | 1 | NULL | 0 |
| 6 | schedule_type | VARCHAR(80) | 1 | '' | 0 |
| 7 | description | TEXT | 1 | '' | 0 |
| 8 | location_label | VARCHAR(255) | 1 | NULL | 0 |
| 9 | latitude | DECIMAL(10,7) | 1 | NULL | 0 |
| 10 | longitude | DECIMAL(10,7) | 1 | NULL | 0 |
| 11 | service_rate | DECIMAL(10,2) | 1 | NULL | 0 |
| 12 | worker_slots | INTEGER UNSIGNED | 1 | 1 | 0 |
| 13 | status | VARCHAR(20) | 1 | open | 0 |
| 14 | job_start_date | DATE | 0 | NULL | 0 |
| 15 | job_end_date | DATE | 0 | NULL | 0 |
| 16 | estimated_working_days | INTEGER | 0 | NULL | 0 |
| 17 | max_distance_km | FLOAT | 1 | 1.0 | 0 |
| 18 | geographic_boundary | VARCHAR(20) | 1 | 1km | 0 |
| 19 | created_at | DATETIME | 1 | NULL | 0 |
| 20 | completed_at | DATETIME | 0 | NULL | 0 |

This table stores job postings created by household users, including the job schedule window (`job_start_date`/`job_end_date`/`estimated_working_days`) and the geographic search radius applied as a hard distance filter during worker matching (`max_distance_km`, with a `geographic_boundary` label of `1km`/`2km`/`5km`/`10km`/`unlimited`).

Values accepted on create are bounded by `JobCreateSerializer`: `service_rate` must be at least 0, `estimated_working_days` at least 1, `max_distance_km` at least 0.1, and `job_end_date` must fall after `job_start_date`.

## Table 20: `jobs_jobimage`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | job_id | BIGINT | 1 | NULL | 0 |
| 2 | image | VARCHAR(100) | 1 | NULL | 0 |
| 3 | uploaded_at | DATETIME | 1 | NULL | 0 |
| 4 | order | INTEGER UNSIGNED | 1 | 0 | 0 |

This table stores images attached to job postings.

## Table 21: `jobs_jobapplication`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | job_id | BIGINT | 1 | NULL | 0 |
| 2 | worker_id | INTEGER | 1 | NULL | 0 |
| 3 | status | VARCHAR(20) | 1 | pending | 0 |
| 4 | applied_at | DATETIME | 1 | NULL | 0 |
| 5 | updated_at | DATETIME | 1 | NULL | 0 |
| 6 | note | TEXT | 1 | '' | 0 |

This table stores worker applications to job postings. `status` uses the terms `pending`, `hired`, `rejected`, and `completed` (a separate job-completion marker, distinct from the household's hire/reject decision) to avoid the earlier ambiguity between an application still awaiting a decision and a job that has finished.

## Table 22: `reviews_review`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | author_id | INTEGER | 1 | NULL | 0 |
| 2 | target_id | INTEGER | 1 | NULL | 0 |
| 3 | author_role | VARCHAR(20) | 1 | NULL | 0 |
| 4 | target_role | VARCHAR(20) | 1 | NULL | 0 |
| 5 | job_id | BIGINT | 0 | NULL | 0 |
| 6 | job_title | VARCHAR(255) | 1 | '' | 0 |
| 7 | rating | DECIMAL(2,1) | 0 | NULL | 0 |
| 8 | quality_of_work | INTEGER | 0 | NULL | 0 |
| 9 | punctuality | INTEGER | 0 | NULL | 0 |
| 10 | communication | INTEGER | 0 | NULL | 0 |
| 11 | professionalism | INTEGER | 0 | NULL | 0 |
| 12 | feedback | TEXT | 1 | '' | 0 |
| 13 | created_at | DATETIME | 1 | NULL | 0 |

This table stores post-completion reviews and feedback. `rating` is the single overall score; the four 1-5 metric columns (`quality_of_work`, `punctuality`, `communication`, `professionalism`) are optional e-commerce-style ratings whose average becomes the review's overall rating when they are provided. A review may only be submitted after the related job has reached `completed` status and the reviewer's application/hire relationship for that job has also completed.

## Table 23: `notifications_notification`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | recipient_id | INTEGER | 1 | NULL | 0 |
| 2 | actor_id | INTEGER | 0 | NULL | 0 |
| 3 | notification_type | VARCHAR(30) | 1 | NULL | 0 |
| 4 | title | VARCHAR(255) | 1 | NULL | 0 |
| 5 | message | TEXT | 1 | NULL | 0 |
| 6 | related_job_id | INTEGER UNSIGNED | 0 | NULL | 0 |
| 7 | related_application_id | INTEGER UNSIGNED | 0 | NULL | 0 |
| 8 | action_type | VARCHAR(40) | 1 | '' | 0 |
| 9 | action_url | VARCHAR(255) | 1 | '' | 0 |
| 10 | requires_action | BOOLEAN | 1 | FALSE | 0 |
| 11 | is_read | BOOLEAN | 1 | FALSE | 0 |
| 12 | created_at | DATETIME | 1 | NULL | 0 |

This table stores in-system notifications, including recipient, optional actor, action context, read status, and creation date. `notification_type` covers ten types: application, acceptance, rejection, hiring, completion, verification, review reminder, account activity, analytics/admin alerts, and job match (AI-based job recommendation notifications, see `AGENTS.md` I.C). The first nine are each mirrored by an automated email; job match notifications are in-system only.

## Table 24: `common_verificationrequest`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | worker_id | INTEGER | 1 | NULL | 0 |
| 2 | primary_id_name | VARCHAR(255) | 1 | NULL | 0 |
| 3 | secondary_doc_name | VARCHAR(255) | 1 | NULL | 0 |
| 4 | primary_id_file | VARCHAR(100) | 0 | NULL | 0 |
| 5 | secondary_doc_file | VARCHAR(100) | 0 | NULL | 0 |
| 6 | notes | TEXT | 1 | '' | 0 |
| 7 | status | VARCHAR(20) | 1 | pending | 0 |
| 8 | submitted_at | DATETIME | 1 | NULL | 0 |
| 9 | reviewed_at | DATETIME | 0 | NULL | 0 |
| 10 | review_note | TEXT | 1 | '' | 0 |

This table stores the original two-document worker verification submissions and administrator review information, kept for backward compatibility alongside the newer multi-document `accounts_verificationdocument` table.

## Table 25: `complaints_complaint`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | complainant_id | INTEGER | 1 | NULL | 0 |
| 2 | respondent_id | INTEGER | 0 | NULL | 0 |
| 3 | job_id | BIGINT | 0 | NULL | 0 |
| 4 | complaint_type | VARCHAR(50) | 1 | NULL | 0 |
| 5 | description | TEXT | 1 | NULL | 0 |
| 6 | status | VARCHAR(20) | 1 | submitted | 0 |
| 7 | resolution | TEXT | 0 | NULL | 0 |
| 8 | admin_notes | TEXT | 0 | NULL | 0 |
| 9 | created_at | DATETIME | 1 | NULL | 0 |
| 10 | updated_at | DATETIME | 1 | NULL | 0 |

This table stores dispute/issue reports filed by a household or worker (`complaint_type`: payment issue, quality of work, no show, safety concern, inappropriate behavior, or other) and the admin resolution workflow (`status`: submitted, under review, resolved, closed).

## Table 26: `matching_routedistancecache`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | job_id | BIGINT | 1 | NULL | 0 |
| 2 | worker_profile_id | BIGINT | 1 | NULL | 0 |
| 3 | job_latitude | DECIMAL(10,7) | 1 | NULL | 0 |
| 4 | job_longitude | DECIMAL(10,7) | 1 | NULL | 0 |
| 5 | worker_latitude | DECIMAL(10,7) | 1 | NULL | 0 |
| 6 | worker_longitude | DECIMAL(10,7) | 1 | NULL | 0 |
| 7 | distance_km | DECIMAL(10,3) | 1 | NULL | 0 |
| 8 | route_points | JSON | 1 | [] | 0 |
| 9 | created_at | DATETIME | 1 | NULL | 0 |
| 10 | updated_at | DATETIME | 1 | NULL | 0 |

This table stores cached road-route distance results (fetched from the OSRM routing service) between job locations and worker profile locations, keyed by job and worker coordinates so repeated matching requests avoid re-fetching the route.

Because each cache miss costs a synchronous outbound HTTP request, collection endpoints (the job list and the application list) read this cache only and never fetch live — an uncached pair simply reports no distance. Detail responses, where the set is bounded and the distance is the point of the screen, still resolve live and populate the cache.

## Table 27: `complaints_complaintevidence`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | complaint_id | BIGINT | 1 | NULL | 0 |
| 2 | image | VARCHAR(100) | 1 | NULL | 0 |
| 3 | uploaded_at | DATETIME | 1 | NULL | 0 |
| 4 | order | INTEGER UNSIGNED | 1 | 0 | 0 |

This table stores photo evidence attached to a report, so an admin can see what happened instead of judging from the description alone. A report accepts at most 5 photos, extension-validated the same way job images are. Rows are ordered by `order` then `uploaded_at`.

## Table 28: `common_revokedtoken`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | jti | VARCHAR(64) | 1 | NULL | 0 |
| 2 | user_id | INTEGER | 1 | NULL | 0 |
| 3 | expires_at | DATETIME | 1 | NULL | 0 |
| 4 | revoked_at | DATETIME | 1 | NULL | 0 |

This table blacklists a JWT before its natural expiry — on logout, for example. `jti` is the token's unique id claim and is indexed and unique. Rows only matter until `expires_at` (which mirrors the token's own `exp`), since after that the token is rejected on expiry alone; stale rows are opportunistically deleted whenever a new one is inserted.

Note that this is per-token revocation. Invalidating *every* token for a user at once — after a password change — is handled instead by `accounts_userprofile.credentials_updated_at`, which needs no rows here.

## Relationship Summary

| Relationship | Cardinality | Description |
|---|---|---|
| `django_content_type` to `auth_permission` | 1:N | One content type can have many permissions. |
| `auth_permission` to `auth_group_permissions` | 1:N | One permission can be assigned to many group-permission records. |
| `auth_group` to `auth_group_permissions` | 1:N | One group can have many permission assignments. |
| `auth_user` to `auth_user_groups` | 1:N | One user can have many group membership records. |
| `auth_group` to `auth_user_groups` | 1:N | One group can contain many user membership records. |
| `auth_user` to `auth_user_user_permissions` | 1:N | One user can have many direct permission assignments. |
| `auth_permission` to `auth_user_user_permissions` | 1:N | One permission can be assigned directly to many users. |
| `django_content_type` to `django_admin_log` | 1:N | One content type can appear in many admin log records. |
| `auth_user` to `django_admin_log` | 1:N | One admin user can create many admin log records. |
| `auth_user` to `accounts_userprofile` | 1:1 | Each user account has one household or worker profile. |
| `auth_user` to `accounts_workeravailability` | 1:N | One worker can create many date-specific availability windows. |
| `auth_user` to `accounts_passwordresetrequest` | 1:N | One user can have many password reset requests. |
| `auth_user` to `accounts_signupverificationrequest` | 1:1 | Each user can have one signup verification request record. |
| `auth_user` to `accounts_workerportfolio` | 1:1 | Each worker has one portfolio record. |
| `auth_user` to `accounts_workerskill` | 1:N | One worker can list many portfolio skills. |
| `auth_user` to `accounts_workercertification` | 1:N | One worker can upload many certifications. |
| `auth_user` to `accounts_workerportfolioitem` | 1:N | One worker can add many work-sample items. |
| `jobs_jobposting` to `accounts_skillrating` | 1:N | One completed job can produce many per-skill ratings. |
| `accounts_workerskill` to `accounts_skillrating` | 1:N | One portfolio skill can receive many household ratings. |
| `auth_user` to `accounts_verificationdocument` | 1:N | One user can submit many identity documents. |
| `auth_user` to `jobs_jobposting` | 1:N | One household can create many job postings. |
| `jobs_jobposting` to `jobs_jobimage` | 1:N | One job posting can have many uploaded images. |
| `jobs_jobposting` to `jobs_jobapplication` | 1:N | One job posting can receive many worker applications. |
| `auth_user` to `jobs_jobapplication` | 1:N | One worker can submit many job applications. |
| `auth_user` to `reviews_review` | 1:N | One user can write and receive many reviews through author and target relationships. |
| `jobs_jobposting` to `reviews_review` | 1:N | One completed job can have reviews from both parties. |
| `auth_user` to `notifications_notification` | 1:N | One user can receive many notifications and can also act as the notification actor. |
| `auth_user` to `common_verificationrequest` | 1:N | One worker can submit many legacy verification requests. |
| `auth_user` to `complaints_complaint` | 1:N | One user can file many complaints and be named as respondent in many others. |
| `jobs_jobposting` to `complaints_complaint` | 1:N | One job can have many complaints filed against it. |
| `jobs_jobposting` to `matching_routedistancecache` | 1:N | One job can have cached distance records for many worker profiles. |
| `accounts_userprofile` to `matching_routedistancecache` | 1:N | One worker profile can appear in many cached job distance records. |
| `complaints_complaint` to `complaints_complaintevidence` | 1:N | One report can carry up to five evidence photos. |
| `auth_user` to `common_revokedtoken` | 1:N | One user can have many individually revoked tokens. |
| `auth_user` to `accounts_workercertification` (as verifier) | 1:N | One administrator can approve or reject many certificates; `SET_NULL` preserves review history if that admin account is deleted. |
| `auth_user` to `accounts_verificationdocument` (as verifier) | 1:N | One administrator can review many identity documents, also `SET_NULL`. |
