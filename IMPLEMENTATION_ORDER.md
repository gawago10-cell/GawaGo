# GawaGo Implementation Execution Order
**Practical Step-by-Step Guide**  
**Date:** September 2, 2026

---

## 🎯 Golden Rule
**Do backend FIRST, then frontend, then documentation**

Build the foundation before building the walls.

---

## 📋 WEEK 1: DATABASE & API FOUNDATIONS

### Day 1-2: Add Missing Database Fields
**Why first:** Everything else depends on this

#### 1. Update Job Model
**File:** `backend/apps/jobs/models.py`

Add these fields to Job model:
```python
job_start_date = models.DateField(null=True, blank=True)
job_end_date = models.DateField(null=True, blank=True)
estimated_working_days = models.IntegerField(null=True, blank=True)
max_distance_km = models.FloatField(default=1.0)
geographic_boundary = models.CharField(
    max_length=20,
    choices=[
        ('1km', '1 Kilometer'),
        ('2km', '2 Kilometers'),
        ('5km', '5 Kilometers'),
        ('10km', '10 Kilometers'),
        ('unlimited', 'Unlimited'),
    ],
    default='1km'
)
```

**Then:** Create and run migration
```bash
python manage.py makemigrations
python manage.py migrate
```

#### 2. Update Application Status Enums
**File:** `backend/apps/jobs/models.py`

Find the Application model and change status choices:
```python
# OLD:
STATUS_CHOICES = [('pending', 'Pending'), ('completed', 'Completed')]

# NEW:
STATUS_CHOICES = [
    ('pending', 'Pending'),
    ('hired', 'Hired'),
    ('rejected', 'Rejected'),
]
```

**Then:** Migrate
```bash
python manage.py makemigrations
python manage.py migrate
```

---

### Day 3: Add Job Completion Tracking
**File:** `backend/apps/jobs/models.py`

Add to Job model:
```python
is_completed = models.BooleanField(default=False)
completed_at = models.DateTimeField(null=True, blank=True)
```

**Reason:** Needed for worker verification before ratings

**Then:** Migrate

---

### Day 4: Update Serializers
**Files:** `backend/apps/jobs/serializers.py`

Update JobSerializer to include new fields:
```python
class JobSerializer(serializers.ModelSerializer):
    class Meta:
        model = Job
        fields = [...existing..., 'job_start_date', 'job_end_date', 
                  'estimated_working_days', 'max_distance_km', 
                  'geographic_boundary', 'is_completed', 'completed_at']
```

Update ApplicationSerializer:
```python
# Change status field to use new choices
```

**Why:** API must send these fields to frontend

---

## 📋 WEEK 2: BACKEND LOGIC

### Day 5: Application Status Logic
**Files:** 
- `backend/apps/jobs/views.py` 
- `backend/apps/jobs/models.py`

#### Step 1: Update application creation
When user applies for job → set status to `pending`

#### Step 2: Update acceptance logic
When household hires → set status to `hired`

#### Step 3: Update rejection logic  
When household rejects → set status to `rejected`

**Test:** Make sure old "completed" status is never used

---

### Day 6: Worker Verification Before Ratings
**Files:**
- `backend/apps/reviews/permissions.py` (NEW FILE)
- `backend/apps/reviews/views.py`

#### Step 1: Create permission class
**File:** `backend/apps/reviews/permissions.py`
```python
class CanRateWorker(permissions.BasePermission):
    def has_permission(self, request, view):
        # Only allow rating if:
        # 1. Job is completed (is_completed=True)
        # 2. Application status is 'hired'
        # 3. User is household or worker
        pass
```

#### Step 2: Update review views
**File:** `backend/apps/reviews/views.py`
- Add `CanRateWorker` permission to rating endpoints
- Check job completion before allowing rating

**Pseudocode:**
```python
if not job.is_completed:
    return Response({"error": "Job not completed"}, status=400)
if application.status != 'hired':
    return Response({"error": "Worker not hired"}, status=400)
```

---

### Day 7-8: Distance Filtering Logic
**File:** `backend/apps/matching/services.py`

#### Step 1: Create distance filter function
```python
def filter_workers_by_distance(job, workers):
    """Filter workers to only those within job's max_distance_km"""
    filtered = []
    for worker in workers:
        distance = calculate_distance(worker.location, job.location)
        if distance <= job.max_distance_km:
            filtered.append(worker)
    return filtered
```

#### Step 2: Update matching algorithm
Modify the matching function to:
1. Get all potential workers
2. Apply distance filter FIRST (hard constraint)
3. Then apply other ranking factors

**Why first:** Distance is a hard boundary, not optional

---

## 📋 WEEK 3: FRONTEND FORMS & INPUTS

### Day 9: Update Job Posting Form
**File:** `frontend/src/components/JobPostingForm.jsx` (or wherever form is)

Add form fields:
- Job Start Date (date picker)
- Job End Date (date picker)
- Estimated Working Days (number input)
- Geographic Boundary (dropdown: 1km, 2km, 5km, 10km, unlimited)

