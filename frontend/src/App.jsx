import React, { lazy, Suspense, useEffect, useMemo, useRef, useState } from "react";
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
  getHouseholdPhoto,
  getWorkerPhoto,
  sanitizePhilippinesPhone,
} from "./utils/formatters";
import { getBarangayCenter, getFallbackBarangay } from "./utils/locationUtils";
import {
  buildCoordinateLocation,
  buildMapPreviewUrl,
  buildTayabasLatLngBounds,
  formatCoordinateAddress,
  getNearestBarangayFromCoordinates,
  getSavedHouseholdLocation,
  haversineDistanceKm,
  isValidGmailAddress,
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
  getStoredObject,
  mergeDemoRecords,
} from "./utils/storageUtils";
import { readResponseData } from "./utils/apiUtils";
import { loadLeafletAssets } from "./utils/mapAssets";
import { renderBarangayOptions } from "./utils/formOptions";
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
import FloatingChatWidget from "./components/FloatingChatWidget";
import ComplaintModal from "./components/ComplaintModal";

const AppViews = lazy(() => import("./components/AppViews"));
const ForgotPasswordView = lazy(() => import("./components/ForgotPasswordView"));
const SuperAdminDashboardView = lazy(() => import("./components/SuperAdminDashboardView"));
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

const CHAT_ENABLED_APPLICATION_STATUSES = new Set(["Hire Request", "Hired", "Completed"]);

