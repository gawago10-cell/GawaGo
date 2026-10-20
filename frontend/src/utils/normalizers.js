import { parseLocationLabel } from "./locationUtils";
import { isTransientBlobUrl } from "./mediaUtils";

function splitFullName(fullName, fallbackUsername = "") {
  const normalized = String(fullName || "").trim();
  if (!normalized) {
    return { firstName: "", lastName: "", displayName: fallbackUsername || "User" };
  }
  const parts = normalized.split(/\s+/);
  return {
    firstName: parts[0] || "",
    lastName: parts.slice(1).join(" "),
    displayName: normalized,
  };
}

export function normalizeReview(review) {
  return {
    id: review.id || `review-${Date.now()}`,
    authorRole: review.authorRole,
    authorUsername: review.authorUsername || "",
    authorName: review.authorName || "User",
    targetUsername: review.targetUsername || "",
    targetName: review.targetName || "User",
    rating: review.rating ?? null,
    feedback: review.feedback || "",
    // normalizeBackendReview derives this from the backend's `job` field --
    // without it here, a worker replying to a household's review always
    // sent job_id: undefined (ReviewCreateSerializer.job_id is required, so
    // the reply just failed, or filed against whatever job happened to be
    // selected elsewhere in the UI).
    jobId: review.jobId || null,
    jobTitle: review.jobTitle || "",
    // The four e-commerce-style metrics behind the overall rating, and the
    // backend's own computed overall_rating (their average when present,
    // else the plain `rating`). Without these the metric breakdown UI has
    // nothing to render and always falls back to the raw star rating.
    qualityOfWork: review.qualityOfWork ?? null,
    punctuality: review.punctuality ?? null,
    communication: review.communication ?? null,
    professionalism: review.professionalism ?? null,
    // DRF serializes a Decimal-backed value as a string but a computed
    // Python float as a number -- get_overall_rating() can return either
    // depending on whether metrics were supplied, so coerce here rather
    // than leaving callers to guess which type they got.
    overallRating: review.overallRating != null ? Number(review.overallRating) : null,
    createdAt: review.createdAt || new Date().toLocaleString("en-PH"),
  };
}

function capitalizeVerificationStatus(status) {
  const normalized = String(status || "").trim().toLowerCase();
  if (normalized === "approved" || normalized === "verified") {
    return "Approved";
  }
  if (normalized === "rejected") {
    return "Rejected";
  }
  if (normalized === "pending") {
    return "Pending";
  }
  return "Under Review";
}

function normalizePreviewUrl(value) {
  return isTransientBlobUrl(value) ? "" : value || "";
}

export function getWorkerVerificationLabel(status) {
  const normalized = String(status || "").trim().toLowerCase();
  if (normalized === "approved" || normalized === "verified") {
    return "Verified";
  }
  if (normalized === "rejected") {
    return "Rejected";
  }
  if (normalized === "pending" || normalized === "under review") {
    return "Under Review";
  }
  return "Not Yet Verified";
}

export function normalizeVerificationRequest(request) {
  if (!request) {
    return null;
  }
  const source = request.verification_request || request;
  const workerId = source.worker ?? source.workerId ?? source.worker_id ?? null;
  const workerUsername = source.worker_username || source.workerUsername || "";
  const workerLocation = parseLocationLabel(source.worker_location_label || source.workerLocationLabel || "");
  return {
    id: source.id,
    accountRole: source.account_role || source.accountRole || "worker",
    workerId,
    workerUsername,
    workerName: source.worker_name || source.workerName || workerUsername || "Worker",
    workerEmail: source.worker_email || source.workerEmail || "",
    workerPhone: source.worker_phone || source.workerPhone || "",
    workerLocationLabel: source.worker_location_label || source.workerLocationLabel || "",
    workerBarangay: workerLocation.barangay,
    workerStreetAddress: workerLocation.streetAddress,
    workerSkills: source.worker_skills || source.workerSkills || [],
    workerHourlyRate: source.worker_hourly_rate ?? source.workerHourlyRate ?? null,
    workerDailyRate: source.worker_daily_rate ?? source.workerDailyRate ?? null,
    workerYearsExperience: source.worker_years_experience ?? source.workerYearsExperience ?? 0,
    workerProfilePhoto: normalizePreviewUrl(source.worker_profile_photo || source.workerProfilePhoto),
    primaryIdType: source.primary_id_type || source.primaryIdType || "",
    primaryIdTypeLabel: source.primary_id_type_label || source.primaryIdTypeLabel || "",
    primaryIdName: source.primary_id_name || source.primaryIdName || "",
    secondaryDocName: source.secondary_doc_name || source.secondaryDocName || "",
    primaryIdPreview: normalizePreviewUrl(source.primary_id_preview || source.primaryIdPreview),
    secondaryDocPreview: normalizePreviewUrl(source.secondary_doc_preview || source.secondaryDocPreview),
    notes: source.notes || "",
    status: capitalizeVerificationStatus(source.status),
    submittedAt: source.submitted_at || source.submittedAt || "",
    reviewedAt: source.reviewed_at || source.reviewedAt || "",
    reviewedBy: source.reviewed_by || source.reviewedBy || "",
    reviewNote: source.review_note || source.reviewNote || "",
  };
}

