import { apiRequest, clearAuthToken, getApiBaseUrl } from "../api/apiClient";
import { EMPTY_HOUSEHOLD_FORM, EMPTY_WORKER_FORM } from "../constants/appConstants";
import { getSavedHouseholdLocation } from "../utils/locationServices";
import { markBackendNotificationRead } from "../services/backendDataService";

export function useGawaGoNavigation({
  backendNotifications,
  currentHousehold,
  currentUser,
  currentWorker,
  householdNotificationsWithReadState,
  refreshNotificationsFromBackend,
  selectedJob,
  setAdminSection,
  setCurrentUser,
  setForgotPasswordError,
  setForgotPasswordForm,
  setForgotPasswordNotice,
  setForgotPasswordStep,
  setHouseholdForm,
  setHouseholdJobCoordinates,
  setHouseholdJobForm,
  setHouseholdJobLocationPreview,
  setHouseholdProfileForm,
  setLoginForm,
  setNotificationReads,
  setSelectedJobId,
  setSelectedVerificationRequestId,
  setSelectedWorkerId,
  setView,
  setWorkerForm,
  setWorkerProfileForm,
  workerApplications,
  workerNotificationsWithReadState,
}) {
  function goHome() {
    setView("home");
  }

  function goBack() {
    if (currentUser?.role === "superadmin") {
      setView("superadmin-dashboard");
      return;
    }
    if (currentUser?.role === "admin") {
      setView("admin-dashboard");
      return;
    }
    if (currentUser?.role === "household") {
      setView("household-dashboard");
      return;
    }
    if (currentUser?.role === "worker") {
      setView("worker-dashboard");
      return;
    }
    setView("home");
  }

  function handleLogout() {
    clearAuthToken();
    setCurrentUser(null);
    setSelectedWorkerId(null);
    setSelectedJobId(null);
    setLoginForm({
      username: "",
      password: "",
      role: "",
    });
    setView("home");
  }

  function openLogin() {
    setForgotPasswordStep("email");
    setForgotPasswordNotice("");
    setForgotPasswordError("");
    setView("login");
  }

  function openForgotPassword() {
    setForgotPasswordStep("email");
    setForgotPasswordNotice("");
    setForgotPasswordError("");
    setForgotPasswordForm({
      email: "",
      token: "",
      newPassword: "",
      confirmPassword: "",
    });
    setView("forgot-password");
  }

  function openWorkerRegister() {
    setWorkerForm(EMPTY_WORKER_FORM);
    setView("register-worker");
  }

  function openHouseholdRegister() {
    setHouseholdForm(EMPTY_HOUSEHOLD_FORM);
    setView("register-household");
  }

  function openWorkerDashboard() {
    setView("worker-dashboard");
  }

  function openWorkerFindJobs() {
    setView("worker-find-jobs");
  }

  function openWorkerApplications() {
    markAllWorkerApplicationsRead();
    markAllWorkerNotificationsRead();
    setView("worker-applications");
  }

  function openWorkerProfile() {
    if (currentWorker) {
      const savedWeeklyAvailability = currentWorker.weeklyAvailability || [];
      const weeklyAvailability = [
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday",
      ].map((weekdayLabel, weekday) => {
        const savedWindow = savedWeeklyAvailability.find((window) => Number(window.weekday) === weekday);
        return {
          id: savedWindow?.id || `weekly-${weekday}`,
          weekday,
          weekdayLabel,
          startTime: savedWindow?.startTime || "09:00",
          endTime: savedWindow?.endTime || "17:00",
          isAvailable: Boolean(savedWindow?.isAvailable),
        };
      });
      setWorkerProfileForm({
        firstName: currentWorker.firstName || "",
        lastName: currentWorker.lastName || "",
        username: currentWorker.username || "",
        email: currentWorker.email || "",
        phone: currentWorker.phone || "",
        barangay: currentWorker.barangay || "",
        streetAddress: currentWorker.streetAddress || "",
        latitude: currentWorker.latitude ?? null,
        longitude: currentWorker.longitude ?? null,
        locationLabel: currentWorker.locationLabel || "",
        locationSource: currentWorker.latitude && currentWorker.longitude ? "saved" : "",
        locationWarning: "",
        locationAccuracy: "",
        bio: currentWorker.bio || "",
        hourlyRate: currentWorker.hourlyRate || "0.00",
        dailyRate: currentWorker.dailyRate || "0.00",
        yearsExperience: currentWorker.yearsExperience || "0",
        skills: currentWorker.skills || [],
        availability: true,
        availabilityWindows: currentWorker.availabilityWindows || [],
        weeklyAvailability,
        profilePhotoFile: null,
        profilePhotoPreview:
          currentWorker.profilePhotoPreview || currentWorker.verificationSubmission?.primaryIdPreview || "",
      });
    }
    setView("worker-profile");
  }

  function openWorkerGetVerified() {
    setView("worker-get-verified");
  }

  function openWorkerNotifications() {
    markAllNotificationsRead(workerNotificationsWithReadState);
    setView("worker-notifications");
  }

  function openAdminDashboard() {
    setAdminSection("verification");
    setView("admin-dashboard");
  }

  function openAdminWorkersHistory() {
    setAdminSection("history");
    setView("admin-dashboard");
  }

  function openHouseholdDashboard() {
    setView("household-dashboard");
  }

  function openHouseholdPostJob() {
    if (currentHousehold?.verification !== "Verified") {
      window.alert("Your household account must be verified before you can post a job.");
      setView("household-get-verified");
      return;
    }
    const savedLocation = getSavedHouseholdLocation(currentHousehold, currentUser);
    setHouseholdJobForm((prev) => ({
      ...prev,
      barangay: savedLocation.barangay,
      streetAddress: savedLocation.streetAddress,
    }));
    setHouseholdJobCoordinates(null);
    setHouseholdJobLocationPreview(null);
    setView("household-post-job");
  }

  function openHouseholdProfile() {
    if (currentHousehold) {
      setHouseholdProfileForm({
        firstName: currentHousehold.firstName || "",
        lastName: currentHousehold.lastName || "",
        username: currentHousehold.username || "",
        email: currentHousehold.email || "",
        phone: currentHousehold.phone || "",
        barangay: currentHousehold.barangay || "",
        streetAddress: currentHousehold.streetAddress || "",
        profilePhotoFile: null,
        profilePhotoName: currentHousehold.profilePhotoName || "",
        profilePhotoPreview: currentHousehold.profilePhotoPreview || "",
      });
    }
    setView("household-profile");
  }

  function openHouseholdGetVerified() {
    setView("household-get-verified");
  }

  function openHouseholdFeedbackAll() {
    setView("household-feedback-all");
  }

  function openHouseholdReviewsAll() {
    setView("household-reviews-all");
  }

  function openHouseholdMyJobs() {
    setSelectedWorkerId(null);
    setView("household-my-jobs");
  }

  function openHouseholdNotifications() {
    setView("household-notifications");
  }

  function openHouseholdJobDetail(jobId) {
    setSelectedJobId(jobId);
    setSelectedWorkerId(null);
    setView("household-job-detail");
  }

  function openWorkerJobDetail(jobId) {
    setSelectedJobId(jobId);
    setSelectedWorkerId(null);
    setView("worker-job-detail");
  }

  function openVerificationRequest(requestId) {
    setSelectedVerificationRequestId(requestId);
  }

  function markNotificationRead(notificationId) {
    if (!notificationId) return;
    setNotificationReads((prev) =>
      prev[notificationId]
        ? prev
        : {
            ...prev,
            [notificationId]: true,
          },
    );
    const backendNotification = backendNotifications.find((item) => item.id === notificationId);
    if (backendNotification?.backendId && currentUser?.username) {
      markBackendNotificationRead(backendNotification.backendId)
        .then(async (wasMarked) => {
          if (wasMarked) {
            await refreshNotificationsFromBackend();
          }
        })
        .catch(() => {
          return;
        });
    }
  }

  function markAllNotificationsRead(notifications) {
    setNotificationReads((prev) => {
      const nextState = {
        ...prev,
      };
      let changed = false;
      notifications.forEach((notification) => {
        if (!nextState[notification.id]) {
          nextState[notification.id] = true;
          changed = true;
        }
      });
      return changed ? nextState : prev;
    });
    notifications.forEach((notification) => {
      if (notification.backendId && currentUser?.username) {
        markBackendNotificationRead(notification.backendId).catch(() => {
          return;
        });
      }
    });
  }

  function markAllWorkerNotificationsRead() {
    markAllNotificationsRead(workerNotificationsWithReadState);
  }

  function markAllWorkerApplicationsRead() {
    if (!workerApplications.length) {
      return;
    }
    setNotificationReads((prev) => {
      const nextState = {
        ...prev,
      };
      let changed = false;
      workerApplications.forEach((job) => {
        if (!["Hired", "Rejected"].includes(job.applicationStatus)) {
          return;
        }
        const notificationId = `worker-application-${job.applicationId}`;
        if (!nextState[notificationId]) {
          nextState[notificationId] = true;
          changed = true;
        }
      });
      return changed ? nextState : prev;
    });
  }

  async function openFilePreview(fileUrl) {
    if (!fileUrl) return;
    const normalizedUrl = String(fileUrl);
    const apiBaseUrl = getApiBaseUrl();
    const apiIndex = normalizedUrl.indexOf("/api/");
    const isProtectedApiDocument = normalizedUrl.startsWith("/api/") || normalizedUrl.startsWith(apiBaseUrl);
    if (!isProtectedApiDocument && apiIndex === -1) {
      window.open(normalizedUrl, "_blank", "noopener,noreferrer");
      return;
    }
    const apiPath = normalizedUrl.startsWith(apiBaseUrl)
      ? normalizedUrl.slice(apiBaseUrl.length).replace(/^\/+/, "")
      : normalizedUrl.slice(apiIndex + "/api/".length);
    try {
      const response = await apiRequest(apiPath, { auth: true });
      if (!response.ok) {
        window.alert("You are not allowed to view this document, or it is no longer available.");
        return;
      }
      const blob = await response.blob();
      const objectUrl = window.URL.createObjectURL(blob);
      window.open(objectUrl, "_blank", "noopener,noreferrer");
      window.setTimeout(() => window.URL.revokeObjectURL(objectUrl), 60_000);
    } catch (error) {
      window.alert("Unable to open this document right now.");
    }
  }

  function openHouseholdNotificationWorker(notification) {
    markNotificationRead(notification.id);
    openMatchedWorkerProfile(notification.workerId, notification.jobId);
  }

  function openMatchedWorkerProfile(worker, jobId = selectedJob?.id) {
    const selectedWorker =
      worker && typeof worker === "object"
        ? {
            id: worker.id ?? null,
            workerId: worker.workerId ?? null,
            userId: worker.userId ?? worker.user_id ?? null,
            profileId: worker.profileId ?? null,
            username: worker.username ?? "",
            workerUsername: worker.workerUsername ?? "",
            displayName:
              worker.displayName ||
              worker.workerName ||
              [worker.firstName, worker.lastName].filter(Boolean).join(" ") ||
              worker.username ||
              worker.workerUsername ||
              "",
          }
        : worker;
    setSelectedWorkerId(selectedWorker);
    if (jobId) setSelectedJobId(jobId);
    setView("household-worker-profile");
  }

  return {
    goBack,
    goHome,
    handleLogout,
    markAllNotificationsRead,
    markAllWorkerApplicationsRead,
    markAllWorkerNotificationsRead,
    markNotificationRead,
    openAdminDashboard,
    openAdminWorkersHistory,
    openFilePreview,
    openForgotPassword,
    openHouseholdDashboard,
    openHouseholdFeedbackAll,
    openHouseholdGetVerified,
    openHouseholdJobDetail,
    openHouseholdMyJobs,
    openHouseholdNotificationWorker,
    openHouseholdNotifications,
    openHouseholdPostJob,
    openHouseholdProfile,
    openHouseholdRegister,
    openHouseholdReviewsAll,
    openLogin,
    openMatchedWorkerProfile,
    openVerificationRequest,
    openWorkerApplications,
    openWorkerDashboard,
    openWorkerFindJobs,
    openWorkerGetVerified,
    openWorkerJobDetail,
    openWorkerNotifications,
    openWorkerProfile,
    openWorkerRegister,
  };
}
