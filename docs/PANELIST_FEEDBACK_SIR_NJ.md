# Panelist Feedback: Sir NJ

**Panelist:** Sir NJ  
**Date:** 2026-09-02  
**Review Focus:** Geographic Boundaries, Job Duration, Worker Employment History, Notifications, Reputation Scoring

---

## Recommendations

### 1. Distance Limitations for Job Allocation
**Priority:** High  
**Category:** Smart Matching & Geographic Constraints

Include **distance limitations or boundaries** for job allocation (such as a 1-kilometer radius) to improve proximity-based matching.

**Current Implementation:**
- System shows straight-line distance or road-route distance
- No hard limit on distance - users can see all available workers

**Suggested Enhancement:**
- Implement configurable distance radius (default 1 km)
- Filter job recommendations to only workers within radius
- Show proximity as a primary matching factor
- Allow users to adjust search radius

**Implementation Details:**

**Backend Changes:**
```python
class Job(models.Model):
    # ... existing fields ...
    max_distance_km = FloatField(default=1.0)  # Configurable per job
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

**Matching Algorithm Enhancement:**
- Pre-filter workers by distance before ranking
- Skip workers outside maximum distance
- Calculate actual travel distance (road-route, not straight-line)
- Consider terrain and accessibility

**Frontend Implementation:**
- Show distance radius selector when posting jobs
- Filter displayed workers by distance
- Show remaining distance from user location to job
- Highlight workers within preferred radius

**Related Backend Files:**
- `backend/apps/matching/services.py` - Update matching algorithm
- `backend/apps/jobs/models.py` - Add distance fields
- `backend/apps/jobs/serializers.py` - Include distance in API response
- `backend/apps/common/services/distance.py` - Improve distance calculation

**Related Frontend Files:**
- `frontend/src/components/LocationDistanceMap.jsx` - Display distance bounds
- `frontend/src/hooks/useMatching.js` - Filter by distance
- Job posting form components

---

### 2. Estimated Number of Working Days
**Priority:** High  
**Category:** Job Details & Planning

Add an **estimated number of working days** for each job posting to help workers understand job duration and plan their schedule.

**Suggested Implementation:**
- Add `estimated_working_days` field to Job model
- Calculate based on job type and scope
- Display prominently in job details
- Use in matching (prefer workers with availability)

**New Fields:**
```python
class Job(models.Model):
    # ... existing fields ...
    estimated_working_days = IntegerField(
        help_text="Estimated number of days to complete this job"
    )
    job_duration_type = CharField(
        max_length=20,
        choices=[
            ('one_time', 'One-Time'),
            ('recurring', 'Recurring'),
            ('ongoing', 'Ongoing'),
        ],
        default='one_time'
    )
    estimated_hours_per_day = FloatField(null=True, blank=True)
    total_estimated_hours = FloatField(null=True, blank=True)
```

**Calculation Logic:**
- If `job_start_date` and `job_end_date` provided, calculate working days
- Consider weekends and holidays (optional)
- Suggest working days based on scope
- Allow household to override estimate

**Frontend Implementation:**
- Show working days in job list view
- Calculate total hours in job details
- Help worker schedule accordingly
- Estimate completion date

**Related Backend Files:**
- `backend/apps/jobs/models.py` - Add duration fields
- `backend/apps/jobs/serializers.py` - Include duration in responses
- `backend/apps/jobs/services.py` - Add duration calculation logic

**Related Frontend Files:**
- `frontend/src/components/WorkerJobDetailView.jsx` - Display duration
- Job posting form components
- Job application consideration

---

### 3. Worker Employment History Feature
**Priority:** High  
**Category:** Worker Profile & Trust

Include a **worker employment history feature** to allow employers to:
- Review and rehire previous workers
- See worker's track record with them
- Assess worker reliability and performance

**Implementation Details:**

**Data Model:**
```python
class WorkerEmploymentHistory(models.Model):
    worker = ForeignKey(User, on_delete=models.CASCADE)
    household = ForeignKey(User, on_delete=models.CASCADE)
    job = ForeignKey(Job, on_delete=models.SET_NULL, null=True)
    start_date = DateTimeField()
    end_date = DateTimeField()
    job_type = CharField(max_length=100)
    status = CharField(
        max_length=20,
        choices=[
            ('completed', 'Completed'),
            ('cancelled', 'Cancelled'),
            ('rejected', 'Rejected'),
        ]
    )
    rating_given = BooleanField(default=False)
    times_worked_together = IntegerField(default=1)
    created_at = DateTimeField(auto_now_add=True)