export function normalizeAvailabilityWindow(window) {
  if (!window) {
    return null;
  }
  return {
    id: window.id || `availability-${Date.now()}`,
    date: window.date || "",
    startTime: window.start_time || window.startTime || "",
    endTime: window.end_time || window.endTime || "",
    isAvailable: window.is_available ?? window.isAvailable ?? true,
  };
}

export function normalizeBackendWorker(currentUser) {
  if (!currentUser || currentUser.role !== "worker" || !currentUser.profile) {
    return null;
  }
  const profile = currentUser.profile;
  const locationParts = parseLocationLabel(profile.location_label);
  return {
    id: currentUser.id || currentUser.username,
    username: currentUser.username,
    firstName: currentUser.first_name || currentUser.firstName || "",
    lastName: currentUser.last_name || currentUser.lastName || "",
    email: currentUser.email || "",
    phone: profile.phone || currentUser.phone || "",
    barangay: currentUser.barangay || locationParts.barangay || "",
    streetAddress: currentUser.streetAddress || locationParts.streetAddress || "",
    bio: profile.bio || currentUser.bio || "",
    hourlyRate: profile.hourly_rate || currentUser.hourlyRate || "0.00",
    dailyRate: profile.daily_rate || currentUser.dailyRate || "0.00",
    yearsExperience: profile.years_experience ?? currentUser.yearsExperience ?? "0",
    skills: profile.skills || currentUser.skills || [],
    verification: profile.verification_status === "verified" ? "Verified" : profile.verification_status === "pending" ? "Under Review" : profile.verification_status === "rejected" ? "Rejected" : "Not Yet Verified",
    rating: profile.display_rating || "No ratings yet",
    reviewsDone: profile.rating_count || 0,
    reputationTier: profile.reputation_tier || "new",
    ratingTrend: profile.rating_trend || "neutral",
    status: "Available",
    distanceKm: null,
    latitude: profile.latitude ?? currentUser.latitude ?? null,
    longitude: profile.longitude ?? currentUser.longitude ?? null,
    profilePhotoPreview: profile.profile_photo_url || profile.profile_photo || currentUser.profilePhotoPreview || "",
    availabilityWindows: (profile.availability_windows || []).map(normalizeAvailabilityWindow).filter(Boolean),
    avatar: (currentUser.displayName || currentUser.username || "W").slice(0, 1).toUpperCase(),
    receivedReviews: [],
    givenFeedback: [],
    verificationNotifications: [],
    applicationNotifications: [],
    verificationRequestId: profile.verification_request?.id || null,
    verificationSubmission: normalizeVerificationRequest(profile.verification_request),
  };
}

export function normalizeBackendWorkerPayload(payload) {
  if (!payload) {
    return null;
  }
  const userPart = payload.user || payload;
  const profilePart = payload.profile || payload.worker_profile || null;
  return normalizeBackendWorker({
    id: userPart.id || userPart.user_id || userPart.username,
    role: profilePart?.role || userPart.role || "worker",
    username: userPart.username || "",
    email: userPart.email || "",
    first_name: userPart.first_name || "",
    last_name: userPart.last_name || "",
    displayName: userPart.display_name || userPart.full_name || userPart.username || "",
    profile: profilePart,
    is_staff: Boolean(userPart.is_staff),
  });
}

