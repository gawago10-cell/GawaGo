import { apiRequest, clearAuthToken } from "../api/apiClient";
import { openProtectedFile } from "../utils/protectedFiles";
import { EMPTY_HOUSEHOLD_FORM, EMPTY_WORKER_FORM } from "../constants/appConstants";
import { getSavedHouseholdLocation } from "../utils/locationServices";
import { markBackendNotificationRead } from "../services/backendDataService";
import { dashboardViewForRole, getUserRole, ROLES } from "../utils/roles";

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
  setRegisterErrors,
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
    const role = getUserRole(currentUser);
    if (role === ROLES.ADMIN) {
      // The admin dashboard is one view with sections; without resetting the
      // section, "Back" from Workers History left the admin where they were.
      setAdminSection?.("verification");
    }
    setView(currentUser ? dashboardViewForRole(role) : "home");
  }

  function handleLogout() {
    // Revoke the token server-side so it can't be reused if it leaks; fired
    // without awaiting so a slow/failed request never delays logging out.
    apiRequest("accounts/logout/", { method: "POST", auth: true, suppressUnauthorized: true }).catch(() => {});
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
    setRegisterErrors?.({});
    setView("register-worker");
  }

  function openHouseholdRegister() {
    setHouseholdForm(EMPTY_HOUSEHOLD_FORM);
    setRegisterErrors?.({});
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

  function openWorkerMyJobs() {
    setSelectedJobId(null);
    setView("worker-my-jobs");
  }

  function openWorkerProfile() {
    if (currentWorker) {
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
        hourlyRate: currentWorker.hourlyRate ?? "",
        dailyRate: currentWorker.dailyRate ?? "",
        yearsExperience: currentWorker.yearsExperience || "0",
        skills: currentWorker.skills || [],
        availability: true,
        availabilityWindows: currentWorker.availabilityWindows || [],
        profilePhotoFile: null,
        // Never the government ID image: it's a private verification
        // document, not something to show as the worker's public photo.
        profilePhotoPreview: currentWorker.profilePhotoPreview || "",
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

  // "My Complaints" -- incidents the user filed or was reported in. The
  // household/worker activity-summary report was removed; admin still has
  // its own Reports tab inside SuperAdminDashboardView.
  function openMyComplaints() {
    setView("my-reports");
  }

  function openHouseholdJobMatches(jobId) {
    setSelectedJobId(jobId);
    setSelectedWorkerId(null);
    setView("household-job-matches");
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

  function openFilePreview(fileUrl) {
    return openProtectedFile(fileUrl);
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
    openHouseholdJobMatches,
    openHouseholdMyJobs,
    openMyComplaints,
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
    openWorkerMyJobs,
    openWorkerNotifications,
    openWorkerProfile,
    openWorkerRegister,
  };
}
