# Panelist Feedback: Ma'am Borella

**Panelist:** Ma'am Borella  
**Date:** 2026-09-02  
**Review Focus:** User verification, dashboard analytics, job details, rating system

---

## Recommendations

### 1. Multiple ID Types for User Verification
**Priority:** High  
**Category:** User Verification & Security

Include multiple ID types for user verification and validation to strengthen the verification process and ensure more robust user authentication.

**Suggested Implementation:**
- Support multiple ID types (National ID, Passport, Driver's License, etc.)
- Store ID type metadata in user profile
- Allow flexible ID verification options

**Related Backend Files:**
- `backend/apps/accounts/models.py` - Update user profile model
- `backend/apps/accounts/serializers.py` - Add ID type fields

---

### 2. Enhanced Dashboard Analytics
**Priority:** High  
**Category:** Analytics & Reporting

Enhance the dashboard by displaying analytics such as:
- Number of applications submitted **daily**
- Number of applications submitted **weekly**
- Number of applications submitted **monthly**
- Number of applications submitted **yearly**

**Suggested Implementation:**
- Update analytics views to aggregate application data by time period
- Add time-series charts to SuperAdminDashboardView
- Use Recharts for visualization (already in use)

**Related Frontend Files:**
- `frontend/src/components/SuperAdminDashboardView.jsx`
- `frontend/src/hooks/useDashboardMetrics.js`

**Related Backend Files:**
- `backend/apps/analytics/views.py`
- `backend/apps/analytics/services.py`

---

### 3. Improved Job Posting Details
**Priority:** High  
**Category:** Job Posting & Scheduling

Improve job posting details by including **both start and end dates** of employment rather than only preferred dates or schedules.

**Suggested Implementation:**
- Add `job_start_date` and `job_end_date` fields to Job model
- Update job serializers to include these fields
- Display date range in job detail views
- Update frontend forms to capture both dates

**Suggested Fields:**
```python
job_start_date = models.DateField()
job_end_date = models.DateField()
estimated_working_days = models.IntegerField(null=True, blank=True)
```

**Related Backend Files:**
- `backend/apps/jobs/models.py` - Add date fields
- `backend/apps/jobs/serializers.py` - Update serialization
- `backend/apps/jobs/views.py` - Update job creation/update logic

**Related Frontend Files:**
- `frontend/src/components/WorkerJobDetailView.jsx`

---

### 4. Application Status Terminology
**Priority:** High  
**Category:** UX & Clarity

Change the application status from **Completed** to **Hired** or **Rejected** for better clarity.

**Current Issue:**
- "Completed" is ambiguous and could mean job completion instead of application status

**Suggested Implementation:**
- Rename application statuses: `Hired` (accepted), `Rejected`, `Pending` (applied)
- Update database enums in application model
- Update all frontend displays
- Update all backend responses

**Related Backend Files:**
- `backend/apps/jobs/models.py` - Update Application model status choices
- `backend/apps/jobs/serializers.py` - Update status field documentation

**Related Frontend Files:**
- `frontend/src/components/WorkerJobDetailView.jsx`
- All views displaying application status

---

### 5. Worker Verification Before Ratings
**Priority:** Critical  
**Category:** Trust & Verification

Add a verification mechanism to confirm that a worker has **actually worked** for the employer before ratings can be submitted.

**Suggested Implementation:**
- Check job completion status before allowing rating submission
- Require both household and worker to confirm job completion
- Track work completion proof (timestamps, location check-ins, etc.)
- Prevent ratings on jobs that are not fully completed

**Related Backend Files:**
- `backend/apps/reviews/views.py` - Add permission checks
- `backend/apps/reviews/permissions.py` - Create custom permission
- `backend/apps/jobs/models.py` - Ensure job completion tracking

---

### 6. Detailed Rating Metrics (E-Commerce Style)
**Priority:** Medium  
**Category:** Reviews & Ratings

Implement detailed rating metrics similar to e-commerce platforms to identify specific areas of worker performance.

**Suggested Metrics:**
- Quality of Work (1-5 stars)
- Punctuality (1-5 stars)
- Communication (1-5 stars)
- Professionalism (1-5 stars)
- Overall Rating (average)

**Suggested Implementation:**
- Update Review model to have multiple metric fields
- Create detailed review form in frontend
- Display breakdown of metrics on worker profile

**Related Backend Files:**
- `backend/apps/reviews/models.py` - Update Review model
- `backend/apps/reviews/serializers.py` - Add metric fields

**Related Frontend Files:**
- Worker profile view components
- Review submission forms

---

### 7. Worker Certifications & Credentials Upload
**Priority:** Medium  
**Category:** Worker Profile Enhancement

Allow workers to upload certifications and credentials (e.g., TESDA certificates) to strengthen their profiles.

**Suggested Implementation:**
- Add file upload field to worker profile
- Support multiple file uploads (certificates, licenses, etc.)
- Validate and display certificates on profile
- Admin approval workflow for certificates

**Related Backend Files:**
- `backend/apps/accounts/models.py` - Add certificate model
- `backend/apps/accounts/views.py` - Add file upload handlers
- `backend/apps/common/permissions.py` - Add certificate validation

---

## Required Revisions

### 1. Update Scope and Limitations
**Priority:** High  
**Document:** AGENTS.md (Scope section)

- Specify the types of workers covered by the study (domestic helpers, skilled workers, etc.)
- Include specific worker categories in Scope section
- Revise to remove statements indicating coverage of the entire City of Tayabas if this is **not** within the actual scope

**Action:** Review and update [docs/README.md](../README.md) and [AGENTS.md](../../AGENTS.md)

---

### 2. Add "Post a New Job" Feature to Functional Requirements
**Priority:** Medium  
**Document:** AGENTS.md

- Ensure **Post a New Job** feature is explicitly listed in Functional Requirements section
- Document the feature's purpose and user flow

**Current Status:** Already implemented in backend/frontend, needs documentation update

---

### 3. Clarify Job Duration in Documentation
**Priority:** High  
**Document:** System Design & Database Schema

Ensure that job duration and employment period are clearly defined in:
- System design documentation
- Database schema documentation
- API documentation
- Frontend forms

**Suggested Fields:**
- Job start date
- Job end date
- Estimated working days
- Job duration type (hourly, daily, weekly, one-time, etc.)

---

### 4. Add Hiring Rate Analytics
**Priority:** Medium  
**Category:** Analytics

Include hiring rate analytics in dashboard:
- Successfully completed hires per worker
- Successful hire percentage
- Hire to application ratio
- Time to hire (average days)

**Related Files:**
- `backend/apps/analytics/views.py`
- `frontend/src/components/SuperAdminDashboardView.jsx`

---

### 5. Display Job Matches by Worker Skills
**Priority:** Medium  
**Category:** Matching & Display

- Display job recommendations based on worker skills
- Show skill match percentage
- Allow workers to see why they were matched to jobs

**Related Files:**
- `backend/apps/matching/services.py`
- `frontend/src/components/WorkerJobDetailView.jsx`

---

### 6. Implement 4-Skill Limit per Worker
**Priority:** High  
**Category:** Data Model

- Define and implement a maximum of **four (4) skills** per worker profile
- Enforce this limit in backend serializers and views
- Update frontend forms to prevent adding more than 4 skills

**Related Backend Files:**
- `backend/apps/accounts/models.py` - Add skill limit validation
- `backend/apps/accounts/serializers.py` - Add validation logic
- `backend/apps/accounts/views.py` - Update skill update endpoints

---

### 7. Show Worker Hiring Statistics
**Priority:** Medium  
**Category:** Analytics & Display

Show on worker profile dashboard:
- Number of successful hires
- Service types completed
- Success rate percentage
- Total earnings (if applicable)

**Related Files:**
- `frontend/src/components/WorkerJobDetailView.jsx` (or worker profile view)
- `backend/apps/analytics/views.py`

---

### 8. Simplify "Reputation and Trust Management" Term
**Priority:** Low  
**Category:** Documentation & Terminology

If the term is too broad or complex for the study scope:
- Simplify to "Reputation System" or "Trust Scoring"
- Clarify scope and specific components included
- Remove overly complex aspects if out of scope

**Related Document:** AGENTS.md (Section II)

---

## Summary

**Key Takeaways:**
1. Worker verification before ratings is critical
2. Application status terminology needs clarity
3. Job duration fields are missing from current design
4. Dashboard analytics need time-based breakdowns
5. Skill limit of 4 per worker should be enforced
6. E-commerce style rating metrics would improve trust
7. Multiple ID types and certificate upload strengthen verification

**Estimated Effort:** Medium (2-3 sprints of development work)