export function normalizeProfileRecord(profile) {
  if (!profile) {
    return null;
  }
  const { firstName, lastName, displayName } = splitFullName(profile.full_name, profile.username);
  const locationParts = parseLocationLabel(profile.location_label);
  return {
    id: profile.user_id || profile.userId || profile.user || profile.id || profile.username,
    profileId: profile.id || null,
    username: profile.username || "",
    firstName,
    lastName,
    displayName,
    email: profile.email || "",
    phone: profile.phone || "",
    barangay: locationParts.barangay,
    streetAddress: locationParts.streetAddress,
    bio: profile.bio || "",
    profilePhotoName: profile.profile_photo ? String(profile.profile_photo).split("/").pop() : "",
    profilePhotoPreview: profile.profile_photo_url || profile.profile_photo || "",
    skills: profile.skills || [],
    hourlyRate: profile.hourly_rate || "0.00",
    dailyRate: profile.daily_rate || "0.00",
    yearsExperience: profile.years_experience ?? "0",
    verification: getWorkerVerificationLabel(profile.verification_status),
    rating: profile.display_rating || "No ratings yet",
    reviewsDone: profile.rating_count || 0,
    latitude: profile.latitude,
    longitude: profile.longitude,
    availabilityWindows: (profile.availability_windows || []).map(normalizeAvailabilityWindow).filter(Boolean),
    role: profile.role || profile.user_type || "worker",
    verificationSubmission: normalizeVerificationRequest(profile.verification_request),
    verificationRequestId: profile.verification_request?.id || null,
    memberSince: profile.date_joined || "",
    // Admin-only (see PublicUserProfileSerializer) -- undefined for a
    // non-staff caller, so isBlocked/isStaff read as falsy rather than
    // crashing.
    isBlocked: Boolean(profile.is_blocked),
    blockedUntil: profile.blocked_until || null,
    blockedReason: profile.blocked_reason || "",
    isStaff: Boolean(profile.is_staff),
  };
}

export function getApiErrorMessage(data, fallback) {
  if (!data) {
    return fallback;
  }
  if (typeof data === "string") {
    return data || fallback;
  }
  if (data.detail) {
    return data.detail;
  }
  const fieldError = Object.values(data)
    .flatMap((value) => (Array.isArray(value) ? value : [value]))
    .find(Boolean);
  if (fieldError) {
    return String(fieldError);
  }
  return fallback;
}

export function normalizeJobRecord(job) {
  if (job?.status === "Found a worker" || job?.status === "Already found a worker" || job?.cancellationReason === "Worker hired") {
    return { ...job, status: "Already found a worker", cancellationReason: "" };
  }
  return job;
}

function normalizeJobStatus(status) {
  const normalized = String(status || "").trim().toLowerCase();
  if (normalized === "assigned" || normalized === "found a worker" || normalized === "already found a worker") {
    return "Already found a worker";
  }
  if (normalized === "completion_requested" || normalized === "completion requested" || normalized === "waiting for household confirmation") {
    return "Waiting for Household Confirmation";
  }
  if (normalized === "completed") {
    return "Completed";
  }
  if (normalized === "cancelled" || normalized === "canceled") {
    return "Cancelled";
  }
  return "Open";
}

function normalizeJobApplicationStatus(status) {
  const normalized = String(status || "").trim().toLowerCase();
  if (normalized === "hired") {
    return "Hired";
  }
  if (normalized === "hire_requested" || normalized === "hire requested") {
    return "Hire Request";
  }
  if (normalized === "rejected") {
    return "Rejected";
  }
  if (normalized === "closed") {
    return "Closed";
  }
  if (normalized === "completed") {
    return "Completed";
  }
  return "Pending";
}

