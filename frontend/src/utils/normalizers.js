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
    jobTitle: review.jobTitle || "",
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

export function normalizeWeeklyAvailabilityWindow(window) {
  if (!window) {
    return null;
  }
  return {
    id: window.id || `weekly-availability-${window.weekday ?? Date.now()}`,
    weekday: Number(window.weekday),
    weekdayLabel: window.weekday_label || window.weekdayLabel || "",
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
    weeklyAvailability: (profile.weekly_availability || [])
      .map(normalizeWeeklyAvailabilityWindow)
      .filter(Boolean),
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
    profilePhotoPreview: profile.profile_photo_url || profile.profile_photo || "",
    availabilityWindows: (profile.availability_windows || []).map(normalizeAvailabilityWindow).filter(Boolean),
    weeklyAvailability: (profile.weekly_availability || [])
      .map(normalizeWeeklyAvailabilityWindow)
      .filter(Boolean),
    role: profile.role || profile.user_type || "worker",
    verificationSubmission: normalizeVerificationRequest(profile.verification_request),
    verificationRequestId: profile.verification_request?.id || null,
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
    workerName: application.worker_name || application.workerName || application.worker_username || "Worker",
    workerLocationLabel: application.worker_location_label || application.workerLocationLabel || "",
    workerLatitude: application.worker_latitude ?? application.workerLatitude ?? null,
    workerLongitude: application.worker_longitude ?? application.workerLongitude ?? null,
    routeDistanceKm: application.route_distance_km ?? application.routeDistanceKm ?? null,
    routePoints: application.route_points || application.routePoints || [],
    status: normalizeJobApplicationStatus(application.status),
    appliedAt: application.applied_at || application.appliedAt || "",
    updatedAt: application.updated_at || application.updatedAt || "",
    note: application.note || "",
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
    jobTitle: job.title || job.job_title || job.required_skill || job.jobType || "",
    serviceType: job.required_skill || job.job_type || job.jobType || job.title || "",
    scheduleType: job.schedule_type || job.scheduleType || job.schedule || "One-Time",
    preferredDate: job.preferred_date || "",
    preferredTime: job.preferred_time || "",
    description: job.description || "",
    barangay: parsedLocation.barangay || job.barangay || "",
    streetAddress: job.street_address || parsedLocation.streetAddress || "",
    latitude: job.latitude ?? job.job_latitude ?? null,
    longitude: job.longitude ?? job.job_longitude ?? null,
    routeDistanceKm: job.route_distance_km ?? job.routeDistanceKm ?? null,
    routePoints: job.route_points || job.routePoints || [],
    offeredRate: String(job.service_rate ?? "0.00"),
    rateType: "Per Day",
    workersNeeded,
    hiredCount,
    status: normalizeJobStatus(job.status),
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
    notificationType: notification.notification_type || notification.notificationType || "analytics",
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
    createdAt: review.created_at || review.createdAt || new Date().toLocaleString("en-PH"),
  });
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
