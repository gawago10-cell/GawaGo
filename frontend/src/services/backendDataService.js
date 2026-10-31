import { apiRequest } from "../api/apiClient";
import { getDisplayName } from "../utils/formatters";
import { readResponseData } from "../utils/apiUtils";
import {
  normalizeBackendComplaint,
  normalizeBackendJob,
  normalizeBackendNotification,
  normalizeBackendReview,
  normalizeBackendWorker,
  normalizeAvailabilityWindow,
  normalizeCertificate,
  normalizeProfileRecord,
  normalizeVerificationRequest,
  getApiErrorMessage,
} from "../utils/normalizers";

function unwrapRecords(data) {
  return Array.isArray(data) ? data : data?.results || [];
}

// DRF paginates list endpoints at PAGE_SIZE (20). The app holds these as
// complete collections, so reading only `results` silently drops everything
// past the first page once a list outgrows it -- follow `next` instead.
const MAX_PAGES = 100;

async function fetchAllRecords(path, options) {
  const records = [];
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const separator = path.includes("?") ? "&" : "?";
    const response = await apiRequest(page === 1 ? path : `${path}${separator}page=${page}`, options);
    if (!response.ok) {
      // A failure on any page -- not just the first -- must not resolve to a
      // truncated-but-successful-looking list: callers treat `null` as "keep
      // whatever we already had" and a real array as "this is the complete,
      // current collection," so a partial page here would silently replace
      // good state with fewer records and no visible error.
      return null;
    }
    const data = await readResponseData(response);
    if (Array.isArray(data)) {
      return data;
    }
    records.push(...(data?.results || []));
    if (!data?.next) {
      return records;
    }
  }
  console.warn(`fetchAllRecords: stopped at MAX_PAGES (${MAX_PAGES}) for ${path}; collection may be incomplete.`);
  return records;
}

export async function fetchVerificationRequests() {
  const records = await fetchAllRecords("common/verification-requests/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!records) {
    return null;
  }
  return records.map(normalizeVerificationRequest).filter(Boolean);
}

export async function fetchAdminAuditLog() {
  const records = await fetchAllRecords("common/admin-action-log/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!records) {
    return null;
  }
  return records.map((row) => ({
    id: `admin-action-${row.id}`,
    timestamp: row.created_at,
    admin: row.actor_username || "Unknown admin",
    action: row.action_label || row.action,
    target: row.target_label || "",
    detail: row.detail || "",
  }));
}

function normalizeAdminAccount(row) {
  return {
    id: row.id,
    username: row.username || "",
    email: row.email || "",
    displayName: row.full_name || row.username || "",
    isActive: Boolean(row.is_active),
    isOwner: Boolean(row.is_superuser),
    roleLabel: row.role_label || (row.is_superuser ? "Full System Control" : "Admin"),
    lastLogin: row.last_login || null,
    dateJoined: row.date_joined || null,
  };
}

export async function fetchAdminAccounts() {
  const records = await fetchAllRecords("accounts/admin/admins/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!records) {
    return null;
  }
  return records.map(normalizeAdminAccount);
}