export function normalizeBackendApplication(application) {
  if (!application) {
    return null;
  }
  return {
    id: application.id,
    workerId: application.worker ?? application.worker_id ?? null,
    workerUsername: application.worker_username || application.workerUsername || "",
    householdPhone: application.household_phone || application.householdPhone || "",
    householdEmail: application.household_email || application.householdEmail || "",
    workerName: application.worker_name || application.workerName || application.worker_username || "Worker",
    workerLocationLabel: application.worker_location_label || application.workerLocationLabel || "",
    // Profile details the applicant cards render, straight off the
    // application so the card doesn't depend on a separate profile fetch.
    workerPhotoUrl: application.worker_profile_photo_url || application.workerPhotoUrl || "",
    workerSkills: application.worker_skills || application.workerSkills || [],
    workerBio: application.worker_bio || application.workerBio || "",
    workerVerification: getWorkerVerificationLabel(
      application.worker_verification_status || application.workerVerificationStatus,
    ),
    workerRatingLabel: application.worker_rating_label || application.workerRatingLabel || "No ratings yet",
    workerRatingCount: application.worker_rating_count ?? application.workerRatingCount ?? 0,
    workerCompletedJobs: application.worker_completed_jobs ?? application.workerCompletedJobs ?? 0,
    workerMatchScore: application.worker_match_score ?? application.workerMatchScore ?? null,
    workerDailyRate: application.worker_daily_rate || application.workerDailyRate || "",
    // The API only fills these (and routePoints) once the worker is hired for
    // this job; before that they are null/empty and only the distance is set.
    workerLatitude: application.worker_latitude ?? application.workerLatitude ?? null,
    workerLongitude: application.worker_longitude ?? application.workerLongitude ?? null,
    routeDistanceKm: application.route_distance_km ?? application.routeDistanceKm ?? null,
    distanceLabel: application.distance_label || application.distanceLabel || "",
    routePoints: application.route_points || application.routePoints || [],
    status: normalizeJobApplicationStatus(application.status),
    // The backend owns the display vocabulary (apps/jobs/statuses.py) so the
    // web and Flutter clients cannot drift apart; `status` above stays for the
    // existing client-side branching only.
    statusStage: application.status_stage || application.statusStage || "",
    statusLabel: application.status_label || application.statusLabel || "",
    appliedAt: application.applied_at || application.appliedAt || "",
    updatedAt: application.updated_at || application.updatedAt || "",
    note: application.note || "",
    // Whether the household can still review this particular worker; the
    // job-level canReview only says some worker on the job is left.
    householdCanReview: Boolean(application.household_can_review ?? application.householdCanReview ?? false),
  };
}

export function normalizeBackendJob(job) {
  if (!job) {
    return null;
  }
  const applications = (job.applications || []).map(normalizeBackendApplication).filter(Boolean);
  const currentWorkerApplication = normalizeBackendApplication(
    job.current_worker_application || job.currentWorkerApplication || null,
  );
  const hiredApplications = applications.filter((application) => ["Hired", "Completed"].includes(application.status));
  const hiredCount = Number(job.hired_count ?? job.hiredCount ?? hiredApplications.length ?? 0);
  const workersNeeded = Number(job.workers_needed ?? job.workersNeeded ?? job.worker_slots ?? 1);
  const parsedLocation = parseLocationLabel(job.location_label || job.locationLabel || job.barangay || "");
  const images = (job.images || []).map((image) => ({
    id: image.id,
    image: image.image_url || image.image,
    uploadedAt: image.uploaded_at || image.uploadedAt || "",
    order: image.order ?? 0,
  }));
  return normalizeJobRecord({
    id: job.id,
    householdUsername: job.household_username || job.householdUsername || "",
    householdName: job.household_name || job.householdName || job.household_username || "Household",
    householdVerificationStatus:
      job.household_verification_status || job.householdVerificationStatus || "",
    // Only the JobApplication payload carries these (gated server-side to
    // the hired worker viewing their own application), not the job itself.
    householdPhone: currentWorkerApplication?.householdPhone || "",
    householdEmail: currentWorkerApplication?.householdEmail || "",
    jobTitle: job.title || job.job_title || job.required_skill || job.jobType || "",
    serviceType: job.required_skill || job.job_type || job.jobType || job.title || "",
    scheduleType: job.schedule_type || job.scheduleType || job.schedule || "One-Time",
    description: job.description || "",
    jobStartDate: job.job_start_date || job.jobStartDate || "",
    jobEndDate: job.job_end_date || job.jobEndDate || "",
    estimatedWorkingDays: job.estimated_working_days ?? job.estimatedWorkingDays ?? null,
    maxDistanceKm: job.max_distance_km ?? job.maxDistanceKm ?? null,
    geographicBoundary: job.geographic_boundary || job.geographicBoundary || "",
    barangay: parsedLocation.barangay || job.barangay || "",
    streetAddress: job.street_address || parsedLocation.streetAddress || "",
    latitude: job.latitude ?? job.job_latitude ?? null,
    longitude: job.longitude ?? job.job_longitude ?? null,
    approximateLatitude: job.approximate_latitude ?? job.approximateLatitude ?? null,
    approximateLongitude: job.approximate_longitude ?? job.approximateLongitude ?? null,
    routeDistanceKm: job.route_distance_km ?? job.routeDistanceKm ?? null,
    distanceLabel: job.distance_label || job.distanceLabel || "",
    routePoints: job.route_points || job.routePoints || [],
    offeredRate: String(job.service_rate ?? "0.00"),
    rateType: job.rate_type_label || job.job_rate_type_label || "Per Day",
    workersNeeded,
    hiredCount,
    status: normalizeJobStatus(job.status),
    statusStage: job.status_stage || job.statusStage || "",
    statusLabel: job.status_label || job.statusLabel || "",
    matchedWorkerIds: hiredApplications.map((application) => application.workerId).filter(Boolean),
    selectedWorkerId: hiredApplications[0]?.workerId || null,
    selectedWorkerName: hiredApplications[0]?.workerName || "",
    hiredAt: hiredApplications[0]?.appliedAt || "",
    applicationStatus: currentWorkerApplication?.status || "",
    applicationId: currentWorkerApplication?.id || null,
    appliedAt: currentWorkerApplication?.appliedAt || "",
    updatedAt: currentWorkerApplication?.updatedAt || "",
    currentWorkerApplication,
    canApply: Boolean(job.can_apply ?? job.canApply ?? false),
    canAcceptHireRequest: Boolean(job.can_accept_hire_request ?? job.canAcceptHireRequest ?? false),
    canRequestCompletion: Boolean(job.can_request_completion ?? job.canRequestCompletion ?? false),
    canReview: Boolean(job.can_review ?? job.canReview ?? false),
    applications,
    images,
    createdAt: job.created_at || job.createdAt || new Date().toISOString(),
    completedAt: job.completed_at || job.completedAt || "",
  });
}