```

**Household-Specific History:**
- Show all previous jobs with same household
- Display frequency of repeat hires
- Show consistency and reliability
- Highlight successful working relationships

**Worker Profile View:**
- Show employment history overview
- Number of repeat customers
- Average rating from repeat customers
- Customer retention percentage

**Features:**
- "Re-hire" quick button for returning workers
- History search and filtering
- Timeline of working relationships
- Earnings history (if tracked)

**Backend Implementation:**
- Auto-create employment history entry when job completes
- Expose employment history via API
- Add employment metrics to worker profile
- Calculate repeat customer stats

**Frontend Implementation:**
- Show employment history in worker profile
- Display in household dashboard
- Easy rehire mechanism
- History filter and search

**Related Backend Files (New):**
- `backend/apps/jobs/employment_history.py` - New module

**Related Backend Files (Existing):**
- `backend/apps/jobs/models.py` - Add employment history model
- `backend/apps/jobs/signals.py` - Auto-create history on completion
- `backend/apps/accounts/views.py` - Expose history endpoint
- `backend/apps/analytics/views.py` - Include history metrics

**Related Frontend Files:**
- `frontend/src/components/WorkerProfileView.jsx` - Display history
- `frontend/src/components/HouseholdDashboardView.jsx` - Show history
- Worker selection/rehire components

---

### 4. Notifications for Job Activities
**Priority:** High  
**Category:** Notifications & Communication

Implement **notifications** to keep users informed about:
- Job applications received
- Application status changes
- Work assignments
- Job status updates
- System activity alerts
- Other relevant notifications

**Current State:**
- Notification system partially implemented
- Structured notification fields in place
- Need completion and enhancement

**Notification Types to Implement:**

**For Workers:**
- New job recommendations
- Application status (accepted/rejected)
- Hire confirmation
- Job details and requirements
- Schedule reminders
- Payment confirmations
- Rating requests
- Message from household

**For Households:**
- New applications received
- Worker accepted offer
- Worker completed job
- Rating submission reminder
- Worker cancellation notice
- Payment confirmations

**For Admins:**
- New user registrations
- Complaint submissions
- Verification requests
- System alerts

**Implementation Enhancement:**
```python
class Notification(models.Model):
    NOTIFICATION_TYPES = [
        ('application_received', 'Application Received'),
        ('application_accepted', 'Application Accepted'),
        ('application_rejected', 'Application Rejected'),
        ('hire_confirmed', 'Hire Confirmed'),
        ('job_completed', 'Job Completed'),
        ('rating_request', 'Rating Request'),
        ('job_cancelled', 'Job Cancelled'),
        ('worker_accepted', 'Worker Accepted'),
        ('work_assigned', 'Work Assigned'),
        ('message_received', 'Message Received'),
    ]
    
    recipient = ForeignKey(User, on_delete=models.CASCADE)
    notification_type = CharField(max_length=50, choices=NOTIFICATION_TYPES)
    title = CharField(max_length=255)
    message = TextField()
    related_job = ForeignKey(Job, null=True, blank=True, on_delete=models.SET_NULL)
    related_worker = ForeignKey(User, null=True, blank=True, on_delete=models.SET_NULL)
    action_url = CharField(max_length=255, null=True, blank=True)
    is_read = BooleanField(default=False)
    created_at = DateTimeField(auto_now_add=True)
```

**Delivery Channels:**
- In-app notifications (real-time)
- Email notifications (important events)
- Push notifications (mobile app)

**Frontend Implementation:**
- Real-time notification bell
- Notification center/history
- Notification preferences
- Mark as read functionality
- Quick action buttons in notifications

**Related Backend Files (Existing):**
- `backend/apps/notifications/models.py` - Enhance model
- `backend/apps/notifications/views.py` - Complete implementation
- `backend/apps/notifications/serializers.py` - Ensure complete data

**Related Frontend Files:**
- `frontend/src/components/NotificationCenter.jsx` - Implement notification UI
- `frontend/src/hooks/useNotifications.js` - Notification state management
- Real-time updates (WebSocket or polling)

---

### 5. Enhanced Reputation Scoring Mechanism
**Priority:** High  
**Category:** Reputation System & Growth

Enhance the reputation scoring mechanism by **allowing worker ratings to improve** as their portfolio and work experience grow.

**Current Approach:**
- Static ratings based on completed jobs
- No growth mechanism
- Doesn't account for improvement

**Suggested Enhancement:**
- Make ratings actionable for worker improvement
- Show growth trajectory
- Reward consistent high performance
- Encourage re-engagement

**Implementation Strategy:**

**1. Rating Improvement Path:**
```python
# Workers can improve by:
- Completing more successful jobs (rating increases from 3.5 to 4+)
- Maintaining consistency (no rating drops)
- Getting positive feedback comments
- Completing skill certifications
- Building portfolio with examples
```

**2. Weighted Rating System:**
- Recent ratings weighted higher than older ones
- Consistent high ratings > one-time high rating
- Quality feedback considered alongside stars
- Trend analysis (improving vs declining)

**3. Visible Growth Indicators:**
- Rating trend chart (last 6 months)
- Completed jobs count
- Average rating vs household average
- Skill endorsements
- Certification progress

**4. Reputation Tiers:**
- New Worker (0-10 jobs)
- Established (10-50 jobs)
- Trusted (50-100 jobs)
- Elite (100+ jobs, 4.5+ rating)

**Backend Implementation:**
```python
class WorkerReputation(models.Model):
    worker = OneToOneField(User, on_delete=models.CASCADE)
    current_rating = FloatField(default=0)
    total_jobs_completed = IntegerField(default=0)
    successful_jobs = IntegerField(default=0)
    average_rating_trend = FloatField(default=0)  # Last 30 days
    reputation_tier = CharField(max_length=20)
    rating_improvement = FloatField(default=0)  # Change over time
    updated_at = DateTimeField(auto_now=True)
