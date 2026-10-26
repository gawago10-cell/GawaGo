import React, { lazy, Suspense, useEffect, useRef, useState } from "react";
import { apiRequest, clearAuthToken, getAuthToken, setAuthToken, setUnauthorizedHandler } from "./api/apiClient";
import {
  BARANGAYS,
  DEMO_HOUSEHOLD_ACCOUNTS,
  DEMO_VERIFICATION_REQUESTS,
  DEMO_WORKER_ACCOUNTS,
  EMPTY_HOUSEHOLD_FORM,
  EMPTY_HOUSEHOLD_REVIEW_FORM,
  EMPTY_WORKER_FEEDBACK_FORM,
  EMPTY_WORKER_FORM,
  IS_DEMO_MODE,
  PHILIPPINES_MAP_CENTER,
  SKILLS,
  STORAGE_KEYS,
} from "./constants/appConstants";
import {
  formatCurrency,
  formatDateTime,
  formatDistance,
  formatLocation,
  formatRate,
  formatScheduleLabel,
  getDisplayName,
  getDisplayRating,
  getWorkerPhoto,
  sanitizePhilippinesPhone,
} from "./utils/formatters";
import {
  deletePortfolioCertification,
  deletePortfolioItem,
  fetchMyAccount,
  fetchMyPortfolio,
  fetchWorkerEmploymentHistory,
  updatePortfolioSkillProficiency,
} from "./services/backendDataService";
import { getBarangayCenter, getFallbackBarangay } from "./utils/locationUtils";
import {
  buildCoordinateLocation,
  buildMapPreviewUrl,
  formatCoordinateAddress,
  getNearestBarangayFromCoordinates,
  getSavedHouseholdLocation,
  haversineDistanceKm,
  isValidEmailAddress,
  resolveLocationCoordinates,
  reverseGeocodeCoordinates,
} from "./utils/locationServices";
import {
  dedupeNotifications,
  getApiErrorMessage,
  getWorkerVerificationLabel,
  isNumericIdentifier,
  normalizeBackendApplication,
  normalizeBackendJob,
  normalizeBackendWorker,
  normalizeBackendWorkerPayload,
  normalizeJobRecord,
  normalizeReview,
  normalizeVerificationRequest,
} from "./utils/normalizers";
import {
  buildMatchedWorkersForJob,
  buildWorkerFallbackFromJob,
  createDemoJobPostings,
  createJobRecord,
  findJobApplicationForWorker,
  getHiredWorkerCount,
  getHiringProgressLabel,
  getJobStatusBadgeClass,
  getPendingApplicationCount,
  getWorkerJobMatches,
  getWorkersNeeded,
} from "./utils/jobUtils";
import {
  getHouseholdNotifications,
  getHouseholdReviewReminderNotifications,
  getVerificationNotifications,
} from "./utils/notificationUtils";
import { getHouseholdReviewSummary, getWorkerReviewSummary } from "./utils/reviewUtils";
import {
  ensureDemoVersion,
  getNotificationReadState,
  getStoredCollection,
  mergeDemoRecords,
} from "./utils/storageUtils";
import { readResponseData } from "./utils/apiUtils";
import { loadLeafletAssets } from "./utils/mapAssets";
import { renderBarangayOptions } from "./utils/formOptions";
import { dashboardViewForRole, getUserRole, isAdminRole, ROLES, resolveGuardedView } from "./utils/roles";
import "./styles/analytics.css";
import { useGawaGoNavigation } from "./hooks/useGawaGoNavigation";
import { useBackendSync } from "./hooks/useBackendSync";
import { usePasswordReset } from "./hooks/usePasswordReset";
import { useGawaGoFormHandlers } from "./hooks/useGawaGoFormHandlers";
import { useGawaGoActions } from "./hooks/useGawaGoActions";
import { useHouseholdJobLocation } from "./hooks/useHouseholdJobLocation";
import { useDashboardMetrics } from "./hooks/useDashboardMetrics";
import { useBackendPolling } from "./hooks/useBackendPolling";
import { useGawaGoDomEffects } from "./hooks/useGawaGoDomEffects";
import { useGawaGoPersistence } from "./hooks/useGawaGoPersistence";
import useViewRouting from "./hooks/useViewRouting";
import ChatWidget from "./components/ChatWidget";

const AppViews = lazy(() => import("./components/AppViews"));
const ForgotPasswordView = lazy(() => import("./components/ForgotPasswordView"));
const SELECTED_JOB_STORAGE_KEY = "gawago-selected-job";
const SuperAdminDashboardView = lazy(() => import("./components/SuperAdminDashboardView"));
const MyComplaintsView = lazy(() => import("./components/MyComplaintsView"));
const WorkerJobDetailView = lazy(() => import("./components/WorkerJobDetailView"));

function ViewLoading() {
  return (
    <main className="min-vh-100 d-flex align-items-center justify-content-center bg-light">
      <div className="text-center">
        <div className="spinner-border text-success" role="status" aria-label="Loading" />
      </div>
    </main>
  );
}

function getToastVariant(message) {
  const normalized = String(message || "").toLowerCase();
  if (
    normalized.includes("unable") ||
    normalized.includes("invalid") ||
    normalized.includes("failed") ||
    normalized.includes("not found") ||
    normalized.includes("not allowed") ||
    normalized.includes("cannot")
  ) {
    return "danger";
  }
  if (
    normalized.includes("please") ||
    normalized.includes("must") ||
    normalized.includes("required") ||
    normalized.includes("already") ||
    normalized.includes("only ")
  ) {
    return "warning";
  }
  if (
    normalized.includes("success") ||
    normalized.includes("sent") ||
    normalized.includes("created") ||
    normalized.includes("updated") ||
    normalized.includes("submitted") ||
    normalized.includes("accepted") ||
    normalized.includes("verified") ||
    normalized.includes("saved")
  ) {
    return "success";
  }
  return "info";
}

function GawaGoToastHost({ toasts, onDismiss }) {
  return (
    <div className="gawago-toast-viewport" aria-live="polite" aria-atomic="true">
      {toasts.map((toast) => (
        <div
          className={`gawago-toast gawago-toast-${toast.variant}`}
          key={toast.id}
          role={toast.variant === "danger" ? "alert" : "status"}
        >
          <div className="gawago-toast-icon" aria-hidden="true" />
          <p>{toast.message}</p>
          <button
            type="button"
            className="gawago-toast-close"
            aria-label="Dismiss notification"
            onClick={() => onDismiss(toast.id)}
          />
        </div>
      ))}
    </div>
  );
}

const EMPTY_CERTIFICATION_FORM = {
  name: "",
  certificateType: "",
  issuer: "",
  issueDate: "",
  expiryDate: "",
  certificateImage: null,
  certificatePreview: "",
};