export function normalizeBackendNotification(notification) {
  if (!notification) {
    return null;
  }
  return {
    id: `backend-notification-${notification.id}`,
    backendId: notification.id,
    notificationType: notification.notification_type || notification.notificationType || "generic",
    title: notification.title || "Notification",
    message: notification.message || "",
    actorId: notification.actor ?? notification.actor_id ?? notification.actorId ?? null,
    actorUsername: notification.actor_username || notification.actorUsername || "",
    jobId: notification.related_job_id ?? notification.relatedJobId ?? notification.job_id ?? notification.jobId ?? null,
    applicationId:
      notification.related_application_id ??
      notification.relatedApplicationId ??
      notification.application_id ??
      notification.applicationId ??
      null,
    actionType: notification.action_type || notification.actionType || "",
    actionUrl: notification.action_url || notification.actionUrl || "",
    requiresAction: Boolean(notification.requires_action ?? notification.requiresAction ?? false),
    date: notification.created_at || notification.createdAt || "Recently",
    unread: !notification.is_read,
  };
}

export function normalizeBackendReview(review) {
  if (!review) {
    return null;
  }
  return normalizeReview({
    id: review.id,
    authorRole: review.author_role || review.authorRole || "",
    authorUsername: review.author_username || review.authorUsername || "",
    authorName: review.author_name || review.authorName || review.author_username || "User",
    targetUsername: review.target_username || review.targetUsername || "",
    targetName: review.target_name || review.targetName || review.target_username || "User",
    rating: review.rating ?? null,
    feedback: review.feedback || "",
    jobId: review.job || review.job_id || review.jobId || "",
    jobTitle: review.job_title || review.jobTitle || "",
    qualityOfWork: review.quality_of_work ?? review.qualityOfWork ?? null,
    punctuality: review.punctuality ?? null,
    communication: review.communication ?? null,
    professionalism: review.professionalism ?? null,
    overallRating: review.overall_rating ?? review.overallRating ?? null,
    createdAt: review.created_at || review.createdAt || new Date().toLocaleString("en-PH"),
  });
}

