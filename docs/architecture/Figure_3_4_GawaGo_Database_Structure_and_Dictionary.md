# GawaGo Database Structure and Dictionary

This section presents the full database structure and dictionary of the GawaGo Employment Platform. The structure follows the current Django backend implementation and includes both Django framework tables and GawaGo application tables.

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
| 10 | location_label | VARCHAR(255) | 1 | '' | 0 |
| 11 | latitude | DECIMAL(10,7) | 0 | NULL | 0 |
| 12 | longitude | DECIMAL(10,7) | 0 | NULL | 0 |
| 13 | profile_photo | VARCHAR(100) | 0 | NULL | 0 |
| 14 | average_rating | DECIMAL(3,2) | 0 | NULL | 0 |
| 15 | rating_count | INTEGER UNSIGNED | 1 | 0 | 0 |

This table stores profile information for household and worker users. It includes skills, service rates, verification status, location coordinates, profile image, and rating summary.

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

## Table 11: `accounts_workerweeklyavailability`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | worker_id | INTEGER | 1 | NULL | 0 |
| 2 | weekday | SMALLINT UNSIGNED | 1 | NULL | 0 |
| 3 | start_time | TIME | 1 | NULL | 0 |
| 4 | end_time | TIME | 1 | NULL | 0 |
| 5 | is_available | BOOLEAN | 1 | TRUE | 0 |

This table stores recurring weekly availability windows for workers. The weekday value ranges from 0 to 6, representing Monday through Sunday.

## Table 12: `accounts_passwordresetrequest`

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

## Table 13: `accounts_signupverificationrequest`

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

## Table 14: `jobs_jobposting`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | household_id | INTEGER | 1 | NULL | 0 |
| 2 | title | VARCHAR(255) | 1 | NULL | 0 |
| 3 | job_type | VARCHAR(120) | 1 | NULL | 0 |
| 4 | required_skill | VARCHAR(120) | 1 | NULL | 0 |
| 5 | schedule | VARCHAR(255) | 1 | NULL | 0 |
| 6 | schedule_type | VARCHAR(80) | 1 | '' | 0 |
| 7 | preferred_date | DATE | 0 | NULL | 0 |
| 8 | preferred_time | TIME | 0 | NULL | 0 |
| 9 | description | TEXT | 1 | '' | 0 |
| 10 | location_label | VARCHAR(255) | 1 | NULL | 0 |
| 11 | latitude | DECIMAL(10,7) | 1 | NULL | 0 |
| 12 | longitude | DECIMAL(10,7) | 1 | NULL | 0 |
| 13 | service_rate | DECIMAL(10,2) | 1 | NULL | 0 |
| 14 | worker_slots | INTEGER UNSIGNED | 1 | 1 | 0 |
| 15 | status | VARCHAR(20) | 1 | open | 0 |
| 16 | created_at | DATETIME | 1 | NULL | 0 |
| 17 | completed_at | DATETIME | 0 | NULL | 0 |

This table stores job postings created by household users.

## Table 15: `jobs_jobimage`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | job_id | BIGINT | 1 | NULL | 0 |
| 2 | image | VARCHAR(100) | 1 | NULL | 0 |
| 3 | uploaded_at | DATETIME | 1 | NULL | 0 |
| 4 | order | INTEGER UNSIGNED | 1 | 0 | 0 |

This table stores images attached to job postings.

## Table 16: `jobs_jobapplication`

| cid | name | type | notnull | dflt_value | pk |
|---:|---|---|---:|---|---:|
| 0 | id | BIGINT | 1 | NULL | 1 |
| 1 | job_id | BIGINT | 1 | NULL | 0 |
| 2 | worker_id | INTEGER | 1 | NULL | 0 |
| 3 | status | VARCHAR(20) | 1 | pending | 0 |
| 4 | applied_at | DATETIME | 1 | NULL | 0 |
| 5 | updated_at | DATETIME | 1 | NULL | 0 |
| 6 | note | TEXT | 1 | '' | 0 |

This table stores worker applications to job postings.

## Table 17: `reviews_review`

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
| 8 | feedback | TEXT | 1 | '' | 0 |
| 9 | created_at | DATETIME | 1 | NULL | 0 |

This table stores post-completion reviews and feedback.

## Table 18: `notifications_notification`

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

This table stores in-system notifications, including recipient, optional actor, action context, read status, and creation date.

## Table 19: `common_verificationrequest`

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

This table stores worker verification submissions and administrator review information.

## Table 20: `matching_routedistancecache`

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

This table stores cached route distance results between job locations and worker profile locations.

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
| `auth_user` to `accounts_workerweeklyavailability` | 1:N | One worker can create many recurring weekly availability windows. |
| `auth_user` to `accounts_passwordresetrequest` | 1:N | One user can have many password reset requests. |
| `auth_user` to `accounts_signupverificationrequest` | 1:1 | Each user can have one signup verification request record. |
| `auth_user` to `jobs_jobposting` | 1:N | One household can create many job postings. |
| `jobs_jobposting` to `jobs_jobimage` | 1:N | One job posting can have many uploaded images. |
| `jobs_jobposting` to `jobs_jobapplication` | 1:N | One job posting can receive many worker applications. |
| `auth_user` to `jobs_jobapplication` | 1:N | One worker can submit many job applications. |
| `auth_user` to `reviews_review` | 1:N | One user can write and receive many reviews through author and target relationships. |
| `jobs_jobposting` to `reviews_review` | 1:N | One completed job can have reviews from both parties. |
| `auth_user` to `notifications_notification` | 1:N | One user can receive many notifications and can also act as the notification actor. |
| `auth_user` to `common_verificationrequest` | 1:N | One worker can submit many verification requests. |
| `jobs_jobposting` to `matching_routedistancecache` | 1:N | One job can have cached distance records for many worker profiles. |
| `accounts_userprofile` to `matching_routedistancecache` | 1:N | One worker profile can appear in many cached job distance records. |

The current full database schema contains 20 tables: 8 Django framework tables and 12 GawaGo application tables. Notification job and application references are stored as logical integer references, while the other listed relationships are enforced through Django foreign key or one-to-one fields.