function App() {
  if (IS_DEMO_MODE) {
    ensureDemoVersion();
  }
  const isAdminPortalPath =
    typeof window !== "undefined" && window.location.pathname.replace(/\/+$/, "") === "/admin";
  const [view, setView] = useState(isAdminPortalPath ? "login" : "home");
  useEffect(() => {
    window.scrollTo(0, 0);
  }, [view]);
  const [loginForm, setLoginForm] = useState({
    username: "",
    password: "",
    role: isAdminPortalPath ? "admin" : "",
  });
  const [loginError, setLoginError] = useState("");
  const [forgotPasswordStep, setForgotPasswordStep] = useState("email");
  const [forgotPasswordForm, setForgotPasswordForm] = useState({
    email: "",
    token: "",
    newPassword: "",
    confirmPassword: "",
  });
  const [forgotPasswordNotice, setForgotPasswordNotice] = useState("");
  const [forgotPasswordError, setForgotPasswordError] = useState("");
  const [forgotPasswordLoading, setForgotPasswordLoading] = useState(false);
  const [appToasts, setAppToasts] = useState([]);
  const [currentUser, setCurrentUser] = useState(null);
  const [registeredWorkers, setRegisteredWorkers] = useState(() =>
    IS_DEMO_MODE ? mergeDemoRecords(getStoredCollection(STORAGE_KEYS.workers, []), DEMO_WORKER_ACCOUNTS) : [],
  );
  const [registeredHouseholds, setRegisteredHouseholds] = useState(() =>
    IS_DEMO_MODE ? mergeDemoRecords(getStoredCollection(STORAGE_KEYS.households, []), DEMO_HOUSEHOLD_ACCOUNTS) : [],
  );
  const [verificationRequests, setVerificationRequests] = useState(() =>
    IS_DEMO_MODE
      ? mergeDemoRecords(getStoredCollection(STORAGE_KEYS.verificationRequests, []), DEMO_VERIFICATION_REQUESTS, "id")
      : [],
  );
  const [postedJobs, setPostedJobs] = useState(() =>
    IS_DEMO_MODE
      ? mergeDemoRecords(
          getStoredCollection(STORAGE_KEYS.jobs, []).map(normalizeJobRecord),
          createDemoJobPostings(),
          "id",
        )
      : [],
  );
  const [backendNotifications, setBackendNotifications] = useState([]);
  const [selectedVerificationRequestId, setSelectedVerificationRequestId] = useState(null);
  const [adminSection, setAdminSection] = useState("verification");
  const [superAdminSection, setSuperAdminSection] = useState("dashboard");
  const [heatMapMetric, setHeatMapMetric] = useState("jobs");
  // Kept per tab so a reload of a job detail or matches screen shows the
  // same job: the URL hash only carries the view, and without this the page
  // fell back to whichever job happened to be first.
  const [selectedJobId, setSelectedJobId] = useState(() => {
    try {
      return window.sessionStorage.getItem(SELECTED_JOB_STORAGE_KEY) || null;
    } catch (error) {
      return null;
    }
  });
  // The recommended-workers screen ranks by the AI score by default; Smart
  // Matching's rule order (AGENTS.md I.B) is one tap away. Each job starts
  // on the AI ranking again.
  const [householdMatchRank, setHouseholdMatchRank] = useState("ai");
  useEffect(() => {
    setHouseholdMatchRank("ai");
  }, [selectedJobId]);
  useEffect(() => {
    try {
      if (selectedJobId === null || selectedJobId === undefined || selectedJobId === "") {
        window.sessionStorage.removeItem(SELECTED_JOB_STORAGE_KEY);
      } else {
        window.sessionStorage.setItem(SELECTED_JOB_STORAGE_KEY, String(selectedJobId));
      }
    } catch (error) {
      // Storage can be unavailable (private mode); the page still works.
    }
  }, [selectedJobId]);
  // A sign-out forgets the selection so the next account in this tab starts
  // fresh. Only a signed-in -> signed-out change counts: currentUser is also
  // null at mount, before the session is restored.
  const previousUserRef = useRef(currentUser);
  useEffect(() => {
    if (previousUserRef.current && !currentUser) {
      setSelectedJobId(null);
    }
    previousUserRef.current = currentUser;
  }, [currentUser]);
  const [selectedWorkerId, setSelectedWorkerId] = useState(null);
  const [notificationReads, setNotificationReads] = useState(() => getNotificationReadState());
  const [workerForm, setWorkerForm] = useState(EMPTY_WORKER_FORM);
  const [householdForm, setHouseholdForm] = useState(EMPTY_HOUSEHOLD_FORM);
  // Per-field errors for the worker/household registration forms.
  const [registerErrors, setRegisterErrors] = useState({});
  const [householdProfileForm, setHouseholdProfileForm] = useState({
    firstName: "",
    lastName: "",
    username: "",
    email: "",
    phone: "",
    barangay: "",
    streetAddress: "",
    profilePhotoFile: null,
    profilePhotoName: "",
    profilePhotoPreview: "",
  });
  const [householdJobForm, setHouseholdJobForm] = useState({
    jobTitle: "",
    serviceType: "",
    customServiceType: "",
    scheduleType: "One-Time",
    description: "",
    barangay: "",
    streetAddress: "",
    offeredRate: "0.00",
    rateType: "Per Day",
    workersNeeded: "1",
    jobStartDate: "",
    jobEndDate: "",
    estimatedWorkingDays: "",
    geographicBoundary: "1km",
  });
  const [householdJobImages, setHouseholdJobImages] = useState([]);
  const [workerProfileForm, setWorkerProfileForm] = useState({
    firstName: "",
    lastName: "",
    username: "",
    email: "",
    phone: "",
    barangay: "",
    streetAddress: "",
    latitude: null,
    longitude: null,
    locationLabel: "",
    locationSource: "",
    locationWarning: "",
    locationAccuracy: "",
    bio: "",
    hourlyRate: "0.00",
    dailyRate: "0.00",
    yearsExperience: "0",
    skills: [],
    availability: true,
    availabilityWindows: [],
    profilePhotoFile: null,
    profilePhotoPreview: "",
    certifications: [],
    workSamples: [],
  });
  const [showCertificationModal, setShowCertificationModal] = useState(false);
  const [showWorkSampleModal, setShowWorkSampleModal] = useState(false);
  const [showSkillModal, setShowSkillModal] = useState(false);
  const [certificationForm, setCertificationForm] = useState({ ...EMPTY_CERTIFICATION_FORM });
  const [workSampleForm, setWorkSampleForm] = useState({
    title: "",
    beforeImage: null,
    beforePreview: "",
    afterImage: null,
    afterPreview: "",
  });
  const [editingCertificationIndex, setEditingCertificationIndex] = useState(null);
  const [editingWorkSampleIndex, setEditingWorkSampleIndex] = useState(null);
  const [viewingWorkSampleIndex, setViewingWorkSampleIndex] = useState(null);
  const [portfolioGalleryOpen, setPortfolioGalleryOpen] = useState(false);
  const [employmentHistory, setEmploymentHistory] = useState([]);
  const [portfolioRefreshKey, setPortfolioRefreshKey] = useState(0);
  const [verificationForm, setVerificationForm] = useState({
    primaryIdType: "",
    // Only used when primaryIdType is "other"; otherwise the backend labels
    // the request from the chosen type.
    primaryIdOtherName: "",
    primaryIdName: "",
    primaryIdFile: null,
    secondaryDocName: "",
    secondaryDocFile: null,
    notes: "",
    primaryIdPreview: "",
    secondaryDocPreview: "",
  });
  const [householdReviewForm, setHouseholdReviewForm] = useState(EMPTY_HOUSEHOLD_REVIEW_FORM);
  const [workerFeedbackForm, setWorkerFeedbackForm] = useState(EMPTY_WORKER_FEEDBACK_FORM);
  const [adminLoginForm, setAdminLoginForm] = useState({
    username: "",
    password: "",
  });
  const [matchedWorkersByJob, setMatchedWorkersByJob] = useState({});
  const [householdJobCoordinates, setHouseholdJobCoordinates] = useState(null);
  const [householdJobLocationPreview, setHouseholdJobLocationPreview] = useState(null);
  const [householdJobMapMode, setHouseholdJobMapMode] = useState("preview");
  const householdJobMapRef = useRef(null);
  const householdJobMapViewRef = useRef({
    center: [PHILIPPINES_MAP_CENTER.latitude, PHILIPPINES_MAP_CENTER.longitude],
    zoom: 6,
    touched: false,
  });
  const householdJobBarangaySyncRef = useRef(0);
  const dismissToast = (toastId) => {
    setAppToasts((prev) => prev.filter((toast) => toast.id !== toastId));
  };
  const { handleForgotPasswordChange, handleForgotPasswordEmailSubmit, handleResetPassword, handleVerifyResetToken } =
    usePasswordReset({
      forgotPasswordForm,
      setForgotPasswordError,
      setForgotPasswordForm,
      setForgotPasswordLoading,
      setForgotPasswordNotice,
      setForgotPasswordStep,
    });
  useEffect(() => {
    if (typeof window === "undefined") {
      return undefined;
    }
    const originalAlert = window.alert;
    window.alert = (message = "") => {
      const text = String(message || "").trim();
      if (!text) {
        return;
      }
      const toastId = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      setAppToasts((prev) => [
        ...prev.slice(-3),
        {
          id: toastId,
          message: text,
          variant: getToastVariant(text),
        },
      ]);
      window.setTimeout(() => {
        setAppToasts((prev) => prev.filter((toast) => toast.id !== toastId));
      }, 5200);
    };
    return () => {
      window.alert = originalAlert;
    };
  }, []);
  useEffect(() => {
    if (!IS_DEMO_MODE) {
      return;
    }
    setRegisteredWorkers((prev) => mergeDemoRecords(prev, DEMO_WORKER_ACCOUNTS));
    setRegisteredHouseholds((prev) => mergeDemoRecords(prev, DEMO_HOUSEHOLD_ACCOUNTS));
    setVerificationRequests((prev) => mergeDemoRecords(prev, DEMO_VERIFICATION_REQUESTS, "id"));
    setPostedJobs((prev) => mergeDemoRecords(prev.map(normalizeJobRecord), createDemoJobPostings(), "id"));
  }, []);
  const backendCurrentWorker = normalizeBackendWorker(currentUser);
  const localCurrentWorker = registeredWorkers.find((item) => item.username === currentUser?.username) || null;
  const currentWorkerRequestFromProfile = normalizeVerificationRequest(currentUser?.profile?.verification_request);
  const currentWorkerVerificationRequest =
    verificationRequests.find((item) => item.workerUsername === currentUser?.username) ||
    currentWorkerRequestFromProfile ||
    localCurrentWorker?.verificationSubmission ||
    backendCurrentWorker?.verificationSubmission ||
    null;
  const currentWorkerVerificationLabel = currentWorkerVerificationRequest?.status
    ? getWorkerVerificationLabel(currentWorkerVerificationRequest.status)
    : getWorkerVerificationLabel(
        currentUser?.profile?.verification_status ||
          backendCurrentWorker?.verification ||
          localCurrentWorker?.verification,
      );
  const currentWorkerBase =
    currentUser?.role === "worker"
      ? backendCurrentWorker
        ? {
            ...localCurrentWorker,
            ...backendCurrentWorker,
            verificationNotifications: [
              ...(localCurrentWorker?.verificationNotifications || []),
              ...(backendCurrentWorker?.verificationNotifications || []),
            ],
            applicationNotifications: [
              ...(localCurrentWorker?.applicationNotifications || []),
              ...(backendCurrentWorker?.applicationNotifications || []),
            ],
            receivedReviews:
              localCurrentWorker?.receivedReviews?.length
                ? localCurrentWorker.receivedReviews
                : backendCurrentWorker.receivedReviews || [],
            givenFeedback:
              localCurrentWorker?.givenFeedback?.length
                ? localCurrentWorker.givenFeedback
                : backendCurrentWorker.givenFeedback || [],
          }
        : localCurrentWorker || null
      : null;
  const currentWorker = currentWorkerBase
    ? {
        ...currentWorkerBase,
        verification: currentWorkerVerificationLabel,
        verificationSubmission: currentWorkerVerificationRequest,
      }
    : null;
  const localCurrentHousehold = registeredHouseholds.find((item) => item.username === currentUser?.username) || null;
  const currentHouseholdVerificationRequest =
    verificationRequests.find((item) => item.workerUsername === currentUser?.username) ||
    normalizeVerificationRequest(currentUser?.profile?.verification_request) ||
    localCurrentHousehold?.verificationSubmission ||
    null;
  const currentHousehold = localCurrentHousehold
    ? {
        ...localCurrentHousehold,
        verification: currentHouseholdVerificationRequest
          ? getWorkerVerificationLabel(currentHouseholdVerificationRequest.status)
          : currentUser?.profile?.verification_status === "verified"
            ? "Verified"
            : currentUser?.profile?.verification_status === "rejected"
              ? "Rejected"
              : "Not Yet Verified",
        verificationSubmission: currentHouseholdVerificationRequest,
      }
    : null;
  const householdJobs = postedJobs.filter((item) => item.householdUsername === currentUser?.username);
  const selectedJob =
    householdJobs.find((item) => String(item.id) === String(selectedJobId)) ||
    householdJobs[0] ||
    postedJobs[0] ||
    null;
  const selectedMatchedWorkers = selectedJob
    ? matchedWorkersByJob[selectedJob.id] || buildMatchedWorkersForJob(selectedJob, registeredWorkers)
    : [];
  const selectedJobApplications = selectedJob?.applications || [];
  const selectedWorkerIdentity =
    selectedWorkerId && typeof selectedWorkerId === "object" ? selectedWorkerId : null;
  const normalizeLookupValue = (value) => String(value ?? "").trim().toLowerCase();
  const valuesMatch = (selectedValues, candidateValues) => {
    const normalizedSelectedValues = selectedValues.map(normalizeLookupValue).filter(Boolean);
    const normalizedCandidateValues = candidateValues.map(normalizeLookupValue).filter(Boolean);
    return normalizedSelectedValues.some((value) => normalizedCandidateValues.includes(value));
  };
  const selectedIdentityUsernameValues = selectedWorkerIdentity
    ? [selectedWorkerIdentity.username, selectedWorkerIdentity.workerUsername]
    : [];
  const selectedIdentityIdValues = selectedWorkerIdentity
    ? [
        selectedWorkerIdentity.id,
        selectedWorkerIdentity.workerId,
        selectedWorkerIdentity.userId,
        selectedWorkerIdentity.user_id,
      ]
    : [];
  const selectedIdentityProfileValues = selectedWorkerIdentity ? [selectedWorkerIdentity.profileId] : [];
  const selectedIdentityNameValues = selectedWorkerIdentity
    ? [selectedWorkerIdentity.displayName, selectedWorkerIdentity.workerName]
    : [];
  const selectedWorkerToken = selectedWorkerIdentity ? "" : normalizeLookupValue(selectedWorkerId);
  const workerMatchesSelectedToken = (worker) => {
    if (!worker) {
      return false;
    }
    if (selectedWorkerIdentity) {
      const workerUsernameValues = [worker.username, worker.workerUsername];
      if (
        selectedIdentityUsernameValues.some((value) => normalizeLookupValue(value)) &&
        workerUsernameValues.some((value) => normalizeLookupValue(value))
      ) {
        return valuesMatch(selectedIdentityUsernameValues, workerUsernameValues);
      }
      const workerNameValues = [
        worker.displayName,
        worker.workerName,
        getDisplayName(worker.firstName, worker.lastName, worker.username),
      ];
      if (
        selectedIdentityNameValues.some((value) => normalizeLookupValue(value)) &&
        workerNameValues.some((value) => normalizeLookupValue(value)) &&
        !valuesMatch(selectedIdentityNameValues, workerNameValues)
      ) {
        return false;
      }
      const workerIdValues = [worker.id, worker.workerId, worker.userId, worker.user_id];
      if (valuesMatch(selectedIdentityIdValues, workerIdValues)) {
        return true;
      }
      if (valuesMatch(selectedIdentityProfileValues, [worker.profileId])) {
        return true;
      }
      const hasSpecificIdentity =
        selectedIdentityUsernameValues.some((value) => normalizeLookupValue(value)) ||
        selectedIdentityIdValues.some((value) => normalizeLookupValue(value)) ||
        selectedIdentityProfileValues.some((value) => normalizeLookupValue(value));
      if (hasSpecificIdentity) {
        return false;
      }
      return valuesMatch(selectedIdentityNameValues, workerNameValues);
    }
    if (!selectedWorkerToken) {
      return false;
    }
    return [
      worker.id,
      worker.workerId,
      worker.userId,
      worker.user_id,
      worker.profileId,
      worker.username,
      worker.workerUsername,
      getDisplayName(worker.firstName, worker.lastName, worker.username),
    ]
      .filter((value) => value !== null && value !== undefined && value !== "")
      .some((value) => String(value).trim().toLowerCase() === selectedWorkerToken);
  };
  const applicationMatchesSelectedToken = (application) => {
    if (!application) {
      return false;
    }
    if (selectedWorkerIdentity) {
      const applicationUsernameValues = [application.workerUsername];
      if (
        selectedIdentityUsernameValues.some((value) => normalizeLookupValue(value)) &&
        applicationUsernameValues.some((value) => normalizeLookupValue(value))
      ) {
        return valuesMatch(selectedIdentityUsernameValues, applicationUsernameValues);
      }
      if (
        selectedIdentityNameValues.some((value) => normalizeLookupValue(value)) &&
        application.workerName &&
        !valuesMatch(selectedIdentityNameValues, [application.workerName])
      ) {
        return false;
      }
      if (valuesMatch(selectedIdentityIdValues, [application.workerId, application.worker_id])) {
        return true;
      }
      const hasSpecificIdentity =
        selectedIdentityUsernameValues.some((value) => normalizeLookupValue(value)) ||
        selectedIdentityIdValues.some((value) => normalizeLookupValue(value));
      if (hasSpecificIdentity) {
        return false;
      }
      return valuesMatch(selectedIdentityNameValues, [application.workerName]);
    }
    if (!selectedWorkerToken) {
      return false;
    }
    return [application.workerId, application.worker_id, application.workerUsername, application.workerName]
      .filter((value) => value !== null && value !== undefined && value !== "")
      .some((value) => String(value).trim().toLowerCase() === selectedWorkerToken);
  };
  const selectedWorkerApplication =
    selectedJobApplications.find((application) => applicationMatchesSelectedToken(application)) || null;
  const matchedSelectedWorker =
    selectedMatchedWorkers.find((worker) => workerMatchesSelectedToken(worker)) ||
    selectedMatchedWorkers.find(
      (worker) =>
        selectedWorkerApplication &&
        (worker.username === selectedWorkerApplication.workerUsername ||
          worker.workerUsername === selectedWorkerApplication.workerUsername ||
          getDisplayName(worker.firstName, worker.lastName, worker.username) === selectedWorkerApplication.workerName ||
          String(worker.id) === String(selectedWorkerApplication.workerId) ||
          String(worker.workerId) === String(selectedWorkerApplication.workerId)),
    ) ||
    null;
  const registeredSelectedWorker =
    registeredWorkers.find((worker) => workerMatchesSelectedToken(worker)) ||
    registeredWorkers.find(
      (worker) =>
        selectedWorkerApplication &&
        (worker.username === selectedWorkerApplication.workerUsername ||
          worker.workerUsername === selectedWorkerApplication.workerUsername ||
          getDisplayName(worker.firstName, worker.lastName, worker.username) === selectedWorkerApplication.workerName ||
          String(worker.id) === String(selectedWorkerApplication.workerId) ||
          String(worker.workerId) === String(selectedWorkerApplication.workerId)),
    ) ||
    null;
  const selectedWorkerRecord = matchedSelectedWorker
    ? {
        ...registeredSelectedWorker,
        ...matchedSelectedWorker,
      }
    : registeredSelectedWorker || buildWorkerFallbackFromJob(selectedJob, selectedWorkerIdentity || selectedWorkerId);
  const selectedWorker = selectedWorkerRecord
    ? {
        ...selectedWorkerRecord,
        // Pin and route come only from this job's application, which the API
        // fills in once the worker is hired for it -- never from elsewhere.
        latitude: selectedWorkerApplication?.workerLatitude ?? null,
        longitude: selectedWorkerApplication?.workerLongitude ?? null,
        distanceKm: selectedWorkerApplication?.routeDistanceKm ?? selectedWorkerRecord.distanceKm ?? null,
        distanceLabel: selectedWorkerApplication?.distanceLabel || selectedWorkerRecord.distanceLabel || "",
        routePoints: selectedWorkerApplication?.routePoints || [],
      }
    : null;
  const selectedWorkerPhoto = getWorkerPhoto(selectedWorker);
  const selectedVerificationRequest =
    verificationRequests.find((item) => item.id === selectedVerificationRequestId) || verificationRequests[0] || null;
  const workerVisibleJobs = getWorkerJobMatches(currentWorker, postedJobs);
  const workerMatchedJobs = workerVisibleJobs.filter((job) => job.matchesSkill);
  const workerMiniPhoto = getWorkerPhoto(currentWorker);
  const householdNotifications = dedupeNotifications([
    ...backendNotifications.filter(
      (item) =>
        item.notificationType === "application" ||
        item.notificationType === "completion" ||
        item.notificationType === "verification" ||
        // Report status changes and account block/restore notices. Households
        // read this list through an allowlist, so without this entry they
        // never saw these updates at all.
        item.notificationType === "account_activity" ||
        // Feedback received from a worker (reviews/views.py TYPE_REVIEW).
        item.notificationType === "review" ||
        // A worker accepting or rejecting a household's hire request
        // (jobs/views.py TYPE_ACCEPTED / TYPE_REJECTION go to the household).
        // Without these the household never learns the worker responded.
        item.notificationType === "accepted" ||
        item.notificationType === "rejection" ||
        // One per completed worker, with its own read state -- the same
        // reminders the mobile app shows.
        item.notificationType === "review_reminder",
    ),
    // Offline demo only: with a backend these duplicated the real
    // notifications, announced an "application" for workers the household
    // had invited, and reminded about the first worker of a job only.
    ...(IS_DEMO_MODE
      ? [
          ...getHouseholdNotifications(householdJobs, registeredWorkers),
          ...getHouseholdReviewReminderNotifications(householdJobs, registeredWorkers, currentHousehold),
        ]
      : []),
  ]);
  const verificationNotifications = getVerificationNotifications(verificationRequests, registeredWorkers);
  const workerNotifications = dedupeNotifications([
    ...backendNotifications.filter((item) => item.notificationType !== "application"),
    ...(currentWorker?.verificationNotifications || []),
    ...(currentWorker?.applicationNotifications || []),
  ]);
  const householdNotificationsWithReadState = householdNotifications.map((item) => ({
    ...item,
    unread: item.unread !== false && !notificationReads[item.id],
  }));
  const workerNotificationsWithReadState = workerNotifications.map((item) => ({
    ...item,
    unread: item.unread !== false && !notificationReads[item.id],
  }));
  const workerApplications = currentWorker
    ? postedJobs.flatMap((job) =>
        (job.applications || [])
          .filter(
            (application) =>
              String(application.workerId) === String(currentWorker.id) ||
              application.workerUsername === currentWorker.username,
          )
          .map((application) => ({
            ...job,
            appliedAt: application.appliedAt,
            updatedAt: application.updatedAt,
            applicationStatus: application.status,
            applicationStatusLabel: application.statusLabel || "",
            applicationId: application.id,
          })),
      )
    : [];
  const selectedWorkerJob =
    selectedJobId == null ? null : postedJobs.find((item) => String(item.id) === String(selectedJobId));
  const selectedWorkerApplicationJob =
    selectedJobId == null ? null : workerApplications.find((item) => String(item.id) === String(selectedJobId));
  const selectedWorkerVisibleJob =
    selectedJobId == null ? null : workerVisibleJobs.find((item) => String(item.id) === String(selectedJobId));
  const currentWorkerJobDetail =
    selectedWorkerApplicationJob ||
    (selectedWorkerVisibleJob && selectedWorkerJob
      ? {
          ...selectedWorkerVisibleJob,
          applications: selectedWorkerJob.applications || [],
        }
      : null) ||
    selectedWorkerJob ||
    workerVisibleJobs[0] ||
    null;
  const currentWorkerJobHousehold = currentWorkerJobDetail
    ? registeredHouseholds.find((item) => item.username === currentWorkerJobDetail.householdUsername)
    : null;
  useEffect(() => {
    if (view !== "worker-job-detail" || currentUser?.role !== "worker" || !selectedJobId || !getAuthToken()) {
      return;
    }
    let cancelled = false;
    async function refreshSelectedWorkerJob() {
      try {
        const response = await apiRequest(`jobs/${selectedJobId}/`, {
          auth: true,
          suppressUnauthorized: true,
        });
        const data = await readResponseData(response);
        if (!response.ok || cancelled) {
          return;
        }
        const normalizedJob = normalizeBackendJob(data);
        if (!normalizedJob) {
          return;
        }
        setPostedJobs((prev) =>
          prev.map((job) =>
            String(job.id) === String(normalizedJob.id) ? normalizedJob : job,
          ),
        );
      } catch (error) {
        return;
      }
    }
    refreshSelectedWorkerJob();
    return () => {
      cancelled = true;
    };
  }, [currentUser?.role, selectedJobId, view]);
  const lastPopulatedWorkerRef = useRef(null);
  useEffect(() => {
    if (!currentWorker || currentWorker.username === lastPopulatedWorkerRef.current) {
      return;
    }
    lastPopulatedWorkerRef.current = currentWorker.username;
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
      locationSource: "",
      locationWarning: "",
      locationAccuracy: "",
      bio: currentWorker.bio || "",
      hourlyRate: currentWorker.hourlyRate || "0.00",
      dailyRate: currentWorker.dailyRate || "0.00",
      yearsExperience: currentWorker.yearsExperience || "0",
      skills: currentWorker.skills || [],
      availability: true,
      availabilityWindows: currentWorker.availabilityWindows || [],
      profilePhotoFile: null,
      profilePhotoPreview: currentWorker.profilePhotoPreview || "",
    });
  }, [currentWorker?.username]);

  useEffect(() => {
    if (!currentWorker || currentUser?.role !== "worker" || !getAuthToken()) {
      setEmploymentHistory([]);
      return;
    }
    const loadEmploymentHistory = async () => {
      try {
        // Paginated: this used to call .map() on the {count, next, results}
        // envelope, throw, and swallow the error, so the section was always
        // empty.
        const history = await fetchWorkerEmploymentHistory(currentWorker.id);
        if (history) {
          setEmploymentHistory(history);
        }
      } catch (error) {
        console.error("Error fetching employment history:", error);
      }
    };
    loadEmploymentHistory();
  }, [currentWorker?.id, currentUser?.role]);

  useEffect(() => {
    if (!currentWorker || currentUser?.role !== "worker" || !getAuthToken()) {
      return;
    }
    const loadPortfolio = async () => {
      try {
        const portfolio = await fetchMyPortfolio();
        if (!portfolio) return;
        setWorkerProfileForm((prev) => ({
          ...prev,
          portfolioSkills: portfolio.portfolioSkills,
          certifications: portfolio.certifications,
          workSamples: portfolio.workSamples,
        }));
      } catch (error) {
        console.error("Error fetching portfolio:", error);
      }
    };
    loadPortfolio();
    // Saving the profile's skills creates or unlists portfolio entries on
    // the backend, so a skill-list change reloads them too.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentWorker?.id, currentUser?.role, portfolioRefreshKey, (currentWorker?.skills || []).join("|")]);
  const handleSetSkillProficiency = async (skillId, proficiency) => {
    try {
      await updatePortfolioSkillProficiency(skillId, proficiency);
      setWorkerProfileForm((prev) => ({
        ...prev,
        portfolioSkills: (prev.portfolioSkills || []).map((skill) =>
          skill.id === skillId ? { ...skill, proficiency } : skill,
        ),
      }));
    } catch (error) {
      addToast(error.message || "Unable to update this skill.", "danger");
    }
  };
  // Saves the worker's skill list on its own. The Add Skills dialog used to
  // only change the form, so "Done" looked final but nothing was stored until
  // the separate "Save Changes" button. Throws with the server's message so
  // the caller can keep its draft open.
  const handleSaveWorkerSkills = async (skills) => {
    const response = await apiRequest("accounts/me/", {
      method: "PATCH",
      auth: true,
      body: { skills },
    });
    const data = await readResponseData(response);
    if (!response.ok) {
      throw new Error(getApiErrorMessage(data, "Unable to save your skills."));
    }
    const savedSkills = Array.isArray(data?.profile?.skills) ? data.profile.skills : skills;
    setWorkerProfileForm((prev) => ({ ...prev, skills: savedSkills }));
    setRegisteredWorkers((prev) =>
      prev.map((item) => (item.username === currentUser?.username ? { ...item, skills: savedSkills } : item)),
    );
    setCurrentUser((prev) => (prev?.profile ? { ...prev, profile: { ...prev.profile, skills: savedSkills } } : prev));
    return savedSkills;
  };
  const adminVisibleWorkers = registeredWorkers.filter((worker) => Boolean(worker.verificationSubmission));
  const pendingVerificationRequests = verificationRequests.filter(
    (item) => item.status === "Pending" || item.status === "Under Review",
  );
  const approvedVerificationRequests = verificationRequests.filter((item) => item.status === "Approved");
  const rejectedVerificationRequests = verificationRequests.filter((item) => item.status === "Rejected");
  const householdUnreadCount = householdNotificationsWithReadState.filter((item) => item.unread).length;
  const workerUnreadCount = workerNotificationsWithReadState.filter((item) => item.unread).length;
  const workerApplicationUnreadCount = workerApplications.filter((job) => {
    const notificationId = `worker-application-${job.applicationId}`;
    return ["Hired", "Rejected"].includes(job.applicationStatus) && !notificationReads[notificationId];
  }).length;
  const {
    mergeBackendWorkerIntoState,
    refreshVerificationStateFromBackend,
    refreshJobsFromBackend,
    refreshProfilesFromBackend,
    refreshRecommendedWorkers,
    refreshNotificationsFromBackend,
    refreshReviewsFromBackend,
    recommendedWorkersLoading,
  } = useBackendSync({
    currentUser,
    registeredWorkers,
    selectedWorker,
    setBackendNotifications,
    setCurrentUser,
    setMatchedWorkersByJob,
    setPostedJobs,
    setRegisteredHouseholds,
    setRegisteredWorkers,
    setSelectedJobId,
    setSelectedVerificationRequestId,
    setSelectedWorkerId,
    setVerificationRequests,
    setView,
  });
  // Reloading the page used to show the logged-out home screen while the
  // stored token stayed in localStorage and kept going out with the
  // background polling -- so the session was still live even though the UI
  // said otherwise. Rebuild it from the token, or clear the token.
  const sessionRestoredRef = useRef(false);
  // True only while a stored token is being exchanged for an account. The
  // role guard and the URL router both wait on it: until the session is
  // known, "not signed in" and "not signed in yet" look identical, and
  // acting on the first would bounce a deep link to login.
  const [sessionRestoring, setSessionRestoring] = useState(
    () => !IS_DEMO_MODE && Boolean(getAuthToken()),
  );
  // Runs once on mount only: this deliberately takes no dependencies, so a
  // re-render cannot cancel the request half-way and leave the session
  // unrestored. currentUser is always null at mount.
  useEffect(() => {
    if (sessionRestoredRef.current || IS_DEMO_MODE) {
      return;
    }
    sessionRestoredRef.current = true;
    if (!getAuthToken()) {
      setSessionRestoring(false);
      return;
    }
    (async () => {
      try {
      const account = await fetchMyAccount();
      if (!account) {
        clearAuthToken();
        return;
      }
      // /accounts/me/ answers { role, user: {...}, profile: {...} }. Reading
      // it as one flat object left username, name, skills, rating and
      // verification empty after every reload, so a refreshed worker looked
      // unverified with no matching jobs and a household saw no jobs at all.
      const accountUser = account.user || {};
      const accountProfile = account.profile || null;
      const role = getUserRole({ role: account.role });
      if (!role) {
        clearAuthToken();
        return;
      }
      const username = accountUser.username || accountProfile?.username || "";
      const displayName = getDisplayName(accountUser.first_name, accountUser.last_name, username);
      setCurrentUser({
        id: accountUser.id || accountProfile?.user_id || username,
        role,
        username,
        email: accountUser.email || "",
        first_name: accountUser.first_name || "",
        last_name: accountUser.last_name || "",
        displayName,
        profile: accountProfile,
        is_staff: isAdminRole(role),
        isSuperAdmin: role === ROLES.SUPERADMIN,
      });
      if (!isAdminRole(role)) {
        const backendWorker = normalizeBackendWorkerPayload({
          user: {
            id: accountUser.id,
            username,
            email: accountUser.email || "",
            first_name: accountUser.first_name || "",
            last_name: accountUser.last_name || "",
            display_name: displayName,
            is_staff: false,
          },
          profile: accountProfile,
        });
        if (backendWorker) {
          mergeBackendWorkerIntoState(backendWorker);
        }
      }
      setView((current) => (current === "home" || current === "login" ? dashboardViewForRole(role) : current));
      } catch (error) {
        // A failed restore must not leave a token the UI believes is gone.
        clearAuthToken();
        console.error("Unable to restore the previous session:", error);
      } finally {
        setSessionRestoring(false);
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const dashboardMetrics = useDashboardMetrics({
    currentUser,
    postedJobs,
    registeredHouseholds,
    registeredWorkers,
    verificationRequests,
  });
  useBackendPolling({
    currentUser,
    currentWorkerVerificationLabel,
    currentWorkerVerificationRequest,
    refreshJobsFromBackend,
    refreshNotificationsFromBackend,
    refreshProfilesFromBackend,
    refreshRecommendedWorkers,
    refreshReviewsFromBackend,
    refreshVerificationStateFromBackend,
    registeredWorkers,
    selectedJob,
    selectedWorker,
    setBackendNotifications,
    setCurrentUser,
    view,
    householdMatchRank,
  });
  useGawaGoPersistence({
    isDemoMode: IS_DEMO_MODE,
    notificationReads,
    postedJobs,
    registeredHouseholds,
    registeredWorkers,
    verificationRequests,
  });
  // Keeps the URL in step with `view` so Back stays inside the app and every
  // screen is linkable. Waits on the session for the same reason the guard
  // below does.
  useViewRouting({
    view,
    setView,
    sessionRestoring,
    fallbackView: isAdminPortalPath ? "login" : "home",
  });
  // Role guard: a view that isn't the current user's (e.g. an admin on a
  // worker screen) is replaced by that user's own dashboard, or login when
  // signed out / the role is unknown. Nothing role-specific renders meanwhile.
  // Suppressed while the session is being restored, when currentUser is still
  // null for everyone.
  const guardedView = sessionRestoring ? null : resolveGuardedView(currentUser, view);
  useEffect(() => {
    if (guardedView) {
      setView(guardedView);
    }
  }, [guardedView]);
  const {
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
  } = useGawaGoNavigation({
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
  });
  const { captureHouseholdJobLocation, placeHouseholdJobPin, syncHouseholdJobBarangayLocation } =
    useHouseholdJobLocation({
      buildCoordinateLocation,
      buildMapPreviewUrl,
      formatCoordinateAddress,
      formatLocation,
      getBarangayCenter,
      getFallbackBarangay,
      getNearestBarangayFromCoordinates,
      householdJobBarangaySyncRef,
      householdJobForm,
      householdJobMapViewRef,
      reverseGeocodeCoordinates,
      setHouseholdJobCoordinates,
      setHouseholdJobForm,
      setHouseholdJobLocationPreview,
      setHouseholdJobMapMode,
    });
  // Post a Job opens with the household's saved barangay filled in; frame the
  // map on it (with a pin to move) instead of on the whole city, where a pin
  // dropped "in the middle" landed in a different barangay.
  useEffect(() => {
    if (view === "household-post-job" && !householdJobLocationPreview && householdJobForm.barangay) {
      syncHouseholdJobBarangayLocation(householdJobForm.barangay, { keepStreetAddress: true });
    }
    // Only on arriving at the screen: later barangay changes sync themselves.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [view]);
  const {
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
    handleConfirmJobCompleted,
    handleHouseholdReviewSubmit,
    handleWorkerFeedbackSubmit,
    handleWorkerFeedbackForReviewSubmit,
    handleWorkerRateHousehold,
    handleUpdateJob,
    handleHouseholdJobSubmit,
    handleAdminApproveVerification,
    handleAdminRejectVerification,
    isSubmittingJob,
    isActionPending,
  } = useGawaGoActions({
    EMPTY_HOUSEHOLD_FORM,
    EMPTY_HOUSEHOLD_REVIEW_FORM,
    EMPTY_WORKER_FEEDBACK_FORM,
    EMPTY_WORKER_FORM,
    apiRequest,
    clearAuthToken,
    createJobRecord,
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
    normalizeReview,
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
    setLoginForm,
    setPostedJobs,
    setRegisterErrors,
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
  });
  const {
    handleHouseholdChange,
    handleHouseholdJobChange,
    handleHouseholdProfileChange,
    handleLoginChange,
    handleVerificationChange,
    handleWorkerChange,
    handleWorkerProfileChange,
    toggleSkill,
    toggleWorkerProfileSkill,
  } = useGawaGoFormHandlers({
    householdJobForm,
    setHouseholdForm,
    setHouseholdJobCoordinates,
    setHouseholdJobForm,
    setHouseholdJobLocationPreview,
    setHouseholdProfileForm,
    setLoginError,
    setLoginForm,
    setRegisterErrors,
    setVerificationForm,
    setWorkerForm,
    setWorkerProfileForm,
    syncHouseholdJobBarangayLocation,
  });
  useGawaGoDomEffects({
    clearAuthToken,
    currentHousehold,
    currentUser,
    getSavedHouseholdLocation,
    householdJobs,
    selectedJobId,
    selectedVerificationRequestId,
    setCurrentUser,
    setHouseholdJobForm,
    setLoginError,
    setLoginForm,
    setSelectedJobId,
    setSelectedVerificationRequestId,
    setSelectedWorkerId,
    setUnauthorizedHandler,
    setView,
    verificationRequests,
    view,
  });
  // An explicit variant wins; the message is only guessed from when none is
  // given (e.g. alert() replacements), so a "Unable to ..." success never
  // shows red and a deliberate warning is never overridden.
  const addToast = (message, variant) => {
    const toastId = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    setAppToasts((prev) => [
      ...prev.slice(-3),
      {
        id: toastId,
        message,
        variant: variant || getToastVariant(message) || "info",
      },
    ]);
    window.setTimeout(() => {
      setAppToasts((prev) => prev.filter((toast) => toast.id !== toastId));
    }, 5200);
  };

  // Certificate and work-sample uploads can take a while (multipart, 90s
  // timeout); a second click meanwhile used to create a duplicate entry,
  // and a duplicate certificate needs its own admin review.
  const portfolioSaveInFlightRef = useRef(false);
  const [portfolioSaving, setPortfolioSaving] = useState(false);
  const beginPortfolioSave = () => {
    if (portfolioSaveInFlightRef.current) return false;
    portfolioSaveInFlightRef.current = true;
    setPortfolioSaving(true);
    return true;
  };
  const endPortfolioSave = () => {
    portfolioSaveInFlightRef.current = false;
    setPortfolioSaving(false);
  };
  const handleAddCertification = async () => {
    if (!certificationForm.certificateType) {
      addToast("Please choose the certificate type", "warning");
      return;
    }
    if (!certificationForm.name.trim()) {
      addToast("Please enter certification name", "warning");
      return;
    }
    if (
      certificationForm.issueDate &&
      certificationForm.expiryDate &&
      certificationForm.expiryDate < certificationForm.issueDate
    ) {
      addToast("The expiry date can't be before the issue date", "warning");
      return;
    }
    if (!certificationForm.certificateImage && !certificationForm.certificatePreview) {
      addToast("Please upload a certificate image", "warning");
      return;
    }
    if (!getAuthToken() || !beginPortfolioSave()) return;
    try {

      const formData = new FormData();
      formData.append("certificate_name", certificationForm.name);
      formData.append("certificate_type", certificationForm.certificateType);
      formData.append("issuer", certificationForm.issuer || "");
      // Blank dates are left off rather than sent empty, which a date field rejects.
      if (certificationForm.issueDate) formData.append("issue_date", certificationForm.issueDate);
      if (certificationForm.expiryDate) formData.append("expiry_date", certificationForm.expiryDate);
      if (certificationForm.certificateImage) {
        formData.append("certificate_file", certificationForm.certificateImage);
      }

      // Editing an existing credential has to PATCH it; posting again just
      // created a second copy.
      const editingId =
        editingCertificationIndex !== null
          ? workerProfileForm.certifications?.[editingCertificationIndex]?.id
          : null;
      const response = await apiRequest(
        editingId
          ? `accounts/me/portfolio/certifications/${editingId}/`
          : "accounts/me/portfolio/certifications/",
        {
          method: editingId ? "PATCH" : "POST",
          auth: true,
          body: formData,
        },
      );

      if (!response.ok) {
        const data = await response.json().catch(() => ({}));
        throw new Error(data.detail || "Failed to save certification");
      }

      setCertificationForm({ ...EMPTY_CERTIFICATION_FORM });
      setEditingCertificationIndex(null);
      setShowCertificationModal(false);
      setPortfolioRefreshKey((key) => key + 1);
      addToast("Certification saved", "success");
    } catch (error) {
      addToast(`Error: ${error.message}`, "danger");
    } finally {
      endPortfolioSave();
    }
  };
  const handleAddWorkSample = async () => {
    if (!workSampleForm.title.trim()) {
      addToast("Please enter work sample title", "warning");
      return;
    }
    if (!workSampleForm.beforePreview || !workSampleForm.afterPreview) {
      addToast("Please upload both before and after images", "warning");
      return;
    }
    if (!getAuthToken() || !beginPortfolioSave()) return;
    try {

      const formData = new FormData();
      formData.append("title", workSampleForm.title);
      formData.append("description", "");
      if (workSampleForm.beforeImage) {
        formData.append("before_image", workSampleForm.beforeImage);
        formData.append("image", workSampleForm.beforeImage);
      }
      if (workSampleForm.afterImage) {
        formData.append("after_image", workSampleForm.afterImage);
      }

      const editingId =
        editingWorkSampleIndex !== null
          ? workerProfileForm.workSamples?.[editingWorkSampleIndex]?.id
          : null;
      const response = await apiRequest(
        editingId ? `accounts/me/portfolio/items/${editingId}/` : "accounts/me/portfolio/items/",
        {
          method: editingId ? "PATCH" : "POST",
          auth: true,
          body: formData,
        },
      );

      if (!response.ok) {
        const data = await response.json().catch(() => ({}));
        throw new Error(data.detail || "Failed to save work sample");
      }

      setWorkSampleForm({ title: "", beforeImage: null, beforePreview: "", afterImage: null, afterPreview: "" });
      setEditingWorkSampleIndex(null);
      setShowWorkSampleModal(false);
      setPortfolioRefreshKey((key) => key + 1);
      addToast("Work sample saved", "success");
    } catch (error) {
      addToast(`Error: ${error.message}`, "danger");
    } finally {
      endPortfolioSave();
    }
  };
  // These used to drop the row from local state only -- and call an
  // undefined showToast(), so the click threw before even doing that. The
  // credential has to be removed on the server or it comes back on reload.
  const handleDeleteCertification = async (index) => {
    const certification = workerProfileForm.certifications?.[index];
    if (!certification) return;
    try {
      if (certification.id) {
        await deletePortfolioCertification(certification.id);
      }
      setWorkerProfileForm((prev) => ({
        ...prev,
        certifications: (prev.certifications || []).filter((_, i) => i !== index),
      }));
      addToast("Certification deleted", "success");
    } catch (error) {
      addToast(`Error: ${error.message}`, "danger");
    }
  };
  const handleDeleteWorkSample = async (index) => {
    const sample = workerProfileForm.workSamples?.[index];
    if (!sample) return;
    try {
      if (sample.id) {
        await deletePortfolioItem(sample.id);
      }
      setWorkerProfileForm((prev) => ({
        ...prev,
        workSamples: (prev.workSamples || []).filter((_, i) => i !== index),
      }));
      addToast("Work sample deleted", "success");
    } catch (error) {
      addToast(`Error: ${error.message}`, "danger");
    }
  };
  const handleEditCertification = (index) => {
    setEditingCertificationIndex(index);
    setCertificationForm(workerProfileForm.certifications[index]);
    setShowCertificationModal(true);
  };
  const handleEditWorkSample = (index) => {
    setEditingWorkSampleIndex(index);
    setWorkSampleForm(workerProfileForm.workSamples[index]);
    setShowWorkSampleModal(true);
  };
  const handleOpenCertificationModal = () => {
    setEditingCertificationIndex(null);
    setCertificationForm({ ...EMPTY_CERTIFICATION_FORM });
    setShowCertificationModal(true);
  };
  const handleOpenWorkSampleModal = () => {
    setEditingWorkSampleIndex(null);
    setWorkSampleForm({ title: "", beforeImage: null, beforePreview: "", afterImage: null, afterPreview: "" });
    setShowWorkSampleModal(true);
  };
  const renderWithToasts = (content) => (
    <>
      <GawaGoToastHost toasts={appToasts} onDismiss={dismissToast} />
      {content}
      <ChatWidget currentUser={currentUser} />
    </>
  );
  if (guardedView) {
    return renderWithToasts(<ViewLoading />);
  }
  if (view === "worker-job-detail") {
    return renderWithToasts(
      <Suspense fallback={<ViewLoading />}>
        <WorkerJobDetailView
          currentUser={currentUser}
          currentWorker={currentWorker}
          currentWorkerJobDetail={currentWorkerJobDetail}
          currentWorkerJobHousehold={currentWorkerJobHousehold}
          handleApplyToJob={handleApplyToJob}
          handleLogout={handleLogout}
          handleWorkerHireDecision={handleWorkerHireDecision}
          handleWorkerRequestCompletion={handleWorkerRequestCompletion}
          openWorkerApplications={openWorkerApplications}
          openWorkerDashboard={openWorkerDashboard}
          openWorkerFindJobs={openWorkerFindJobs}
          openWorkerGetVerified={openWorkerGetVerified}
          openWorkerMyJobs={openWorkerMyJobs}
          openMyComplaints={openMyComplaints}
          openWorkerNotifications={openWorkerNotifications}
          openWorkerProfile={openWorkerProfile}
          workerApplicationUnreadCount={workerApplicationUnreadCount}
          workerMiniPhoto={workerMiniPhoto}
          addToast={addToast}
        />
      </Suspense>
    );
  }
  if (view === "superadmin-dashboard") {
    return renderWithToasts(
      <Suspense fallback={<ViewLoading />}>
        <SuperAdminDashboardView
          currentUser={currentUser}
          dashboardMetrics={dashboardMetrics}
          handleAdminApproveVerification={handleAdminApproveVerification}
          handleAdminRejectVerification={handleAdminRejectVerification}
          handleLogout={handleLogout}
          heatMapMetric={heatMapMetric}
          openFilePreview={openFilePreview}
          openVerificationRequest={openVerificationRequest}
          pendingVerificationRequests={pendingVerificationRequests}
          postedJobs={postedJobs}
          refreshProfilesFromBackend={refreshProfilesFromBackend}
          registeredHouseholds={registeredHouseholds}
          registeredWorkers={registeredWorkers}
          rejectedVerificationRequests={rejectedVerificationRequests}
          selectedVerificationRequest={selectedVerificationRequest}
          setHeatMapMetric={setHeatMapMetric}
          setSuperAdminSection={setSuperAdminSection}
          superAdminSection={superAdminSection}
          verificationRequests={verificationRequests}
        />
      </Suspense>
    );
  }
  if (view === "forgot-password") {
    return renderWithToasts(
      <Suspense fallback={<ViewLoading />}>
        <ForgotPasswordView
          form={forgotPasswordForm}
          step={forgotPasswordStep}
          notice={forgotPasswordNotice}
          error={forgotPasswordError}
          loading={forgotPasswordLoading}
          onChange={handleForgotPasswordChange}
          onEmailSubmit={handleForgotPasswordEmailSubmit}
          onVerifyToken={handleVerifyResetToken}
          onResetPassword={handleResetPassword}
          onOpenLogin={openLogin}
          onOpenForgotPassword={openForgotPassword}
        />
      </Suspense>
    );
  }
  if (view === "my-reports") {
    return renderWithToasts(
      <Suspense fallback={<ViewLoading />}>
        <MyComplaintsView
          currentUser={currentUser}
          currentHousehold={currentHousehold}
          currentWorker={currentWorker}
          handleLogout={handleLogout}
          openHouseholdDashboard={openHouseholdDashboard}
          openHouseholdPostJob={openHouseholdPostJob}
          openHouseholdMyJobs={openHouseholdMyJobs}
          openHouseholdProfile={openHouseholdProfile}
          openHouseholdGetVerified={openHouseholdGetVerified}
          openHouseholdNotifications={openHouseholdNotifications}
          openWorkerDashboard={openWorkerDashboard}
          openWorkerFindJobs={openWorkerFindJobs}
          openWorkerProfile={openWorkerProfile}
          openWorkerApplications={openWorkerApplications}
          openWorkerMyJobs={openWorkerMyJobs}
          openWorkerGetVerified={openWorkerGetVerified}
          openWorkerNotifications={openWorkerNotifications}
          workerApplicationUnreadCount={workerApplicationUnreadCount}
        />
      </Suspense>
    );
  }
  return renderWithToasts(
    <Suspense fallback={<ViewLoading />}>
      <AppViews
      SKILLS={SKILLS}
      adminSection={adminSection}
      adminVisibleWorkers={adminVisibleWorkers}
      approvedVerificationRequests={approvedVerificationRequests}
      buildMatchedWorkersForJob={buildMatchedWorkersForJob}
      currentHousehold={currentHousehold}
      currentUser={currentUser}
      currentWorker={currentWorker}
      dashboardMetrics={dashboardMetrics}
      isAdminPortalPath={isAdminPortalPath}
      formatCurrency={formatCurrency}
      formatDateTime={formatDateTime}
      formatDistance={formatDistance}
      formatLocation={formatLocation}
      formatRate={formatRate}
      formatScheduleLabel={formatScheduleLabel}
      getDisplayName={getDisplayName}
      getJobStatusBadgeClass={getJobStatusBadgeClass}
      goBack={goBack}
      handleAdminApproveVerification={handleAdminApproveVerification}
      handleAdminRejectVerification={handleAdminRejectVerification}
      handleApplyToJob={handleApplyToJob}
      handleCancelJob={handleCancelJob}
      handleConfirmJobCompleted={handleConfirmJobCompleted}
      handleHireWorker={handleHireWorker}
      handleWorkerRequestCompletion={handleWorkerRequestCompletion}
      handleHouseholdChange={handleHouseholdChange}
      handleHouseholdJobChange={handleHouseholdJobChange}
      handleHouseholdJobSubmit={handleHouseholdJobSubmit}
      isSubmittingJob={isSubmittingJob}
      isActionPending={isActionPending}
      portfolioSaving={portfolioSaving}
      handleSetSkillProficiency={handleSetSkillProficiency}
      householdMatchRank={householdMatchRank}
      setHouseholdMatchRank={setHouseholdMatchRank}
      recommendedWorkersLoading={recommendedWorkersLoading}
      handleHouseholdProfileChange={handleHouseholdProfileChange}
      handleHouseholdProfileSave={handleHouseholdProfileSave}
      handleHouseholdRegisterSubmit={handleHouseholdRegisterSubmit}
      handleHouseholdReviewSubmit={handleHouseholdReviewSubmit}
      handleLoginChange={handleLoginChange}
      handleLoginSubmit={handleLoginSubmit}
      handleLogout={handleLogout}
      handleRejectApplication={handleRejectApplication}
      handleVerificationChange={handleVerificationChange}
      handleVerificationSubmit={handleVerificationSubmit}
      handleWorkerChange={handleWorkerChange}
      handleWorkerProfileChange={handleWorkerProfileChange}
      handleWorkerProfileSave={handleWorkerProfileSave}
      handleWorkerFeedbackForReviewSubmit={handleWorkerFeedbackForReviewSubmit}
      handleWorkerRateHousehold={handleWorkerRateHousehold}
      handleUpdateJob={handleUpdateJob}
      handleWorkerRegisterSubmit={handleWorkerRegisterSubmit}
      householdForm={householdForm}
      registerErrors={registerErrors}
      householdJobCoordinates={householdJobCoordinates}
      householdJobForm={householdJobForm}
      householdJobImages={{ files: householdJobImages, onChange: setHouseholdJobImages }}
      householdJobLocationPreview={householdJobLocationPreview}
      householdJobMapMode={householdJobMapMode}
      householdJobMapRef={householdJobMapRef}
      householdJobMapViewRef={householdJobMapViewRef}
      householdJobs={householdJobs}
      householdNotificationsWithReadState={householdNotificationsWithReadState}
      householdProfileForm={householdProfileForm}
      householdReviewForm={householdReviewForm}
      householdUnreadCount={householdUnreadCount}
      loginError={loginError}
      loginForm={loginForm}
      markAllNotificationsRead={markAllNotificationsRead}
      markNotificationRead={markNotificationRead}
      openAdminDashboard={openAdminDashboard}
      openAdminWorkersHistory={openAdminWorkersHistory}
      openFilePreview={openFilePreview}
      openForgotPassword={openForgotPassword}
      openHouseholdDashboard={openHouseholdDashboard}
      openHouseholdFeedbackAll={openHouseholdFeedbackAll}
      openHouseholdGetVerified={openHouseholdGetVerified}
      openHouseholdJobMatches={openHouseholdJobMatches}
      openHouseholdMyJobs={openHouseholdMyJobs}
      openMyComplaints={openMyComplaints}
      addToast={addToast}
      openHouseholdNotifications={openHouseholdNotifications}
      openHouseholdPostJob={openHouseholdPostJob}
      openHouseholdProfile={openHouseholdProfile}
      openHouseholdRegister={openHouseholdRegister}
      openHouseholdReviewsAll={openHouseholdReviewsAll}
      openLogin={openLogin}
      openMatchedWorkerProfile={openMatchedWorkerProfile}
      openVerificationRequest={openVerificationRequest}
      openWorkerApplications={openWorkerApplications}
      openWorkerDashboard={openWorkerDashboard}
      openWorkerFindJobs={openWorkerFindJobs}
      openWorkerGetVerified={openWorkerGetVerified}
      openWorkerJobDetail={openWorkerJobDetail}
      openWorkerMyJobs={openWorkerMyJobs}
      openWorkerNotifications={openWorkerNotifications}
      openWorkerProfile={openWorkerProfile}
      openWorkerRegister={openWorkerRegister}
      pendingVerificationRequests={pendingVerificationRequests}
      registeredHouseholds={registeredHouseholds}
      registeredWorkers={registeredWorkers}
      rejectedVerificationRequests={rejectedVerificationRequests}
      renderBarangayOptions={renderBarangayOptions}
      captureHouseholdJobLocation={captureHouseholdJobLocation}
      loadLeafletAssets={loadLeafletAssets}
      placeHouseholdJobPin={placeHouseholdJobPin}
      selectedJob={selectedJob}
      selectedMatchedWorkers={selectedMatchedWorkers}
      selectedVerificationRequest={selectedVerificationRequest}
      selectedVerificationRequestId={selectedVerificationRequestId}
      selectedWorker={selectedWorker}
      selectedWorkerPhoto={selectedWorkerPhoto}
      setHouseholdReviewForm={setHouseholdReviewForm}
      setHouseholdJobMapMode={setHouseholdJobMapMode}
      setSelectedJobId={setSelectedJobId}
      setSelectedWorkerId={setSelectedWorkerId}
      setWorkerForm={setWorkerForm}
      setWorkerProfileForm={setWorkerProfileForm}
      toggleSkill={toggleSkill}
      toggleWorkerProfileSkill={toggleWorkerProfileSkill}
      handleSaveWorkerSkills={handleSaveWorkerSkills}
      showCertificationModal={showCertificationModal}
      setShowCertificationModal={setShowCertificationModal}
      showSkillModal={showSkillModal}
      setShowSkillModal={setShowSkillModal}
      showWorkSampleModal={showWorkSampleModal}
      setShowWorkSampleModal={setShowWorkSampleModal}
      certificationForm={certificationForm}
      setCertificationForm={setCertificationForm}
      workSampleForm={workSampleForm}
      setWorkSampleForm={setWorkSampleForm}
      handleAddCertification={handleAddCertification}
      handleAddWorkSample={handleAddWorkSample}
      handleDeleteCertification={handleDeleteCertification}
      handleDeleteWorkSample={handleDeleteWorkSample}
      handleEditCertification={handleEditCertification}
      handleEditWorkSample={handleEditWorkSample}
      handleOpenCertificationModal={handleOpenCertificationModal}
      handleOpenWorkSampleModal={handleOpenWorkSampleModal}
      editingCertificationIndex={editingCertificationIndex}
      editingWorkSampleIndex={editingWorkSampleIndex}
      viewingWorkSampleIndex={viewingWorkSampleIndex}
      setViewingWorkSampleIndex={setViewingWorkSampleIndex}
      portfolioGalleryOpen={portfolioGalleryOpen}
      setPortfolioGalleryOpen={setPortfolioGalleryOpen}
      employmentHistory={employmentHistory}
      verificationForm={verificationForm}
      verificationRequests={verificationRequests}
      view={view}
      workerApplicationUnreadCount={workerApplicationUnreadCount}
      workerApplications={workerApplications}
      workerForm={workerForm}
      workerMatchedJobs={workerMatchedJobs}
      workerMiniPhoto={workerMiniPhoto}
      workerNotificationsWithReadState={workerNotificationsWithReadState}
      workerProfileForm={workerProfileForm}
      workerUnreadCount={workerUnreadCount}
      workerVisibleJobs={workerVisibleJobs}
      />
    </Suspense>
  );
}
export default App;
