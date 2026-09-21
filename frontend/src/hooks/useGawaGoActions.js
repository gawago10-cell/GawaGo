import { useRef, useState } from "react";

import { BARANGAY_CENTERS } from "../constants/appConstants";
import { getBarangayCenter, normalizeBarangayName } from "../utils/locationUtils";

function getBarangayCenterCoordinates(barangay) {
  const normalizedBarangay = normalizeBarangayName(barangay);
  const center = BARANGAY_CENTERS[normalizedBarangay] || getBarangayCenter(normalizedBarangay);
  return {
    latitude: center?.latitude ?? null,
    longitude: center?.longitude ?? null,
  };
}

function omitSensitiveAccountFields(account) {
  const { password, confirmPassword, ...safeAccount } = account;
  return safeAccount;
}

export function useGawaGoActions({
  EMPTY_HOUSEHOLD_FORM,
  EMPTY_HOUSEHOLD_REVIEW_FORM,
  EMPTY_WORKER_FEEDBACK_FORM,
  EMPTY_WORKER_FORM,
  apiRequest,
  clearAuthToken,
  currentHousehold,
  currentUser,
  currentWorker,
  findJobApplicationForWorker,
  formatLocation,
  formatScheduleLabel,
  getApiErrorMessage,
  getAuthToken,
  getDisplayName,
  getHiredWorkerCount,
  getSavedHouseholdLocation,
  getWorkersNeeded,
  householdForm,
  householdJobCoordinates,
  householdJobForm,
  householdJobImages,
  householdJobLocationPreview,
  householdProfileForm,
  householdReviewForm,
  isNumericIdentifier,
  isValidGmailAddress,
  loginForm,
  mergeBackendWorkerIntoState,
  normalizeBackendApplication,
  normalizeBackendJob,
  normalizeBackendWorkerPayload,
  normalizeVerificationRequest,
  postedJobs,
  readResponseData,
  refreshJobsFromBackend,
  refreshNotificationsFromBackend,
  refreshRecommendedWorkers,
  refreshReviewsFromBackend,
  refreshVerificationStateFromBackend,
  registeredHouseholds,
  registeredWorkers,
  resolveLocationCoordinates,
  selectedJob,
  selectedJobId,
  selectedWorker,
  setAuthToken,
  setCurrentUser,
  setHouseholdForm,
  setHouseholdJobCoordinates,
  setHouseholdJobForm,
  setHouseholdJobImages,
  setHouseholdJobLocationPreview,
  setHouseholdReviewForm,
  setLoginForm,
  setPostedJobs,
  setRegisteredHouseholds,
  setRegisteredWorkers,
  setSelectedJobId,
  setSelectedVerificationRequestId,
  setVerificationRequests,
  setView,
  setWorkerFeedbackForm,
  setWorkerForm,
  verificationForm,
  verificationRequests,
  workerFeedbackForm,
  workerForm,
  workerProfileForm,
}) {
  // Guards handleHouseholdJobSubmit against a double-click. A ref (not a
  // plain closure variable) is required: this whole hook body re-runs on
  // every render, and a state update during resolveLocationCoordinates'
  // multi-second geocode round-trip would otherwise re-render before the
  // POST resolves, silently resetting a plain variable's guard.
  const isSubmittingJobRef = useRef(false);
  const [isSubmittingJob, setIsSubmittingJob] = useState(false);

  function handleApplyToJob(jobId) {
    if (!currentWorker) {
      window.alert("Please login as a worker first.");
      return;
    }
    const job = postedJobs.find((item) => item.id === jobId);
    if (!job) {
      window.alert("Job not found.");
      return;
    }
    if (!job.canApply) {
      window.alert("Applications are unavailable for this job right now.");
      return;
    }
    (async () => {
      try {
        const response = await apiRequest(`jobs/${jobId}/apply/`, {
          method: "POST",
          auth: true,
          body: {
            note: "",
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to apply for this job."));
        }
        const appliedAt = data?.applied_at || new Date().toLocaleString("en-PH");
        const application = {
          id: data?.id || `application-${job.id}-${currentWorker.id}-${Date.now()}`,
          workerId: data?.worker || currentWorker.id,
          workerName:
            data?.worker_name ||
            getDisplayName(currentWorker.firstName, currentWorker.lastName, currentWorker.username),
          workerUsername: data?.worker_username || currentWorker.username,
          appliedAt,
          status: "Pending",
        };
        setPostedJobs((prev) =>
          prev.map((item) =>
            item.id === jobId
              ? {
                  ...item,
                  applications: [...(item.applications || []), application],
                }
              : item,
          ),
        );
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert("Application sent to the household.");
        setView("worker-applications");
      } catch (error) {
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert(error.message || "Unable to apply for this job. Please try again.");
      }
    })();
  }
  function handleHireWorker() {
    if (!currentHousehold) {
      window.alert("Please login as a household first.");
      return;
    }
    if (currentHousehold.verification !== "Verified") {
      window.alert("Your household account must be verified before you can hire workers.");
      setView("household-get-verified");
      return;
    }
    if (!selectedWorker) {
      window.alert("Worker profile not found.");
      return;
    }
    if (String(selectedWorker.verification).toLowerCase() !== "verified") {
      window.alert("This worker must be verified before they can be hired.");
      return;
    }
    if (!selectedJob) {
      window.alert("Please select a job first.");
      return;
    }
    if (getHiredWorkerCount(selectedJob) >= getWorkersNeeded(selectedJob)) {
      window.alert("This job already has enough hired workers.");
      return;
    }
    const existingApplication = findJobApplicationForWorker(selectedJob, selectedWorker);
    if (existingApplication?.status === "Hired") {
      window.alert("This worker is already hired for this job.");
      return;
    }
    if (existingApplication?.status === "Hire Request") {
      window.alert("A hire request was already sent to this worker.");
      return;
    }
    if (existingApplication && !isNumericIdentifier(existingApplication.id)) {
      window.alert("This application is not synced with the backend yet. Please refresh jobs and try again.");
      refreshJobsFromBackend();
      return;
    }
    (async () => {
      const requestedAt = new Date().toLocaleString("en-PH");
      // Applying is itself consent, so accepting an applicant hires them
      // outright. A worker who never applied was surfaced by matching and has
      // not agreed to anything yet, so they still get a request to confirm.
      const isApplicant = existingApplication?.status === "Pending";
      const applicationRecord = {
        ...existingApplication,
        id: existingApplication?.id || `hire-request-${selectedJob.id}-${selectedWorker.id}-${Date.now()}`,
        workerId: selectedWorker.id,
        workerName: getDisplayName(selectedWorker.firstName, selectedWorker.lastName, selectedWorker.username),
        workerUsername: selectedWorker.username,
        status: isApplicant ? "Hired" : "Hire Request",
        requestedAt,
      };
      try {
        const response = existingApplication
          ? await apiRequest(`jobs/applications/${existingApplication.id}/status/`, {
              method: "PATCH",
              auth: true,
              body: {
                status: isApplicant ? "hired" : "hire_requested",
              },
            })
          : await apiRequest(`jobs/${selectedJob.id}/hire-request/`, {
              method: "POST",
              auth: true,
              body: {
                worker_id: selectedWorker.id,
                worker_username: selectedWorker.username,
              },
            });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(
            getApiErrorMessage(data, isApplicant ? "Unable to hire this worker." : "Unable to send hire request."),
          );
        }
        const normalizedApplication = normalizeBackendApplication(data);
        setPostedJobs((prev) =>
          prev.map((job) => {
            if (job.id !== selectedJob.id) {
              return job;
            }
            const nextApplication = normalizedApplication || applicationRecord;
            const previousApplications = job.applications || [];
            const hasExistingApplication = previousApplications.some((application) => {
              const matchesWorkerId =
                application.workerId != null && String(application.workerId) === String(selectedWorker.id);
              const matchesWorkerUsername =
                application.workerUsername &&
                selectedWorker.username &&
                application.workerUsername === selectedWorker.username;
              return matchesWorkerId || matchesWorkerUsername;
            });
            const applications = hasExistingApplication
              ? previousApplications.map((application) => {
                  const matchesWorkerId =
                    application.workerId != null && String(application.workerId) === String(selectedWorker.id);
                  const matchesWorkerUsername =
                    application.workerUsername &&
                    selectedWorker.username &&
                    application.workerUsername === selectedWorker.username;
                  return matchesWorkerId || matchesWorkerUsername ? nextApplication : application;
                })
              : [...previousApplications, nextApplication];
            const nextJob = {
              ...job,
              cancellationReason: "",
              applications,
            };
            return nextJob;
          }),
        );
        setRegisteredWorkers((prev) =>
          prev.map((worker) =>
            worker.id === selectedWorker.id
              ? {
                  ...worker,
                  applicationNotifications: [
                    ...(worker.applicationNotifications || []),
                    {
                      id: `hire-request-${selectedJob.id}-${selectedWorker.id}-${Date.now()}`,
                      applicationId: normalizedApplication?.id || applicationRecord.id,
                      jobId: selectedJob.id,
                      title: isApplicant ? "Application accepted" : "Hire request",
                      message: isApplicant
                        ? `${getDisplayName(currentHousehold.firstName, currentHousehold.lastName, currentHousehold.username)} accepted your application for ${selectedJob.jobTitle || selectedJob.serviceType}.`
                        : `${getDisplayName(currentHousehold.firstName, currentHousehold.lastName, currentHousehold.username)} wants to hire you for ${selectedJob.jobTitle || selectedJob.serviceType}.`,
                      date: requestedAt,
                      unread: true,
                    },
                  ],
                }
              : worker,
          ),
        );
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
        const workerLabel = getDisplayName(selectedWorker.firstName, selectedWorker.lastName, selectedWorker.username);
        window.alert(
          isApplicant
            ? `${workerLabel} is hired. The job is now in progress.`
            : `Hire request sent to ${workerLabel}. They can accept or reject it from Notifications.`,
        );
        setView("household-dashboard");
      } catch (error) {
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert(error.message || "Unable to complete this action.");
      }
    })();
  }
  function handleWorkerHireDecision(applicationId, decision) {
    if (!currentWorker) {
      window.alert("Please login as a worker first.");
      return;
    }
    if (!isNumericIdentifier(applicationId)) {
      window.alert("This hire request is not synced with the backend yet. Please refresh and try again.");
      refreshJobsFromBackend();
      return;
    }
    const normalizedDecision = decision === "accept" ? "accept" : "reject";
    (async () => {
      try {
        const response = await apiRequest(`jobs/applications/${applicationId}/decision/`, {
          method: "PATCH",
          auth: true,
          body: {
            decision: normalizedDecision,
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to respond to hire request."));
        }
        const normalizedApplication = normalizeBackendApplication(data);
        if (normalizedApplication) {
          setPostedJobs((prev) =>
            prev.map((job) => ({
              ...job,
              applications: (job.applications || []).map((application) =>
                String(application.id) === String(applicationId) ? normalizedApplication : application,
              ),
            })),
          );
        }
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert(normalizedDecision === "accept" ? "Hire request accepted." : "Hire request rejected.");
        setView("worker-applications");
      } catch (error) {
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert(error.message || "Unable to respond to hire request.");
      }
    })();
  }
  function handleWorkerRequestCompletion(jobId, note = "") {
    if (!currentWorker) {
      window.alert("Please login as a worker first.");
      return;
    }
    const job = postedJobs.find((item) => String(item.id) === String(jobId));
    if (!job) {
      window.alert("Job not found.");
      return;
    }
    const application = (job.applications || []).find(
      (item) =>
        item.status === "Hired" &&
        (String(item.workerId) === String(currentWorker.id) || item.workerUsername === currentWorker.username),
    );
    if (!application) {
      window.alert("Only the hired worker can request completion for this job.");
      return;
    }
    if (!isNumericIdentifier(job.id)) {
      window.alert("This job is not synced with the backend yet. Please refresh jobs and try again.");
      refreshJobsFromBackend();
      return;
    }
    (async () => {
      try {
        const response = await apiRequest(`jobs/${job.id}/request-completion/`, {
          method: "POST",
          auth: true,
          body: {
            note: String(note || "").trim(),
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to request completion."));
        }
        const normalizedJob = normalizeBackendJob(data);
        if (normalizedJob) {
          setPostedJobs((prev) =>
            prev.map((item) => (String(item.id) === String(normalizedJob.id) ? normalizedJob : item)),
          );
        }
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert("Completion request sent to the household.");
      } catch (error) {
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert(error.message || "Unable to request completion. Please try again.");
      }
    })();
  }
  function handleRejectApplication(workerId = selectedWorker?.id, jobId = selectedJob?.id) {
    if (currentHousehold?.verification !== "Verified") {
      window.alert("Your household account must be verified before you can manage job applications.");
      setView("household-get-verified");
      return;
    }
    const job = postedJobs.find((item) => item.id === jobId);
    const worker = registeredWorkers.find((item) => String(item.id) === String(workerId)) || selectedWorker || null;
    if (!job || !worker) {
      window.alert("Application not found.");
      return;
    }
    const existingApplication = findJobApplicationForWorker(job, worker);
    if (!existingApplication) {
      window.alert("Only workers who applied to this job can be rejected.");
      return;
    }
    if (existingApplication.status === "Hired") {
      window.alert("This worker is already hired and cannot be rejected from this application.");
      return;
    }
    if (!isNumericIdentifier(existingApplication.id)) {
      window.alert("This application is not synced with the backend yet. Please refresh jobs and try again.");
      refreshJobsFromBackend();
      return;
    }
    (async () => {
      const rejectedAt = new Date().toLocaleString("en-PH");
      const message = `Thank you for applying to ${job.jobTitle || job.serviceType}. The household chose another applicant for now, but you can still apply to other open jobs.`;
      const applicationStatusTargetId = existingApplication.id;
      try {
        const response = await apiRequest(`jobs/applications/${applicationStatusTargetId}/status/`, {
          method: "PATCH",
          auth: true,
          body: {
            status: "rejected",
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to reject application."));
        }
        const normalizedApplication = normalizeBackendApplication(data);
        setPostedJobs((prev) =>
          prev.map((item) =>
            item.id === jobId
              ? {
                  ...item,
                  applications: (item.applications || []).map((application) => {
                    const matchesWorkerId =
                      application.workerId != null && String(application.workerId) === String(worker.id);
                    const matchesWorkerUsername =
                      application.workerUsername && worker.username && application.workerUsername === worker.username;
                    return matchesWorkerId || matchesWorkerUsername
                      ? {
                          ...(normalizedApplication || application),
                          status: "Rejected",
                          rejectedAt,
                          rejectionMessage: message,
                        }
                      : application;
                  }),
                }
              : item,
          ),
        );
        setRegisteredWorkers((prev) =>
          prev.map((item) =>
            item.id === workerId
              ? {
                  ...item,
                  applicationNotifications: [
                    ...(item.applicationNotifications || []),
                    {
                      id: `rejected-${jobId}-${workerId}-${Date.now()}`,
                      title: "Application update",
                      message,
                      date: rejectedAt,
                      unread: true,
                    },
                  ],
                }
              : item,
          ),
        );
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert(message);
        setView("household-dashboard");
      } catch (error) {
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert(error.message || "Unable to reject application.");
      }
    })();
  }
  function handleLoginSubmit(event) {
    event.preventDefault();
    const username = loginForm.username.trim();
    if (!username || !loginForm.password) {
      window.alert("Please enter your username and password.");
      return;
    }
    (async () => {
      try {
        const response = await apiRequest("accounts/login/", {
          method: "POST",
          auth: false,
          body: {
            username,
            password: loginForm.password,
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          const loginError = new Error(data?.detail || "Login failed.");
          loginError.status = response.status;
          throw loginError;
        }
        setAuthToken(data?.access || "");
        const resolvedRole = data?.role || data?.profile?.role || (data?.is_staff ? "superadmin" : "worker");
        const isSuperAdmin = resolvedRole === "superadmin";
        setCurrentUser({
          id: data?.id || data?.user_id || username,
          role: resolvedRole,
          username: data?.username || username,
          email: data?.email || "",
          first_name: data?.profile?.username ? "" : "",
          last_name: "",
          displayName: data?.display_name || data?.username || username,
          profile: data?.profile || null,
          is_staff: Boolean(data?.is_staff),
          isSuperAdmin,
        });
        const backendWorker = normalizeBackendWorkerPayload({
          user: {
            id: data?.id || data?.user_id || username,
            username: data?.username || username,
            email: data?.email || "",
            first_name: data?.profile?.full_name ? "" : "",
            last_name: "",
            display_name: data?.display_name || data?.username || username,
            is_staff: Boolean(data?.is_staff),
          },
          profile: data?.profile || null,
        });
        if (backendWorker) {
          mergeBackendWorkerIntoState(backendWorker);
        }
        setView(
          isSuperAdmin
            ? "superadmin-dashboard"
            : resolvedRole === "admin"
              ? "admin-dashboard"
              : resolvedRole === "household"
                ? "household-dashboard"
                : "worker-dashboard",
        );
        // The jobs list is fetched anonymously before login (no per-user
        // application data), and the background poll that would otherwise
        // pick up the authenticated view can take several seconds. Refresh
        // immediately so pages like "My Applications" aren't briefly empty
        // right after logging in.
        refreshJobsFromBackend();
        refreshNotificationsFromBackend();
      } catch (error) {
        if (error.status === 403) {
          window.alert(error.message || "Account is not verified yet.");
          return;
        }
        clearAuthToken();
        window.alert(error.message || "Login failed. Please check your username and password.");
      }
    })();
  }
  function handleWorkerRegisterSubmit(event) {
    event.preventDefault();
    const requiredFields = [
      workerForm.firstName,
      workerForm.lastName,
      workerForm.username,
      workerForm.email,
      workerForm.phone,
      workerForm.barangay,
      workerForm.streetAddress,
      workerForm.password,
      workerForm.confirmPassword,
    ];
    if (requiredFields.some((field) => !String(field || "").trim())) {
      window.alert("Please complete all required fields.");
      return;
    }
    if (!isValidGmailAddress(workerForm.email)) {
      window.alert("Please enter a complete Gmail address, for example example@gmail.com.");
      return;
    }
    if (workerForm.password.length < 8) {
      window.alert("Password must be at least 8 characters long.");
      return;
    }
    if (workerForm.password !== workerForm.confirmPassword) {
      window.alert("Worker passwords do not match.");
      return;
    }
    const usernameTaken = registeredWorkers.some(
      (item) => item.username.toLowerCase() === workerForm.username.trim().toLowerCase(),
    );
    if (usernameTaken) {
      window.alert("Username already exists for a worker account.");
      return;
    }
    (async () => {
      try {
        let resolvedLocation = null;
        try {
          resolvedLocation = await resolveLocationCoordinates(workerForm.barangay, workerForm.streetAddress, false);
        } catch {
          resolvedLocation = null;
        }
        const normalizedBarangay = normalizeBarangayName(workerForm.barangay);
        const barangayCoordinates = getBarangayCenterCoordinates(normalizedBarangay);
        const workerLatitude = workerForm.latitude ?? resolvedLocation?.latitude ?? barangayCoordinates.latitude;
        const workerLongitude = workerForm.longitude ?? resolvedLocation?.longitude ?? barangayCoordinates.longitude;
        const workerLocationLabel =
          workerForm.locationLabel ||
          resolvedLocation?.locationLabel ||
          formatLocation(workerForm.barangay, workerForm.streetAddress);
        const response = await apiRequest("accounts/register/", {
          method: "POST",
          auth: false,
          body: {
            username: workerForm.username.trim(),
            email: workerForm.email.trim(),
            password: workerForm.password,
            first_name: workerForm.firstName.trim(),
            last_name: workerForm.lastName.trim(),
            role: "worker",
            phone: workerForm.phone.trim(),
            bio: workerForm.bio.trim(),
            years_experience: Number(workerForm.yearsExperience || 0),
            skills: Array.from(
              new Set([
                ...(workerForm.skills || []),
                ...(workerForm.customSkill.trim() ? [workerForm.customSkill.trim()] : []),
              ]),
            ),
            hourly_rate: workerForm.hourlyRate,
            daily_rate: workerForm.dailyRate,
            location_label: workerLocationLabel,
            latitude: workerLatitude,
            longitude: workerLongitude,
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to create worker account."));
        }
        const backendWorker = normalizeBackendWorkerPayload({
          user: data?.user,
          profile: data?.profile,
        });
        const workerAccount = {
          ...omitSensitiveAccountFields(workerForm),
          skills: Array.from(
            new Set([
              ...(workerForm.skills || []),
              ...(workerForm.customSkill.trim() ? [workerForm.customSkill.trim()] : []),
            ]),
          ),
          id: Date.now(),
          username: workerForm.username.trim(),
          verification: "Not Yet Verified",
          rating: "No ratings yet",
          reviewsDone: 0,
          status: "Available",
          distanceKm: null,
          barangay: normalizedBarangay,
          streetAddress: workerForm.streetAddress,
          locationLabel: workerLocationLabel,
          latitude: workerLatitude,
          longitude: workerLongitude,
          avatar: (workerForm.firstName || workerForm.username || "W").slice(0, 1).toUpperCase(),
          receivedReviews: [],
          givenFeedback: [],
          verificationNotifications: [],
          applicationNotifications: [],
          emailVerified: true,
        };
        setRegisteredWorkers((prev) => [
          backendWorker
            ? {
                ...backendWorker,
                barangay: normalizedBarangay,
                streetAddress: workerForm.streetAddress,
                latitude: workerLatitude,
                longitude: workerLongitude,
                emailVerified: true,
              }
            : workerAccount,
          ...prev.filter((item) => item.username?.toLowerCase() !== workerAccount.username.toLowerCase()),
        ]);
        setWorkerForm(EMPTY_WORKER_FORM);
        setLoginForm({
          username: "",
          password: "",
          role: "worker",
        });
        setView("login");
        window.alert(data?.detail || "Worker account created. You can now login.");
      } catch (error) {
        window.alert(error.message || "Unable to create worker account.");
      }
    })();
  }
  function handleHouseholdRegisterSubmit(event) {
    event.preventDefault();
    const requiredFields = [
      householdForm.firstName,
      householdForm.lastName,
      householdForm.username,
      householdForm.email,
      householdForm.phone,
      householdForm.barangay,
      householdForm.streetAddress,
      householdForm.password,
      householdForm.confirmPassword,
    ];
    if (requiredFields.some((field) => !String(field || "").trim())) {
      window.alert("Please complete all required fields.");
      return;
    }
    if (!isValidGmailAddress(householdForm.email)) {
      window.alert("Please enter a complete Gmail address, for example example@gmail.com.");
      return;
    }
    if (householdForm.password.length < 8) {
      window.alert("Password must be at least 8 characters long.");
      return;
    }
    if (householdForm.password !== householdForm.confirmPassword) {
      window.alert("Household passwords do not match.");
      return;
    }
    const usernameTaken = registeredHouseholds.some(
      (item) => item.username.toLowerCase() === householdForm.username.trim().toLowerCase(),
    );
    if (usernameTaken) {
      window.alert("Username already exists for a household account.");
      return;
    }
    (async () => {
      try {
        const resolvedLocation = await resolveLocationCoordinates(
          householdForm.barangay,
          householdForm.streetAddress,
          false,
        );
        const response = await apiRequest("accounts/register/", {
          method: "POST",
          auth: false,
          body: {
            username: householdForm.username.trim(),
            email: householdForm.email.trim(),
            password: householdForm.password,
            first_name: householdForm.firstName.trim(),
            last_name: householdForm.lastName.trim(),
            role: "household",
            phone: householdForm.phone.trim(),
            location_label:
              resolvedLocation?.locationLabel || formatLocation(householdForm.barangay, householdForm.streetAddress),
            latitude: resolvedLocation?.latitude ?? null,
            longitude: resolvedLocation?.longitude ?? null,
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to create household account."));
        }
        const householdAccount = {
          ...omitSensitiveAccountFields(householdForm),
          id: Date.now(),
          username: householdForm.username.trim(),
          latitude: resolvedLocation?.latitude ?? null,
          longitude: resolvedLocation?.longitude ?? null,
          emailVerified: true,
        };
        setRegisteredHouseholds((prev) => [...prev, householdAccount]);
        setHouseholdForm(EMPTY_HOUSEHOLD_FORM);
        setLoginForm({
          username: "",
          password: "",
          role: "household",
        });
        setView("login");
        window.alert(data?.detail || "Household account created. You can now login.");
      } catch (error) {
        window.alert(error.message || "Unable to create household account.");
      }
    })();
  }
  function handleWorkerProfileSave(event) {
    event.preventDefault();
    if (!currentUser || currentUser.role !== "worker") {
      window.alert("No worker account is currently logged in.");
      return;
    }
    (async () => {
      let resolvedLocation = null;
      try {
        resolvedLocation = await resolveLocationCoordinates(
          workerProfileForm.barangay,
          workerProfileForm.streetAddress,
          false,
        );
      } catch {
        resolvedLocation = null;
      }
      const normalizedBarangay = normalizeBarangayName(workerProfileForm.barangay);
      const barangayCoordinates = getBarangayCenterCoordinates(normalizedBarangay);
      const workerLatitude = workerProfileForm.latitude ?? resolvedLocation?.latitude ?? barangayCoordinates.latitude;
      const workerLongitude = workerProfileForm.longitude ?? resolvedLocation?.longitude ?? barangayCoordinates.longitude;
      const workerLocationLabel =
        workerProfileForm.locationLabel ||
        resolvedLocation?.locationLabel ||
        formatLocation(workerProfileForm.barangay, workerProfileForm.streetAddress);
      const nextWorkerPatch = {
        firstName: workerProfileForm.firstName,
        lastName: workerProfileForm.lastName,
        email: workerProfileForm.email,
        phone: workerProfileForm.phone,
        barangay: normalizedBarangay,
        streetAddress: workerProfileForm.streetAddress,
        bio: workerProfileForm.bio,
        hourlyRate: workerProfileForm.hourlyRate,
        dailyRate: workerProfileForm.dailyRate,
        yearsExperience: workerProfileForm.yearsExperience,
        skills: workerProfileForm.skills,
        availabilityWindows: workerProfileForm.availabilityWindows || [],
        locationLabel: workerLocationLabel,
        latitude: workerLatitude,
        longitude: workerLongitude,
      };
      try {
        if (getAuthToken()) {
          const availabilityWindows = (workerProfileForm.availabilityWindows || []).filter(
            (window) => window.date && window.startTime && window.endTime,
          );
          if (availabilityWindows.some((window) => window.startTime === window.endTime)) {
            throw new Error("Availability start and end time must be different.");
          }
          const profilePayload = {
            first_name: workerProfileForm.firstName,
            last_name: workerProfileForm.lastName,
            email: workerProfileForm.email,
            phone: workerProfileForm.phone,
            bio: workerProfileForm.bio,
            years_experience: Number(workerProfileForm.yearsExperience || 0),
            skills: workerProfileForm.skills,
            hourly_rate: workerProfileForm.hourlyRate,
            daily_rate: workerProfileForm.dailyRate,
            location_label: workerLocationLabel,
            latitude: nextWorkerPatch.latitude,
            longitude: nextWorkerPatch.longitude,
          };
          const requestBody = workerProfileForm.profilePhotoFile ? new FormData() : profilePayload;
          if (requestBody instanceof FormData) {
            Object.entries(profilePayload).forEach(([key, value]) => {
              requestBody.append(key, key === "skills" ? JSON.stringify(value || []) : value ?? "");
            });
            requestBody.append("profile_photo", workerProfileForm.profilePhotoFile);
          }
          const response = await apiRequest("accounts/me/", {
            method: "PATCH",
            auth: true,
            body: requestBody,
          });
          const data = await readResponseData(response);
          if (!response.ok) {
            throw new Error(getApiErrorMessage(data, "Unable to update worker profile."));
          }
          const availabilityResponse = await apiRequest("accounts/me/availability/", {
            method: "PUT",
            auth: true,
            body: {
              availability_windows: availabilityWindows.map((window) => ({
                date: window.date,
                start_time: window.startTime,
                end_time: window.endTime,
                is_available: window.isAvailable !== false,
              })),
            },
          });
          const availabilityData = await readResponseData(availabilityResponse);
          if (!availabilityResponse.ok) {
            throw new Error(getApiErrorMessage(availabilityData, "Unable to update worker availability."));
          }
          nextWorkerPatch.availabilityWindows = Array.isArray(availabilityData)
            ? availabilityData.map((window) => ({
                id: window.id,
                date: window.date || "",
                startTime: window.start_time || "",
                endTime: window.end_time || "",
                isAvailable: window.is_available ?? true,
              }))
            : availabilityWindows;
          const backendWorker = normalizeBackendWorkerPayload({
            user: data?.user || {
              username: currentUser.username,
              email: workerProfileForm.email,
              first_name: workerProfileForm.firstName,
              last_name: workerProfileForm.lastName,
            },
            profile: data?.profile,
          });
          if (backendWorker) {
            const savedProfilePhoto = backendWorker.profilePhotoPreview || workerProfileForm.profilePhotoPreview || "";
            mergeBackendWorkerIntoState({
              ...backendWorker,
              barangay: workerProfileForm.barangay,
              streetAddress: workerProfileForm.streetAddress,
              locationLabel: workerLocationLabel,
              latitude: nextWorkerPatch.latitude,
              longitude: nextWorkerPatch.longitude,
                profilePhotoPreview: savedProfilePhoto,
                availabilityWindows: nextWorkerPatch.availabilityWindows,
              });
            nextWorkerPatch.profilePhotoPreview = savedProfilePhoto;
          }
        }
        setRegisteredWorkers((prev) =>
          prev.map((item) => {
            if (item.username !== currentUser.username) {
              return item;
            }
            return {
              ...item,
              ...nextWorkerPatch,
              profilePhotoPreview: nextWorkerPatch.profilePhotoPreview || workerProfileForm.profilePhotoPreview || item.profilePhotoPreview || "",
              receivedReviews: item.receivedReviews || [],
              givenFeedback: item.givenFeedback || [],
            };
          }),
        );
        setCurrentUser((prev) => {
          if (!prev) return prev;
          return {
            ...prev,
            displayName: getDisplayName(
              workerProfileForm.firstName,
              workerProfileForm.lastName,
              workerProfileForm.username,
            ),
            profile: prev.profile
              ? {
                  ...prev.profile,
                  phone: workerProfileForm.phone,
                  bio: workerProfileForm.bio,
                  years_experience: Number(workerProfileForm.yearsExperience || 0),
                  skills: workerProfileForm.skills,
                  hourly_rate: workerProfileForm.hourlyRate,
                  daily_rate: workerProfileForm.dailyRate,
                  availability_windows: nextWorkerPatch.availabilityWindows,
                  location_label: workerLocationLabel,
                  latitude: nextWorkerPatch.latitude,
                  longitude: nextWorkerPatch.longitude,
                  profile_photo_url: nextWorkerPatch.profilePhotoPreview || prev.profile.profile_photo_url || "",
                }
              : prev.profile,
          };
        });
        window.alert("Worker profile updated.");
      } catch (error) {
        window.alert(error.message || "Unable to update worker profile.");
      }
    })();
  }
  function handleVerificationSubmit(event) {
    event.preventDefault();
    if (
      !verificationForm.primaryIdName ||
      !verificationForm.secondaryDocName ||
      !verificationForm.primaryIdFile ||
      !verificationForm.secondaryDocFile
    ) {
      window.alert("Please upload both required verification documents.");
      return;
    }
    const account = currentUser?.role === "worker" ? currentWorker : registeredHouseholds.find(
      (item) => item.username === currentUser?.username,
    );
    if (!account || !["worker", "household"].includes(currentUser?.role)) {
      window.alert("Please login with a worker or household account first.");
      return;
    }
    if (
      account.verification === "Verified" ||
      (account.verificationSubmission &&
        ["Pending", "Under Review"].includes(account.verificationSubmission.status))
    ) {
      window.alert(
        account.verification === "Verified"
          ? "Your account is already verified."
          : "Your verification request is already under review.",
      );
      return;
    }
    (async () => {
      const requestRecord = new FormData();
      requestRecord.append("primary_id_name", verificationForm.primaryIdName);
      requestRecord.append("secondary_doc_name", verificationForm.secondaryDocName);
      requestRecord.append("primary_id_file", verificationForm.primaryIdFile);
      requestRecord.append("secondary_doc_file", verificationForm.secondaryDocFile);
      requestRecord.append("notes", verificationForm.notes || "");
      try {
        const response = await apiRequest("common/verification-requests/", {
          method: "POST",
          auth: true,
          body: requestRecord,
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to submit verification request."));
        }
        const normalizedRequest = normalizeVerificationRequest(data.verification_request || data);
        const backendAccount = data.account || data.worker;
        const backendWorker =
          currentUser.role === "worker" ? normalizeBackendWorkerPayload(backendAccount) : null;
        setVerificationRequests((prev) => {
          const existingIndex = prev.findIndex(
            (item) => item.workerUsername === account.username && item.status !== "Rejected",
          );
          if (existingIndex >= 0) {
            return prev.map((item, index) => (index === existingIndex ? normalizedRequest : item));
          }
          return [normalizedRequest, ...prev];
        });
        if (currentUser.role === "worker" && backendWorker) {
          mergeBackendWorkerIntoState({
            ...backendWorker,
            verification: "Under Review",
            verificationRequestId: normalizedRequest.id,
            verificationSubmission: normalizedRequest,
            verificationNotifications: [
              {
                id: `submission-${normalizedRequest.id}`,
                title: "Verification Submitted",
                message: "Your documents were sent to the admin for review.",
                date: normalizedRequest.submittedAt || new Date().toLocaleString("en-PH"),
                unread: true,
              },
            ],
          });
        } else if (currentUser.role === "worker") {
          setRegisteredWorkers((prev) =>
            prev.map((item) =>
              item.username === account.username
                ? {
                    ...item,
                    verification: "Under Review",
                    verificationRequestId: normalizedRequest.id,
                    verificationSubmission: normalizedRequest,
                    verificationNotifications: [
                      {
                        id: `submission-${normalizedRequest.id}`,
                        title: "Verification Submitted",
                        message: "Your documents were sent to the admin for review.",
                        date: normalizedRequest.submittedAt || new Date().toLocaleString("en-PH"),
                        unread: true,
                      },
                    ],
                  }
                : item,
            ),
          );
        } else {
          setRegisteredHouseholds((prev) =>
            prev.map((item) =>
              item.username === account.username
                ? {
                    ...item,
                    verification: "Under Review",
                    verificationRequestId: normalizedRequest.id,
                    verificationSubmission: normalizedRequest,
                  }
                : item,
            ),
          );
        }
        setCurrentUser((prev) =>
          prev
            ? {
                ...prev,
                profile:
                  backendAccount?.profile ||
                  (prev.profile
                    ? {
                        ...prev.profile,
                        verification_status: "pending",
                        verification_request: normalizedRequest,
                      }
                    : prev.profile),
              }
            : prev,
        );
        await refreshVerificationStateFromBackend();
        window.alert("Verification request submitted. Status is now Under Review.");
      } catch (error) {
        // Must never read as success -- a fallback claiming the documents
        // were submitted here would tell the worker/household their
        // verification is under review when the request actually failed.
        window.alert(error.message || "Unable to submit verification documents. Please try again.");
      }
    })();
  }
  function handleHouseholdProfileSave(event) {
    event.preventDefault();
    if (!currentUser || currentUser.role !== "household") {
      window.alert("No household account is currently logged in.");
      return;
    }
    (async () => {
      let savedProfilePhoto = householdProfileForm.profilePhotoPreview || "";
      try {
        if (getAuthToken()) {
          const profilePayload = {
            first_name: householdProfileForm.firstName,
            last_name: householdProfileForm.lastName,
            email: householdProfileForm.email,
            phone: householdProfileForm.phone,
            location_label: formatLocation(householdProfileForm.barangay, householdProfileForm.streetAddress),
          };
          const requestBody = householdProfileForm.profilePhotoFile ? new FormData() : profilePayload;
          if (requestBody instanceof FormData) {
            Object.entries(profilePayload).forEach(([key, value]) => requestBody.append(key, value ?? ""));
            requestBody.append("profile_photo", householdProfileForm.profilePhotoFile);
          }
          const response = await apiRequest("accounts/me/", {
            method: "PATCH",
            auth: true,
            body: requestBody,
          });
          const data = await readResponseData(response);
          if (!response.ok) {
            throw new Error(getApiErrorMessage(data, "Unable to update household profile."));
          }
          savedProfilePhoto =
            data?.profile?.profile_photo_url ||
            data?.profile?.profile_photo ||
            data?.profile?.profile_photo_preview ||
            householdProfileForm.profilePhotoPreview ||
            "";
        }
      } catch (error) {
        window.alert(error.message || "Unable to save household profile photo.");
        return;
      }
    setRegisteredHouseholds((prev) =>
      prev.map((item) => {
        if (item.username !== currentUser.username) {
          return item;
        }
        return {
          ...item,
          firstName: householdProfileForm.firstName,
          lastName: householdProfileForm.lastName,
          email: householdProfileForm.email,
          phone: householdProfileForm.phone,
          barangay: householdProfileForm.barangay,
          streetAddress: householdProfileForm.streetAddress,
          profilePhotoName: householdProfileForm.profilePhotoName || item.profilePhotoName || "",
          profilePhotoPreview: savedProfilePhoto || item.profilePhotoPreview || "",
          receivedFeedback: item.receivedFeedback || [],
        };
      }),
    );
    setCurrentUser((prev) => {
      if (!prev) return prev;
      return {
        ...prev,
        barangay: householdProfileForm.barangay,
        streetAddress: householdProfileForm.streetAddress,
        displayName: getDisplayName(
          householdProfileForm.firstName,
          householdProfileForm.lastName,
          householdProfileForm.username,
        ),
        profile: prev.profile
          ? {
              ...prev.profile,
              location_label: formatLocation(householdProfileForm.barangay, householdProfileForm.streetAddress),
              profile_photo_url: savedProfilePhoto || prev.profile.profile_photo_url || "",
            }
          : prev.profile,
      };
    });
    setPostedJobs((prev) =>
      prev.map((job) => {
        if (job.householdUsername !== currentUser.username) {
          return job;
        }
        return {
          ...job,
          householdName: getDisplayName(
            householdProfileForm.firstName,
            householdProfileForm.lastName,
            householdProfileForm.username,
          ),
        };
      }),
    );
    window.alert("Household profile updated.");
    })();
  }
  function handleCancelJob(jobId) {
    const job = postedJobs.find((item) => item.id === jobId);
    if (!job) {
      return;
    }
    (async () => {
      try {
        const response = await apiRequest(`jobs/${jobId}/`, {
          method: "PATCH",
          auth: true,
          body: {
            status: "cancelled",
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to cancel job."));
        }
        const normalizedJob = normalizeBackendJob(data);
        if (normalizedJob) {
          setPostedJobs((prev) =>
            prev.map((item) => (String(item.id) === String(normalizedJob.id) ? normalizedJob : item)),
          );
        }
        await refreshJobsFromBackend();
      } catch (error) {
        await refreshJobsFromBackend();
        window.alert(error.message || "Unable to cancel job. Please try again.");
      } finally {
        if (String(selectedJobId) === String(jobId)) {
          setSelectedJobId(null);
        }
      }
    })();
  }
  function handleConfirmJobCompleted(jobId = selectedJob?.id) {
    if (currentHousehold?.verification !== "Verified") {
      window.alert("Your household account must be verified before you can complete a job.");
      setView("household-get-verified");
      return;
    }
    if (!jobId) {
      window.alert("Select a job first.");
      return;
    }
    (async () => {
      try {
        const response = await apiRequest(`jobs/${jobId}/`, {
          method: "PATCH",
          auth: true,
          body: {
            status: "completed",
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to complete job."));
        }
        const normalizedJob = normalizeBackendJob(data);
        if (normalizedJob) {
          setPostedJobs((prev) =>
            prev.map((item) => (String(item.id) === String(normalizedJob.id) ? normalizedJob : item)),
          );
        }
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
      } catch (error) {
        await refreshJobsFromBackend();
        window.alert(error.message || "Unable to complete job. Please try again.");
      }
    })();
  }
  // Returns whether the review was actually saved, so the modal that hosts
  // this form only closes on success -- it used to close unconditionally
  // right after calling this (a fire-and-forget inner IIFE the caller never
  // awaited), so a rejected review surfaced later as an alert with the
  // filled-in form already gone.
  async function handleHouseholdReviewSubmit(event) {
    event.preventDefault();
    if (!currentHousehold || !selectedWorker) {
      window.alert("Select a worker first.");
      return false;
    }
    const rating = parseFloat(householdReviewForm.rating);
    if (!rating) {
      window.alert("Please select a star rating first.");
      return false;
    }
    if (!selectedJob?.id) {
      window.alert("Select a completed job first.");
      return false;
    }
    return (async () => {
      try {
        const body = {
          target_username: selectedWorker.username,
          job_id: selectedJob?.id,
          job_title: selectedJob?.jobTitle || selectedJob?.serviceType || "",
          rating,
          feedback: householdReviewForm.feedback.trim(),
        };

        if (householdReviewForm.quality_of_work) body.quality_of_work = parseInt(householdReviewForm.quality_of_work);
        if (householdReviewForm.punctuality) body.punctuality = parseInt(householdReviewForm.punctuality);
        if (householdReviewForm.communication) body.communication = parseInt(householdReviewForm.communication);
        if (householdReviewForm.professionalism) body.professionalism = parseInt(householdReviewForm.professionalism);

        const response = await apiRequest("reviews/", {
          method: "POST",
          auth: true,
          body,
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to submit review."));
        }
        setHouseholdReviewForm(EMPTY_HOUSEHOLD_REVIEW_FORM);
        await refreshReviewsFromBackend();
        // Also re-pull jobs: canReview flips off once the review lands, which is
        // what moves the job out of the dashboard's "Completed" list.
        await refreshJobsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert("Review submitted for the worker.");
        return true;
      } catch (error) {
        await refreshReviewsFromBackend();
        window.alert(error.message || "Unable to submit review. Please try again.");
        return false;
      }
    })();
  }
  function handleWorkerFeedbackSubmit(event) {
    event.preventDefault();
    if (!currentWorker || !selectedJob) {
      window.alert("Select a completed job first.");
      return;
    }
    const household = registeredHouseholds.find((item) => item.username === selectedJob.householdUsername);
    if (!household) {
      window.alert("Household profile not found.");
      return;
    }
    const rating = parseFloat(workerFeedbackForm.rating);
    if (!rating) {
      window.alert("Please select a household rating first.");
      return;
    }
    (async () => {
      try {
        const body = {
          target_username: household.username,
          job_id: selectedJob?.id,
          job_title: selectedJob?.jobTitle || selectedJob?.serviceType || "",
          rating,
          feedback: workerFeedbackForm.feedback.trim(),
        };

        if (workerFeedbackForm.quality_of_work) body.quality_of_work = parseInt(workerFeedbackForm.quality_of_work);
        if (workerFeedbackForm.punctuality) body.punctuality = parseInt(workerFeedbackForm.punctuality);
        if (workerFeedbackForm.communication) body.communication = parseInt(workerFeedbackForm.communication);
        if (workerFeedbackForm.professionalism) body.professionalism = parseInt(workerFeedbackForm.professionalism);

        const response = await apiRequest("reviews/", {
          method: "POST",
          auth: true,
          body,
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to submit feedback."));
        }
        setWorkerFeedbackForm(EMPTY_WORKER_FEEDBACK_FORM);
        await refreshReviewsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert("Feedback submitted for the household.");
      } catch (error) {
        await refreshReviewsFromBackend();
        window.alert(error.message || "Unable to submit feedback. Please try again.");
      }
    })();
  }
  function handleWorkerFeedbackForReviewSubmit(review, feedbackText, ratingValue = "5") {
    if (!currentWorker) {
      window.alert("Please login as a worker first.");
      return;
    }
    const feedback = String(feedbackText || "").trim();
    if (!feedback) {
      window.alert("Please write feedback before sending.");
      return;
    }
    const rating = parseFloat(ratingValue);
    if (!rating) {
      window.alert("Please select a household rating first.");
      return;
    }
    const householdUsername = review?.authorUsername || "";
    const household =
      registeredHouseholds.find((item) => item.username === householdUsername) ||
      registeredHouseholds.find(
        (item) => getDisplayName(item.firstName, item.lastName, item.username) === review?.authorName,
      );
    if (!household) {
      window.alert("Household profile not found.");
      return;
    }
    if (!review?.jobId) {
      // Guessing selectedJob?.id here would risk filing the reply against
      // whatever job happens to be selected elsewhere in the UI rather than
      // the one this review is actually about.
      window.alert("Unable to determine which job this review is for. Please try again.");
      return;
    }
    (async () => {
      try {
        const response = await apiRequest("reviews/", {
          method: "POST",
          auth: true,
          body: {
            target_username: household.username,
            job_id: review.jobId,
            job_title: review?.jobTitle || "",
            rating,
            feedback,
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to submit feedback."));
        }
        await refreshReviewsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert("Anonymous feedback sent to the household.");
      } catch (error) {
        await refreshReviewsFromBackend();
        window.alert(error.message || "Unable to submit anonymous feedback. Please try again.");
      }
    })();
  }
  function handleHouseholdJobSubmit(event) {
    event.preventDefault();
    if (!currentUser || currentUser.role !== "household") {
      window.alert("Please login as a household account first.");
      return;
    }
    if (currentHousehold?.verification !== "Verified") {
      window.alert("Your household account must be verified before you can post a job.");
      setView("household-get-verified");
      return;
    }
    const serviceType = householdJobForm.serviceType === "Other"
      ? (householdJobForm.customServiceType || "").trim()
      : householdJobForm.serviceType;
    if (
      !serviceType ||
      !householdJobForm.preferredDate ||
      !householdJobForm.preferredTime ||
      getWorkersNeeded(householdJobForm) < 1
    ) {
      window.alert("Please complete the service type, preferred date, preferred time, and number of workers needed.");
      return;
    }
    if (isSubmittingJobRef.current) {
      // Ignore a double-click/double-submit rather than posting the job
      // twice -- resolveLocationCoordinates below is a multi-second geocode
      // round-trip, leaving a wide window for a second click to land before
      // the first POST resolves.
      return;
    }
    isSubmittingJobRef.current = true;
    setIsSubmittingJob(true);
    (async () => {
     try {
      const resolvedLocation =
        householdJobLocationPreview ||
        (await resolveLocationCoordinates(householdJobForm.barangay, householdJobForm.streetAddress, true));
      const scheduledLabel = `${formatScheduleLabel(householdJobForm.scheduleType)}${householdJobForm.preferredDate ? ` on ${householdJobForm.preferredDate}` : ""}${householdJobForm.preferredTime ? ` at ${householdJobForm.preferredTime}` : ""}`;
      const resolvedLatitude =
        resolvedLocation?.latitude ??
        householdJobCoordinates?.latitude ??
        currentUser?.profile?.latitude ??
        currentHousehold?.latitude ??
        null;
      const resolvedLongitude =
        resolvedLocation?.longitude ??
        householdJobCoordinates?.longitude ??
        currentUser?.profile?.longitude ??
        currentHousehold?.longitude ??
        null;
      if (resolvedLatitude == null || resolvedLongitude == null) {
        window.alert(
          "Location is required before posting a job. Click 'Use My Current Location' or complete the barangay and street fields so we can estimate the map location first.",
        );
        return;
      }
      if (resolvedLocation) {
        setHouseholdJobLocationPreview(resolvedLocation);
        setHouseholdJobCoordinates({
          latitude: resolvedLatitude,
          longitude: resolvedLongitude,
        });
      }
      const distanceKmMap = { '1km': 1.0, '2km': 2.0, '5km': 5.0, '10km': 10.0, 'unlimited': 999999 };
      const geoBoundary = householdJobForm.geographicBoundary || '1km';
      const payload = {
        title: householdJobForm.jobTitle.trim() || serviceType,
        job_type: serviceType,
        required_skill: serviceType,
        schedule: scheduledLabel,
        schedule_type: householdJobForm.scheduleType,
        preferred_date: householdJobForm.preferredDate,
        preferred_time: householdJobForm.preferredTime,
        description: householdJobForm.description.trim(),
        location_label:
          resolvedLocation?.locationLabel ||
          formatLocation(householdJobForm.barangay.trim(), householdJobForm.streetAddress.trim()),
        latitude: resolvedLatitude,
        longitude: resolvedLongitude,
        service_rate: householdJobForm.offeredRate,
        worker_slots: getWorkersNeeded(householdJobForm),
        job_start_date: householdJobForm.jobStartDate || null,
        job_end_date: householdJobForm.jobEndDate || null,
        estimated_working_days: householdJobForm.estimatedWorkingDays ? parseInt(householdJobForm.estimatedWorkingDays, 10) : null,
        max_distance_km: distanceKmMap[geoBoundary] || 1.0,
        geographic_boundary: geoBoundary,
      };
      const imageFiles = Array.isArray(householdJobImages) ? householdJobImages : [];
      let shouldResetHouseholdJobForm = false;
      let postedJobForMatching = null;
      try {
        const requestBody = imageFiles.length > 0 ? new FormData() : payload;
        if (requestBody instanceof FormData) {
          Object.entries(payload).forEach(([key, value]) => {
            requestBody.append(key, value ?? "");
          });
          imageFiles.forEach((file) => requestBody.append("images", file));
        }
        const response = await apiRequest("jobs/", {
          method: "POST",
          auth: true,
          body: requestBody,
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to post job."));
        }
        const normalizedJob = normalizeBackendJob(data);
        if (normalizedJob) {
          setPostedJobs((prev) => [normalizedJob, ...prev.filter((job) => job.id !== normalizedJob.id)]);
          setSelectedJobId(normalizedJob.id);
          postedJobForMatching = normalizedJob;
        }
        shouldResetHouseholdJobForm = true;
      } catch (error) {
        await refreshJobsFromBackend();
        window.alert(error.message || "Unable to post job. Please review the form and try again.");
        return;
      } finally {
        if (shouldResetHouseholdJobForm) {
          const savedLocation = getSavedHouseholdLocation(currentHousehold, currentUser);
          setHouseholdJobCoordinates(null);
          setHouseholdJobLocationPreview(null);
          setHouseholdJobImages([]);
          setHouseholdJobForm({
            jobTitle: "",
            serviceType: "",
            customServiceType: "",
            scheduleType: "One-Time",
            preferredDate: "",
            preferredTime: "",
            description: "",
            barangay: savedLocation.barangay,
            streetAddress: savedLocation.streetAddress,
            offeredRate: "0.00",
            rateType: "Per Day",
            workersNeeded: "1",
            jobStartDate: "",
            jobEndDate: "",
            estimatedWorkingDays: "",
            geographicBoundary: "1km",
          });
          if (postedJobForMatching) {
            refreshRecommendedWorkers(postedJobForMatching.id, "ai");
          }
          refreshJobsFromBackend();
          setView("household-job-matches");
        }
      }
     } finally {
      isSubmittingJobRef.current = false;
      setIsSubmittingJob(false);
     }
    })();
  }
  function handleAdminApproveVerification(requestId) {
    if (!getAuthToken()) {
      window.alert("Please log in with a backend admin account before approving verification requests.");
      return;
    }
    const request = verificationRequests.find((item) => item.id === requestId);
    if (!request) return;
    (async () => {
      try {
        const response = await apiRequest(`common/verification-requests/${requestId}/review/`, {
          method: "POST",
          auth: true,
          body: {
            action: "approve",
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to approve verification request."));
        }
        const normalizedRequest = normalizeVerificationRequest(data.verification_request || data);
        const reviewedAt = normalizedRequest.reviewedAt || new Date().toLocaleString("en-PH");
        const backendAccount = data.account || data.worker;
        const backendWorker =
          normalizedRequest.accountRole === "worker" ? normalizeBackendWorkerPayload(backendAccount) : null;
        setVerificationRequests((prev) => prev.map((item) => (item.id === requestId ? normalizedRequest : item)));
        if (normalizedRequest.accountRole === "worker" && backendWorker) {
          mergeBackendWorkerIntoState({
            ...backendWorker,
            verification: "Verified",
            verificationReviewedAt: reviewedAt,
            verificationReviewedBy: currentUser?.displayName || "Admin",
            profilePhotoPreview: normalizedRequest.primaryIdPreview || backendWorker.profilePhotoPreview || "",
            verificationNotifications: [
              {
                id: `approved-${normalizedRequest.id}`,
                title: "Verified",
                message: "Your worker account has been verified by the admin.",
                date: reviewedAt,
                unread: true,
              },
            ],
          });
        } else if (normalizedRequest.accountRole === "worker") {
          setRegisteredWorkers((prev) =>
            prev.map((worker) =>
              worker.id === normalizedRequest.workerId
                ? {
                    ...worker,
                    verification: "Verified",
                    verificationReviewedAt: reviewedAt,
                    verificationReviewedBy: currentUser?.displayName || "Admin",
                    profilePhotoPreview: normalizedRequest.primaryIdPreview || worker.profilePhotoPreview || "",
                    verificationNotifications: [
                      {
                        id: `approved-${normalizedRequest.id}`,
                        title: "Verified",
                        message: "Your worker account has been verified by the admin.",
                        date: reviewedAt,
                        unread: true,
                      },
                    ],
                  }
                : worker,
            ),
          );
        } else {
          setRegisteredHouseholds((prev) =>
            prev.map((household) =>
              String(household.id) === String(normalizedRequest.workerId) ||
              household.username === normalizedRequest.workerUsername
                ? {
                    ...household,
                    verification: "Verified",
                    verificationReviewedAt: reviewedAt,
                    verificationReviewedBy: currentUser?.displayName || "Admin",
                    verificationSubmission: normalizedRequest,
                  }
                : household,
            ),
          );
        }
        await refreshVerificationStateFromBackend();
        await refreshNotificationsFromBackend();
        window.alert(`Verification approved. ${normalizedRequest.accountRole === "household" ? "Household" : "Worker"} is now Verified.`);
        setSelectedVerificationRequestId(requestId);
        setView(currentUser?.isSuperAdmin ? "superadmin-dashboard" : "admin-dashboard");
      } catch (error) {
        // Must never read as success: a fallback like "Verified {name}."
        // here would tell the admin the approval went through when it
        // didn't, and navigating away regardless hid that nothing changed.
        window.alert(error.message || "Unable to approve this verification request. Please try again.");
      }
    })();
  }
  function handleAdminRejectVerification(requestId) {
    if (!getAuthToken()) {
      window.alert("Please log in with a backend admin account before rejecting verification requests.");
      return;
    }
    const request = verificationRequests.find((item) => item.id === requestId);
    if (!request) return;
    const reviewNote =
      window.prompt("Enter rejection note:", "Please resubmit clearer documents.") || "Rejected by admin.";
    (async () => {
      try {
        const response = await apiRequest(`common/verification-requests/${requestId}/review/`, {
          method: "POST",
          auth: true,
          body: {
            action: "reject",
            review_note: reviewNote,
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to reject verification request."));
        }
        const normalizedRequest = normalizeVerificationRequest(data.verification_request || data);
        const reviewedAt = normalizedRequest.reviewedAt || new Date().toLocaleString("en-PH");
        const backendAccount = data.account || data.worker;
        const backendWorker =
          normalizedRequest.accountRole === "worker" ? normalizeBackendWorkerPayload(backendAccount) : null;
        setVerificationRequests((prev) => prev.map((item) => (item.id === requestId ? normalizedRequest : item)));
        if (normalizedRequest.accountRole === "worker" && backendWorker) {
          mergeBackendWorkerIntoState({
            ...backendWorker,
            verification: "Rejected",
            verificationReviewedAt: reviewedAt,
            verificationReviewedBy: currentUser?.displayName || "Admin",
            verificationRejectionNote: reviewNote,
            profilePhotoPreview: backendWorker.profilePhotoPreview || "",
            verificationNotifications: [
              {
                id: `rejected-${normalizedRequest.id}`,
                title: "Verification Rejected",
                message: reviewNote,
                date: reviewedAt,
                unread: true,
              },
            ],
          });
        } else if (normalizedRequest.accountRole === "worker") {
          setRegisteredWorkers((prev) =>
            prev.map((worker) =>
              worker.id === normalizedRequest.workerId
                ? {
                    ...worker,
                    verification: "Rejected",
                    verificationReviewedAt: reviewedAt,
                    verificationReviewedBy: currentUser?.displayName || "Admin",
                    verificationRejectionNote: reviewNote,
                    profilePhotoPreview: worker.profilePhotoPreview || "",
                    verificationNotifications: [
                      {
                        id: `rejected-${normalizedRequest.id}`,
                        title: "Verification Rejected",
                        message: reviewNote,
                        date: reviewedAt,
                        unread: true,
                      },
                    ],
                  }
                : worker,
            ),
          );
        } else {
          setRegisteredHouseholds((prev) =>
            prev.map((household) =>
              String(household.id) === String(normalizedRequest.workerId) ||
              household.username === normalizedRequest.workerUsername
                ? {
                    ...household,
                    verification: "Rejected",
                    verificationReviewedAt: reviewedAt,
                    verificationReviewedBy: currentUser?.displayName || "Admin",
                    verificationRejectionNote: reviewNote,
                    verificationSubmission: normalizedRequest,
                  }
                : household,
            ),
          );
        }
        await refreshVerificationStateFromBackend();
        await refreshNotificationsFromBackend();
        window.alert("Verification rejected. Please check admin review notes.");
        setSelectedVerificationRequestId(requestId);
        setView(currentUser?.isSuperAdmin ? "superadmin-dashboard" : "admin-dashboard");
      } catch (error) {
        // Must never read as success -- see the matching note in
        // handleAdminApproveVerification above.
        window.alert(error.message || "Unable to reject this verification request. Please try again.");
      }
    })();
  }
  return {
    handleApplyToJob,
    handleHireWorker,
    handleWorkerRequestCompletion,
    handleWorkerHireDecision,
    handleRejectApplication,
    handleLoginSubmit,
    handleWorkerRegisterSubmit,
    handleHouseholdRegisterSubmit,
    handleWorkerProfileSave,
    handleVerificationSubmit,
    handleHouseholdProfileSave,
    handleCancelJob,
    handleHouseholdReviewSubmit,
    handleWorkerFeedbackSubmit,
    handleWorkerFeedbackForReviewSubmit,
    handleHouseholdJobSubmit,
    handleConfirmJobCompleted,
    handleAdminApproveVerification,
    handleAdminRejectVerification,
    isSubmittingJob,
  };
}