```

**Calculation Logic:**
- Update reputation score after each job completion
- Calculate rolling average for trend
- Apply decay to old ratings
- Reward consistency
- Show improvement trajectory

**Frontend Display:**
- Show rating history chart
- Display reputation tier badge
- Highlight improvement arrows
- Show job completion milestones
- Display skill badges earned

**Related Backend Files:**
- `backend/apps/reviews/models.py` - Enhance rating fields
- `backend/apps/reviews/services.py` - Add reputation calculation
- `backend/apps/reviews/signals.py` - Update on new ratings
- `backend/apps/analytics/views.py` - Include reputation trends

**Related Frontend Files:**
- Worker profile views - Display reputation trends
- Dashboard - Show reputation growth
- Job recommendation - Consider reputation trajectory

---

## Required Revisions

### 1. Include Global Literature and Related Studies
**Priority:** Medium  
**Document:** Project Documentation (Introduction section)

Include global literature and related studies in the Introduction to strengthen the study's foundation:
- Academic papers on gig economy and job matching
- Studies on trust and verification in platforms
- Literature on geographic constraints in matching
- References to e-commerce reputation systems

**Action:** Update documentation with academic references

---

### 2. Define and Justify Proximity Range
**Priority:** High  
**Document:** AGENTS.md and Architecture Documentation

Define and justify the proximity range/geographic boundaries used in smart matching:

**Document:**
- Why 1-kilometer radius was chosen (or proposed limit)
- How distance is calculated (straight-line vs road-route)
- Geographic context of Tayabas City
- Impact on job allocation and worker availability
- Exceptions or special cases

**Suggested Section:**
```
### Geographic Proximity in Smart Matching

- **Distance Calculation Method:** Road-route distance using [service]
- **Default Maximum Radius:** 1 kilometer
- **Rationale:** Proximity to Tayabas City dimensions and typical commute times
- **Flexibility:** Employers can adjust radius per job posting
- **Impact on Matching:** Workers beyond limit not recommended (can still apply)
```

**Related Documents:**
- AGENTS.md (Smart Matching section)
- Architecture documentation
- System design specs

---

### 3. Clarify Reputation Scoring Criteria
**Priority:** High  
**Document:** AGENTS.md and Documentation

Clearly discuss the computation and criteria used for reputation scoring:

**Document Should Include:**
- Rating calculation method (average of all ratings)
- Time-based weighting (recent ratings matter more)
- Minimum rating assignment (default 4-star if no rating)
- Rating improvement criteria
- Reputation tier definitions
- Performance metrics included

**Suggested Section:**
```
### Reputation Scoring Methodology

#### Rating Calculation
- Average of all household ratings for worker
- Default 4-star assigned if no rating within 48-72 hours
- Recent ratings (last 6 months) weighted 70%, older 30%

#### Reputation Tiers
- New: 0-10 jobs completed
- Established: 10-50 jobs, 3.5+ rating
- Trusted: 50+ jobs, 4.0+ rating
- Elite: 100+ jobs, 4.5+ rating

#### Performance Metrics
- Job completion rate
- Average rating
- Rating consistency (standard deviation)
- Repeat hire rate
- Time-on-task (efficiency)
```

**Related Documents:**
- AGENTS.md (Section II - Reputation System)
- Architecture/system design docs
- Database schema documentation

---

## Summary

**Key Takeaways:**
1. Geographic proximity is critical for practical job matching (1 km radius recommended)
2. Working days estimation helps workers plan and manage schedules
3. Employment history builds trust and enables easy rehiring
4. Comprehensive notification system critical for user engagement
5. Reputation should reward improvement and growth, not just absolute ratings
6. Documentation must explain these systems clearly and justify design choices

**Quick Wins:**
- Add estimated working days field (easy backend change)
- Implement employment history tracking (medium effort)

**Strategic Initiatives:**
- Complete notification system (ongoing)
- Enhance reputation scoring with growth mechanics
- Document proximity-based matching rationale

**Estimated Total Effort:** Medium (2-3 weeks of development)

---

## Implementation Priority

### Phase 1 (Immediate)
- [ ] Add distance boundary/radius to job model
- [ ] Add estimated working days to job
- [ ] Update job serializers
- [ ] Document proximity justification

### Phase 2 (Next Sprint)
- [ ] Implement employment history tracking
- [ ] Complete notification system
- [ ] Update notification views and serializers
- [ ] Add notification preferences UI

### Phase 3 (Follow-up)
- [ ] Enhance reputation scoring algorithm
- [ ] Add reputation tier system
- [ ] Create reputation trend analytics
- [ ] Update worker profile display

---

## Questions for Clarification

- Should 1 km be the only option or configurable per job?
- How should employment history be displayed to workers? (visible to all or private?)
- What happens to workers who refuse jobs (impact on reputation)?
- Should notification preferences be granular per type or general on/off?
- How should reputation be reset or recovered for low-rating workers?