function formatChatTimestamp(value = new Date()) {
  const parsedValue = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(parsedValue.getTime())) {
    return "Recently";
  }
  return parsedValue.toLocaleString("en-PH", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

function createChatConversationId(jobId, workerKey) {
  return `chat-${jobId}-${workerKey}`;
}

function App() {
  if (IS_DEMO_MODE) {
    ensureDemoVersion();
  }
  const isAdminPortalPath =
    typeof window !== "undefined" && window.location.pathname.replace(/\/+$/, "") === "/admin";
  const [view, setView] = useState(isAdminPortalPath ? "login" : "home");
  const [loginForm, setLoginForm] = useState({
    username: "",
    password: "",
    role: isAdminPortalPath ? "admin" : "",
  });
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
  const [chatMessagesByConversation, setChatMessagesByConversation] = useState(() =>
    IS_DEMO_MODE ? getStoredObject(STORAGE_KEYS.chatMessages, {}) : {},
  );
  const [activeChatConversationId, setActiveChatConversationId] = useState(null);
  const [backendNotifications, setBackendNotifications] = useState([]);
  const [selectedVerificationRequestId, setSelectedVerificationRequestId] = useState(null);
  const [adminSection, setAdminSection] = useState("verification");
  const [superAdminSection, setSuperAdminSection] = useState("verification");
  const [heatMapMetric, setHeatMapMetric] = useState("jobs");
  const [selectedJobId, setSelectedJobId] = useState(null);
  const [selectedWorkerId, setSelectedWorkerId] = useState(null);
  const [notificationReads, setNotificationReads] = useState(() => getNotificationReadState());
  const [workerForm, setWorkerForm] = useState(EMPTY_WORKER_FORM);
  const [householdForm, setHouseholdForm] = useState(EMPTY_HOUSEHOLD_FORM);
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
    preferredDate: "",
    preferredTime: "",
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
  const [certificationForm, setCertificationForm] = useState({
    name: "",
    certificateImage: null,
    certificatePreview: "",
  });
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
  const [ratingModalOpen, setRatingModalOpen] = useState(false);
  const [ratingJobId, setRatingJobId] = useState(null);
  const [ratingWorker, setRatingWorker] = useState(null);
  const [skillRatings, setSkillRatings] = useState({});
  const [showComplaintModal, setShowComplaintModal] = useState(false);
  const [complaintForm, setComplaintForm] = useState({
    complaint_type: "",
    description: "",
    job: null,
  });
  const [verificationForm, setVerificationForm] = useState({
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
        latitude: selectedWorkerApplication?.workerLatitude ?? selectedWorkerRecord.latitude ?? null,
        longitude: selectedWorkerApplication?.workerLongitude ?? selectedWorkerRecord.longitude ?? null,
        distanceKm: selectedWorkerApplication?.routeDistanceKm ?? selectedWorkerRecord.distanceKm ?? null,
        routePoints: selectedWorkerApplication?.routePoints || selectedWorkerRecord.routePoints || [],
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
        item.title === "New feedback received",
    ),
    ...getHouseholdNotifications(householdJobs, registeredWorkers),
    ...getHouseholdReviewReminderNotifications(householdJobs, registeredWorkers, currentHousehold),
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
  const availableChatConversations = useMemo(() => {
    if (!currentUser?.role) {
      return [];
    }

    const conversations = postedJobs.flatMap((job) =>
      (job.applications || [])
        .filter((application) => CHAT_ENABLED_APPLICATION_STATUSES.has(application.status))
        .map((application) => {
          const registeredWorker =
            registeredWorkers.find(
              (worker) =>
                String(worker.id) === String(application.workerId) ||
                (worker.username && worker.username === application.workerUsername),
            ) || null;
          const registeredHousehold =
            registeredHouseholds.find((household) => household.username === job.householdUsername) || null;
          const workerName = getDisplayName(
            registeredWorker?.firstName,
            registeredWorker?.lastName,
            application.workerName || application.workerUsername || "Worker",
          );
          const householdName = getDisplayName(
            registeredHousehold?.firstName,
            registeredHousehold?.lastName,
            job.householdName || job.householdUsername || "Household",
          );
          const workerKey = application.workerId || application.workerUsername || workerName;
          const conversationId = createChatConversationId(job.id, workerKey);
          const isHouseholdParticipant = currentUser.role === "household" && job.householdUsername === currentUser.username;
          const isWorkerParticipant =
            currentUser.role === "worker" &&
            (String(application.workerId) === String(currentWorker?.id) ||
              (application.workerUsername && application.workerUsername === currentWorker?.username));

          if (!isHouseholdParticipant && !isWorkerParticipant) {
            return null;
          }

          return {
            id: conversationId,
            jobId: job.id,
            applicationId: application.id,
            jobTitle: job.jobTitle || job.serviceType || "Service Request",
            statusLabel: application.status,
            rateLabel: formatRate(job.offeredRate, job.rateType),
            otherPartyName: isHouseholdParticipant ? workerName : householdName,
            otherPartyPhoto: isHouseholdParticipant ? getWorkerPhoto(registeredWorker) : getHouseholdPhoto(registeredHousehold),
            currentUserRole: currentUser.role,
            householdUsername: job.householdUsername,
            householdName,
            workerUsername: application.workerUsername || registeredWorker?.username || "",
            workerName,
            otherPartyRole: isHouseholdParticipant ? "worker" : "household",
            otherPartyProfile: isHouseholdParticipant
              ? {
                  bio: registeredWorker?.bio || "No background provided yet.",
                  location: formatLocation(registeredWorker?.barangay, registeredWorker?.streetAddress),
                  verification: registeredWorker?.verification || "Not Yet Verified",
                  skills: registeredWorker?.skills || [],
                  rate: formatRate(registeredWorker?.dailyRate || job.offeredRate, "Per Day"),
                  phone: registeredWorker?.phone ? `+63${registeredWorker.phone}` : "",
                  email: registeredWorker?.email || "",
                }
              : {
                  bio: "Household account connected to this hiring request.",
                  location: formatLocation(registeredHousehold?.barangay, registeredHousehold?.streetAddress),
                  verification: registeredHousehold?.verification || "Verified Household",
                  skills: [],
                  rate: formatRate(job.offeredRate, job.rateType),
                  phone: registeredHousehold?.phone ? `+63${registeredHousehold.phone}` : "",
                  email: registeredHousehold?.email || "",
                },
          };
        })
        .filter(Boolean),
    );

    return conversations.sort((left, right) => {
      const leftMessages = chatMessagesByConversation[left.id] || [];
      const rightMessages = chatMessagesByConversation[right.id] || [];
      const leftLast = leftMessages[leftMessages.length - 1]?.createdAt || "";
      const rightLast = rightMessages[rightMessages.length - 1]?.createdAt || "";
      return String(rightLast).localeCompare(String(leftLast));
    });
  }, [chatMessagesByConversation, currentUser?.role, currentUser?.username, currentWorker?.id, currentWorker?.username, postedJobs, registeredHouseholds, registeredWorkers, formatRate]);
  const activeChatConversation =
    availableChatConversations.find((conversation) => String(conversation.id) === String(activeChatConversationId)) ||
    availableChatConversations[0] ||
    null;
  const chatMessagesForWidget = useMemo(
    () =>
      Object.fromEntries(
        Object.entries(chatMessagesByConversation).map(([conversationId, messages]) => [
          conversationId,
          (messages || []).map((message) => ({
            ...message,
            isCurrentUser:
              message.senderRole !== "system" &&
              ((currentUser?.role === "household" && message.senderUsername === currentHousehold?.username) ||
                (currentUser?.role === "worker" && message.senderUsername === currentWorker?.username)),
          })),
        ]),
      ),
    [chatMessagesByConversation, currentHousehold?.username, currentUser?.role, currentWorker?.username],
  );
  useEffect(() => {
    if (!availableChatConversations.length) {
      setActiveChatConversationId(null);
      return;
    }
    if (!activeChatConversationId || !availableChatConversations.some((conversation) => conversation.id === activeChatConversationId)) {
      setActiveChatConversationId(availableChatConversations[0].id);
    }
  }, [activeChatConversationId, availableChatConversations]);
  useEffect(() => {
    if (!availableChatConversations.length) {
      return;
    }
    setChatMessagesByConversation((prev) => {
      let changed = false;
      const nextState = { ...prev };
      availableChatConversations.forEach((conversation) => {
        if (nextState[conversation.id]?.length) {
          return;
        }
        changed = true;
        nextState[conversation.id] = [
          {
            id: `${conversation.id}-system`,
            senderRole: "system",
            senderLabel: "System",
            text: `Chat opened for ${conversation.jobTitle}. Messaging is available because a hire request now exists between the household and worker.`,
            imageUrl: "",
            imageName: "",
            isCurrentUser: false,
            createdAt: new Date().toISOString(),
            createdAtLabel: formatChatTimestamp(),
          },
        ];
      });
      return changed ? nextState : prev;
    });
  }, [availableChatConversations]);
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
    const fetchEmploymentHistory = async () => {
      try {
        const response = await apiRequest(`jobs/?worker=${currentWorker.id}&status=completed`, {
          auth: true,
        });
        if (response.ok) {
          const jobs = await response.json();
          const historyData = jobs.map((job) => ({
            id: job.id,
            title: job.job_title || job.title,
            household_name: job.household_name,
            location: job.location,
            completed_at: job.completed_at,
            skill_ratings: job.skill_ratings || [],
          }));
          setEmploymentHistory(historyData);
        }
      } catch (error) {
        console.log("Error fetching employment history:", error);
      }
    };
    fetchEmploymentHistory();
  }, [currentWorker?.id, currentUser?.role]);
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
  });
  useGawaGoPersistence({
    chatMessages: chatMessagesByConversation,
    isDemoMode: IS_DEMO_MODE,
    notificationReads,
    postedJobs,
    registeredHouseholds,
    registeredWorkers,
    verificationRequests,
  });
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
      resolveLocationCoordinates,
      reverseGeocodeCoordinates,
      setHouseholdJobCoordinates,
      setHouseholdJobForm,
      setHouseholdJobLocationPreview,
      setHouseholdJobMapMode,
    });
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
    handleHouseholdJobSubmit,
    handleAdminApproveVerification,
    handleAdminRejectVerification,
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
    isValidGmailAddress,
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
    setHouseholdForm,
    setHouseholdJobCoordinates,
    setHouseholdJobForm,
    setHouseholdJobLocationPreview,
    setHouseholdProfileForm,
    setLoginForm,
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
    setLoginForm,
    setSelectedJobId,
    setSelectedVerificationRequestId,
    setSelectedWorkerId,
    setUnauthorizedHandler,
    setView,
    verificationRequests,
    view,
  });
  const addToast = (message, variant = "info") => {
    const toastId = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    setAppToasts((prev) => [
      ...prev.slice(-3),
      {
        id: toastId,
        message,
        variant: getToastVariant(message) || variant,
      },
    ]);
    window.setTimeout(() => {
      setAppToasts((prev) => prev.filter((toast) => toast.id !== toastId));
    }, 5200);
  };

  const openRatingModal = (job, worker) => {
    setRatingJobId(job.id);
    setRatingWorker(worker);
    setSkillRatings({});
    setRatingModalOpen(true);
  };

  const handleSubmitRatings = async () => {
    if (!ratingJobId || !ratingWorker) return;

    const ratedSkills = Object.keys(skillRatings).filter(skill => skillRatings[skill]);
    if (ratedSkills.length === 0) {
      addToast("Please rate at least one skill", "warning");
      return;
    }

    try {
      if (!getAuthToken()) return;

      for (const skillId of ratedSkills) {
        const response = await apiRequest("jobs/skill-ratings/", {
          method: "POST",
          auth: true,
          body: {
            job: ratingJobId,
            worker: ratingWorker.id,
            skill: skillId,
            rating: skillRatings[skillId],
          },
        });

        if (!response.ok) {
          throw new Error("Failed to submit rating");
        }
      }

      addToast("Ratings submitted successfully", "success");
      setRatingModalOpen(false);
      setRatingJobId(null);
      setRatingWorker(null);
      setSkillRatings({});
    } catch (error) {
      addToast(`Error submitting ratings: ${error.message}`, "danger");
    }
  };

  const handleSubmitComplaint = async () => {
    if (!complaintForm.complaint_type.trim()) {
      addToast("Please select a complaint type", "warning");
      return;
    }
    if (!complaintForm.description.trim()) {
      addToast("Please describe the issue", "warning");
      return;
    }

    try {
      if (!getAuthToken()) return;

      const payload = {
        complaint_type: complaintForm.complaint_type,
        description: complaintForm.description,
      };
      if (complaintForm.job) {
        payload.job = complaintForm.job;
      }

      const response = await apiRequest("complaints/create/", {
        method: "POST",
        auth: true,
        body: payload,
      });

      if (!response.ok) {
        throw new Error("Failed to submit complaint");
      }

      addToast("Complaint submitted successfully. We will review it shortly.", "success");
      setShowComplaintModal(false);
      setComplaintForm({ complaint_type: "", description: "", job: null });
    } catch (error) {
      addToast(`Error submitting complaint: ${error.message}`, "danger");
    }
  };

  const handleAddCertification = async () => {
    if (!certificationForm.name.trim()) {
      addToast("Please enter certification name", "warning");
      return;
    }
    if (!certificationForm.certificateImage && !certificationForm.certificatePreview) {
      addToast("Please upload a certificate image", "warning");
      return;
    }
    try {
      if (!getAuthToken()) return;

      const formData = new FormData();
      formData.append("certificate_name", certificationForm.name);
      if (certificationForm.certificateImage) {
        formData.append("certificate_file", certificationForm.certificateImage);
      }

      const response = await apiRequest("accounts/me/portfolio/certifications/", {
        method: "POST",
        auth: true,
        body: formData,
      });

      if (!response.ok) {
        const data = await response.json().catch(() => ({}));
        throw new Error(data.detail || "Failed to save certification");
      }

      const updatedCertifications = [...(workerProfileForm.certifications || [])];
      updatedCertifications.push({ name: certificationForm.name, certificatePreview: certificationForm.certificatePreview });
      setWorkerProfileForm((prev) => ({ ...prev, certifications: updatedCertifications }));
      setCertificationForm({ name: "", certificateImage: null, certificatePreview: "" });
      setEditingCertificationIndex(null);
      setShowCertificationModal(false);
      addToast("Certification saved", "success");
    } catch (error) {
      addToast(`Error: ${error.message}`, "danger");
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
    try {
      if (!getAuthToken()) return;

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

      const response = await apiRequest("accounts/me/portfolio/items/", {
        method: "POST",
        auth: true,
        body: formData,
      });

      if (!response.ok) {
        const data = await response.json().catch(() => ({}));
        throw new Error(data.detail || "Failed to save work sample");
      }

      const updatedSamples = [...(workerProfileForm.workSamples || [])];
      updatedSamples.push({
        title: workSampleForm.title,
        beforePreview: workSampleForm.beforePreview,
        afterPreview: workSampleForm.afterPreview
      });
      setWorkerProfileForm((prev) => ({ ...prev, workSamples: updatedSamples }));
      setWorkSampleForm({ title: "", beforeImage: null, beforePreview: "", afterImage: null, afterPreview: "" });
      setEditingWorkSampleIndex(null);
      setShowWorkSampleModal(false);
      addToast("Work sample saved", "success");
    } catch (error) {
      addToast(`Error: ${error.message}`, "danger");
    }
  };
  const handleDeleteCertification = (index) => {
    const updatedCertifications = workerProfileForm.certifications.filter((_, i) => i !== index);
    setWorkerProfileForm((prev) => ({ ...prev, certifications: updatedCertifications }));
    showToast("Certification deleted", "success");
  };
  const handleDeleteWorkSample = (index) => {
    const updatedSamples = workerProfileForm.workSamples.filter((_, i) => i !== index);
    setWorkerProfileForm((prev) => ({ ...prev, workSamples: updatedSamples }));
    showToast("Work sample deleted", "success");
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
    setCertificationForm({ name: "", certificateImage: null, certificatePreview: "" });
    setShowCertificationModal(true);
  };
  const handleOpenWorkSampleModal = () => {
    setEditingWorkSampleIndex(null);
    setWorkSampleForm({ title: "", beforeImage: null, beforePreview: "", afterImage: null, afterPreview: "" });
    setShowWorkSampleModal(true);
  };
  const handleSendChatMessage = (conversationId, payload) => {
    const text = String(payload?.text || "").trim();
    const imageUrl = String(payload?.imageUrl || "");
    const imageName = String(payload?.imageName || "");
    if (!conversationId || (!text && !imageUrl) || !currentUser?.role) {
      return;
    }
    const senderDisplayName =
      currentUser.role === "household"
        ? getDisplayName(currentHousehold?.firstName, currentHousehold?.lastName, currentHousehold?.username)
        : getDisplayName(currentWorker?.firstName, currentWorker?.lastName, currentWorker?.username);
    const message = {
      id: `${conversationId}-${Date.now()}`,
      senderRole: currentUser.role,
      senderUsername: currentUser.username,
      senderLabel: senderDisplayName,
      text,
      imageUrl,
      imageName,
      createdAt: new Date().toISOString(),
      createdAtLabel: formatChatTimestamp(),
    };
    setChatMessagesByConversation((prev) => ({
      ...prev,
      [conversationId]: [...(prev[conversationId] || []), message],
    }));
  };
  const renderWithToasts = (content) => (
    <>
      <GawaGoToastHost toasts={appToasts} onDismiss={dismissToast} />
      {content}
      <FloatingChatWidget
        conversations={availableChatConversations}
        currentConversationId={activeChatConversation?.id || null}
        messagesByConversation={chatMessagesForWidget}
        onSelectConversation={setActiveChatConversationId}
        onSendMessage={handleSendChatMessage}
      />
    </>
  );
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
          openWorkerNotifications={openWorkerNotifications}
          openWorkerProfile={openWorkerProfile}
          workerApplicationUnreadCount={workerApplicationUnreadCount}
          workerMiniPhoto={workerMiniPhoto}
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
      handleWorkerRegisterSubmit={handleWorkerRegisterSubmit}
      householdForm={householdForm}
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
      openHouseholdJobDetail={openHouseholdJobDetail}
      openHouseholdMyJobs={openHouseholdMyJobs}
      openHouseholdNotificationWorker={openHouseholdNotificationWorker}
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
      showCertificationModal={showCertificationModal}
      setShowCertificationModal={setShowCertificationModal}
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
      ratingModalOpen={ratingModalOpen}
      setRatingModalOpen={setRatingModalOpen}
      ratingJobId={ratingJobId}
      ratingWorker={ratingWorker}
      skillRatings={skillRatings}
      setSkillRatings={setSkillRatings}
      openRatingModal={openRatingModal}
      handleSubmitRatings={handleSubmitRatings}
      showComplaintModal={showComplaintModal}
      setShowComplaintModal={setShowComplaintModal}
      complaintForm={complaintForm}
      setComplaintForm={setComplaintForm}
      handleSubmitComplaint={handleSubmitComplaint}
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
