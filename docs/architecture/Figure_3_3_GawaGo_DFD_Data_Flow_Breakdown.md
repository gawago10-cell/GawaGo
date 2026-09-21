# GawaGo Data Flow Diagram Breakdown

This document supports Figure 3.3, the GawaGo Data Flow Diagram. The diagram is aligned with the current full database schema and uses 20 data stores: 8 Django framework stores and 12 GawaGo application stores.

## External Entities

| External Entity | Description |
|---|---|
| Household | Registers, manages a profile, posts jobs, reviews applicants, confirms hiring, receives notifications, and submits reviews. |
| Worker | Registers, manages a profile and availability, applies to jobs, submits verification documents, receives notifications, and reviews households. |
| System Administrator | Reviews verification requests, monitors platform activity, and views analytics reports. |
| Email Service | Sends email notifications for account activity, password reset, verification, and job-related updates. |

## Processes

| Process | Name | Description |
|---|---|---|
| 1.0 | User Registration and Authentication | Handles account registration, login, signup verification, password reset, and user permission/authentication support. |
| 2.0 | Profile, Availability, and Verification Setup | Stores household/worker profile data, date-specific worker availability, and verification submissions. |
| 3.0 | Job Posting Management | Allows households to create and manage job postings and job images. |
| 4.0 | Worker Application Management | Allows workers to browse jobs and submit applications. |
| 5.0 | Smart Matching and Route Distance | Uses worker profile, availability, job location, and route distance cache data to support worker recommendations. |
| 6.0 | Hiring, Completion, and Job Status | Updates application and job statuses during hiring, completion request, completion, rejection, and closing flows. |
| 7.0 | Reviews and Reputation | Stores household-to-worker and worker-to-household reviews and updates rating summaries. |
| 8.0 | Notification Management | Creates in-system notifications and sends email notification requests. |
| 9.0 | Administration and Analytics | Uses operational data to monitor users, jobs, verification, reviews, rates, locations, and activity metrics. |

## Data Stores

| Store | Table | Description |
|---|---|---|
| D1 | `django_content_type` | Stores Django model metadata for permissions and admin logs. |
| D2 | `auth_permission` | Stores Django permission definitions. |
| D3 | `auth_group` | Stores Django permission groups. |
| D4 | `auth_group_permissions` | Stores group-to-permission assignments. |
| D5 | `auth_user` | Stores base user account, credential, and account status data. |
| D6 | `auth_user_groups` | Stores user-to-group assignments. |
| D7 | `auth_user_user_permissions` | Stores direct user-to-permission assignments. |
| D8 | `django_admin_log` | Stores Django admin action logs. |
| D9 | `accounts_userprofile` | Stores household and worker profile information, rates, skills, location, verification status, and rating summary. |
| D10 | `accounts_workeravailability` | Stores worker date-specific availability windows. |
| D11 | ~~`accounts_workerweeklyavailability`~~ | **Retired.** The table was dropped in accounts migration 0009; worker availability is date-specific only (D10). The identifier is kept so D12+ and the connection list stay stable. |
| D12 | `accounts_passwordresetrequest` | Stores password reset request tokens and status. |
| D13 | `accounts_signupverificationrequest` | Stores signup email verification request tokens and status. |
| D14 | `jobs_jobposting` | Stores household job postings, schedule, location, rate, and status. |
| D15 | `jobs_jobimage` | Stores job posting image attachments. |
| D16 | `jobs_jobapplication` | Stores worker applications and hiring/application status. |
| D17 | `reviews_review` | Stores reviews, ratings, feedback, and related job references. |
| D18 | `notifications_notification` | Stores in-system notifications and action context. |
| D19 | `common_verificationrequest` | Stores worker verification document submissions and admin review results. |
| D20 | `matching_routedistancecache` | Stores cached distance and route information between jobs and worker profiles. |

## Main Data Flows

| Flow | Source | Destination | Data |
|---|---|---|---|
| F1 | Household / Worker | 1.0 User Registration and Authentication | Registration details, login credentials, signup verification, password reset request. |
| F2 | 1.0 User Registration and Authentication | D5, D12, D13 | User accounts, password reset requests, signup verification requests. |
| F3 | 1.0 User Registration and Authentication | D1-D7 | Django content type, permission, group, and user permission data used by authentication and authorization. |
| F4 | Household / Worker | 2.0 Profile, Availability, and Verification Setup | Profile details, skills, rates, location, availability, and verification documents. |
| F5 | 2.0 Profile, Availability, and Verification Setup | D9-D10, D19 | Profile, availability, and verification request records. |
| F6 | Household | 3.0 Job Posting Management | Job type, schedule, location, service rate, description, and images. |
| F7 | 3.0 Job Posting Management | D14-D15 | Job posting and job image records. |
| F8 | Worker | 4.0 Worker Application Management | Job browsing request and job application details. |
| F9 | 4.0 Worker Application Management | D14, D16 | Job listings and application records. |
| F10 | 5.0 Smart Matching and Route Distance | D9-D10, D14, D20 | Worker profile, availability, job location, and cached route distance data. |
| F11 | 5.0 Smart Matching and Route Distance | Household | Ranked worker suggestions and distance indicators. |
| F12 | Household / Worker | 6.0 Hiring, Completion, and Job Status | Hiring decision, rejection, completion request, and completion confirmation. |
| F13 | 6.0 Hiring, Completion, and Job Status | D14, D16 | Updated job and application statuses. |
| F14 | Household / Worker | 7.0 Reviews and Reputation | Rating and feedback after completed services. |
| F15 | 7.0 Reviews and Reputation | D17, D9 | Review records and updated profile rating summaries. |
| F16 | 8.0 Notification Management | D18 | In-system notification records. |
| F17 | 8.0 Notification Management | Email Service | Email notification request. |
| F18 | System Administrator | 9.0 Administration and Analytics | Monitoring and reporting request. |
| F19 | 9.0 Administration and Analytics | D8, D9, D14-D20 | Admin logs and operational data for analytics reports. |
| F20 | 9.0 Administration and Analytics | System Administrator | Dashboard metrics, verification metrics, geographic distribution, and service rate summaries. |

## Notes

- Analytics are computed from operational tables and are not stored in a separate analytics table in the current Django models.
- `notifications_notification.related_job_id` and `related_application_id` are logical integer references, not enforced foreign keys.
- The DFD includes Django framework stores because the current database schema and database dictionary include the full 20-table schema.
- **This diagram models a subset of the current schema.** It was drawn before the worker portfolio, dispute-resolution, and token-revocation features landed, so the following tables have no store on it: `accounts_workerportfolio`, `accounts_workerskill`, `accounts_workercertification`, `accounts_workerportfolioitem`, `accounts_skillrating`, `accounts_verificationdocument`, `complaints_complaint`, `complaints_complaintevidence`, and `common_revokedtoken`. The database dictionary (Figure 3.4) is the authoritative list of tables; this figure should be redrawn if those flows need to be shown.
