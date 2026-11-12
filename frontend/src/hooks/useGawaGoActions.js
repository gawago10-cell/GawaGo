import { useRef, useState } from "react";

import { knownBarangay, normalizeBarangayName } from "../utils/locationUtils";
import { dashboardViewForRole, getUserRole, isAdminRole, ROLES } from "../utils/roles";
import {
  focusFirstInvalidField,
  validateRegistration,
  validateWorkerRegistration,
  WORKER_PIN_REQUIRED_MESSAGE,
  WORKER_REGISTRATION_FIELD_ORDER,
} from "../utils/registrationValidation";
import { resolveWorkerSkills, validateWorkerSkills } from "../utils/skillUtils";
import { getReviewMetricAverage } from "../utils/reviewUtils";
import { isConfirmedJobPin } from "./useHouseholdJobLocation";
import { askReason, confirmDialog } from "../components/AppDialogs";
import { withdrawApplication } from "../services/backendDataService";

function omitSensitiveAccountFields(account) {
  const { password, confirmPassword, ...safeAccount } = account;
  return safeAccount;
}

export function useGawaGoActions({
  setPendingSignupEmail,
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
  isValidEmailAddress,
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
  refreshProfilesFromBackend,
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
  setLoginError,
  setRegisterErrors,
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
  setWorkerProfileForm,
  verificationForm,
  verificationRequests,
  workerFeedbackForm,
  workerForm,
  workerProfileForm,
}) {
  // Guards handleHouseholdJobSubmit against a double-click. A ref (not a
  // plain closure variable) is required: this whole hook body re-runs on
  // every render, and a state update during the POST (an image upload can
  // take seconds) would otherwise re-render before it resolves, silently
  // resetting a plain variable's guard.
  const isSubmittingJobRef = useRef(false);
  const [isSubmittingJob, setIsSubmittingJob] = useState(false);
  // Same double-click guard for every other request-sending action: a second
  // click while the first request is in flight is ignored instead of sending
  // a duplicate that the server rejects with a contradictory message.
  const actionsInFlightRef = useRef(new Set());
  const [, setActionsInFlightVersion] = useState(0);
  function isActionPending(key) {
    return actionsInFlightRef.current.has(key);
  }
  async function runExclusive(key, task) {
    if (actionsInFlightRef.current.has(key)) {
      return false;
    }
    actionsInFlightRef.current.add(key);
    setActionsInFlightVersion((version) => version + 1);
    try {
      return await task();
    } finally {
      actionsInFlightRef.current.delete(key);
      setActionsInFlightVersion((version) => version + 1);
    }
  }

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
    runExclusive(`apply-${jobId}`, async () => {
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
    });
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
    runExclusive(`hire-${selectedJob.id}-${selectedWorker.id}`, async () => {
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
    });
  }
  // The worker steps away (fourth scan, 2026-11-01): a pending application
  // is taken back after a confirm; a hire is given up before the job starts,
  // with a reason the household reads.
  async function handleWorkerWithdraw(job) {
    if (!job?.applicationId || !isNumericIdentifier(job.applicationId)) {
      window.alert("This application is not synced with the backend yet. Please refresh and try again.");
      return;
    }
    const title = job.jobTitle || job.title || job.serviceType || "this job";
    const household = job.householdName || job.householdUsername || "The household";
    const backingOut = Boolean(job.canBackOut);
    let reason = "";
    if (backingOut) {
      const answer = await askReason({
        title: `Back out of ${title}?`,
        message: `${household} is told you can't take this job, with your reason, so they can hire someone else.`,
        label: "Why can't you take this job?",
        placeholder: "e.g. I'm sick and can't work that week.",
        confirmLabel: "Back out",
        cancelLabel: "Keep job",
        tone: "danger",
        requiredMessage: "Tell the household why you can't take this job.",
      });
      if (answer === null) return;
      reason = answer;
    } else {
      const confirmed = await confirmDialog({
        title: `Withdraw your application for ${title}?`,
        message: `${household} is told. You can apply again while the job is still taking applicants.`,
        confirmLabel: "Withdraw",
        cancelLabel: "Keep application",
        tone: "danger",
      });
      if (!confirmed) return;
    }
    runExclusive(`withdraw-${job.applicationId}`, async () => {
      try {
        await withdrawApplication(job.applicationId, reason);
        window.alert(
          backingOut ? `You backed out of ${title}. ${household} has been told.` : `Your application for ${title} was withdrawn.`,
        );
      } catch (error) {
        window.alert(error.message || "Unable to withdraw from this job. Please try again.");
      } finally {
        await refreshJobsFromBackend();
      }
    });
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
    runExclusive(`hire-decision-${applicationId}`, async () => {
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
    });
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
    const applicationStatusTargetId = existingApplication.id;
    runExclusive(`reject-application-${applicationStatusTargetId}`, async () => {
      const rejectedAt = new Date().toLocaleString("en-PH");
      const message = `Thank you for applying to ${job.jobTitle || job.serviceType}. The household chose another applicant for now, but you can still apply to other open jobs.`;
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
    });
  }
  function handleLoginSubmit(event) {
    event.preventDefault();
    const username = loginForm.username.trim();
    setLoginError("");
    if (!username || !loginForm.password) {
      setLoginError("Please enter your username and password.");
      return;
    }
    runExclusive("login-submit", async () => {
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
        if (!response.ok && data?.verification_required) {
          setPendingSignupEmail?.(data.email || "");
          setView("confirm-email");
          return;
        }
        if (!response.ok) {
          const loginError = new Error(data?.detail || "Login failed.");
          loginError.status = response.status;
          throw loginError;
        }
        // The account role comes from the login response only -- never from
        // profile.role, which defaults to "worker" even for admin accounts.
        const resolvedRole = getUserRole({ role: data?.role, is_staff: data?.is_staff });
        if (!resolvedRole) {
          const roleError = new Error("This account type isn't supported here. Please contact support.");
          roleError.status = 403;
          throw roleError;
        }
        setAuthToken(data?.access || "");
        const isSuperAdmin = resolvedRole === ROLES.SUPERADMIN;
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
        if (backendWorker && !isAdminRole(resolvedRole)) {
          mergeBackendWorkerIntoState(backendWorker);
        }
        setView(dashboardViewForRole(resolvedRole));
        // The jobs list is fetched anonymously before login (no per-user
        // application data), and the background poll that would otherwise
        // pick up the authenticated view can take several seconds. Refresh
        // immediately so pages like "My Applications" aren't briefly empty
        // right after logging in.
        refreshJobsFromBackend();
        refreshNotificationsFromBackend();
      } catch (error) {
        if (error.status === 403) {
          setLoginError(error.message || "Account is not verified yet.");
          return;
        }
        clearAuthToken();
        setLoginError(error.message || "Login failed. Please check your username and password.");
      }
    });
  }
  function handleWorkerRegisterSubmit(event) {
    event.preventDefault();
    const formErrors = validateWorkerRegistration(workerForm);
    setRegisterErrors(formErrors);
    if (Object.keys(formErrors).length > 0) {
      focusFirstInvalidField(formErrors, event.currentTarget, WORKER_REGISTRATION_FIELD_ORDER);
      return;
    }
    const registrationSkills = resolveWorkerSkills(workerForm.skills, workerForm.customSkill);
    const usernameTaken = registeredWorkers.some(
      (item) => item.username.toLowerCase() === workerForm.username.trim().toLowerCase(),
    );
    if (usernameTaken) {
      window.alert("Username already exists for a worker account.");
      return;
    }
    runExclusive("register", async () => {
      try {
        // The pin is required (validateWorkerRegistration): matching measures
        // road distance from it, and the geocoded guesses this used to fall
        // back on put workers up to 13 km from home. The label is built from
        // the form so it always names the barangay.
        const normalizedBarangay = normalizeBarangayName(workerForm.barangay);
        const workerLatitude = workerForm.latitude;
        const workerLongitude = workerForm.longitude;
        const workerLocationLabel = formatLocation(normalizedBarangay, workerForm.streetAddress.trim());
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
            skills: registrationSkills,
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
        if (data?.verification_required) {
          setWorkerForm(EMPTY_WORKER_FORM);
          setPendingSignupEmail?.(data.email || "");
          setView("confirm-email");
          return;
        }
        const backendWorker = normalizeBackendWorkerPayload({
          user: data?.user,
          profile: data?.profile,
        });
        const workerAccount = {
          ...omitSensitiveAccountFields(workerForm),
          skills: registrationSkills,
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
    });
  }
  function handleHouseholdRegisterSubmit(event) {
    event.preventDefault();
    const formErrors = validateRegistration(householdForm);
    if (
      !formErrors.username &&
      registeredHouseholds.some(
        (item) => item.username.toLowerCase() === householdForm.username.trim().toLowerCase(),
      )
    ) {
      formErrors.username = "That username is already taken.";
    }
    setRegisterErrors(formErrors);
    if (Object.keys(formErrors).length > 0) {
      focusFirstInvalidField(formErrors, event.currentTarget);
      return;
    }
    runExclusive("register", async () => {
      try {
        // No map on this form: a street the geocoder places precisely, or
        // else the barangay's centre -- never the town centre.
        const resolvedLocation = await resolveLocationCoordinates(householdForm.barangay, householdForm.streetAddress);
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
        if (data?.verification_required) {
          setHouseholdForm(EMPTY_HOUSEHOLD_FORM);
          setPendingSignupEmail?.(data.email || "");
          setView("confirm-email");
          return;
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
    });
  }
  function handleWorkerProfileSave(event) {
    event.preventDefault();
    if (!currentUser || currentUser.role !== "worker") {
      window.alert("No worker account is currently logged in.");
      return false;
    }
    // Changing the barangay clears the pin; the worker pins the new spot
    // rather than being moved to a geocoded guess.
    if (workerProfileForm.latitude == null || workerProfileForm.longitude == null) {
      window.alert(WORKER_PIN_REQUIRED_MESSAGE);
      return false;
    }
    // Saving used to keep a barangay the list can't show (an old
    // "Poblacion" label), so the profile never got a real one.
    if (!knownBarangay(workerProfileForm.barangay)) {
      window.alert("Choose your barangay from the list.");
      return false;
    }
    const skillErrors = validateWorkerSkills(workerProfileForm.skills, "");
    if (skillErrors.skills) {
      window.alert(skillErrors.skills);
      return false;
    }
    // Resolves true once saved, so the form leaves edit mode only then: a
    // refused save used to lock the form with the worker's edits in it.
    return runExclusive("worker-profile-save", async () => {
      const normalizedBarangay = normalizeBarangayName(workerProfileForm.barangay);
      const workerLatitude = workerProfileForm.latitude;
      const workerLongitude = workerProfileForm.longitude;
      const workerLocationLabel = formatLocation(normalizedBarangay, String(workerProfileForm.streetAddress || "").trim());
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
            // Only an email change needs it (the backend asks then).
            ...(workerProfileForm.currentPassword ? { current_password: workerProfileForm.currentPassword } : {}),
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
          // An email change signs out other devices and hands this one a
          // fresh token; the old one no longer works, even for the request
          // just below.
          if (data?.access) {
            setAuthToken(data.access);
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
        setWorkerProfileForm((prev) => ({ ...prev, currentPassword: "" }));
        setCurrentUser((prev) => {
          if (!prev) return prev;
          return {
            ...prev,
            email: workerProfileForm.email,
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
        return true;
      } catch (error) {
        window.alert(error.message || "Unable to update worker profile.");
        return false;
      }
    });
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
    if (!verificationForm.primaryIdType) {
      window.alert("Please choose which government ID you are uploading.");
      return;
    }
    if (verificationForm.primaryIdType === "other" && !(verificationForm.primaryIdOtherName || "").trim()) {
      window.alert("Please name the government ID you are uploading.");
      return;
    }
    // Same bounds as the backend: 4 to 30 letters and digits once dashes and
    // spaces are dropped.
    const idNumberLength = String(verificationForm.primaryIdNumber || "").replace(/[^0-9a-z]/gi, "").length;
    if (idNumberLength < 4 || idNumberLength > 30) {
      window.alert("Enter the ID number exactly as it is printed on your ID.");
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
    runExclusive("verification-submit", async () => {
      const requestRecord = new FormData();
      requestRecord.append("primary_id_type", verificationForm.primaryIdType || "other");
      // The backend fills the label from the chosen type; it only reads this
      // when the type is "other".
      if ((verificationForm.primaryIdType || "other") === "other") {
        requestRecord.append("primary_id_name", verificationForm.primaryIdOtherName || "");
      }
      requestRecord.append("primary_id_number", String(verificationForm.primaryIdNumber || "").trim());
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
        // An ID number that belongs to a permanently blocked account is
        // rejected on arrival (AGENTS.md II.D). Show the backend's answer
        // instead of claiming the request is under review.
        if (normalizedRequest?.status === "Rejected") {
          if (backendAccount?.profile) {
            setCurrentUser((prev) => (prev ? { ...prev, profile: backendAccount.profile } : prev));
          }
          await refreshVerificationStateFromBackend();
          window.alert(normalizedRequest.reviewNote || "We couldn't verify this ID. Contact support if you think this is a mistake.");
          return;
        }
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
    });
  }
  function handleHouseholdProfileSave(event) {
    event.preventDefault();
    if (!currentUser || currentUser.role !== "household") {
      window.alert("No household account is currently logged in.");
      return;
    }
    runExclusive("household-profile-save", async () => {
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
    });
  }
  async function handleCancelJob(jobId) {
    const job = postedJobs.find((item) => item.id === jobId);
    if (!job) {
      return;
    }
    // A hired worker is told why the job is called off (the backend
    // requires it then, and says so in cancel_needs_reason).
    const hasHiredWorker =
      job.cancelNeedsReason || (job.applications || []).some((application) => application.status === "Hired");
    let cancelReason = "";
    if (hasHiredWorker) {
      const answer = await askReason({
        title: `Cancel ${job.jobTitle || job.title || "this job"}?`,
        message: "The hired worker is told the job is off and why. This can't be undone.",
        label: "Why are you cancelling?",
        placeholder: "e.g. The worker didn't arrive on the agreed day.",
        confirmLabel: "Cancel job",
        cancelLabel: "Keep job",
        tone: "danger",
        requiredMessage: "Please give a reason; the hired worker will see it.",
      });
      if (answer === null) return;
      cancelReason = answer.trim();
      if (!cancelReason) {
        window.alert("Please give a reason; the hired worker will see it.");
        return;
      }
    } else {
      const confirmed = await confirmDialog({
        title: `Cancel ${job.jobTitle || job.title || "this job"}?`,
        message: "Workers no longer see it, and anyone waiting is told. This can't be undone.",
        confirmLabel: "Cancel job",
        cancelLabel: "Keep job",
        tone: "danger",
      });
      if (!confirmed) return;
    }
    runExclusive(`cancel-job-${jobId}`, async () => {
      try {
        const response = await apiRequest(`jobs/${jobId}/`, {
          method: "PATCH",
          auth: true,
          body: {
            status: "cancelled",
            ...(cancelReason ? { cancel_reason: cancelReason } : {}),
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
    });
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
    runExclusive(`complete-${jobId}`, async () => {
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
    });
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
    // With metrics rated, the overall rating is their average (AGENTS.md
    // II.A), not the star picker's default 5.
    const rating = getReviewMetricAverage(householdReviewForm) ?? parseFloat(householdReviewForm.rating);
    if (!rating) {
      window.alert("Please select a star rating first.");
      return false;
    }
    if (!selectedJob?.id) {
      window.alert("Select a completed job first.");
      return false;
    }
    return runExclusive(`review-${selectedJob.id}-${selectedWorker.id}`, async () => {
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
        // what moves the job out of the dashboard's "Completed" list. The
        // worker's rating and review count live on their profile, which
        // otherwise kept showing "New · 0 reviews" until a reload.
        await refreshJobsFromBackend();
        await refreshProfilesFromBackend?.();
        await refreshNotificationsFromBackend();
        window.alert("Review submitted for the worker.");
        return true;
      } catch (error) {
        await refreshReviewsFromBackend();
        window.alert(error.message || "Unable to submit review. Please try again.");
        return false;
      }
    });
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
    runExclusive(`worker-feedback-${selectedJob.id}`, async () => {
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
    });
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
    runExclusive(`worker-feedback-reply-${review.jobId}`, async () => {
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
    });
  }
  // Saves an open job's edited details. Only fields that changed are sent:
  // an unchanged start date already in the past would otherwise be refused
  // as a past date. Throws with the server's message so the dialog can show
  // it.
  async function handleUpdateJob(job, form) {
    const rateTypeValue = (label) => ({ "Per Hour": "per_hour", "Fixed Rate": "fixed" })[label] || "per_day";
    const changes = {};
    const setIfChanged = (key, next, previous) => {
      if (String(next ?? "") !== String(previous ?? "")) {
        changes[key] = next;
      }
    };
    setIfChanged("title", form.jobTitle.trim(), job.jobTitle);
    setIfChanged("description", form.description.trim(), job.description);
    if (Number(form.offeredRate) !== Number(job.offeredRate)) {
      changes.service_rate = form.offeredRate;
    }
    setIfChanged("rate_type", rateTypeValue(form.rateType), rateTypeValue(job.rateType));
    if (Number(form.workersNeeded) !== Number(job.workersNeeded)) {
      changes.worker_slots = Number(form.workersNeeded);
    }
    setIfChanged("job_start_date", form.jobStartDate, job.jobStartDate);
    setIfChanged("job_end_date", form.jobEndDate || null, job.jobEndDate || null);
    // Working days are no longer typed in: the dates set how long a job
    // runs. A job posted with a count keeps it until its dates change to
    // include an end date, then drops it, so the old count can't conflict
    // with the new schedule. Without an end date the count still sets the
    // job's length, so it stays.
    if (
      job.estimatedWorkingDays != null &&
      form.jobEndDate &&
      ("job_start_date" in changes || "job_end_date" in changes)
    ) {
      changes.estimated_working_days = null;
    }
    setIfChanged("geographic_boundary", form.geographicBoundary, job.geographicBoundary || "1km");
    // The backend moves the date in the "One-Time starting ..." schedule line
    // itself when the start date changes.
    if (Object.keys(changes).length === 0) {
      return job;
    }
    const response = await apiRequest(`jobs/${job.id}/`, { method: "PATCH", auth: true, body: changes });
    const data = await readResponseData(response);
    if (!response.ok) {
      throw new Error(getApiErrorMessage(data, "Unable to save this job."));
    }
    const updatedJob = normalizeBackendJob(data);
    if (updatedJob) {
      setPostedJobs((prev) => prev.map((item) => (item.id === updatedJob.id ? updatedJob : item)));
    }
    if ("geographic_boundary" in changes) {
      // A wider or narrower radius changes who matches.
      refreshRecommendedWorkers(job.id, "ai");
    }
    window.alert("Job updated.");
    return updatedJob;
  }
  // AGENTS.md II.A: workers rate households too. The web form for this sat in
  // a panel nothing opened, and only appeared once the household had
  // reviewed first; this is reached from the completed job itself.
  function handleWorkerRateHousehold(job, ratingValue, feedbackText = "") {
    const rating = parseFloat(ratingValue);
    if (!currentWorker || !job?.id || !job.householdUsername) {
      window.alert("Unable to tell which household this job was for. Please refresh and try again.");
      return Promise.resolve(false);
    }
    if (!(rating >= 1 && rating <= 5)) {
      window.alert("Please choose a rating from 1 to 5 stars.");
      return Promise.resolve(false);
    }
    return runExclusive(`worker-rate-household-${job.id}`, async () => {
      try {
        const response = await apiRequest("reviews/", {
          method: "POST",
          auth: true,
          body: {
            target_username: job.householdUsername,
            job_id: job.id,
            rating,
            feedback: String(feedbackText || "").trim(),
          },
        });
        const data = await readResponseData(response);
        if (!response.ok) {
          throw new Error(getApiErrorMessage(data, "Unable to rate the household."));
        }
        await refreshReviewsFromBackend();
        await refreshNotificationsFromBackend();
        window.alert("Thanks. Your rating was sent to the household anonymously.");
        return true;
      } catch (error) {
        await refreshReviewsFromBackend();
        window.alert(error.message || "Unable to rate the household. Please try again.");
        return false;
      }
    });
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
      !householdJobForm.jobStartDate ||
      getWorkersNeeded(householdJobForm) < 1
    ) {
      window.alert("Please complete the service type, job start date, and number of workers needed.");
      return;
    }
    // A job pays something (spec II.B); the backend refuses less than PHP 1.
    if (!(Number(householdJobForm.offeredRate) >= 1)) {
      window.alert("Enter an offered rate of at least PHP 1.00.");
      return;
    }
    // The job site is a pin the household confirmed (a device fix, or a
    // spot pinned or dragged to on the map). Falling back to a geocoded
    // address or the profile's point used to post jobs up to 13 km from the
    // real site, with a 1 km default matching radius.
    if (!isConfirmedJobPin(householdJobLocationPreview)) {
      window.alert(
        "Pin the job site before posting: use your current location, drag the pin on the map, or pin it manually.",
      );
      return;
    }
    if (isSubmittingJobRef.current) {
      // Ignore a double-click/double-submit rather than posting the job
      // twice while the first POST is still in flight.
      return;
    }
    isSubmittingJobRef.current = true;
    setIsSubmittingJob(true);
    (async () => {
     try {
      const resolvedLocation = householdJobLocationPreview;
      const scheduledLabel = `${formatScheduleLabel(householdJobForm.scheduleType)}${householdJobForm.jobStartDate ? ` starting ${householdJobForm.jobStartDate}` : ""}`;
      const resolvedLatitude = resolvedLocation.latitude;
      const resolvedLongitude = resolvedLocation.longitude;
      const distanceKmMap = { '1km': 1.0, '2km': 2.0, '5km': 5.0, '10km': 10.0, 'unlimited': 999999 };
      const geoBoundary = householdJobForm.geographicBoundary || '1km';
      const payload = {
        title: householdJobForm.jobTitle.trim() || serviceType,
        job_type: serviceType,
        required_skill: serviceType,
        schedule: scheduledLabel,
        schedule_type: householdJobForm.scheduleType,
        description: householdJobForm.description.trim(),
        // Built from the form, which the pin keeps in step, so it always
        // names the barangay that workers and the demand-by-barangay
        // analytics rely on.
        location_label: formatLocation(
          householdJobForm.barangay.trim() || resolvedLocation.barangay || "",
          householdJobForm.streetAddress.trim(),
        ),
        latitude: resolvedLatitude,
        longitude: resolvedLongitude,
        service_rate: householdJobForm.offeredRate,
        rate_type: { "Per Hour": "per_hour", "Fixed Rate": "fixed" }[householdJobForm.rateType] || "per_day",
        worker_slots: getWorkersNeeded(householdJobForm),
        job_start_date: householdJobForm.jobStartDate || null,
        job_end_date: householdJobForm.jobEndDate || null,
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
            description: "",
            barangay: savedLocation.barangay,
            streetAddress: savedLocation.streetAddress,
            offeredRate: "",
            rateType: "Per Day",
            workersNeeded: "1",
            jobStartDate: "",
            jobEndDate: "",
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
    runExclusive(`verification-review-${requestId}`, async () => {
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
            // Never the government ID image -- it's a private verification
            // document, not the worker's public profile photo.
            profilePhotoPreview: backendWorker.profilePhotoPreview || "",
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
                    profilePhotoPreview: worker.profilePhotoPreview || "",
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
    });
  }
  async function handleAdminRejectVerification(requestId) {
    if (!getAuthToken()) {
      window.alert("Please log in with a backend admin account before rejecting verification requests.");
      return;
    }
    const request = verificationRequests.find((item) => item.id === requestId);
    if (!request) return;
    // prompt() returns null when the admin cancels; the old `|| fallback`
    // turned that into a rejection they never confirmed.
    // No ready-made note: one click used to send "Please resubmit clearer
    // documents." whatever was actually wrong (fourth scan, 2026-11-01).
    const reviewNote = await askReason({
      title: `Reject ${request.workerName || "this verification"}?`,
      message: "They will see this note and can send their documents again.",
      label: "What should they fix?",
      placeholder: "e.g. The ID photo is cut off at the bottom.",
      confirmLabel: "Reject",
      tone: "danger",
      requiredMessage: "Please give a rejection reason so the applicant knows what to fix.",
    });
    if (reviewNote === null) return;
    const trimmedNote = reviewNote.trim();
    if (!trimmedNote) {
      window.alert("Please give a rejection reason so the applicant knows what to fix.");
      return;
    }
    runExclusive(`verification-review-${requestId}`, async () => {
      try {
        const response = await apiRequest(`common/verification-requests/${requestId}/review/`, {
          method: "POST",
          auth: true,
          body: {
            action: "reject",
            review_note: trimmedNote,
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
            verificationRejectionNote: trimmedNote,
            profilePhotoPreview: backendWorker.profilePhotoPreview || "",
            verificationNotifications: [
              {
                id: `rejected-${normalizedRequest.id}`,
                title: "Verification Rejected",
                message: trimmedNote,
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
                    verificationRejectionNote: trimmedNote,
                    profilePhotoPreview: worker.profilePhotoPreview || "",
                    verificationNotifications: [
                      {
                        id: `rejected-${normalizedRequest.id}`,
                        title: "Verification Rejected",
                        message: trimmedNote,
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
                    verificationRejectionNote: trimmedNote,
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
    });
  }
  return {
    handleApplyToJob,
    handleHireWorker,
    handleWorkerHireDecision,
    handleWorkerWithdraw,
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
    handleWorkerRateHousehold,
    handleUpdateJob,
    handleHouseholdJobSubmit,
    handleConfirmJobCompleted,
    handleAdminApproveVerification,
    handleAdminRejectVerification,
    isSubmittingJob,
    isActionPending,
  };
}
