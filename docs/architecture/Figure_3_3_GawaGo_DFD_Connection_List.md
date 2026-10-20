# Figure 3.3 GawaGo DFD Connection List

This file lists every connector used in `Figure_3_3_GawaGo_DFD.drawio`.

## External Entity and Service Flows

| ID | From | To | Data Flow |
| --- | --- | --- | --- |
| F1 | Household User | 1.0 User Registration and Login | Registration / login details |
| F2 | 1.0 User Registration and Login | Household User | Authentication result |
| F3 | Worker User | 1.0 User Registration and Login | Worker registration / login |
| F4 | 1.0 User Registration and Login | Worker User | Authentication result |
| F5 | Worker User | 2.0 Profile and Availability | Profile, skills, rates, availability |
| F6 | Household User | 2.0 Profile and Availability | Household profile information |
| F7 | Household User | 3.0 Job Posting Management | Job posting details |
| F8 | 3.0 Job Posting Management | Worker User | Job listings / application status |
| F9 | Worker User | 4.0 Job Application Management | Application details |
| F10 | Household User | 4.0 Job Application Management | Applicant review / hiring choice |
| F11 | Household User | 5.0 Smart Matching and Distance | Search criteria |
| F12 | 5.0 Smart Matching and Distance | Household User | Ranked matches and distance |
| F13 | Household User | 6.0 Hiring and Completion | Hire request / completion request |
| F14 | Worker User | 6.0 Hiring and Completion | Acceptance / completion update |
| F15 | Worker User | 7.0 Worker Verification Management | Verification documents |
| F16 | System Administrator | 7.0 Worker Verification Management | Verification decision |
| F17 | Household User | 8.0 Review and Rating | Rating and feedback |
| F18 | Worker User | 8.0 Review and Rating | Rating and feedback |
| F19 | System Administrator | 9.0 Notifications and Analytics | Monitoring request |
| F20 | 9.0 Notifications and Analytics | System Administrator | Analytics reports |
| F21 | 9.0 Notifications and Analytics | Email Notification Service | Email notification request |
| F22 | Email Notification Service | 9.0 Notifications and Analytics | Delivery status |

## Process-to-Process Flows

| ID | From | To | Data Flow |
| --- | --- | --- | --- |
| PP1 | 1.0 User Registration and Login | 2.0 Profile and Availability | Profile context |
| PP2 | 3.0 Job Posting Management | 5.0 Smart Matching and Distance | Job details |
| PP3 | 4.0 Job Application Management | 6.0 Hiring and Completion | Application records |
| PP4 | 6.0 Hiring and Completion | 8.0 Review and Rating | Completion data |
| PP5 | 8.0 Review and Rating | 9.0 Notifications and Analytics | Review reminders / events |

## Data Store Flows

| ID | From | To | Data Flow |
| --- | --- | --- | --- |
| S1 | 1.0 User Registration and Login | D5 auth_user | User records |
| S2 | 1.0 User Registration and Login | D13 accounts_signupverificationrequest | Signup verification |
| S3 | 1.0 User Registration and Login | D12 accounts_passwordresetrequest | Password reset |
| S4 | 1.0 User Registration and Login | D1 django_content_type | Content / permission metadata |
| S5 | 1.0 User Registration and Login | D2 auth_permission | Permission records |
| S6 | 1.0 User Registration and Login | D3 auth_group | Group records |
| S7 | 1.0 User Registration and Login | D4 auth_group_permissions | Group-permission links |
| S8 | 1.0 User Registration and Login | D6 auth_user_groups | User-group links |
| S9 | 1.0 User Registration and Login | D7 auth_user_user_permissions | User-permission links |
| S10 | 9.0 Notifications and Analytics | D8 django_admin_log | Admin log records |
| S11 | 2.0 Profile and Availability | D9 accounts_userprofile | Profile records |
| S12 | 2.0 Profile and Availability | D10 accounts_workeravailability | Availability records |
| S13 | ~~2.0 Profile and Availability~~ | ~~D11 accounts_workerweeklyavailability~~ | **Retired** with D11 (table dropped in accounts migration 0009). |
| S14 | 3.0 Job Posting Management | D14 jobs_jobposting | Job posting records |
| S15 | 3.0 Job Posting Management | D15 jobs_jobimage | Job image records |
| S16 | 4.0 Job Application Management | D16 jobs_jobapplication | Application records |
| S17 | D9 accounts_userprofile | 5.0 Smart Matching and Distance | Matching profile data |
| S18 | D10 accounts_workeravailability | 5.0 Smart Matching and Distance | Availability data |
| S19 | 5.0 Smart Matching and Distance | D20 matching_routedistancecache | Route distance cache |
| S20 | 6.0 Hiring and Completion | D14 jobs_jobposting | Hire / completion updates |
| S21 | 6.0 Hiring and Completion | D16 jobs_jobapplication | Application status updates |
| S22 | 7.0 Worker Verification Management | D19 common_verificationrequest | Verification records |
| S23 | 8.0 Review and Rating | D17 reviews_review | Review records |
| S24 | 9.0 Notifications and Analytics | D18 notifications_notification | Notification records |
| S25 | D14 jobs_jobposting | 9.0 Notifications and Analytics | Analytics source data |
| S26 | D16 jobs_jobapplication | 9.0 Notifications and Analytics | Analytics source data |
| S27 | D17 reviews_review | 9.0 Notifications and Analytics | Analytics source data |
| S28 | D19 common_verificationrequest | 9.0 Notifications and Analytics | Analytics source data |

## Reading Guide

- Left side: external actors and outside services.
- Center: GawaGo system processes from registration to analytics.
- Right side: database stores aligned with the current schema.
- Red lines: user-facing or service-facing data movement.
- Gray lines: internal process or database data movement.