**Make sure to:**
- Validate that end_date > start_date
- Calculate days between dates
- Show error if dates are invalid

---

### Day 10: Test API Integration
**File:** Any React component that posts jobs

When submitting job form:
1. Send all new fields to backend
2. Verify backend returns the fields in response
3. Log the response to check data

**Debug checklist:**
- [ ] job_start_date is sent
- [ ] job_end_date is sent
- [ ] estimated_working_days is sent
- [ ] max_distance_km is sent
- [ ] geographic_boundary is sent
- [ ] Backend doesn't error out

---

## 📋 WEEK 4: FRONTEND DISPLAY

### Day 11: Update Job Detail View
**File:** `frontend/src/components/WorkerJobDetailView.jsx`

Display new fields:
```jsx
<div>
    <p><strong>Job Period:</strong> {job.job_start_date} to {job.job_end_date}</p>
    <p><strong>Estimated Days:</strong> {job.estimated_working_days}</p>
    <p><strong>Search Radius:</strong> {job.geographic_boundary}</p>
</div>
```

---

### Day 12: Update Application Status Display
**Files:** All components showing application status

OLD CODE:
```jsx
status === 'completed' ? 'Completed' : 'Pending'
```

NEW CODE:
```jsx
const statusLabels = {
    'pending': 'Applied',
    'hired': 'Hired',
    'rejected': 'Rejected'
}
statusLabels[status]
```

**Find and replace in:**
- Worker dashboard
- Household dashboard
- Job list views
- Application list views

---

### Day 13: Update Worker List Display
**File:** Any component showing worker recommendations

Add distance display:
```jsx
<p>{distance.toFixed(1)} km away</p>
```

Show distance in matching results

---

### Day 14: Test All Frontend
**Checklist:**
- [ ] Can post job with dates and distance
- [ ] Job details show dates and distance
- [ ] Application status shows correct terms
- [ ] Worker list shows distances
- [ ] Can filter workers by distance
- [ ] Can mark job as completed
- [ ] Cannot rate until job completed

---

## 📋 WEEK 5: POLISH & DOCUMENTATION

### Day 15: Code Review & Fix Bugs
- Test all features end-to-end
- Fix any bugs found
- Test edge cases (dates in past, invalid distances, etc.)

### Day 16: Documentation Update
**File:** `docs/README.md` and `AGENTS.md`

Add sections:
- Distance filtering explained
- Application status terminology
- Job date fields explained
- Worker verification requirement

### Day 17: Commit & PR
- Create branch: `feature/panelist-critical-items`
- Commit all changes
- Create pull request
- Request review

---

## 🚀 WEEK 6+: NEXT BATCH (HIGH PRIORITY)

Once Week 1-5 is done and merged, move to:

### Batch 2 (Week 6):
1. **Worker Portfolio Feature** (most complex)
2. **Complaint System** (medium complexity)
3. **Employment History** (medium complexity)

### Batch 3 (Week 7):
1. **Enhanced Analytics** (dashboard updates)
2. **Detailed Rating Metrics** (form update)
3. **Notifications** (if not already done)

### Batch 4 (Week 8+):
1. **Reputation Scoring** (complex algorithm)
2. **AI Matching** (very complex, may need 2 weeks)
3. **UI/UX Polish** (last, for overall look)

---

## 📌 DEPENDENCY MAP

```
DATABASE FIELDS (Day 1-4)
    ↓
MIGRATIONS (Day 1-4)
    ↓
SERIALIZERS (Day 4)
    ↓
BACKEND LOGIC (Day 5-8)
    ├→ APPLICATION STATUS
    ├→ VERIFICATION CHECKS
    └→ DISTANCE FILTERING
    ↓
FRONTEND FORMS (Day 9-10)
    ├→ JOB POSTING FORM
    └→ TEST API INTEGRATION
    ↓
FRONTEND DISPLAY (Day 11-14)
    ├→ JOB DETAILS
    ├→ APPLICATION STATUS
    ├→ WORKER LIST
    └→ FULL END-TO-END TEST
    ↓
DOCUMENTATION (Day 15-17)
    ├→ README UPDATES
    └→ COMMIT & MERGE
```

---

## ✅ Success Criteria for Week 1-5

When done, your app should:
- ✅ Accept job_start_date and job_end_date when posting jobs
- ✅ Show job dates in all job detail views
- ✅ Only show workers within the geographic_boundary distance
- ✅ Use correct terminology: Pending/Hired/Rejected (not Completed)
- ✅ Prevent ratings until job is marked completed
- ✅ Allow households to mark jobs as completed
- ✅ All tests pass
- ✅ Documentation updated

---

## 💡 Pro Tips

1. **Work on ONE thing at a time** - Don't jump around
2. **Test after EACH step** - Don't batch test at end
3. **Keep database migrations separate** - One migration per change
4. **Frontend last** - Gets easier once backend works
5. **Commit frequently** - Small commits, not huge ones

---

**Ready to start? Begin with Day 1: Adding database fields to Job model in `backend/apps/jobs/models.py`**
