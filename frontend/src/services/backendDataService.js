import { apiRequest } from "../api/apiClient";
import { getDisplayName } from "../utils/formatters";
import { readResponseData } from "../utils/apiUtils";
import {
  normalizeBackendJob,
  normalizeBackendNotification,
  normalizeBackendReview,
  normalizeBackendWorker,
  normalizeAvailabilityWindow,
  normalizeProfileRecord,
  normalizeVerificationRequest,
  getApiErrorMessage,
} from "../utils/normalizers";

function unwrapRecords(data) {
  return Array.isArray(data) ? data : data?.results || [];
}

export async function fetchVerificationRequests() {
  const response = await apiRequest("common/verification-requests/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!response.ok) {
    return null;
  }
  const data = await readResponseData(response);
  return unwrapRecords(data).map(normalizeVerificationRequest).filter(Boolean);
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
  const response = await apiRequest("jobs/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!response.ok) {
    return null;
  }
  const data = await readResponseData(response);
  return unwrapRecords(data).map(normalizeBackendJob).filter(Boolean);
}

export async function fetchProfiles() {
  const response = await apiRequest("accounts/profiles/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!response.ok) {
    return null;
  }
  const data = await readResponseData(response);
  const normalizedProfiles = unwrapRecords(data).map(normalizeProfileRecord).filter(Boolean);
  return {
    normalizedProfiles,
    workerProfiles: normalizedProfiles.filter((profile) => profile.role === "worker"),
    householdProfiles: normalizedProfiles.filter((profile) => profile.role === "household"),
  };
}

export async function fetchRecommendedWorkers(jobId) {
  const response = await apiRequest(`matching/recommended-workers/?job_id=${encodeURIComponent(jobId)}`, {
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
      };
    })
    .filter(Boolean);
}

export async function fetchNotifications(username) {
  const response = await apiRequest("notifications/", {
    auth: true,
    suppressUnauthorized: true,
  });
  if (!response.ok) {
    return null;
  }
  const data = await readResponseData(response);
  return unwrapRecords(data).map(normalizeBackendNotification).filter(Boolean);
}

export async function fetchReviews({ username, role, selectedWorkerUsername = "" }) {
  const requests = [
    apiRequest(`reviews/?username=${encodeURIComponent(username)}`, { auth: false, suppressUnauthorized: true }),
    apiRequest(`reviews/?author_username=${encodeURIComponent(username)}`, { auth: true, suppressUnauthorized: true }),
  ];
  if (role === "household" && selectedWorkerUsername) {
    requests.push(apiRequest(`reviews/?username=${encodeURIComponent(selectedWorkerUsername)}`, { auth: false, suppressUnauthorized: true }));
  }
  const responses = await Promise.all(requests);
  return Promise.all(responses.map(async (response) => {
    if (!response.ok) {
      return [];
    }
    const data = await readResponseData(response);
    return unwrapRecords(data).map(normalizeBackendReview).filter(Boolean);
  }));
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
