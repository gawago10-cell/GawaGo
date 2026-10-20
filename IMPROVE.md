# GawaGo Improvement Roadmap
**Based on Panelist Feedback**  
**Date:** September 2, 2026

---

## Overview
This guide outlines the improvements and features recommended by the thesis defense panelists (Ma'am Borella, Sir LA, Sir NJ). The recommendations are organized by priority and include specific implementation details.

---

## 🔴 CRITICAL PRIORITY (Must Do First)

### 1. Worker Verification Before Ratings
**Panelist:** Ma'am Borella  
**Impact:** Trust System  
**Status:** ✅ COMPLETED

**Implementation Details:**
- ✅ `ReviewListCreateView.post()` requires `job.status == JobPosting.STATUS_COMPLETED` before a review can be created
- ✅ Requires a matching `JobApplication` with `STATUS_COMPLETED` between the specific author/target pair (mutual job relationship, not just job status)
- ✅ Two-step completion flow in `jobs/views.py` — worker marks the job done, household then confirms ("please confirm if the service was completed")
- ✅ Duplicate-review guard: rejects a second review for the same job/author/target combination

**Files implemented:**
- ✅ `backend/apps/reviews/views.py` — Eligibility + completion checks in `post()`
- ✅ `backend/apps/jobs/views.py` — Worker-marks-done / household-confirms completion flow
- ✅ `backend/apps/jobs/models.py` — `JobPosting`/`JobApplication` completion status tracking

---

### 2. Change Application Status Terminology
**Panelist:** Ma'am Borella  
**Impact:** User Clarity  
**Status:** ✅ COMPLETED

**What to do:**
- Rename application statuses: **Hired** (accepted), **Rejected**, **Pending** (applied)
- Remove "Completed" status (too confusing with job completion)
- Update backend enums and API responses
- Update all frontend displays

**Files to modify:**
- `backend/apps/jobs/models.py` — Update Application model status choices
- `backend/apps/jobs/serializers.py` — Update status field
- All frontend components showing application status

---

### 3. Add Job Start & End Dates
**Panelist:** Ma'am Borella  
**Impact:** Job Scheduling  
**Status:** ✅ COMPLETED

**What to do:**
- Add `job_start_date` and `job_end_date` to Job model
- Add `estimated_working_days` field
- Display date range in job details and forms
- Update job serializers and views

**Suggested database fields:**
```python
job_start_date = DateField()
job_end_date = DateField()
estimated_working_days = IntegerField(null=True, blank=True)
```

**Files to modify:**
- `backend/apps/jobs/models.py` — Add date fields
- `backend/apps/jobs/serializers.py` — Include in API
- `backend/apps/jobs/views.py` — Update job creation logic
- Frontend job posting form

---

### 4. Geographic Distance Boundaries
**Panelist:** Sir NJ  
**Impact:** Job Matching  
**Status:** ✅ COMPLETED

**What to do:**
- Implement distance radius limits (recommend 1 km default)
- Pre-filter workers by distance before showing recommendations
- Allow households to adjust radius per job posting
- Make distance a hard constraint (not just ranking factor)

**Suggested database field:**
```python
max_distance_km = FloatField(default=1.0)
geographic_boundary = CharField(choices=[...])
```

**Files to modify:**
- `backend/apps/matching/services.py` — Filter by distance
- `backend/apps/jobs/models.py` — Add distance fields
- Frontend job posting form

---

## 🟡 HIGH PRIORITY (Next Sprint)

### 5. Worker Portfolio Feature
**Panelists:** Sir LA, Sir NJ  
**Impact:** Trust & Worker Profile  
**Status:** ✅ COMPLETED

**What to do:**
- Create portfolio section showing:
  - ✅ Skills with proficiency levels
  - ✅ Experience and years in field
  - ✅ Certifications (TESDA, licenses, etc.)
  - ✅ Previous work history/examples
  - ✅ Work samples or photos
  - ✅ Skill-based ratings from households

**Database models created:**
- ✅ `WorkerPortfolio` — Main portfolio
- ✅ `WorkerSkill` — Skills with proficiency and ratings
- ✅ `WorkerCertification` — Certificates/credentials
- ✅ `WorkerPortfolioItem` — Work samples
- ✅ `SkillRating` — Individual skill ratings from households

**Files created:**
- ✅ `backend/apps/accounts/models.py` — Added 5 new models
- ✅ `backend/apps/accounts/serializers.py` — Added 5 new serializers
- ✅ `backend/apps/accounts/views.py` — Added 5 new API views
- ✅ `backend/apps/accounts/urls.py` — Added portfolio endpoints
- ✅ `backend/apps/accounts/migrations/0008_*.py` — Database migration
- ✅ `frontend/src/components/WorkerPortfolioEditView.jsx` — Worker portfolio editor
- ✅ `frontend/src/components/SkillRatingForm.jsx` — Skill rating form for households
- ✅ `frontend/src/components/WorkerPortfolioViewPublic.jsx` — Portfolio view for households

---

### 6. Complaint & Issue Reporting System
**Panelist:** Sir LA  
**Impact:** Dispute Resolution  
**Status:** ✅ COMPLETED

**Implementation Details:**

**Backend Infrastructure:**
- ✅ Complaint Model: 6 complaint types (Payment Issue, Quality of Work, No Show, Safety Concern, Inappropriate Behavior, Other)
- ✅ 4 complaint statuses: Submitted, Under Review, Resolved, Closed
- ✅ API endpoints for creating and viewing complaints
- ✅ Admin endpoints for reviewing and resolving complaints
- ✅ Auto timestamps (created_at, updated_at)

**Complaint Types Supported:**
- Payment Issue
- Quality of Work
- No Show
- Safety Concern
- Inappropriate Behavior
- Other

> **Corrected 2026-09-14.** This list previously read as a routing table
> ("No Show → Flag worker for attendance issue", etc.), implying per-type
> automation. **No such automation exists, and none ever did.** There is no
> signals file and no flagging field anywhere in the codebase; `complaint_type`
> is used for exactly three things: storing the value, filtering the admin
> queue, and naming the type in a status-change notification. All six types
> are handled identically — the report lands in the admin queue and a human
> reviews it, sets a status, and writes a resolution note. The type is
> metadata for that reviewer, not a trigger. Admins *can* now act on a report
> by blocking the reported account (see #26).

**Frontend Features:**
- ✅ Complaint Modal component with form validation
- ✅ Type selection dropdown
- ✅ Optional job selection (for job-specific complaints)
- ✅ Rich description text area with formatting hints
- ✅ Privacy notice about confidential handling
- ✅ Accessibility (proper labels, aria attributes)
- ✅ Complaint submission button in household job panel (after job completion)

**Admin Interface:**
- ✅ List all complaints with filters (status, type)
- ✅ View complaint details
- ✅ Update complaint status
- ✅ Add admin notes and resolution
- ✅ Django admin interface for full management

**Status Tracking:**
- Submitted → Initial complaint filed
- Under Review → Admin is reviewing
- Resolved → Action taken, resolution provided
- Closed → Case closed

**Files Implemented:**
- ✅ `backend/apps/complaints/models.py` — Complaint model with 6 types, 4 statuses
- ✅ `backend/apps/complaints/serializers.py` — Full serialization with related data
- ✅ `backend/apps/complaints/views.py` — API endpoints (create, list, detail, admin views)
- ✅ `backend/apps/complaints/urls.py` — URL routing
- ✅ `backend/apps/complaints/admin.py` — Django admin configuration
- ✅ `backend/apps/complaints/tests.py` — Unit tests
- ✅ `backend/apps/complaints/apps.py` — App configuration
- ✅ `backend/apps/complaints/migrations/0001_initial.py` — Database migration
- ✅ `backend/config/settings/base.py` — Added to INSTALLED_APPS
- ✅ `backend/config/urls.py` — Added API route at /api/complaints/
- ✅ `frontend/src/components/ComplaintModal.jsx` — Modal form with validation
- ✅ `frontend/src/App.jsx` — State management and handlers
- ✅ `frontend/src/components/AppViews.jsx` — Modal rendering and complaint button

---

### 7. Employment History Tracking
**Panelist:** Sir NJ  
**Impact:** Worker Trust & Rehiring  
**Status:** ✅ COMPLETED

**What to do:**
- ✅ Track every job worker completes with each household
- ✅ Show previous jobs on worker profile (Employment History section)
- ✅ Display skill ratings from households per job
- ✅ Calculate overall rating from all skill ratings
- ✅ Allow households to rate workers after job completion

**Implementation Details:**
- ✅ Added Employment History section in Worker My Profile
  - Shows completed jobs with household names and locations
  - Displays individual skill ratings (Cleaning 5⭐, Cooking 4⭐, etc.)
  - Auto-calculates overall rating average
- ✅ Household Rating Interface
  - "Rate Worker" button on completed jobs
  - Star rating modal for each of worker's skills
  - Submit ratings that save to SkillRating model
  - Ratings appear in worker's Employment History

**Files modified:**
- `frontend/src/App.jsx` — Added employment history state, fetch logic, rating handlers
- `frontend/src/components/AppViews.jsx` — Added Employment History display section + rating modal
- `backend/apps/accounts/models.py` — Using existing SkillRating model
- `backend/apps/accounts/views.py` — Using existing SkillRatingView for API

---

### 8. Enhanced Dashboard Analytics
**Panelist:** Ma'am Borella  
**Impact:** Admin Monitoring  
**Status:** ✅ COMPLETED

**Implementation Details:**
- ✅ Hiring Success Rate - % of applications that result in hires
- ✅ Job Match Rate - % of jobs successfully matched  
- ✅ Worker Hiring Statistics - Total hired workers, repeat hires, hire percentage
- ✅ Application Trends - Monthly line chart showing application volume
- ✅ Service Type Breakdown - Bar chart showing job distribution by service type
- ✅ Monthly Job Postings - Bar chart tracking job volume trends

**Metric Cards on Analytics Dashboard:**
- Hiring Success Rate (%) — Green card
- Job Match Rate (%) — Blue card  
- Hired Workers count — Yellow card
- Repeat Hires count — Primary blue card

**Charts Added:**
- Application Trends (Line chart) — Shows application volume trends
- Service Type Distribution (Bar chart) — Shows job breakdown by service
- Monthly Job Postings (Bar chart) — Shows job posting trends

**Files Modified:**
- ✅ `frontend/src/hooks/useDashboardMetrics.js` — Added analytics calculation functions
- ✅ `frontend/src/components/SuperAdminDashboardView.jsx` — Added Analytics tab with cards and charts

---

### 9. Comprehensive Notifications System
**Panelist:** Sir NJ  
**Impact:** User Engagement  
**Status:** ✅ COMPLETED

**Implementation Details:**

**Backend Notification Triggers - 9 Triggers Active:**
- ✅ Job Application Submitted → Notify household with job details
- ✅ Application Accepted (Hired) → Notify worker with acceptance details
- ✅ Application Rejected → Notify worker with rejection notice
- ✅ Job Completion → Notify both parties of completion
- ✅ Rating Submitted → Notify rated worker with skill ratings
- ✅ Verification Status Change → Notify worker of verification result
- ✅ Message Received → Notify recipient of new message
- ✅ Admin Alerts → Notifications for registrations and flags
- ✅ Email Integration → Automated email notifications for all types

**Backend Infrastructure:**
- ✅ Notification Model: 9 notification types with full tracking
- ✅ create_notification() Service: Handles creation + email sending
- ✅ 9 create_notification() calls in jobs/views.py
- ✅ Notification serializers for API responses
- ✅ Notification API views for frontend access

**Frontend Notifications:**
- ✅ Notification utilities (getHouseholdNotifications, getWorkerNotifications)
- ✅ Backend notifications state management
- ✅ Notification read state tracking (notificationReads)
- ✅ Verification notifications integration
- ✅ Application notifications integration
- ✅ Household & Worker notification filtering
- ✅ Real-time notification display with unread badges

**Supported Notification Types:**
- Application notifications
- Acceptance notifications
- Rejection notifications
- Hiring notifications
- Completion notifications
- Verification notifications
- Review reminders
- Account activity alerts
- Rating notifications
- Message notifications

**Files Implemented:**
- ✅ `backend/apps/notifications/models.py` — 9 notification types
- ✅ `backend/apps/notifications/services.py` — create_notification + email
- ✅ `backend/apps/notifications/views.py` — Notification API endpoints
- ✅ `backend/apps/jobs/views.py` — 9 notification triggers wired up
- ✅ `frontend/src/App.jsx` — Notification state + filtering logic
- ✅ `frontend/src/utils/notificationUtils.js` — Notification utilities

---

## 🟠 MEDIUM PRIORITY (Polish & Enhancement)

### 10. E-Commerce Style Rating Metrics
**Panelist:** Ma'am Borella  
**Impact:** Trust System  
**Status:** ✅ COMPLETED

**Implementation Details:**

**Backend Rating Metrics (4 detailed fields):**
- ✅ Quality of Work (1-5 scale)
- ✅ Punctuality (1-5 scale)
- ✅ Communication (1-5 scale)
- ✅ Professionalism (1-5 scale)
- ✅ Overall Rating (auto-calculated average)

**Database Changes:**
- ✅ Added 4 IntegerField columns to Review model
- ✅ Each field: choices 1-5, nullable
- ✅ Migration 0006_review_* applied successfully

**API Serialization:**
- ✅ ReviewSerializer includes all 4 metrics + overall_rating
- ✅ ReviewCreateSerializer accepts metrics fields
- ✅ get_overall_rating() method calculates average automatically
- ✅ Backward compatible (overall_rating shows single rating if metrics empty)

**Frontend Review Form (Household & Worker):**
- ✅ 4 new metric rating sections (each with 1-5 button selector)
- ✅ Metrics sections optional (appear below overall rating)
- ✅ Green success button styling for selected rating
- ✅ Clear labels for each metric
- ✅ Mobile responsive layout

**Review Display:**
- ✅ Shows overall_rating in title row (calc. average or fallback to rating)
- ✅ Displays all 4 metrics with star emoji breakdown
- ✅ Responsive 2-column layout for metrics display
- ✅ Metrics shown inline with feedback text

**Files Modified:**
- ✅ `backend/apps/reviews/models.py` — Added 4 metric IntegerFields
- ✅ `backend/apps/reviews/migrations/0006_*.py` — Database migration
- ✅ `backend/apps/reviews/serializers.py` — Metrics in serializer + overall_rating method
- ✅ `backend/apps/reviews/views.py` — Create review with metrics
- ✅ `frontend/src/constants/appConstants.js` — Added metric fields to EMPTY forms
- ✅ `frontend/src/hooks/useGawaGoActions.js` — Metrics included in submission
- ✅ `frontend/src/components/AppViews.jsx` — Metric rating UI + display

---

### 11. Worker Certification Upload
**Panelist:** Ma'am Borella  
**Impact:** Worker Credibility  
**Status:** ✅ COMPLETED

**Implementation Details:**

**Backend Certification Model (Enhanced):**
- ✅ 5 Certificate Types: TESDA, License, Credential, Certification, Other
- ✅ 3 Verification Statuses: Pending, Approved, Rejected
- ✅ Admin Approval Workflow with notes and timestamp
- ✅ Auto-verification flag (is_verified set when approved)
- ✅ File upload support (certificate_file field)
- ✅ Multiple file uploads per worker (related_name="portfolio_certifications")
- ✅ Metadata fields: issuer, issue_date, expiry_date

**Admin Certificate Verification:**
- ✅ CertificateVerificationAdminView for listing pending certificates
- ✅ Admin approval endpoint with verification status & notes
- ✅ Automatic notification sent to worker on approval/rejection
- ✅ Filter by status (pending, approved, rejected)
- ✅ Track verified_by admin and verified_at timestamp

**Frontend Certificate Management:**
- ✅ Certificate Type dropdown in upload form (5 types)
- ✅ Verified badge display on profile certificates (✓ Verified)
- ✅ Verified badge in portfolio gallery view
- ✅ Multiple certificate uploads supported
- ✅ Edit/Delete buttons for workers

**API Endpoints:**
- ✅ POST `/api/accounts/me/portfolio/certifications/` — Worker upload
- ✅ DELETE `/api/accounts/me/portfolio/certifications/<cert_id>/` — Worker delete
- ✅ PATCH `/api/accounts/me/portfolio/certifications/<cert_id>/` — Worker edit
- ✅ GET `/api/accounts/admin/certificates/` — Admin list pending
- ✅ PATCH `/api/accounts/admin/certificates/<cert_id>/` — Admin verify

**Files Modified:**
- ✅ `backend/apps/accounts/models.py` — Added 5 new fields to WorkerCertification
- ✅ `backend/apps/accounts/migrations/0010_*.py` — Database migration
- ✅ `backend/apps/accounts/serializers.py` — Updated WorkerCertificationSerializer
- ✅ `backend/apps/accounts/views.py` — Added CertificateVerificationAdminView
- ✅ `backend/apps/accounts/urls.py` — Added admin certificate endpoints
- ✅ `frontend/src/components/AppViews.jsx` — Certificate type dropdown + verified badges

---

### 12. Multiple ID Types for Verification
**Panelist:** Ma'am Borella  
**Impact:** User Verification  
**Status:** ✅ COMPLETED

**Implementation Details:**

**Backend Verification Document System:**
- ✅ 8 ID Types supported:
  - National ID (UMID/GSIS/SSS)
  - Passport
  - Driver's License
  - Voter ID
  - TIN ID
  - UMID
  - Postal ID
  - Other Government ID
- ✅ VerificationDocument model with full admin approval workflow
- ✅ 3 Verification Statuses: Pending, Approved, Rejected
- ✅ Admin notes and verified_at tracking
- ✅ Primary/secondary document support

**UserProfile Enhancement:**
- ✅ primary_id_type field to store worker's chosen ID type
- ✅ Links to chosen ID type for flexibility

**API Endpoints:**
- ✅ POST `/api/accounts/me/verification-documents/` — Worker upload
- ✅ GET `/api/accounts/me/verification-documents/` — Worker view own documents
- ✅ DELETE `/api/accounts/me/verification-documents/<doc_id>/` — Worker delete
- ✅ GET `/api/accounts/admin/verification-documents/?status=pending` — Admin list
- ✅ PATCH `/api/accounts/admin/verification-documents/<doc_id>/` — Admin verify

**Features:**
- ✅ Document file upload (supports all file types)
- ✅ ID number/reference tracking
- ✅ Primary document flag (is_primary)
- ✅ Automatic notification on verification status change
- ✅ Audit trail (verified_by, verified_at, verification_notes)
- ✅ Status filtering for admin dashboard

**Files Modified:**
- ✅ `backend/apps/accounts/models.py` — VerificationDocument model + primary_id_type field
- ✅ `backend/apps/accounts/migrations/0011_*.py` — Database migration
- ✅ `backend/apps/accounts/serializers.py` — VerificationDocumentSerializer
- ✅ `backend/apps/accounts/views.py` — VerificationDocumentView + VerificationDocumentAdminView
- ✅ `backend/apps/accounts/urls.py` — API endpoints

---

### 13. Enhanced Reputation Scoring
**Panelist:** Sir NJ  
**Impact:** Worker Growth  
**Status:** ✅ COMPLETED

**Implementation Details:**
- ✅ Added reputation_tier field to UserProfile (choices: new, established, trusted, elite)
- ✅ Added rating_trend field to UserProfile (choices: improving, declining, neutral)
- ✅ Created calculate_reputation_tier() function in reviews/services.py
  - Elite: 4.5+ rating with 5+ reviews
  - Trusted: 4.0+ rating with 5+ reviews
  - Established: 3.5+ rating with 5+ reviews
  - New: default tier for new workers
- ✅ Created calculate_rating_trend() function to compare recent (30 days) vs older ratings
- ✅ Created update_worker_reputation() function to update both tier and trend after each review
- ✅ Updated ReviewCreateView to call update_worker_reputation() after new review
- ✅ Updated UserProfileSerializer to include reputation_tier and rating_trend
- ✅ Updated frontend to display reputation badges on worker profiles
  - ⭐ Elite, ✓ Trusted, ◆ Established, ◇ New
  - 📈 Improving or 📉 Declining trend indicators

**Files Modified:**
- ✅ `backend/apps/accounts/models.py` — Added reputation_tier and rating_trend fields
- ✅ `backend/apps/accounts/migrations/0012_*.py` — Migration for new fields
- ✅ `backend/apps/accounts/serializers.py` — Added fields to UserProfileSerializer
- ✅ `backend/apps/reviews/services.py` — Added calculation functions
- ✅ `backend/apps/reviews/views.py` — Call update_worker_reputation() after review
- ✅ `frontend/src/utils/normalizers.js` — Map reputation_tier and rating_trend from API
- ✅ `frontend/src/components/AppViews.jsx` — Display reputation badges on worker profiles

---

### 14. Lighter UI/UX Design
**Panelist:** Sir LA  
**Impact:** User Experience  
**Status:** ✅ COMPLETED

**What to do:**
- Review and simplify current interface
- Reduce visual clutter
- Use lighter color palette
- Improve component spacing and hierarchy
- Better mobile responsiveness

**Consider using:** The new.html prototype as reference design

**Progress so far:**
- ✅ Fixed app-wide bug: views never reset scroll position on navigation, so on mobile a page opened already-scrolled had its top content (banner, first stat card) hidden under the sticky mobile header. Added a `window.scrollTo(0, 0)` on view change in `App.jsx`.
- ✅ Found that the app already has an established cream/green design system (`--gg-*` tokens in `main.css`), but some panels (e.g. the household My Jobs panel) still carried an older, unrelated blue-gradient theme (~140 leftover occurrences of that palette across `main.css`). Migrated the My Jobs panel to the established tokens.
- ✅ Migrated the household job detail modal (worker panel, job summary, completion steps, review form) off the same leftover blue theme — most visibly, the "current step" indicator used plain blue while "done" steps used green, two competing accents on one screen.
- ✅ Migrated the worker job detail view's key-value list and button shadow off the same leftover blue theme. Cross-checked all other classes it uses (`.profile-card`, `.household-profile-photo/fallback`, `.worker-completion-request-card`, `.profile-card-head`) against `main.css` — already green/cream via base rules or the existing global card-theme override, so nothing else needed there.
- ✅ Superadmin Analytics tab: replaced random Bootstrap-default chart colors (indigo/red/cyan/purple) with the dataviz skill's validated categorical palette (CVD-safety checked via `validate_palette.js`), switched the single-series line chart to the brand green, and migrated the remaining leftover blue theme in `analytics.css` (section/card borders, heatmap panel, verification document cards, barangay ranking list, and the Job Demand/Worker Availability progress-bar meters, which previously used two unrelated gradients).
- All four views identified with the leftover blue-gradient theme (household My Jobs, household job detail, worker job detail, superadmin analytics) are now migrated to the established `--gg-*` cream/green tokens. No further views flagged.
- ⏳ Favicon was also missing entirely (index.html linked an empty `data:` icon); added `frontend/public/favicon.svg` from the existing `gawago_icon_mark_combined_v2.svg` icon mark. Not part of #14's original scope but same "polish" bucket.

**Files to review:**
- `frontend/src/components/` — All UI components
- `frontend/src/styles/` — CSS and Bootstrap customizations (search for `rgba(173, 197, 255`, `rgba(31, 72, 221`, `#0d1f48`, `#10224d` to find remaining leftover-blue-theme spots)

---

### 15. AI-Based Job Matching
**Panelist:** Sir LA  
**Impact:** Recommendation Quality  
**Status:** 🔶 IN PROGRESS (content-based recommender + explainability done; learning from history pending)

**Implementation Details:**
- ✅ Content-based recommender: TF-IDF skill similarity + road-distance proximity, blended into one `ai_score` (`backend/apps/matching/recommendations.py`)
- ✅ Pull-based endpoint: `GET /api/matching/recommended-jobs/` ranks open jobs for the logged-in worker
- ✅ Push-based notifications: `post_save` signal scores every new job against candidate workers and notifies matches above threshold (`backend/apps/matching/signals.py`)
- ✅ Match confidence score surfaced in the UI (`% match`, distance) in `frontend/src/components/AppViews.jsx`
- ✅ Explainability breakdown — each recommendation returns `skill_contribution`, `proximity_contribution`, and `exact_skill_match`; UI shows a two-segment bar plus a "Why this match: X% skill fit, Y% proximity" line
- ⏳ Collaborative filtering / learning from historical hire outcomes — needs a worker-job interaction dataset that doesn't exist yet (noted as a future enhancement in `recommendations.py`)

**Files implemented:**
- ✅ `backend/apps/matching/recommendations.py` — Scoring algorithm + explainability breakdown
- ✅ `backend/apps/matching/signals.py` — Proactive notification hook
- ✅ `backend/apps/matching/views.py`, `urls.py`, `serializers.py` — `recommended-jobs` endpoint
- ✅ `backend/apps/notifications/models.py` — `TYPE_JOB_MATCH` notification type
- ✅ `frontend/src/services/backendDataService.js`, `frontend/src/components/AppViews.jsx`, `frontend/src/styles/main.css` — Fetch + display recommendations with breakdown bar

**Remaining work:**
- Collaborative filtering / learning from historical hire outcomes (needs interaction data that doesn't exist yet)

---

### 16. Household-Side AI Matching After Posting
**Impact:** Recommendation Quality
**Status:** ✅ COMPLETED

**Problem:** AI matching only ran worker-side (ranking jobs for a worker). Households got the older rule-based Smart Matching score with no explainability, and recommendations were buried at the bottom of the job detail screen — three taps after posting, which is exactly when they matter most.

**Implementation Details:**
- ✅ `get_recommended_workers()` in `backend/apps/matching/recommendations.py` — the same TF-IDF + proximity score, run in the opposite direction. `_build_score_result()` was already symmetric in (job, worker), so both directions share one scorer and one explainability breakdown.
- ✅ `/api/matching/recommended-workers/` now returns `ai_score`, `skill_similarity`, `skill_contribution`, `proximity_contribution`, and `exact_skill_match` on every result, alongside the existing Smart Matching fields.
- ✅ `?rank=ai` re-ranks by AI score. **Default stays `smart`** so Smart Matching's documented priority order (verification before distance, per Sir NJ) is not silently replaced — the two features stay complementary, as AGENTS.md I.B/I.C describe.
- ✅ Web: posting a job now lands on a new `household-job-matches` screen showing AI-ranked workers with a `% match` badge and the skill-vs-proximity breakdown bar.
- ✅ Mobile: same flow — `_JobMatches` screen pushed straight after posting, reusing `_RecommendedWorkerRow` with a new `_AiMatchBreakdown`.
- ✅ Removed the blocking `window.alert("Job posted successfully.")`; the new screen carries the success state.

**Files implemented:**
- ✅ `backend/apps/matching/{recommendations,views,serializers}.py`, `backend/apps/matching/tests.py`
- ✅ `frontend/src/components/AppViews.jsx`, `hooks/useGawaGoActions.js`, `hooks/useBackendSync.js`, `services/backendDataService.js`
- ✅ `mobile/lib/src/features/household/` (models, repository, home screen)

---

### 17. Admin Dashboard / Analytics Split
**Impact:** Admin Monitoring
**Status:** ✅ COMPLETED

**Problem:** There was no Dashboard tab at all. Everything dashboard-shaped — hiring KPIs, the operational snapshot, trend charts — was stacked inside the Analytics tab, which also held the heat map, geographic tables, and pricing trends. One very long scroll mixing "what is happening now" with "how has it trended".

**Implementation Details:**
- ✅ Added a `Dashboard` tab, now the default landing tab for superadmins.
- ✅ Moved onto Dashboard: the operational snapshot (accounts, employment activity, trust/verification) and the hiring performance block (hiring success rate, job match rate, hired workers, repeat hires, application trends, service distribution, monthly postings).
- ✅ Left on Analytics: barangay heat map, monthly job requests, most requested services, geographic analytics, rating distribution, average rates, pricing trends.
- ✅ Fixed leftover non-theme chart colors in the moved block (`#4CAF50`, `#2196F3` → brand green `#2d7a4f`), and migrated the AI breakdown bar off Bootstrap blue onto the `--gg-*` palette.

**Files modified:**
- ✅ `frontend/src/components/SuperAdminDashboardView.jsx`, `frontend/src/App.jsx`, `frontend/src/styles/main.css`

---

### 18. Role Reports (Household, Worker, Admin) — Later Scoped Back To Admin Only
**Impact:** Employment Analytics — satisfies AGENTS.md IV.A "Dashboard and Reports"
**Status:** ✅ COMPLETED, then narrowed per user feedback

**Problem:** No report or export capability existed anywhere — no endpoints, and no PDF/CSV library in either `requirements.txt` or `package.json`.

**Implementation Details:**
- ✅ New `backend/apps/reports/` app. `GET /api/reports/me/` (role-aware: household or worker) and `GET /api/reports/platform/` (staff only).
- ✅ `?start=`/`?end=` date bounds, defaulting to a trailing 180 days; reversed bounds are swapped rather than returning an empty window.
- ✅ `?export=csv` returns a CSV attachment. Uses Python's stdlib `csv` — **no new dependency**. Note the switch is `export`, not `format`: DRF reserves `format` for content negotiation and `?format=csv` 404s before the view runs.
- ✅ All three scopes share one envelope (`scope`/`title`/`period`/`summary`/`sections`), so one renderer covers every role on each client.

**Scoped back (2026-09-13):** the household/worker activity-summary report was removed from both web and mobile — the user only wanted this for admin. `ReportsView.jsx` (web) and `ReportView` (mobile) are now admin/platform-only; the "Reports" nav entry and `openReports()` navigation were deleted from every household/worker sidebar on both platforms. The `/api/reports/me/` backend endpoint and its tests were left in place (harmless, fully tested, no client calls it) rather than deleted, in case a future UI wants it — flag this if you want it removed too.

**Also fixed while narrowing scope:** the admin platform report's summary cards used raw `<span>` elements for label/value instead of the shared `MetricCard` component (`DashboardLayout.jsx`) that every other metric card in the app uses. Spans are inline, so a wrapping label (e.g. "TOTAL HOUSEHOLDS") didn't push the value onto its own line — the big number floated to the right of a two-line label instead of stacking below it. Switched to `<MetricCard>` (which uses block `<p>` elements) and gave `.reports-summary-grid .metric-card` an explicit flex-column layout for defense in depth.

**Files implemented:**
- ✅ `backend/apps/reports/{services,views,urls,tests}.py`, `backend/config/{urls.py,settings/base.py}`
- ✅ `frontend/src/components/ReportsView.jsx` (now admin-only, uses `MetricCard`), `services/backendDataService.js`, `hooks/useGawaGoNavigation.js`, `components/AppViews.jsx`, `components/DashboardLayout.jsx`, `styles/analytics.css`
- ✅ `mobile/lib/src/features/reports/report_repository.dart` (now platform-only), `mobile/lib/src/shared/widgets/report_view.dart`, `household_home_screen.dart`, `worker_home_screen.dart`

---

### 19. Report an Issue — Complaint Flow Rebuilt
**Impact:** Dispute Resolution
**Status:** ✅ COMPLETED

**Problem:** "Reports" was initially built (see #18) as an activity/earnings summary, but that's not what a household means by "report an issue" when e.g. a worker did something wrong — that's an incident report that should reach admin. The pre-existing Complaint backend (`apps/complaints`, panelist feedback #6) was never actually wired up to be usable: the respondent was never set (any complaint's `respondent_username` came back empty — nobody knew who a complaint was about), only households could file (no worker-side button existed anywhere), no admin screen existed on either web or mobile to see or act on filed complaints despite the endpoints existing, and the only job picker only offered completed/hired jobs.

**Implementation Details:**
- ✅ Backend: `ComplaintCreateView` now requires a `job` and derives the `respondent` server-side — a household names which applicant the report is about (validated to actually have an application on that job, at any status), a worker's report always targets that job's household (client-supplied `respondent` is ignored for workers). An unrelated user gets 403.
- ✅ `ComplaintUpdateAdminView` validates `status` against real choices (400 on garbage) and notifies the complainant — not the respondent — when status changes, preserving the "handled confidentially" promise.
- ✅ Web: `ComplaintModal.jsx` rebuilt self-contained (job + role + applicants props, own submit/validation), reachable from both household (`AppViews.jsx` job detail) and worker (`WorkerJobDetailView.jsx`, new) job detail screens, at any job status. Added `MyComplaintsView.jsx` ("My Reports" nav entry, every sidebar) to check status, and `AdminComplaintsQueue.jsx` as its own superadmin tab ("Reported Issues") — distinct from the "Reports" activity tab, answering the "why do admin and user reports look the same" question: they don't, one is a work queue, the other a personal summary.
- ✅ Mobile: new `features/complaints/` (models, repository), `shared/widgets/report_issue_dialog.dart` and `my_complaints_view.dart` wired into both household and worker home screens as a "My Reports" page plus a "Report an Issue" button on each job detail screen, and `features/complaints/presentation/admin_complaints_queue.dart` as an admin tab gated on `isSuperAdmin` (matching the backend's `IsPlatformSuperAdmin` requirement — a plain admin account would only get 403s).
- ✅ Fixed a mobile-only gap found while wiring this up: `HouseholdApplication` had no `workerId` field (only the application's own `id`), so there was no way to identify which user a household's applicant actually was — needed to name a respondent. Added `workerId` from the JSON `worker` field.

**Files implemented:**
- ✅ `backend/apps/complaints/{views,serializers,tests}.py`
- ✅ `frontend/src/components/ComplaintModal.jsx`, `MyComplaintsView.jsx`, `AdminComplaintsQueue.jsx`, `WorkerJobDetailView.jsx`, `AppViews.jsx`, `App.jsx`, `hooks/useGawaGoNavigation.js`, `services/backendDataService.js`, `utils/normalizers.js`, `components/SuperAdminDashboardView.jsx`, `components/DashboardLayout.jsx`
- ✅ `mobile/lib/src/features/complaints/`, `mobile/lib/src/shared/widgets/{report_issue_dialog,my_complaints_view}.dart`, `mobile/lib/src/features/household/data/household_models.dart`, `household_home_screen.dart`, `worker_home_screen.dart`, `admin_home_screen.dart`
- ✅ `docs/api/README.md`, `AGENTS.md` II.D

---

### 20. Bug Fixes Found While Building The Above
**Status:** ✅ COMPLETED

Three endpoints were dead or broken and sat directly in the path of the parity work:
- ✅ `VerificationDocumentSerializer` was used in `accounts/views.py` but never imported — every `/api/accounts/*/verification-documents/` call raised `NameError`. Added the import.
- ✅ `SkillRatingView.post()` took no `job_id` while its URL passed one (`TypeError`), and its serializer omitted the required `worker` field entirely. Now takes `job_id`, derives `worker` from the rated skill, **verifies the household owns the job**, and requires the job to be `completed`. `job`/`worker` are read-only so a household cannot attribute a rating to an unrelated job or worker.
- ✅ `ComplaintSerializer` referenced `job.serviceType` and `job.barangay`, which do not exist on `JobPosting` — any complaint attached to a job broke serialization. Now uses `job.job_type` / `job.title` / `job.location_label`.

---

### 21. Post-a-Job Matching Animation + The Dead Air Behind It
**Impact:** User Experience
**Status:** ✅ COMPLETED

**Problem:** Workers got an AI "scanning" animation from *Find Jobs for Me*, but households got nothing after posting a job. Investigating that surfaced the real issue: `handleHouseholdJobSubmit` **awaited** `refreshRecommendedWorkers` *before* navigating, and that endpoint takes ~10s on a job's first call (per-candidate road-route lookups against an external routing service, no short timeout). So posting a job left the household staring at the unchanged form for ten seconds with zero feedback.

**Implementation Details:**
- ✅ Navigation now happens *before* the matching fetch, so the scan animation covers the wait instead of playing after it.
- ✅ Scan holds while `recommendedWorkersLoading` is true (min 2.4s, 25s hard cap) rather than a fixed timer, so it tracks the real request.
- ✅ Tags are drawn from the job itself (service type, barangay, schedule, rate) and laid out in bands so they stay legible instead of overlapping.

**Files implemented:**
- ✅ `frontend/src/components/AppViews.jsx`, `hooks/useBackendSync.js` (new `recommendedWorkersLoading` flag), `hooks/useGawaGoActions.js`, `App.jsx`

---

### 22. Skill-Rating Flow — Three Broken Paths, Then Unified
**Impact:** Trust System
**Status:** ✅ COMPLETED

**Problem:** There were three separate skill/review UIs, two of which silently did nothing:
- `SkillRatingForm.jsx` called `apiRequest(path, "POST", body)` — a positional signature that does not exist. The method fell back to `GET` and the body was dropped, so **ratings were never saved while the UI still alerted "Skills rated successfully!"**. It also read `response.skills` off an unparsed `Response`, so the skill list always rendered empty.
- The Dashboard "Rate Worker" modal POSTed to `jobs/skill-ratings/` (**404 — no such route**; the real one is `accounts/jobs/<job_id>/skill-ratings/`) and sent `skill: "skill_0"`, a positional array-index string rather than a real skill id.
- The two household review forms collected different fields: the My Jobs one had Quality of Work / Punctuality / Communication / Professionalism; the Dashboard one had only an overall rating.

**Implementation Details:**
- ✅ Both clients fixed to the real `apiRequest(path, options)` signature, correct endpoint, and real skill ids; errors now surface via `getApiErrorMessage` instead of a blanket success alert.
- ✅ Review metrics extracted into one shared `renderHouseholdReviewMetricInputs()` used by **both** review forms, so the same feedback is collected either way.
- ✅ A job's own service type is now always offered as a rateable row even when the worker never listed it — previously you could not rate the very work you hired someone for. Backend accepts `skill_name` + `worker_id` and creates the `WorkerSkill` on the completed worker.
- ✅ "+ Add another skill to rate" picker for work done outside the posted scope (hired to plumb, also fixed a light). Each skill keeps its own average on the worker's portfolio.
- ✅ **Authorization gap closed:** a client-supplied `skill` id was never checked against the job, so a household could attach a rating to a worker who never worked it. Now rejected with 403. Covered by `SkillRatingPermissionTests`.

**Files implemented:**
- ✅ `backend/apps/accounts/{views,serializers,tests}.py`
- ✅ `frontend/src/components/{SkillRatingForm,AppViews}.jsx`, `frontend/src/App.jsx`

---

### 23. Security Hardening
**Impact:** Platform Security
**Status:** ✅ COMPLETED (2 follow-ups noted)

**Problem:** An audit found the account-security layer thin: no brute-force protection, no password rules, and no way to invalidate a stolen token.

**Implementation Details:**
- ✅ **401 vs 403:** `JWTAuthentication` never implemented `authenticate_header()`, so DRF downgraded `NotAuthenticated` to **403**. The web client only reacts to `401`, so an expired session silently failed instead of logging the user out. Adding the method fixed the whole auth-expiry UX on web *and* mobile (mobile already handled 401 correctly). 13 tests asserting the old 403 were corrected.
- ✅ **Rate limiting:** `ScopedRateThrottle` on login (10/min per IP) and the password-reset family (5/min). Verified live — attempts 1-10 return 400, 11+ return 429.
- ✅ **Password validators:** `AUTH_PASSWORD_VALIDATORS` was absent entirely, so the existing `validate_password()` call was a no-op. Added (min 8, not common, not all-numeric, not similar to username) and wired into `RegisterSerializer`, which had *no* password validation at all.
- ✅ **Token revocation:** JWTs now carry `jti` + `iat`. New `RevokedToken` table blacklists a token on logout; `UserProfile.credentials_updated_at` invalidates every token issued before a password change. `LogoutView` was previously a no-op that flushed an unused Django session — and the web client never even called it. Both fixed. Backward compatible: pre-existing tokens without `jti`/`iat` still authenticate.
- ✅ **CSP:** added to `frontend/index.html` (blocks injected inline scripts/eval — the actual XSS execution vector) and a `ContentSecurityPolicyMiddleware` for Django-rendered HTML (admin/DRF). Verified in-browser that Leaflet, OSM tiles, and Google Fonts still load with zero violations.
- ✅ **Object-level authorization audit:** walked every endpoint taking an object id. Worker-owned mutations (skills, certifications, portfolio items, documents) and notifications are all correctly scoped to `request.user`; admin review endpoints are correctly staff-gated. One real gap found and fixed — see #22.

**Known, deliberately not changed:**
- ⚠️ `LoginView` reactivates an `is_active=False` account on a correct password (`test_login_activates_existing_inactive_account_with_valid_password` locks this in for legacy accounts). Harmless today because **nothing in the codebase sets `is_active=False`** — but if a ban/suspend feature is ever built, it must **not** reuse `is_active`, or this will silently undo it.
- ⏳ Stateless JWT means a revoked token is only checked against the blacklist; there is no refresh-token rotation. Logout revokes the current device's token only.

**Files implemented:**
- ✅ `backend/apps/common/{authentication,models,middleware}.py`, `backend/apps/accounts/{views,serializers,models,tests}.py`, `backend/config/settings/base.py`
- ✅ `frontend/index.html`, `frontend/src/hooks/useGawaGoNavigation.js`

---

### 24. PostgreSQL Migration
**Impact:** Infrastructure
**Status:** ✅ COMPLETED

**Problem:** Settings only supported SQLite (dev) and MySQL. Despite the MySQL config, no `.env` existed, so `DJANGO_USE_SQLITE_FOR_DEV` defaulted to `True` — the app had actually been running on a 41MB `dev-db.sqlite3` the whole time.

**Implementation Details:**
- ✅ New `DJANGO_DB_ENGINE` env var (`mysql` | `postgresql`), **defaulting to `mysql`** so existing setups are unaffected. Port default follows the engine (3306 / 5432).
- ✅ `psycopg[binary]` added to `requirements.txt`; `.env.example` documents the new setting.
- ✅ All 68 migrations applied cleanly to a fresh `gawago` database. Verified `connection.vendor == "postgresql"` against the live server, not just assumed.
- ✅ Note: `manage.py test` still forces SQLite (`"test" in sys.argv`) by design for fast CI — so the test suite does **not** exercise Postgres.
- ✅ Stale `dev-db.sqlite3` / `db.sqlite3` removed. A pre-migration JSON dump is retained at `backups/`.

**Gotcha worth remembering:** PostgreSQL 15+ no longer grants schema rights via `GRANT ALL PRIVILEGES ON DATABASE`. `GRANT ALL ON SCHEMA public TO gawago_user;` is required separately or `migrate` fails with "permission denied for schema public".

---

### 25. Mobile Parity Check
**Impact:** Mobile UX
**Status:** ✅ COMPLETED

The security work is server-side, so mobile inherits it automatically — mobile already treated 401 as session-expired and auto-logged out, and it has no registration screen, so the new password rules need no mobile UI. One genuine gap found and fixed:
- ✅ **429 had no handling** — it fell into a generic `unknown` error type. Added `ApiErrorType.rateLimited` and a friendly message that extracts the wait time from DRF's throttle response ("Too many attempts. Please wait 42 seconds and try again.") instead of showing its server-log phrasing.

**Files implemented:**
- ✅ `mobile/lib/src/core/errors/api_error.dart`, `mobile/lib/src/core/api/gawago_api.dart`

---

### 26. Photo Evidence on Reports + Admin Account Blocking
**Impact:** Dispute Resolution
**Status:** ✅ COMPLETED

**Problem:** A report was description-only — an admin had to judge "the worker damaged the sink" from text alone, with no way to see it. And having reviewed a report, the admin had no action available beyond setting a status and writing a note; there was no way to actually suspend an abusive account.

**Implementation Details:**
- ✅ New `ComplaintEvidence` model — photos attach to a report (max 5, extension-validated the same way job images are). `ComplaintCreateView` accepts multipart; the JSON path is unchanged when no photo is attached, so existing callers are unaffected.
- ✅ Web and mobile both get a picker with thumbnail previews and per-photo removal before submitting; the admin queue renders the photos (web: click to open full size).
- ✅ **Blocking uses `UserProfile.is_blocked`, deliberately NOT `User.is_active`** — login reactivates any inactive account that supplies the right password (kept for legacy accounts, see #23), which would silently undo every block. This is exactly the landmine flagged in #23, avoided.
- ✅ A block is enforced in `JWTAuthentication` per-request, so it takes effect **immediately on sessions already signed in**, not just at next login. `LoginView` refuses blocked accounts with 403.
- ✅ Admin accounts cannot be blocked from the report queue, blocks are reversible ("Restore"), and the blocked user is notified with the admin's stated reason.

**Verified end-to-end (not just unit-tested):** filed a report with a photo from the real web UI → 201 with the file on disk → signed in as admin → photo visible in the review modal → clicked Block → confirmed `is_blocked=True` in the database and the worker's login refused with 403.

**Files implemented:**
- ✅ `backend/apps/complaints/{models,serializers,views,urls,tests}.py`, `backend/apps/accounts/{models,views}.py`, `backend/apps/common/authentication.py`
- ✅ `frontend/src/components/{ComplaintModal,AdminComplaintsQueue}.jsx`, `services/backendDataService.js`, `utils/normalizers.js`
- ✅ `mobile/lib/src/features/complaints/` (models, repository, admin queue), `mobile/lib/src/shared/widgets/report_issue_dialog.dart`

---

## 🔍 END-TO-END CODEBASE AUDIT (2026-09-16) — Open Issues

A full backend/frontend/mobile sweep (four parallel audits: backend endpoint
connectivity, backend logic/bugs, frontend flow/logic, mobile parity) plus
manual verification of every HIGH-severity claim against the actual code.

**Every 🔴 HIGH, 🟡 MEDIUM and ⚪ LOW item was addressed on 2026-09-16.**
Item #13 turned out not to be cleanup at all but documented features missing
their UI — the admin certificate workflow was built; the duplicate ID-document
system was left for a product decision rather than shipping a second,
competing verification flow. See that entry for what still needs deciding.

### 🔴 HIGH — broken features / silent data loss — ✅ ALL FIXED 2026-09-16

1. ✅ **Worker portfolio had never displayed real data, for any worker, anywhere it's used.** `WorkerPortfolioViewPublic.jsx` did `setPortfolio(response)` directly from `apiRequest(...)`, but `apiRequest` (`frontend/src/api/apiClient.js:93`) returns the **raw, unparsed `fetch` `Response`** — every other caller follows it with `readResponseData(response)`. `Object.keys()` on a raw `Response` always returns `[]` (its fields are prototype getters), so the empty-check was always true and every worker's skills/certifications/work-samples rendered as "No portfolio information yet" regardless of what the backend returned.
   **Fixing it exposed two more bugs behind it**, since the component's display code had literally never executed with real data:
   - `skill.average_rating.toFixed(1)` threw `TypeError` and crashed the component into the ErrorBoundary — DRF serializes `DecimalField` as a **string** (`"5.00"`), which has no `.toFixed()`. Now `Number(...)`-coerced.
   - `.worker-portfolio-public` has `overflow: hidden`, so as a flex item in the modal's flex column it was crushed to a 2px sliver (same root cause as the `.admin-reports-table-card` bug fixed 2026-09-15). Fixed with `flex-shrink: 0`.
   **Verified end-to-end**: worker1's real portfolio ("House Cleaning", beginner, ★ 5.0 from 2 ratings) now renders in the admin profile modal, confirmed against the live API response body.
2. ✅ **`VerificationDocumentView.post` crashed with a 500 on every real submission.** The view set `data["user"] = request.user.id`, but `VerificationDocumentSerializer` marks `"user"` as `read_only`, so DRF silently dropped it from `validated_data`; `VerificationDocument.user` is a non-nullable FK, so `.save()` hit an `IntegrityError`. Now passes `serializer.save(user=request.user)`, matching `WorkerCertificationView.post`. The entire "Multiple ID Types for Verification" upload endpoint (item #12 above) was broken end-to-end with zero test coverage — **3 regression tests added** (`VerificationDocumentUploadTests`), including one asserting a client can't attribute an upload to another user.
3. ✅ **Silent pagination truncation on every list endpoint.** `PAGE_SIZE: 20` globally with no `pagination_class` override anywhere, while `unwrapRecords()` only read `data.results` and never followed `data.next` — so once any collection outgrew 20, the rest silently vanished. Added a `fetchAllRecords()` helper in `backendDataService.js` that follows `next` (bounded at 100 pages), and converted all 7 paginated list fetchers to it: jobs, profiles, notifications, reviews, verification requests, and both complaint queues.
4. ✅ **Mobile: every worker profile save threw a spurious error toast.** `saveWeeklyAvailability()` called `PUT /accounts/me/weekly-availability/`, which does not exist — **the `WorkerWeeklyAvailability` model was deliberately deleted in migration `0009`**. Both clients still carried a weekly-scheduler UI writing to nothing (mobile 404'd; the web silently drops `weekly_availability` in its profile PATCH, since no backend field consumes it). Per product decision, the dead path was removed from mobile: the repository method, the save call, the `WeeklyAvailability` model, the "Add Schedule" dialog and the whole "Weekly availability" form section. Workers keep the working **date-specific** availability editor.
   ⚠️ **Still open**: the web's weekly-availability editor (`useGawaGoNavigation.js:122-163`, `useGawaGoActions.js:962`) is the same dead feature and should get the same treatment.
5. ✅ **Mobile: worker-side AI job matching was entirely unimplemented.** Mobile never called `/matching/recommended-jobs/`. Added `RecommendedJob` model, `WorkerRepository.getRecommendedJobs()`, and a new **"Matched For You"** worker page listing AI-ranked jobs with a `% match` badge, distance, and the two-segment skill-vs-proximity breakdown bar — mirroring the household-side `_AiMatchBreakdown` so both directions of the recommender explain themselves identically. Verified with `flutter analyze` + a debug APK build (not a physical-device run).

### 🟡 MEDIUM — ✅ ALL FIXED 2026-09-16

6. ✅ **Job scheduling fields were write-only.** The post-a-job form collected `jobStartDate`/`jobEndDate`/`estimatedWorkingDays`/`geographicBoundary` (Critical-priority panelist asks, items #3/#4 above) and the backend stored and returned all of them, but `normalizeBackendJob` never read a single one back in — so none of it was ever shown again. All 5 fields are now normalized, and the job period + estimated working days render in three places: the worker's job detail view, the worker-facing job card, and the household dashboard's active-job card.
7. ✅ **`SkillRating.rating` had no range validation**, unlike `Review.rating`. A household could submit `9.9` or a negative value and permanently skew a worker's displayed skill average. The serializer now enforces 1-5, covered by a regression test asserting `9.9`, `0` and `-3` are all rejected.
8. ✅ **`JobCreateSerializer` accepted nonsensical numbers.** `service_rate` now has `min_value=0`, `estimated_working_days` `min_value=1`, and `max_distance_km` `min_value=0.1`, with a test covering all three.
9. ✅ **N+1 external routing calls in list serialization.** `JobApplicationSerializer`/`JobPostingSerializer` resolved a road route per row, each an outbound OSRM/OpenRouteService round-trip on a cache miss. Added `get_cached_road_route()` (cache-only, never calls out) and a `route_lookup` serializer-context flag that the two collection endpoints (`JobApplicationListView`, `JobViewSet.list`) opt into.
   **Detail responses deliberately still resolve live** — a job's detail page has a bounded applicant set and the distance is the point of that screen. An existing test caught the first attempt at this (which keyed off serializer nesting and wrongly downgraded job-detail applicants), so the opt-in is explicit at the view instead. New test asserts the application list makes zero outbound routing calls.
10. ✅ **Mobile suspension was permanent-only.** Mobile now matches the web: Suspend 3 Days / Suspend 7 Days / Block Permanently, a Restore action, and a chip showing `Suspended until <date>` vs `Account blocked (permanent)`. Added `duration_days` to the repository call and `respondentBlockedUntil` to the model.
11. ✅ **Mobile reputation tier / rating-trend badges were absent** — the fields weren't even parsed. `WorkerProfile` now reads `reputation_tier`/`rating_trend` and the worker dashboard's welcome band shows the same badges as the web (⭐ Elite / ✓ Trusted / ◆ Established / ◇ New, plus 📈 Improving / 📉 Declining when not neutral). Covered by two model tests, including the default-fallback case.
12. ✅ **Mobile reviews had only a single overall rating.** The household review form now collects the same 4 optional metrics as the web (quality of work / punctuality / communication / professionalism) via a compact star row each, submits them, and the shared review history renders the breakdown. `GawaGoReview` parses all four.

### ⚪ LOW / cleanup — ✅ FIXED 2026-09-16 (except #13, which needs a decision)

13. ⚠️ **NOT dead code — backend features with no UI. Resolved by building the missing UI, not by deleting.**
    Investigating this reversed the original finding. The "orphaned" endpoints turned out to be **features documented above as COMPLETED that simply had no screen** (verified: zero callers — the only frontend matches were CSS class names).

    ✅ **Admin certificate verification (item #11) is now a real, closed loop.** Workers could already upload certificates (`App.jsx` → `accounts/me/portfolio/certifications/`), but no admin could ever approve them. Added `frontend/src/components/AdminCredentialsQueue.jsx` as a new **"Worker Credentials"** superadmin tab: filter by pending/approved/rejected, view the uploaded file, and approve or reject with a note that reaches the worker as a notification. Backend needed `worker_username` on `WorkerCertificationSerializer` — the queue lists certificates across all workers and previously had no way to say whose was whose. Covered by 4 new tests (`CertificateVerificationAdminTests`), including that a worker gets 403 from the admin queue.

    ⚠️ **The ID-document system (item #12) is a duplicate of the shipped flow — a product decision, deliberately not forced.** There are two identity systems: `common/verification-requests/` (primary + secondary ID) is the one that actually ships with a full worker-submit and admin-review UI, while `accounts/*/verification-documents/` is a separate 8-ID-type implementation with no UI. **Building a second worker-facing upload would have put two competing verification flows in front of users**, so it wasn't done. The new Worker Credentials tab includes a "Government IDs" queue that reads the 8-type system (so it works the moment anything populates it) and its empty state explains where identity is actually collected today. **Decide one way or the other before the defense: either consolidate onto the multi-ID-type system, or drop it.**

    `POST /api/accounts/verify-signup/` was also left alone on purpose: wiring it in would gate registration behind email verification, contradicting the shipped "register then log in immediately" behaviour that `test_registered_worker_can_login_immediately` locks in. That's a product change, not a bug fix.

    Deliberately kept, no action needed: `reports/me/` (already a documented decision in item #18), complaint single-detail retrieve, verification-request detail/document routes, and the portfolio PATCH-in-place endpoints — all harmless REST completeness. The `applications/<str:pk>/status/` "legacy" route is also intentional, not dead: `JobApplicationStatusView` has an explicit `isdigit()` guard so a non-numeric id returns a clean JSON 404 instead of an HTML one.
14. ✅ **Deleted `frontend/src/components/WorkerPortfolioEditView.jsx`.** Confirmed zero importers, and the real portfolio editing lives in `App.jsx` with the correct `apiRequest(path, options)` signature — so workers keep full add/delete of certifications and work samples. The dead file still carried a stub `alert("...coming soon")`, a literal no-op button, and the old 3-arg `apiRequest` bug. Recoverable from git history if ever needed.
15. ✅ **Both admin views now use the shared `IsPlatformAdmin` permission class** instead of hand-rolled `is_staff or is_superuser` checks, removing the divergent second copy of the gating logic.
16. ✅ **Complaint notifications re-typed** from `analytics` to `Notification.TYPE_ACCOUNT_ACTIVITY` (the choice already existed, so no migration).
    **This surfaced a real bug worth more than the rename:** households read their notifications through an *allowlist* of types (workers use a denylist), and neither `analytics` nor `account_activity` was in it — so a household **never saw status updates on reports they filed**, or a block/restore notice. Added `account_activity` to the household allowlist in `App.jsx`, which is what actually makes these notifications reach the person they're addressed to.

---

## 🔍 SECOND END-TO-END AUDIT (2026-09-16, after the fixes above)

A second four-way sweep run once every item from the first audit was fixed,
deliberately aimed at ground the first pass did **not** cover: the apps it
skipped (analytics, reports, reviews, matching internals, settings), the large
frontend mutation hooks, web-versus-mobile divergence, and a regression review
of the first audit's own fixes. Every 🔴 HIGH below was re-verified by hand
against the source before being listed.

### ⚠️ Regressions introduced by the first audit's fixes

- ✅ **FIXED — worker portfolio showed an empty white box instead of the empty state.** `WorkerPortfolioView.get` does `WorkerPortfolio.objects.get_or_create(...)`, so the endpoint *always* returns a populated object (8 keys). Once the response was actually parsed, `Object.keys(portfolio).length === 0` could never be true again, so a worker who has filled nothing in fell through to a bordered box with every section gated off. The original bug had masked this, because `Object.keys()` on an unparsed `Response` is always `[]`. Emptiness is now judged on real content (bio, years, skills, certifications, work samples). The same fix un-nested `years_experience`, which was previously invisible whenever `bio` was blank.
- ⏳ **"Road distance unavailable" now appears across Find Jobs — still needs a decision, not fixed.** Making list endpoints cache-only removed the N+1 outbound routing calls, but `RouteDistanceCache` is only ever populated by the recommender, so any job it never scored now renders `getWorkerJobDistanceLabel`'s failure string (`AppViews.jsx:329-336`) where a real distance used to show. There is no haversine helper anywhere in the backend. Options: (a) add a free straight-line estimate, clearly labelled approximate; (b) soften the UI text so a not-yet-computed distance doesn't read as an error; (c) accept it. This is a product tradeoff rather than a defect, left for a decision.
- ✅ **FIXED — `fetchAllRecords` silently truncated on a mid-pagination failure.** It returned `page === 1 ? null : records`, so a 500 on page 2 yielded a short list indistinguishable from a complete one. Now any page failure returns `null`, matching every caller's existing "keep current state, don't overwrite with less" contract. `MAX_PAGES` truncation is unchanged (a real 2000+ record collection is implausible here) but now logs a `console.warn` so it's visible if it ever happens. Verified with 4 isolated unit checks against the extracted logic (page-1 failure, page-2 failure, full success, bare-array response) — all pass.
- ✅ **FIXED — latent 500 on `GET me/verification-documents/<doc_id>/` and `admin/certificates/<cert_id>/`.** `get(self, request)` took no id argument, so Django's routing would raise `TypeError` the moment anything called GET on the detail URL (both were reachable only via DELETE/PATCH until now). All three affected views (`VerificationDocumentView`, `VerificationDocumentAdminView`, `CertificateVerificationAdminView`) now accept an optional id and return the single record, matching normal REST semantics, with a 404 (not 500) when the id doesn't exist or belongs to someone else. 6 new regression tests; the existing list-view tests still pass, confirming the optional parameter didn't disturb the collection routes.
- ⏳ Switching the two admin views to `IsPlatformAdmin` narrowed access from `is_staff or is_superuser` to `is_staff` only. No code path in the repo creates a superuser without staff, so this is equivalent today — noted because it is a real narrowing, not something to fix without a reason to.

### 🔴 HIGH — ✅ ALL FIXED 2026-09-16

1. ✅ **The automatic 3.5-star rating no longer blocks the household's real review.** Added `Review.is_system_generated` (migration `0007_review_is_system_generated`), set `True` only by `assign_default_worker_ratings`. `ReviewListCreateView.post` now rejects a duplicate only when the existing review is real; when it's the placeholder, the real review **replaces it in place** (same row, `is_system_generated` cleared, `200` instead of `201`) rather than being turned away. New tests: a household can still submit a real review after the default was assigned, and the profile's average rating updates to reflect it. 20/20 review tests pass.
2. ✅ **`GET /api/reviews/` no longer performs unbounded writes on every call.** Kept `AllowAny` (reviews are meant to be publicly readable) but gated the `assign_due_default_worker_ratings()` sweep behind a cache lock (`cache.add`, 5-minute cooldown) — the first caller in the window still triggers it (preserving the "self-heals on read" behavior an existing test locks in), but a looped anonymous client can no longer force the sweep to re-run on every request. New test asserts a second immediate call does nothing.
3. ✅ **CSV report export now escapes formula-triggering cells.** Added `_csv_safe()` in `reports/services.py` — any cell starting with `=`, `+`, `-`, `@`, tab or CR is prefixed with `'`, neutralizing it in Excel/Sheets while leaving it readable. Verified with a unit test covering all five trigger characters and an integration test that renames a worker to `=cmd|'/c calc'!A1` and confirms the real CSV export escapes it end-to-end.
4. ✅ **Households now see hire-request accept/reject notifications.** Added `accepted` and `rejection` to the household notification allowlist in `App.jsx` — the exact strings the backend already sends via `TYPE_ACCEPTED`/`TYPE_REJECTION`, confirmed against `notifications/models.py` and traced through `normalizeBackendNotification` end-to-end.
5. ✅ **Mobile now follows DRF pagination.** `GawaGoApi.getList` follows `next` across pages (bounded at 100, matching the web fix) instead of returning only the first page's `results`. New test drives a 2-page mock response and confirms all records are collected and the second request hits the exact `next` URL.
6. ✅ **Mobile job posting now sends its own radius.** Added a `max_distance_km` lookup mirroring the web client's `distanceKmMap` (`1km`→1.0 … `unlimited`→999999), sent alongside `geographic_boundary` so a "10km" job actually matches workers within 10 km on mobile too.
7. ✅ **Mobile admins can now view the actual ID document before approving.** Added `GawaGoApi.getBytes()` (an authenticated raw-bytes fetch — `Image.network` has no way to attach the bearer token an `IsAuthenticated` file route requires) and a "View" button on each document row that fetches and displays it in a full-screen image viewer. Two new API tests cover the auth header and the error path.
8. ✅ **`SECRET_KEY` placeholder can no longer boot with `DEBUG=False`.** `config/settings/base.py` now raises `ImproperlyConfigured` if `DJANGO_SECRET_KEY` is still the well-known default while debug is off — closing the gap where `DJANGO_SETTINGS_MODULE=config.settings.base` (bypassing `production.py`'s own check) could otherwise sign live JWTs with a key anyone can find in this repo. Verified the exact scenario is now blocked, and that normal `.env`-backed startup (`manage.py check`) is unaffected.
9. ✅ **Worker review replies now carry the correct `job_id`.** `normalizeReview` was silently dropping the `jobId` field `normalizeBackendReview` computed for it — a one-line fix. Also removed the `selectedJob?.id` fallback in `useGawaGoActions.js`, which would have guessed the wrong job now that the real value is available; the handler now refuses with a clear message instead of silently misattributing a reply.
10. ✅ **Post-a-job can no longer be double-submitted.** Added a `useRef`-backed guard in `useGawaGoActions.js` (a plain closure variable would reset on the re-render that `resolveLocationCoordinates`'s multi-second geocode round-trip is likely to trigger, defeating the guard exactly when it matters) plus a real `isSubmittingJob` state threaded through to disable the Post Job button and show "Posting..." while the request is in flight.
    ⚠️ **Not exercised live**: verified by code trace, a clean build, and a zero-console-error smoke test on the shared files this touched (`App.jsx`, `AppViews.jsx`, `useGawaGoActions.js`), but not with an actual double-click through a verified household account — flag this if you want it double-checked live before a demo.

### 🟡 MEDIUM — ✅ ALL FIXED 2026-09-16

11. ✅ **Metrics-only reviews now count toward the average.** `recalculate_user_rating` filters on `Q(rating__isnull=False) | Q(quality_of_work__isnull=False) | ...` instead of just `rating`, and sums `effective_review_rating()` per review — so a review scored only on the four metrics (no overall star) is no longer silently dropped. Also fixed the adjacent bug where the auto-assigned 3.5-star placeholder blocked a household from ever submitting a real review: `Review` gained `is_system_generated`, and `POST /reviews/` now updates the placeholder in place (200) instead of rejecting the request (400) when the existing review is system-generated. Covered by 3 new tests in `apps/reviews/tests.py`; all 24 tests in the app pass.
12. ✅ **The four review metrics now render on web.** `normalizeReview`/`normalizeBackendReview` (`normalizers.js`) now carry `qualityOfWork`, `punctuality`, `communication`, `professionalism` and `overallRating` through to the UI, and the one display block reading them in `AppViews.jsx` was fixed from stale snake_case (`review.quality_of_work`) to the camelCase fields the normalizer actually produces — it was silently matching nothing before. Verified live via Playwright against a review with metrics.
13. ✅ **`jobMatchRate` can no longer exceed 100%.** `reports/services.py` now intersects hired-application job IDs against the actual in-period job ID set (`matched_job_ids = {app.job_id for app in hired if app.job_id in job_list_ids}`) instead of counting every hire regardless of when its job was posted. New test asserts the rate is capped even when hires reference jobs outside the report window.
14. ✅ **Rating trend no longer flips on a single review.** `calculate_rating_trend` now requires at least 2 reviews in *each* window (added `RATING_TREND_MIN_SAMPLES_PER_WINDOW = 2`) before returning "improving"/"declining", otherwise "neutral". Also fixed the staleness half of the bug: `GET /reviews/` now opportunistically recomputes the target user's reputation (cooldown-gated per user, same `cache.add()` pattern as the sweep below) so a dormant worker's badge self-heals on next view instead of staying stale indefinitely. 3 new tests in `RatingTrendTests`.
15. ✅ **The two rankers now agree on `unlimited` boundaries.** Moved `DISTANCE_UNLIMITED` into `matching/services.py` and made `build_match_results` treat `geographic_boundary == "unlimited"` the same way `_within_radius()` in `recommendations.py` already did — `max_distance_km` is ignored when the boundary is unlimited, in both rankers now. New test drives a job configured `unlimited` + a small `max_distance_km` and confirms a distant worker still matches. Root cause shared with the already-fixed HIGH #6.
16. ✅ **Exact skill matches bypass the multi-skill dilution penalty.** `matching/signals.py` now notifies when `ai_score >= threshold OR exact_skill_match`, so a worker with an exact skill match is notified regardless of how much cosine similarity a longer skill list dilutes — radius is still enforced upstream. New test: a 4-skill worker with an exact match at 5 km (ai_score ≈0.40, below the 0.5 threshold) is still notified.
17. ✅ **SMTP calls can no longer hang a request indefinitely.** Added `EMAIL_TIMEOUT` (default 10s, overridable via `EMAIL_TIMEOUT_SECONDS`) to `config/settings/base.py`. New test confirms `get_connection().timeout` picks it up.
18. ✅ **AI ranking is no longer clobbered by the background poll.** `useBackendPolling`'s recommended-workers effect now passes `rank="ai"` only while `view === "household-job-matches"` (matching what the initiating screen requested) instead of always refetching with no `rank`, which previously overwrote the AI-ranked result with the default smart ranking a moment later.
19. ✅ **Failure paths report failure.** `handleAdminApproveVerification`/`handleAdminRejectVerification`/`handleVerificationSubmit` in `useGawaGoActions.js` now show an explicit "Unable to ... Please try again." message on the catch branch and no longer navigate away or claim success when the request actually failed.
20. ✅ **Polling can no longer repaint a previous account's data.** `useBackendSync.js` now captures `currentUserRef` (a ref, since a plain closure variable goes stale across the re-renders an in-flight `await` survives) and re-checks it immediately before each commit in `refreshVerificationStateFromBackend`, `refreshJobsFromBackend`, `refreshNotificationsFromBackend`, and `refreshReviewsFromBackend` — a response for a since-logged-out or since-switched account is now discarded instead of applied.
21. ✅ **The household review modal now waits for the POST before closing.** `handleHouseholdReviewSubmit` is now `async` and returns `true`/`false`; the modal's `onSubmit` awaits it and only calls `closeDashboardModal()` on success, so a failed submit leaves the form open with its data intact instead of vanishing before the error is visible.
22. ✅ **Confirmation added to the three remaining irreversible actions.** `window.confirm(...)` guards now wrap rejecting an applicant (both call sites), confirming job completion, and rejecting a hire request (mobile's `WorkerJobDetailView.jsx` too), matching the existing guard on job cancellation.
23. ✅ **`avg_rating` is now weighted by review count.** Both `reports/services.py` and `analytics/services.py` replaced `Avg("average_rating")` (an unweighted mean of means) with `Sum(F("average_rating") * F("rating_count")) / Sum("rating_count")`, so a worker with 200 reviews counts 200× more than one with a single review. New weighted-average tests in both apps.
24. ✅ **Mobile worker→household reviews now send all four metrics.** `WorkerRepository.reviewHousehold()` gained optional `qualityOfWork`/`punctuality`/`communication`/`professionalism` params (sent via Dart's null-aware map spread), and `worker_home_screen.dart`'s review dialog now has 4 additional dropdowns feeding them through — matching the web worker form.
25. ✅ **Mobile can no longer confirm completion before the worker marks the job done.** `household_home_screen.dart`'s `onConfirmCompleted`/`canConfirm` now require `job.status == 'completion_requested'` (removed the `|| job.status == 'assigned'` branch, in both places), with a new "You'll be notified once the worker marks this job done." message shown while `assigned`.
26. ✅ **Mobile multipart uploads now get the same friendly-error classification as every other request.** `multipartPost`, `multipartPostMany`, and `multipartPatch` in `gawago_api.dart` now route through the existing `_send()` helper instead of calling `_client.send()` directly, so a dropped connection during an image/document upload surfaces as a classified network error instead of raw `SocketException` text. New test throws `http.ClientException` from a mocked multipart upload and asserts `ApiException.isNetworkError`.
27. ✅ **Mobile job posting now caps images at 5 × 5 MB, matching web.** `household_home_screen.dart`'s `_pickImages()` now rejects individual files over 5 MB and trims the selection to 5 images, with a message naming whichever oversized files were skipped.
28. ✅ **Mobile's "Forgot your password?" now opens the full reset flow.** Added `GawaGoApi.requestPasswordReset()`/`resetPassword()` (mirroring the web `/accounts/forgot-password/` and `/accounts/reset-password/` calls) and a 2-step dialog in `_LoginPanelState` (email → code + new password) wired to the button, replacing the dead `onPressed: () {}`. `reset-password` validates the code itself, so there's no separate verify-token round trip.

### ⚪ LOW — ✅ ALL FIXED 2026-09-16

29. ✅ **Review notifications now use `TYPE_ACCOUNT_ACTIVITY`**, the same mistyping fix already applied to complaints in LOW #16. The web household allowlist's fragile `item.title === "New feedback received"` fallback (needed only because the type didn't match) was removed now that the type itself is correct.
30. ✅ **Suspended or logged-out workers no longer receive match notifications.** `notify_matching_workers` now filters `user__is_active=True` and excludes anyone currently blocked (permanent, or a timed suspension still in effect) — an `is_blocked=True` filter alone would have also skipped a worker whose timed block already expired but hasn't been lazily cleared yet, so the exclusion checks `blocked_until` directly instead. New test covers all four cases: permanently blocked, still-timed-blocked, and inactive are excluded; expired-but-not-yet-cleared is still notified.
31. ✅ **Rating distribution rounds half up, not to even.** Added `_round_half_up()` (clamped to 1-5) so 4.5 and 2.5 bucket the way a reader expects, and a sub-0.5 average (a data anomaly) lands in the 1-star bucket instead of vanishing from the chart. New `RatingDistributionRoundingTests`; the existing dashboard test's fixture (a 4.50-rated worker) was previously asserting the old, wrong 4-star bucket and now asserts 5-star.
32. ✅ **`CORS_ALLOWED_ORIGINS` now strips whitespace**, matching the `ALLOWED_HOSTS` pattern already used one line above it — a space after a comma in the env var no longer silently drops that origin.
33. ✅ **Monthly report buckets now follow the requested window.** `_month_buckets` computes the span between `period["start"]` and `period["end"]` and sizes the bucket count to it (clamped to 6-24 months) instead of a fixed 6, so a custom range longer than 6 months no longer drops everything before the trailing 6 months from the chart. New `MonthlyBucketTests` cover the default window, a 1-year window, and an extreme 10-year window hitting the cap.
34. ✅ **Removed the dead weekly-availability path end-to-end**, matching mobile's earlier HIGH #4 removal: deleted `normalizeWeeklyAvailabilityWindow`, the duplicate `profilePhotoPreview` key and both `weekly_availability` reads in `normalizers.js`, and the now-pointless `weeklyAvailability` threading through `useGawaGoActions.js` and `useGawaGoNavigation.js` (a computed 7-day form array that nothing rendered). Also removed the stale `weekly_availability` fixture key from `mobile/test/features/role_workflow_test.dart`.
35. ✅ **Turned out to be a real bug, not just dead reads — fixed with a new field.** `registeredHouseholds`/`registeredWorkers` never had phone/email because `PublicUserProfileSerializer` always withholds them, which meant the worker job-detail screen's "contact details become available after you are hired" promise had nothing behind it — it always showed "Contact details not provided" even to a hired worker. Added `household_phone`/`household_email` to `JobApplicationSerializer`, gated to the hired worker viewing their own application (`status` is `hired` or `completed`, and `worker_id == request.user.id`), and wired the web UI to read them from the job's `currentWorkerApplication` instead of the (correctly still redacted) profile record. 3 new tests cover hidden-before-hire, visible-once-hired, and never-leaks-to-a-different-applicant.
36. ✅ **Removed `openHouseholdNotificationWorker` entirely** (from `useGawaGoNavigation.js`, `App.jsx`, and `AppViews.jsx`) — dead code with no call site, and broken besides (read `notification.workerId`, which doesn't exist; the normalizer produces `actorId`).
37. ✅ **Mobile's admin report queue now shows full account context.** Added `ComplaintPartyDetail` (mirroring `_party_detail()`) and parsed `complainant_detail`/`respondent_detail` in `ComplaintReport.fromJson`; the queue row and review sheet now show each party's display name, rating, barangay, member-since date, phone and email instead of a bare username. Also fixed `GawaGoReview.fromJson` to fall back to `overall_rating` when `rating` is null (a metrics-only review), and gave the worker-location-picker's "Pin on Map Manually" button (`gawago_app.dart`) a real `onPressed` — it was `null`, permanently disabled, even though the map's own `onTap` already places a pin unconditionally. New tests for the complaint detail parsing and the review rating fallback.
38. ✅ **`rank=smart` no longer pays for the AI scoring pass.** `_build_response` now only calls `_merge_ai_scores` (which runs the full content-based scorer) when `rank == "ai"`; otherwise a new `_default_ai_fields` fills the same zero-score defaults directly. New test mocks `get_recommended_workers` and asserts it's never called for the default/smart rank, only for `rank=ai`.
39. ✅ **`_WorkerMyReports` converted to a `StatefulWidget`** caching its `getProfile()` future in `initState`-equivalent field init, matching the existing `_WorkerApplicationsState` pattern — the profile is now fetched once per screen visit instead of on every parent rebuild.

### Cross-cutting themes

- **The notification type filter is a recurring defect source.** Households read notifications through an *allowlist* of types while workers use a denylist, so every new notification type is invisible to households until someone remembers to add it. That produced two separate bugs (LOW #16 and HIGH #4) plus the #29 mistyping fixed above — the filter is still hand-maintained and worth inverting or deriving from the backend's own type list at some point.
- **The same bug class often exists on both clients but gets fixed on one.** DRF pagination was fixed on web and is still live on mobile (HIGH #5); the radius mapping is correct on web and missing on mobile (HIGH #6); the weekly-availability dead code was removed from mobile in HIGH #4 well before web caught up in #34 above. Worth checking the other client whenever one is fixed.
- **Rendering paths that have never run against real data are where crashes hide.** The portfolio component crashed on `.toFixed()` the first time real data reached it, then showed a blank box for the empty case. `AdminCredentialsQueue.jsx` has the same exposure — both its queues were empty in the dev database, so its row rendering is still unproven against live records. (Unresolved — noted for the next pass.)

---

## 📋 DOCUMENTATION UPDATES

### Update AGENTS.md:
- [x] Add "Post a New Job" to Functional Requirements — already covered under I.A
- [x] Clarify Scope & Limitations (specify worker types, geographic area) — already covered under V
- [x] Document AI-based matching approach — added new I.C section describing the content-based recommender, pull/push delivery, and explainability breakdown; corrected V's outdated "not implemented" claim; added a Definition of Terms entry
- [x] Explain proximity range justification — already covered under V
- [x] Define reputation scoring criteria — already covered under II.A
- [x] Add portfolio feature details — already covered under II.C

### Update Architecture Docs:
- [x] Database schema changes — added the `job_match` notification type to `GawaGo_Current_Database_Schema.dbml` and the database dictionary (no new tables; AI matching only added a notification type choice)
- [x] API endpoint documentation — added `GET /api/matching/recommended-jobs/` to `docs/api/README.md`
- [x] Matching algorithm explanation — covered by the new AGENTS.md I.C section and the API doc entry above
- [x] Reputation calculation logic — already covered by AGENTS.md II.A and the `accounts_userprofile` dictionary entry; no changes needed

---

## 🎯 Implementation Strategy

### Phase 1 (This Week - Critical)
- [x] Job start/end dates
- [x] Distance boundaries
- [x] Application status terminology
- [x] Worker verification before ratings

### Phase 2 (Next Week - High Priority)
- [x] Worker portfolio feature
- [x] Complaint/issue system
- [x] Employment history tracking
- [x] Complete notifications

### Phase 3 (Following Week - Polish)
- [x] Enhanced analytics
- [x] Rating metrics
- [x] Reputation scoring
- [x] UI/UX improvements (bug fixes + clutter reduction complete across household, worker, and superadmin views)

### Phase 4 (Later - Advanced)
- [x] AI matching — content-based recommender (pull + push) + explainability breakdown done; learning from history still pending
- [x] Certification uploads
- [x] Multiple ID types

---

## 📊 Quick Reference by Panelist

**Ma'am Borella** (Focus: Trust & Analytics)
- Worker verification before ratings ✅ COMPLETED
- Application status terminology ✅ CRITICAL
- Job start/end dates ✅ CRITICAL
- Multiple ID types ✅ COMPLETED
- Dashboard analytics ✅ COMPLETED
- E-commerce rating metrics ✅ COMPLETED
- Certification uploads ✅ COMPLETED

**Sir LA** (Focus: UX & Features)
- Lighter UI/UX design ✅ COMPLETED
- Complaint/issue reporting ✅ HIGH
- Worker portfolio ✅ HIGH
- AI-based job matching 🔶 IN PROGRESS (recommender + explainability done, learning from history pending)

**Sir NJ** (Focus: Geographic & Tracking)
- Distance boundaries ✅ CRITICAL
- Employment history ✅ COMPLETED
- Notifications ✅ HIGH
- Enhanced reputation scoring ✅ COMPLETED
- Estimated working days ✅ CRITICAL

---

## 🚀 Success Criteria

When these improvements are complete:
- ✅ Trust system is robust (verification, history, ratings)
- ✅ Job matching is more accurate (distance, portfolio, AI)
- ✅ Users stay engaged (notifications, complaints, history)
- ✅ Data is transparent (analytics, reputation tiers)
- ✅ UI is intuitive and responsive
- ✅ Documentation explains all systems clearly

---

---

## ✅ PORTFOLIO FEATURE - COMPLETED (September 2-3, 2026)

**7 Components Fully Implemented:**
1. ✅ **Skills & Expertise** - Grid display of worker skills with badges
2. ✅ **Certifications** - Certificate image uploads with gallery view
3. ✅ **Work Samples** - Before/After images with side-by-side comparison
4. ✅ **Portfolio Gallery** - Full-screen "View More" section showing all portfolios
5. ✅ **Employment History** - Track completed jobs with household info and ratings
6. ✅ **Skill Ratings Display** - Show individual skill ratings from households
7. ✅ **Household Rating Interface** - Households can rate workers on specific skills after job completion

**UI Improvements:**
- ✅ Consistent color palette (green success, dark labels)
- ✅ Before/After labels in corners (not center)
- ✅ Clickable images to expand in modals
- ✅ Star-based rating interface (1-5 stars)
- ✅ Automatic overall rating calculation

**Backend Integration:**
- ✅ FormData for image uploads (Certifications, Work Samples)
- ✅ SkillRating API for submitting household ratings
- ✅ Employment History fetched from completed jobs
- ✅ Data persists after refresh

**Files Modified:**
- Frontend: `App.jsx`, `AppViews.jsx`
- Backend: Existing models `WorkerCertification`, `WorkerPortfolioItem`, `SkillRating`

---

**Last Updated:** September 16, 2026  
**Status:** Portfolio feature complete ✅ | AI job-match recommender complete in both directions, now including mobile's worker-side "Matched For You" screen ✅ | Admin Dashboard split from Analytics ✅ | Role activity reports with CSV export ✅ | Report-an-issue complaint flow with photo evidence, plus timed (3/7-day) and permanent account suspension on web and mobile ✅ | Admin certificate review queue shipped ✅ | Superadmin User Management directory shipped (Sept 16) — a platform-wide household/worker browser with the suspend/restore action generalized off the complaint-review queue ✅ | Architecture docs reconciled against the models (Sept 16) ✅ | Development roadmap active

**Audit state (Sept 16):** the first end-to-end audit is fully closed — all HIGH, MEDIUM and LOW items fixed, except #13, which was reclassified as a product decision about two duplicate identity-verification systems (resolved by building the missing admin certificate UI; the duplicate ID-document system was deliberately left rather than shipping a second, competing worker upload). The second audit is now **fully closed** too — its regressions, all 10 HIGH items, all 18 MEDIUM items, and all 11 LOW items are fixed; see their sections above for what changed and how each was verified. Its cross-cutting themes (the notification allowlist as a recurring defect source, fixes landing on one client but not the other, untested render paths hiding crashes) are noted but not independently tracked as action items — the notification allowlist theme is meaningfully improved by the #29 fix above, and `AdminCredentialsQueue.jsx`'s untested empty-queue render path remains open for a future pass.

**Verification baseline at this point:** 227 backend tests passing (full suite), 60 mobile tests passing (57 after the MEDIUM fixes + 3 new tests: admin complaint-queue account detail parsing ×2, a metrics-only review's `overall_rating` fallback), `flutter analyze` clean (only the 4 pre-existing `use_null_aware_elements` infos in `complaint_repository.dart`), and the web production build clean.