export async function createAdminAccount({ username, email, password, firstName, lastName }) {
  const response = await apiRequest("accounts/admin/admins/", {
    method: "POST",
    auth: true,
    body: {
      username,
      email,
      password,
      first_name: firstName || "",
      last_name: lastName || "",
    },
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(getApiErrorMessage(data, "Unable to create that admin account."));
  }
  return normalizeAdminAccount(data);
}

export async function setAdminAccountActive(username, isActive) {
  const response = await apiRequest(`accounts/admin/admins/${encodeURIComponent(username)}/`, {
    method: "PATCH",
    auth: true,
    body: { is_active: isActive },
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(getApiErrorMessage(data, "Unable to update that admin account."));
  }
  return normalizeAdminAccount(data);
}

export async function fetchCurrentAccount(currentUser) {
  const response = await apiRequest("accounts/me/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!response.ok) {
    return null;
  }
  const profileData = await readResponseData(response);
  const refreshedUser = {
    id: profileData?.user?.id || currentUser.id || currentUser.username,
    role: currentUser.role,
    username: profileData?.user?.username || currentUser.username,
    email: profileData?.user?.email || currentUser.email || "",
    first_name: profileData?.user?.first_name || currentUser.first_name || "",
    last_name: profileData?.user?.last_name || currentUser.last_name || "",
    displayName: profileData?.user?.first_name || profileData?.user?.last_name
      ? getDisplayName(profileData?.user?.first_name || "", profileData?.user?.last_name || "", profileData?.user?.username || currentUser.username)
      : (currentUser.displayName || currentUser.username),
    profile: profileData?.profile || currentUser.profile || null,
    is_staff: Boolean(currentUser.is_staff),
  };
  return {
    refreshedUser,
    worker: normalizeBackendWorker(refreshedUser),
  };
}

export async function updateWorkerAvailability(availabilityWindows) {
  const response = await apiRequest("accounts/me/availability/", {
    method: "PUT",
    auth: true,
    body: {
      availability_windows: (availabilityWindows || []).map((window) => ({
        date: window.date,
        start_time: window.startTime,
        end_time: window.endTime,
        is_available: window.isAvailable !== false,
      })),
    },
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(getApiErrorMessage(data, "Unable to update availability."));
  }
  return unwrapRecords(data).map(normalizeAvailabilityWindow).filter(Boolean);
}

export async function fetchJobs() {
  const records = await fetchAllRecords("jobs/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!records) {
    return null;
  }
  return records.map(normalizeBackendJob).filter(Boolean);
}

export async function fetchMyAccount() {
  const response = await apiRequest("accounts/me/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!response.ok) {
    return null;
  }
  return readResponseData(response);
}

export async function fetchWorkerEmploymentHistory(workerId) {
  const records = await fetchAllRecords(`jobs/?worker=${workerId}&status=completed`, {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!records) {
    return null;
  }
  return records.map((job) => ({
    id: job.id,
    title: job.title,
    household_name: job.household_name,
    location: job.location_label || "",
    completed_at: job.completed_at,
    skill_ratings: job.skill_ratings || [],
  }));
}

export async function fetchMyPortfolio() {
  const response = await apiRequest("accounts/me/portfolio/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!response.ok) {
    return null;
  }
  const data = await readResponseData(response);
  return {
    bio: data?.bio || "",
    yearsExperience: data?.years_experience ?? 0,
    // One entry per profile skill (the backend keeps the two in step), with
    // the proficiency the worker set and the households' rating.
    portfolioSkills: (data?.skills || []).map((item) => ({
      id: item.id,
      name: item.skill_name || "",
      proficiency: item.proficiency || "",
      averageRating: item.average_rating ?? null,
      ratingCount: item.rating_count ?? 0,
    })),
    certifications: (data?.certifications || []).map((item) => ({
      id: item.id,
      name: item.certificate_name || "",
      certificateType: item.certificate_type || "",
      issuer: item.issuer || "",
      issueDate: item.issue_date || "",
      expiryDate: item.expiry_date || "",
      verificationStatus: item.verification_status || "pending",
      isVerified: Boolean(item.is_verified),
      certificatePreview: item.certificate_file_url || "",
      fileType: item.certificate_file_type || "",
    })),
    workSamples: (data?.portfolio_items || []).map((item) => ({
      id: item.id,
      title: item.title || "",
      description: item.description || "",
      beforePreview: item.before_image_url || item.image_url || "",
      afterPreview: item.after_image_url || "",
    })),
  };
}

export async function updatePortfolioSkillProficiency(skillId, proficiency) {
  const response = await apiRequest(`accounts/me/portfolio/skills/${skillId}/`, {
    method: "PATCH",
    auth: true,
    body: { proficiency },
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(getApiErrorMessage(data, "Unable to update this skill."));
  }
  return data;
}

export async function deletePortfolioCertification(certificationId) {
  const response = await apiRequest(`accounts/me/portfolio/certifications/${certificationId}/`, {
    method: "DELETE",
    auth: true,
  });
  if (!response.ok && response.status !== 404) {
    const data = await readResponseData(response);
    throw new Error(getApiErrorMessage(data, "Unable to delete this certification."));
  }
}

export async function deletePortfolioItem(itemId) {
  const response = await apiRequest(`accounts/me/portfolio/items/${itemId}/`, {
    method: "DELETE",
    auth: true,
  });
  if (!response.ok && response.status !== 404) {
    const data = await readResponseData(response);
    throw new Error(getApiErrorMessage(data, "Unable to delete this work sample."));
  }
}

export async function fetchProfiles() {
  const records = await fetchAllRecords("accounts/profiles/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!records) {
    return null;
  }
  const normalizedProfiles = records.map(normalizeProfileRecord).filter(Boolean);
  return {
    normalizedProfiles,
    workerProfiles: normalizedProfiles.filter((profile) => profile.role === "worker"),
    householdProfiles: normalizedProfiles.filter((profile) => profile.role === "household"),
  };
}

export async function fetchRecommendedWorkers(jobId, rank) {
  const rankParam = rank ? `&rank=${encodeURIComponent(rank)}` : "";
  const response = await apiRequest(`matching/recommended-workers/?job_id=${encodeURIComponent(jobId)}${rankParam}`, {
    auth: true,
    suppressUnauthorized: true,
  });
  if (response.status === 404) {
    return [];
  }
  if (!response.ok) {
    return null;
  }
  const data = await readResponseData(response);
  return Array.isArray(data?.results) ? data.results : [];
}

export async function fetchRecommendedJobs() {
  const response = await apiRequest("matching/recommended-jobs/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (response.status === 403) {
    return null;
  }
  if (!response.ok) {
    return null;
  }
  const data = await readResponseData(response);
  const results = Array.isArray(data?.results) ? data.results : [];
  return results
    .map((entry) => {
      const job = normalizeBackendJob(entry.job);
      if (!job) {
        return null;
      }
      return {
        ...job,
        aiScore: entry.ai_score,
        aiSkillSimilarity: entry.skill_similarity,
        aiDistanceKm: entry.distance_km,
        aiSkillContribution: entry.skill_contribution,
        aiProximityContribution: entry.proximity_contribution,
        aiExactSkillMatch: entry.exact_skill_match,
      };
    })
    .filter(Boolean);
}

export async function fetchNotifications(username) {
  const records = await fetchAllRecords("notifications/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!records) {
    return null;
  }
  return records.map(normalizeBackendNotification).filter(Boolean);
}

export async function fetchReviews({ username, role, selectedWorkerUsername = "" }) {
  const requests = [
    fetchAllRecords(`reviews/?username=${encodeURIComponent(username)}`, { auth: false, suppressUnauthorized: true }),
    fetchAllRecords(`reviews/?author_username=${encodeURIComponent(username)}`, { auth: true, suppressUnauthorized: true }),
  ];
  if (role === "household" && selectedWorkerUsername) {
    requests.push(fetchAllRecords(`reviews/?username=${encodeURIComponent(selectedWorkerUsername)}`, { auth: false, suppressUnauthorized: true }));
  }
  const results = await Promise.all(requests);
  // A failed list stays null ("keep what we had"), the same contract as
  // fetchAllRecords: turning it into [] used to blank the review screens
  // until the next poll.
  return results.map((records) => (records ? records.map(normalizeBackendReview).filter(Boolean) : null));
}

// Chat between a household and the worker it hired. A conversation id is the
// hire's JobApplication id; the backend refuses (403) once the hire is no
// longer active, so errors carry the HTTP status for the widget to react to.
function normalizeChatMessage(message) {
  return {
    id: message.id,
    conversationId: message.conversation_id,
    senderId: message.sender_id,
    senderName: message.sender_name || "",
    isMine: Boolean(message.is_mine),
    content: message.content || "",
    createdAt: message.created_at || "",
    isRead: Boolean(message.is_read),
    status: "sent",
  };
}

function normalizeConversation(conversation) {
  const other = conversation.other_party || {};
  return {
    id: conversation.id,
    jobId: conversation.job_id,
    jobTitle: conversation.job_title || "Service Request",
    statusLabel: conversation.status_label || "",
    serviceRate: conversation.service_rate,
    otherPartyName: other.name || other.username || "",
    otherPartyRole: other.role || "",
    otherPartyPhoto: other.photo_url || "",
    lastMessage: conversation.last_message ? normalizeChatMessage(conversation.last_message) : null,
    unreadCount: conversation.unread_count || 0,
  };
}

async function chatRequest(path, options, fallbackMessage) {
  const response = await apiRequest(path, { auth: true, ...options });
  const data = await readResponseData(response);
  if (!response.ok) {
    const error = new Error(getApiErrorMessage(data, fallbackMessage));
    error.status = response.status;
    throw error;
  }
  return data;
}

export async function getConversations() {
  const data = await chatRequest("conversations/", { suppressUnauthorized: true }, "Unable to load conversations.");
  return unwrapRecords(data).map(normalizeConversation);
}

export async function getMessages(hireId, afterId = null) {
  const query = afterId ? `?after=${encodeURIComponent(afterId)}` : "";
  const data = await chatRequest(
    `conversations/${hireId}/messages/${query}`,
    { suppressUnauthorized: true },
    "Unable to load messages.",
  );
  return unwrapRecords(data).map(normalizeChatMessage);
}

export async function sendMessage(hireId, content) {
  const data = await chatRequest(
    `conversations/${hireId}/messages/`,
    { method: "POST", body: { content } },
    "Message not sent.",
  );
  return normalizeChatMessage(data);
}

export async function markConversationRead(hireId) {
  return chatRequest(
    `conversations/${hireId}/read/`,
    { method: "POST", suppressUnauthorized: true },
    "Unable to update messages.",
  );
}

/**
 * "Report an issue" -- an incident filed against a specific job's other
 * party (a household reporting a worker, or vice versa), reviewed by admin.
 * Distinct from the activity reports above: this is a complaint queue, not
 * a personal summary.
 */
export async function fetchMyComplaints(statusFilter) {
  const query = statusFilter ? `?status=${encodeURIComponent(statusFilter)}` : "";
  const records = await fetchAllRecords(`complaints/${query}`, { auth: true, suppressUnauthorized: true });
  if (!records) {
    return null;
  }
  return records.map(normalizeBackendComplaint).filter(Boolean);
}

export async function createComplaint({ jobId, respondentId, complaintType, description, evidence = [] }) {
  const fields = {
    job: jobId,
    respondent: respondentId,
    complaint_type: complaintType,
    description,
  };
  // Photos force multipart; without them keep the plain JSON body so the
  // existing (JSON-only) callers and tests are unaffected.
  let body = fields;
  if (evidence.length > 0) {
    body = new FormData();
    Object.entries(fields).forEach(([key, value]) => {
      if (value !== undefined && value !== null) body.append(key, value);
    });
    evidence.forEach((file) => body.append("evidence", file));
  }
  const response = await apiRequest("complaints/create/", {
    method: "POST",
    auth: true,
    body,
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(getApiErrorMessage(data, "Unable to submit this complaint."));
  }
  return normalizeBackendComplaint(data);
}

export async function fetchAdminComplaints({ status: statusFilter, type: typeFilter } = {}) {
  const params = new URLSearchParams();
  if (statusFilter) params.set("status", statusFilter);
  if (typeFilter) params.set("type", typeFilter);
  const query = params.toString();
  const records = await fetchAllRecords(`complaints/admin/${query ? `?${query}` : ""}`, {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!records) {
    return null;
  }
  return records.map(normalizeBackendComplaint).filter(Boolean);
}

export async function updateComplaintAdmin(complaintId, { status: nextStatus, resolution, adminNotes }) {
  const body = {};
  if (nextStatus !== undefined) body.status = nextStatus;
  if (resolution !== undefined) body.resolution = resolution;
  if (adminNotes !== undefined) body.admin_notes = adminNotes;
  const response = await apiRequest(`complaints/admin/${complaintId}/`, {
    method: "PATCH",
    auth: true,
    body,
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(getApiErrorMessage(data, "Unable to update this complaint."));
  }
  return normalizeBackendComplaint(data);
}

export async function setComplaintRespondentBlocked(complaintId, { blocked, reason = "", durationDays = null }) {
  const response = await apiRequest(`complaints/admin/${complaintId}/block/`, {
    method: "POST",
    auth: true,
    body: { blocked, reason, duration_days: durationDays },
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(getApiErrorMessage(data, "Unable to update this account."));
  }
  return normalizeBackendComplaint(data);
}

/**
 * The User Management screen's suspend/restore action -- targets a username
 * directly, unlike setComplaintRespondentBlocked() above which only works
 * through a complaint record. Both hit the same shared backend logic.
 */
export async function setUserAccountBlocked(username, { blocked, reason = "", durationDays = null }) {
  const response = await apiRequest(`accounts/profiles/${encodeURIComponent(username)}/block/`, {
    method: "POST",
    auth: true,
    body: { blocked, reason, duration_days: durationDays },
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(getApiErrorMessage(data, "Unable to update this account."));
  }
  return normalizeProfileRecord(data);
}

function buildReportQuery({ start, end } = {}) {
  const params = new URLSearchParams();
  if (start) params.set("start", start);
  if (end) params.set("end", end);
  const query = params.toString();
  return query ? `?${query}` : "";
}

export async function fetchPlatformReport(period) {
  const response = await apiRequest(`reports/platform/${buildReportQuery(period)}`, {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!response.ok) {
    return null;
  }
  return readResponseData(response);
}

/**
 * Reports download as CSV through the same endpoints. The browser cannot set
 * an Authorization header on a plain link, so the file is fetched normally
 * and handed to the user as an object URL.
 */
export async function downloadPlatformReportCsv(period) {
  const query = buildReportQuery(period);
  const separator = query ? "&" : "?";
  const response = await apiRequest(`reports/platform/${query}${separator}export=csv`, { auth: true });
  if (!response.ok) {
    throw new Error("Unable to download the report.");
  }
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "gawago-platform-report.csv";
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
  return true;
}

/** The superadmin complaints queue as CSV, with the same status filter. */
export async function downloadComplaintsCsv({ status: statusFilter } = {}) {
  const params = new URLSearchParams({ export: "csv" });
  if (statusFilter) params.set("status", statusFilter);
  const response = await apiRequest(`complaints/admin/?${params.toString()}`, { auth: true });
  if (!response.ok) {
    throw new Error("Unable to download the complaints.");
  }
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `gawago-complaints${statusFilter ? `-${statusFilter}` : ""}.csv`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
  return true;
}

export async function fetchDashboardMetrics() {
  const response = await apiRequest("analytics/dashboard-metrics/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!response.ok) {
    throw new Error("Failed to load dashboard metrics");
  }
  return readResponseData(response);
}

export async function markBackendNotificationRead(backendId) {
  if (!backendId) {
    return false;
  }
  const response = await apiRequest(`notifications/${backendId}/read/`, {
    method: "PATCH",
    auth: true,
    suppressUnauthorized: true,
  });
  return response.ok;
}

export async function deleteBackendNotification(backendId) {
  if (!backendId) {
    return false;
  }
  const response = await apiRequest(`notifications/${backendId}/`, {
    method: "DELETE",
    auth: true,
  });
  if (!response.ok) {
    const data = await readResponseData(response);
    throw new Error(getApiErrorMessage(data, "Unable to delete notification."));
  }
  return true;
}

export async function requestPasswordReset(email) {
  const response = await apiRequest("accounts/forgot-password/", {
    method: "POST",
    auth: false,
    body: { email },
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(data?.detail || "Unable to send reset code.");
  }
  return data;
}

export async function verifyPasswordResetToken(email, token) {
  const response = await apiRequest("accounts/verify-reset-token/", {
    method: "POST",
    auth: false,
    body: { email, token },
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(data?.detail || "Invalid reset code.");
  }
  return data;
}

export async function resetPassword({ email, token, newPassword }) {
  const response = await apiRequest("accounts/reset-password/", {
    method: "POST",
    auth: false,
    body: { email, token, new_password: newPassword },
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(data?.detail || "Unable to reset password.");
  }
  return data;
}

/**
 * Admin certificate verification (panelist feature #11) and worker ID
 * document verification (#12). Both backends shipped with tests but no UI,
 * so these are the client calls that finally make them reachable.
 */
export async function fetchAdminCertificates(statusFilter = "pending") {
  const query = statusFilter ? `?status=${encodeURIComponent(statusFilter)}` : "";
  const records = await fetchAllRecords(`accounts/admin/certificates/${query}`, {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!records) {
    return null;
  }
  return records.map(normalizeCertificate).filter(Boolean);
}

export async function reviewCertificate(certificateId, { status, notes = "" }) {
  const response = await apiRequest(`accounts/admin/certificates/${certificateId}/`, {
    method: "PATCH",
    auth: true,
    body: { verification_status: status, verification_notes: notes },
  });
  const data = await readResponseData(response);
  if (!response.ok) {
    throw new Error(getApiErrorMessage(data, "Unable to review this certificate."));
  }
  return normalizeCertificate(data);
}

