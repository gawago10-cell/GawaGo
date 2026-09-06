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
**Status:** ⏳ Pending (backend setup done, permission checks needed)

**What to do:**
- Add verification mechanism to confirm worker actually worked before allowing ratings
- Check job completion status before rating submission
- Require both household and worker to confirm job completion
- Prevent ratings on incomplete jobs

**Files to modify:**
- `backend/apps/reviews/views.py` — Add permission checks
- `backend/apps/reviews/permissions.py` — Create custom permission
- `backend/apps/jobs/models.py` — Ensure job completion tracking

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
- Payment Issue → Notify household to investigate payment
- Quality of Work → Initiate quality review process
- No Show → Flag worker for attendance issue
- Safety Concern → Flag for admin safety review
- Inappropriate Behavior → Flag for conduct review
- Other → Generic complaint handling

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
**Status:** Needs Review

**What to do:**
- Review and simplify current interface
- Reduce visual clutter
- Use lighter color palette
- Improve component spacing and hierarchy
- Better mobile responsiveness

**Consider using:** The new.html prototype as reference design

**Files to review:**
- `frontend/src/components/` — All UI components
- `frontend/src/styles/` — CSS and Bootstrap customizations

---

### 15. AI-Based Job Matching
**Panelist:** Sir LA  
**Impact:** Recommendation Quality  
**Status:** Not implemented (complex)

**What to do:**
- Build ML model to predict job-worker fit
- Analyze historical performance data
- Provide match confidence score
- Learn from successful/failed matches
- Explain recommendations to users

**Estimated effort:** High (2-4 weeks)

**Files to create:**
- `backend/apps/matching/ml_models/` — New module
- Prediction and training pipelines

---

## 📋 DOCUMENTATION UPDATES

### Update AGENTS.md:
- [ ] Add "Post a New Job" to Functional Requirements (already exists, just needs docs)
- [ ] Clarify Scope & Limitations (specify worker types, geographic area)
- [ ] Document AI-based matching approach
- [ ] Explain proximity range justification
- [ ] Define reputation scoring criteria
- [ ] Add portfolio feature details

### Update Architecture Docs:
- [ ] Database schema changes
- [ ] API endpoint documentation
- [ ] Matching algorithm explanation
- [ ] Reputation calculation logic

---

## 🎯 Implementation Strategy

### Phase 1 (This Week - Critical)
- [ ] Job start/end dates
- [ ] Distance boundaries
- [ ] Application status terminology
- [ ] Worker verification before ratings

### Phase 2 (Next Week - High Priority)
- [x] Worker portfolio feature
- [ ] Complaint/issue system
- [x] Employment history tracking
- [ ] Complete notifications

### Phase 3 (Following Week - Polish)
- [x] Enhanced analytics
- [ ] Rating metrics
- [ ] Reputation scoring
- [ ] UI/UX improvements

### Phase 4 (Later - Advanced)
- [ ] AI matching (if timeline allows)
- [ ] Certification uploads
- [ ] Multiple ID types

---

## 📊 Quick Reference by Panelist

**Ma'am Borella** (Focus: Trust & Analytics)
- Worker verification before ratings ✅ CRITICAL
- Application status terminology ✅ CRITICAL
- Job start/end dates ✅ CRITICAL
- Multiple ID types
- Dashboard analytics
- E-commerce rating metrics
- Certification uploads

**Sir LA** (Focus: UX & Features)
- Lighter UI/UX design
- Complaint/issue reporting ✅ HIGH
- Worker portfolio ✅ HIGH
- AI-based job matching

**Sir NJ** (Focus: Geographic & Tracking)
- Distance boundaries ✅ CRITICAL
- Employment history ✅ COMPLETED
- Notifications ✅ HIGH
- Enhanced reputation scoring
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

**Last Updated:** September 3, 2026  
**Status:** Portfolio feature complete ✅ | Development roadmap active