function normalizeComplaintParty(detail) {
  if (!detail) {
    return null;
  }
  return {
    username: detail.username || "",
    displayName: detail.display_name || detail.username || "",
    role: detail.role || "",
    averageRating: detail.average_rating != null ? Number(detail.average_rating) : null,
    ratingCount: detail.rating_count || 0,
    locationLabel: detail.location_label || "",
    memberSince: detail.member_since || "",
    phone: detail.phone || "",
    email: detail.email || "",
  };
}

export function normalizeBackendComplaint(complaint) {
  if (!complaint) {
    return null;
  }
  return {
    id: complaint.id,
    complainantUsername: complaint.complainant_username || "",
    respondentUsername: complaint.respondent_username || "",
    complainantDetail: normalizeComplaintParty(complaint.complainant_detail),
    respondentDetail: normalizeComplaintParty(complaint.respondent_detail),
    jobId: complaint.job || null,
    jobTitle: complaint.job_title || "",
    jobName: complaint.job_name || "",
    jobBarangay: complaint.job_barangay || "",
    jobServiceType: complaint.job_service_type || "",
    jobStatus: complaint.job_status || "",
    complaintType: complaint.complaint_type || "",
    description: complaint.description || "",
    evidence: (complaint.evidence || [])
      .map((item) => ({ id: item.id, imageUrl: item.image_url || "" }))
      .filter((item) => item.imageUrl),
    respondentIsBlocked: Boolean(complaint.respondent_is_blocked),
    respondentBlockedUntil: complaint.respondent_blocked_until || null,
    status: complaint.status || "submitted",
    resolution: complaint.resolution || "",
    adminNotes: complaint.admin_notes || "",
    createdAt: complaint.created_at || "",
    updatedAt: complaint.updated_at || "",
  };
}

export function dedupeNotifications(notifications) {
  const seenKeys = new Set();
  return notifications.filter((notification) => {
    const type = String(notification.notificationType || notification.type || "generic").toLowerCase();
    const title = String(notification.title || "").trim().toLowerCase();
    const actor =
      notification.workerId ||
      notification.actorId ||
      notification.actorUsername ||
      notification.workerUsername ||
      "";
    const job = notification.jobId || "";
    const application = notification.applicationId || "";
    const key =
      type === "application" || title === "new worker application"
        ? `application-${job}-${actor || application}`
        : type === "verification"
          ? `verification-${title}-${notification.backendId || notification.id}`
          : `${type}-${title}-${job}-${application}-${String(notification.message || "").trim().toLowerCase()}`;
    if (seenKeys.has(key)) {
      return false;
    }
    seenKeys.add(key);
    return true;
  });
}

export function isNumericIdentifier(value) {
  if (value == null || value === "") {
    return false;
  }
  return /^\d+$/.test(String(value));
}

export function normalizeCertificate(certificate) {
  if (!certificate) {
    return null;
  }
  return {
    id: certificate.id,
    workerUsername: certificate.worker_username || "",
    workerName: certificate.worker_name || certificate.worker_username || "",
    workerLocationLabel: certificate.worker_location_label || "",
    workerMemberSince: certificate.worker_member_since || "",
    certificateType: certificate.certificate_type || "",
    certificateTypeLabel: certificate.certificate_type_label || certificate.certificate_type || "",
    certificateName: certificate.certificate_name || "",
    issuer: certificate.issuer || "",
    issueDate: certificate.issue_date || "",
    expiryDate: certificate.expiry_date || "",
    fileUrl: certificate.certificate_file_url || certificate.certificate_file || "",
    // "image" | "pdf" | "file" | "" -- the file URL is a permission-checked
    // API route with no extension, so the type has to come from the backend.
    fileType: certificate.certificate_file_type || "",
    isVerified: Boolean(certificate.is_verified),
    verificationStatus: certificate.verification_status || "pending",
    verificationNotes: certificate.verification_notes || "",
    verifiedByUsername: certificate.verified_by_username || "",
    verifiedAt: certificate.verified_at || "",
    createdAt: certificate.created_at || "",
  };
}

// Sidebar label for the verification page. New profiles default to
// verification_status "pending", so "Under Review" must come from an actual
// submitted request -- otherwise an account that never uploaded an ID read
// "Under Review".
export function getVerificationNavLabel(account) {
  if (account?.verification === "Verified") return "Verified";
  if (["Pending", "Under Review"].includes(account?.verificationSubmission?.status)) return "Under Review";
  if (account?.verification === "Rejected") return "Verify Again";
  return "Get Verified";
}
