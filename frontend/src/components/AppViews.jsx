import React, { useEffect, useMemo, useRef, useState } from "react";
import { DashboardSidebar, MobileDashboardTopbar, SidebarIcon } from "./DashboardLayout";
import { buildAdminNavItems } from "../utils/roles";
import HomeView from "./HomeView";
import ComplaintModal from "./ComplaintModal";
import SkillRatingForm from "./SkillRatingForm";
import { CertificateStatusBadge, CertificateThumb } from "./CertificatePreview";
import HouseholdJobMapPanel from "./HouseholdJobMapPanel";
import JobImageUpload from "./JobImageUpload";
import LocationDistanceMap from "./LocationDistanceMap";
import WorkerJobsMap from "./WorkerJobsMap";
import HouseholdWorkersMap from "./HouseholdWorkersMap";
import WorkerLocationPicker from "./WorkerLocationPicker";
import WorkerSkillsDialog from "./WorkerSkillsDialog";
import EditJobDialog from "./EditJobDialog";
import WorkerPortfolioViewPublic from "./WorkerPortfolioViewPublic";
import VerificationRoleTabs, { filterVerificationRequestsByRole } from "./VerificationRoleTabs";
import { getBarangayFromBoundary } from "../utils/geofenceUtils";
import { getBarangayCenter, getNearestBarangay } from "../utils/locationUtils";
import { getApplicationStatusLabel, getPendingApplicationCount, getWorkersNeeded } from "../utils/jobUtils";
import { getHouseholdInitials } from "../utils/formatters";
import { deleteBackendNotification, fetchRecommendedJobs } from "../services/backendDataService";
import { AI_SKILL_WEIGHT, EMPTY_HOUSEHOLD_REVIEW_FORM, GOVERNMENT_ID_TYPES, MAX_WORKER_SKILLS, OTHER_SKILL } from "../constants/appConstants";
import { isInsideTayabasCity } from "../utils/tayabasMapFrame";
import { formatExperience, formatJobDate, formatTimeAgo, formatTimestamp, formatWorkerRate, getWorkerPhoto, parseRatingValue } from "../utils/formatters";
import { getVerificationNavLabel } from "../utils/normalizers";
import { getReviewMetricAverage } from "../utils/reviewUtils";

const HOUSEHOLD_DISMISSED_NOTIFICATIONS_KEY = "gawago-household-dismissed-notifications";
const WORKER_DISMISSED_NOTIFICATIONS_KEY = "gawago-worker-dismissed-notifications";
const AI_SCAN_STATUS_PHASES = [
  "Scanning open jobs near you…",
  "Comparing your skills to job requirements…",
  "Ranking by relevance and distance…",
];
// The score a review counts for: the average of the four metrics when they
// were given (AGENTS.md II.A), otherwise the star rating -- the same rule the
// backend uses for a worker's average, so the two can't disagree.
// The calendar day in the viewer's own timezone, as a date <input> gives it.
// toISOString() is UTC, which filed anything posted before 8am in the
// Philippines under the previous day.
function localDateKey(date) {
  return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

function reviewScore(review) {
  const value = review.overallRating ?? review.rating;
  return value == null ? null : Number(value);
}

const AI_SCAN_MIN_DURATION_MS = 2400;
const HOUSEHOLD_SCAN_MAX_DURATION_MS = 25000;
const HOUSEHOLD_SCAN_STATUS_PHASES = [
  "Scanning available workers nearby…",
  "Comparing worker skills to your job…",
  "Ranking by skill fit and travel distance…",
];

export default function AppViews({
  SKILLS,
  adminSection,
  adminVisibleWorkers,
  approvedVerificationRequests,
  buildMatchedWorkersForJob,
  currentHousehold,
  currentUser,
  currentWorker,
  dashboardMetrics,
  formatCurrency,
  formatDateTime,
  formatDistance,
  formatLocation,
  formatRate,
  formatScheduleLabel,
  getDisplayName,
  goBack,
  handleAdminApproveVerification,
  handleAdminRejectVerification,
  handleApplyToJob,
  handleCancelJob,
  handleConfirmJobCompleted,
  handleHireWorker,
  handleHouseholdChange,
  handleHouseholdJobChange,
  handleHouseholdJobSubmit,
  isSubmittingJob,
  isActionPending,
  portfolioSaving = false,
  handleSetSkillProficiency = () => {},
  householdMatchRank = "ai",
  setHouseholdMatchRank = () => {},
  handleHouseholdProfileChange,
  handleHouseholdProfileSave,
  handleHouseholdRegisterSubmit,
  registerErrors,
  handleHouseholdReviewSubmit,
  handleLoginChange,
  handleLoginSubmit,
  recommendedWorkersLoading,
  handleLogout,
  handleRejectApplication,
  handleVerificationChange,
  handleVerificationSubmit,
  handleWorkerChange,
  handleWorkerFeedbackForReviewSubmit,
  handleWorkerRateHousehold,
  handleUpdateJob,
  handleWorkerProfileChange,
  handleWorkerProfileSave,
  handleWorkerRegisterSubmit,
  householdForm,
  householdJobCoordinates,
  householdJobForm,
  householdJobImages,
  householdJobLocationPreview,
  householdJobMapMode,
  householdJobMapRef,
  householdJobMapViewRef,
  householdJobs,
  householdNotificationsWithReadState,
  householdProfileForm,
  householdReviewForm,
  householdUnreadCount,
  isAdminPortalPath,
  loginError,
  loginForm,
  markAllNotificationsRead,
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
  pendingVerificationRequests,
  registeredHouseholds,
  registeredWorkers,
  rejectedVerificationRequests,
  renderBarangayOptions,
  captureHouseholdJobLocation,
  loadLeafletAssets,
  placeHouseholdJobPin,
  selectedJob,
  selectedMatchedWorkers,
  selectedVerificationRequest,
  selectedVerificationRequestId,
  selectedWorker,
  selectedWorkerPhoto,
  setHouseholdReviewForm,
  setHouseholdJobMapMode,
  setSelectedJobId,
  setSelectedWorkerId,
  setWorkerForm,
  setWorkerProfileForm,
  toggleSkill,
  toggleWorkerProfileSkill,
  handleSaveWorkerSkills,
  showCertificationModal,
  setShowCertificationModal,
  showSkillModal,
  setShowSkillModal,
  showWorkSampleModal,
  setShowWorkSampleModal,
  certificationForm,
  setCertificationForm,
  workSampleForm,
  setWorkSampleForm,
  handleAddCertification,
  handleAddWorkSample,
  handleDeleteCertification,
  handleDeleteWorkSample,
  handleEditCertification,
  handleEditWorkSample,
  handleOpenCertificationModal,
  handleOpenWorkSampleModal,
  editingCertificationIndex,
  editingWorkSampleIndex,
  viewingWorkSampleIndex,
  setViewingWorkSampleIndex,
  portfolioGalleryOpen,
  setPortfolioGalleryOpen,
  employmentHistory,
  addToast,
  verificationForm,
  verificationRequests,
  view,
  workerApplicationUnreadCount,
  workerApplications,
  workerForm,
  workerMatchedJobs,
  workerMiniPhoto,
  workerNotificationsWithReadState,
  workerProfileForm,
  workerUnreadCount,
  workerVisibleJobs,
}) {
  const [showComplaintModal, setShowComplaintModal] = useState(false);
  // Offered right after a household's review, as on mobile: per-skill
  // ratings (AGENTS.md II.A) roll up into the worker's portfolio skills.
  const [skillRatingTarget, setSkillRatingTarget] = useState(null);
  const [householdFeedbackDateFilter, setHouseholdFeedbackDateFilter] = useState("");
  const [householdNotificationDateFilter, setHouseholdNotificationDateFilter] = useState("");
  const [householdReviewDateFilter, setHouseholdReviewDateFilter] = useState("");
  const [householdReviewRatingFilter, setHouseholdReviewRatingFilter] = useState("");
  const [workerFeedbackDateFilter, setWorkerFeedbackDateFilter] = useState("");
  const [workerHouseholdReplyDrafts, setWorkerHouseholdReplyDrafts] = useState({});
  const [workerRatingDateFilter, setWorkerRatingDateFilter] = useState("");
  const [workerProfilePanel, setWorkerProfilePanel] = useState("profile");
  const [workerJobTypeFilter, setWorkerJobTypeFilter] = useState("All Types");
  const [workerBarangayFilter, setWorkerBarangayFilter] = useState("");
  const [workerApplicationStatusFilter, setWorkerApplicationStatusFilter] = useState("All");
  const [adminVerificationRoleFilter, setAdminVerificationRoleFilter] = useState("all");
  const visibleAdminVerificationRequests = filterVerificationRequestsByRole(
    verificationRequests || [],
    adminVerificationRoleFilter,
  );
  const [workerFindJobsView, setWorkerFindJobsView] = useState("list");
  const [matchedSkillFilter, setMatchedSkillFilter] = useState("All");
  const [householdMatchesView, setHouseholdMatchesView] = useState("list");
  const [aiModeActive, setAiModeActive] = useState(false);
  const [aiRecommendedJobs, setAiRecommendedJobs] = useState(null);
  const [aiRecommendationsLoading, setAiRecommendationsLoading] = useState(false);
  const [aiRecommendationsError, setAiRecommendationsError] = useState("");
  const [scatterTags, setScatterTags] = useState([]);
  const [scatterStatusIndex, setScatterStatusIndex] = useState(0);
  const scatterJitterIntervalRef = useRef(null);
  const scatterStatusIntervalRef = useRef(null);
  const [householdScanActive, setHouseholdScanActive] = useState(false);
  const [householdScatterTags, setHouseholdScatterTags] = useState([]);
  const [householdScanStatusIndex, setHouseholdScanStatusIndex] = useState(0);
  const householdScanLoadingRef = useRef(false);
  householdScanLoadingRef.current = Boolean(recommendedWorkersLoading);
  const [ratingExtraSkillChoice, setRatingExtraSkillChoice] = useState("");
  const [workerMarketSearch, setWorkerMarketSearch] = useState("");
  const [workerMarketExpanded, setWorkerMarketExpanded] = useState(false);
  const [householdNotificationMenuId, setHouseholdNotificationMenuId] = useState(null);
  const [householdNotificationDeletingId, setHouseholdNotificationDeletingId] = useState(null);
  const [workerNotificationPreview, setWorkerNotificationPreview] = useState(null);
  const [workerNotificationMenuId, setWorkerNotificationMenuId] = useState(null);
  const [workerNotificationDeletingId, setWorkerNotificationDeletingId] = useState(null);
  const [householdDismissedNotificationIds, setHouseholdDismissedNotificationIds] = useState(() => {
    if (typeof window === "undefined") {
      return [];
    }
    try {
      const stored = JSON.parse(window.localStorage.getItem(HOUSEHOLD_DISMISSED_NOTIFICATIONS_KEY) || "{}");
      return stored?.[currentUser?.username] || [];
    } catch {
      return [];
    }
  });
  const [workerDismissedNotificationIds, setWorkerDismissedNotificationIds] = useState(() => {
    if (typeof window === "undefined") {
      return [];
    }
    try {
      const stored = JSON.parse(window.localStorage.getItem(WORKER_DISMISSED_NOTIFICATIONS_KEY) || "{}");
      return stored?.[currentUser?.username] || [];
    } catch {
      return [];
    }
  });
  const addWorkerDateAvailability = () => {
    setWorkerProfileForm((prev) => ({
      ...prev,
      availabilityWindows: [
        ...(prev.availabilityWindows || []),
        {
          id: `availability-${Date.now()}`,
          date: "",
          startTime: "09:00",
          endTime: "17:00",
          isAvailable: true,
        },
      ],
    }));
  };
  const updateWorkerDateAvailability = (id, field, value) => {
    setWorkerProfileForm((prev) => ({
      ...prev,
      availabilityWindows: (prev.availabilityWindows || []).map((window) =>
        window.id === id ? { ...window, [field]: value } : window,
      ),
    }));
  };
  const removeWorkerDateAvailability = (id) => {
    setWorkerProfileForm((prev) => ({
      ...prev,
      availabilityWindows: (prev.availabilityWindows || []).filter((window) => window.id !== id),
    }));
  };
  const [workerProfileEditing, setWorkerProfileEditing] = useState(false);
  const [workerPhotoModalOpen, setWorkerPhotoModalOpen] = useState(false);
  const [dashboardModal, setDashboardModal] = useState(null);
  const [myJobsFilter, setMyJobsFilter] = useState("all");
  const [pendingHireWorkerId, setPendingHireWorkerId] = useState(null);
  const [householdProfileEditing, setHouseholdProfileEditing] = useState(false);
  const [selectedWorkerRouteDistanceKm, setSelectedWorkerRouteDistanceKm] = useState(null);
  const [workerHireRequestPreview, setWorkerHireRequestPreview] = useState(null);
  const [workerRateHouseholdJob, setWorkerRateHouseholdJob] = useState(null);
  const [editingJob, setEditingJob] = useState(null);
  const [workerRateHouseholdDraft, setWorkerRateHouseholdDraft] = useState({ rating: "", feedback: "" });
  const hasRatedHouseholdForJob = (jobId) =>
    (currentWorker?.givenFeedback || []).some((feedback) => String(feedback.jobId) === String(jobId));
  const verificationAccount = currentUser?.role === "household" ? currentHousehold : currentWorker;
  const isHouseholdVerification = currentUser?.role === "household";
  const verificationNavLabel = getVerificationNavLabel(verificationAccount);
  // Local date (not UTC) so late-evening users in PH aren't blocked from today.
  const todayIsoDate = new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 10);
  const pendingVerificationSubmission =
    verificationAccount?.verificationSubmission &&
    ["Pending", "Under Review"].includes(verificationAccount.verificationSubmission.status);
  const navIcon = (name) => <SidebarIcon name={name} />;
  const getDistancePoint = (record, requireTayabasLocation = false) => {
    const latitude = record?.latitude ?? null;
    const longitude = record?.longitude ?? null;
    if (
      latitude !== null &&
      longitude !== null &&
      Number.isFinite(Number(latitude)) &&
      Number.isFinite(Number(longitude))
    ) {
      const numericLatitude = Number(latitude);
      const numericLongitude = Number(longitude);
      if (requireTayabasLocation && !isInsideTayabasCity(numericLatitude, numericLongitude)) {
        return null;
      }
      return {
        latitude: numericLatitude,
        longitude: numericLongitude,
        boundaryBarangay:
          getBarangayFromBoundary(numericLatitude, numericLongitude) ||
          getNearestBarangay(numericLatitude, numericLongitude),
      };
    }
    if (requireTayabasLocation) {
      return null;
    }
    return getBarangayCenter(record?.barangay || "");
  };
  const getWorkerJobDistanceLabel = (job) => {
    if (!currentWorker || !job) {
      return "";
    }
    if (job.distanceLabel) {
      return job.distanceLabel;
    }
    const backendDistanceKm = job.routeDistanceKm ?? job.distanceKm ?? null;
    return backendDistanceKm !== null && backendDistanceKm !== undefined && backendDistanceKm !== ""
      ? formatDistance(backendDistanceKm)
      : "Road distance unavailable";
  };
  const workerPendingHireRequests = workerApplications.filter((job) => job.canAcceptHireRequest);
  const visibleWorkerNotifications = workerNotificationsWithReadState.filter(
    (notification) => !workerDismissedNotificationIds.includes(notification.id),
  );
  const workerPendingHireRequestNotifications = visibleWorkerNotifications.filter(
    (item) => item.actionType === "hire_request" && item.requiresAction && item.applicationId,
  );
  const workerHireRequestCards =
    workerPendingHireRequestNotifications.length > 0
      ? workerPendingHireRequestNotifications.map((notification) => {
          const matchingJob =
            workerPendingHireRequests.find(
              (job) =>
                String(job.applicationId) === String(notification.applicationId) ||
                String(job.id) === String(notification.jobId),
            ) || {};
          return {
            ...matchingJob,
            notificationId: notification.id,
            notificationBackendId: notification.backendId,
            notificationMessage: notification.message,
            notificationTitle: notification.title,
            actorUsername: notification.actorUsername,
            actionUrl: notification.actionUrl,
            requiresAction: notification.requiresAction,
            applicationId: notification.applicationId,
            applicationStatus: "Hire Request",
            id: notification.jobId ?? matchingJob.id,
            updatedAt: notification.date || matchingJob.updatedAt,
            unread: notification.unread,
          };
        })
      : workerPendingHireRequests
          .map((job) => ({
            ...job,
            notificationId: `hire-request-${job.applicationId || job.id}`,
          }))
          .filter((job) => !workerDismissedNotificationIds.includes(job.notificationId));
  const workerHireRequestPreviewJob = workerHireRequestPreview
    ? workerHireRequestCards.find(
        (job) => String(job.applicationId) === String(workerHireRequestPreview.applicationId),
      ) || workerHireRequestPreview
    : null;
  const hiringNotificationHasRequestCard = (notification) => {
    if (notification.actionType === "hire_request" && notification.requiresAction && notification.applicationId) {
      return true;
    }
    if (notification.notificationType !== "hiring") {
      return false;
    }
    const message = String(notification.message || "").toLowerCase();
    return workerPendingHireRequests.some((job) => {
      const title = String(job.jobTitle || "").trim().toLowerCase();
      const serviceType = String(job.serviceType || "").trim().toLowerCase();
      return (title && message.includes(title)) || (serviceType && message.includes(serviceType));
    });
  };
  const workerGeneralNotifications = visibleWorkerNotifications.filter(
    (item) => item.notificationType !== "hiring" || !hiringNotificationHasRequestCard(item),
  );
  const selectedWorkerApplication =
    selectedJob && selectedWorker
      ? (selectedJob.applications || []).find(
          (item) =>
            String(item.workerId) === String(selectedWorker.id) ||
            item.workerUsername === selectedWorker.username,
        )
      : null;
  const selectedJobVisibleApplications = (selectedJob?.applications || []).filter(
    (application) => application.status !== "Rejected" && application.status !== "Closed",
  );
  const selectedJobApplicantWorkers = selectedJobVisibleApplications.map((application) => {
    const existingWorker = registeredWorkers.find(
      (worker) =>
        String(worker.id) === String(application.workerId) ||
        worker.username === application.workerUsername,
    );
    return {
      ...(existingWorker || {}),
      id: existingWorker?.id || application.workerId,
      username: existingWorker?.username || application.workerUsername,
      firstName: existingWorker?.firstName || application.workerName || "",
      lastName: existingWorker?.lastName || "",
      // The application now carries the worker's profile details, so an
      // applicant card renders fully even when registeredWorkers hasn't
      // loaded (or never included this worker).
      displayName: application.workerName || existingWorker?.displayName || "",
      profilePhotoPreview: application.workerPhotoUrl || existingWorker?.profilePhotoPreview || "",
      barangay: existingWorker?.barangay || application.workerLocationLabel || "",
      bio: application.workerBio || existingWorker?.bio || "",
      skills: application.workerSkills?.length ? application.workerSkills : existingWorker?.skills || [],
      verification: application.workerVerification || existingWorker?.verification || "Not Yet Verified",
      rating: application.workerRatingLabel || existingWorker?.rating || "No ratings yet",
      reviewsDone: application.workerRatingCount ?? existingWorker?.reviewsDone ?? 0,
      completedJobs: application.workerCompletedJobs ?? 0,
      aiScore: application.workerMatchScore ?? null,
      distanceKm: application.routeDistanceKm ?? null,
      distanceLabel: application.distanceLabel || "",
      dailyRate: application.workerDailyRate || existingWorker?.dailyRate || "0.00",
      avatar: existingWorker?.avatar || (application.workerName || application.workerUsername || "W").slice(0, 1).toUpperCase(),
      applicationStatus: application.status,
      applicationStatusLabel: application.statusLabel || "",
      appliedAt: application.appliedAt,
    };
  });
  // Only badge a "Top match" when there is something to compare: a single
  // applicant, or applicants the scorer couldn't rank, shouldn't get one.
  const topApplicantKey = (() => {
    const scored = selectedJobApplicantWorkers.filter((applicant) => Number(applicant.aiScore) > 0);
    if (scored.length < 2) {
      return null;
    }
    const best = scored.reduce((leader, applicant) =>
      Number(applicant.aiScore) > Number(leader.aiScore) ? applicant : leader,
    );
    return String(best.id || best.username);
  })();
  const selectedJobApplicantKeys = new Set(
    selectedJobVisibleApplications.flatMap((application) =>
      [application.workerId, application.workerUsername]
        .filter((value) => value !== null && value !== undefined && value !== "")
        .map((value) => String(value)),
    ),
  );
  const selectedSuggestedWorkers = selectedMatchedWorkers.filter(
    (worker) =>
      !selectedJobApplicantKeys.has(String(worker.id)) &&
      !selectedJobApplicantKeys.has(String(worker.workerId)) &&
      !selectedJobApplicantKeys.has(String(worker.username)),
  );
  // Sorted here rather than trusting the response order: background polling
  // re-fetches this list in Smart Matching order, which would otherwise
  // silently reshuffle the AI ranking under the user.
  const smartMatchRanking = householdMatchRank === "smart";
  // Smart Matching keeps the backend's rule order (skill, verification,
  // distance, then rating and rate); the AI view sorts by score here because
  // the polled list can arrive in either order.
  const aiMatchedWorkersForSelectedJob = smartMatchRanking
    ? [...selectedSuggestedWorkers]
    : [...selectedSuggestedWorkers].sort((first, second) => (second.aiScore || 0) - (first.aiScore || 0));
  // Chips are built from the skills the matched workers actually have, so the
  // row never offers a category that would filter the list down to nothing.
  const matchedSkillOptions = [
    "All",
    ...Array.from(
      new Set(aiMatchedWorkersForSelectedJob.flatMap((worker) => worker.skills || []).filter(Boolean)),
    ),
  ];
  const visibleMatchedWorkers =
    matchedSkillFilter === "All"
      ? aiMatchedWorkersForSelectedJob
      : aiMatchedWorkersForSelectedJob.filter((worker) => (worker.skills || []).includes(matchedSkillFilter));
  const canRejectSelectedWorkerApplication =
    selectedWorkerApplication && !["Hire Request", "Hired", "Rejected"].includes(selectedWorkerApplication.status);
  const selectedWorkerHireButtonLabel =
    selectedWorkerApplication?.status === "Pending"
      ? "Accept Applicant"
      : selectedWorkerApplication?.status === "Hired"
        ? "Already Hired"
        : selectedWorkerApplication?.status === "Hire Request"
          ? "Hire Request Sent"
          : "Send Hire Request";
  const selectedWorkerHireButtonDisabled = ["Hired", "Hire Request", "Completed"].includes(
    selectedWorkerApplication?.status,
  );
  const selectedWorkerVerificationRequest =
    selectedWorker
      ? verificationRequests.find((item) => item.id === selectedWorker.verificationRequestId) ||
        verificationRequests.find((item) => item.workerId === selectedWorker.id) ||
        selectedWorker.verificationSubmission ||
        null
      : null;
  const householdWorkerFeedback = currentHousehold?.receivedFeedback || [];
  const householdSubmittedReviews = currentHousehold?.givenFeedback || [];
  const workerHouseholdReviews = currentWorker?.receivedReviews || [];
  const workerHouseholdFeedback = workerHouseholdReviews.filter((review) => review.feedback || review.comment);
  const workerHouseholdRatings = workerHouseholdReviews.filter((review) => reviewScore(review) != null);
  // "My Jobs" splits the worker's hired work from their finished history. The
  // application stays Hired while the job runs, including once completion has
  // been requested, so the job status is what separates the two lists.
  const workerInProgressJobs = workerApplications.filter(
    (job) =>
      job.applicationStatus === "Hired" && job.status !== "Completed" && job.status !== "Cancelled",
  );
  const workerCompletedJobs = workerApplications.filter(
    (job) => job.applicationStatus === "Completed" || job.status === "Completed",
  );
  const getWorkerReviewForJob = (jobId) =>
    workerHouseholdRatings.find((review) => String(review.jobId) === String(jobId)) || null;
  const workerRatingCounts = [5, 4, 3, 2, 1].map((rating) => ({
    rating,
    count: workerHouseholdRatings.filter((review) => Math.round(reviewScore(review)) === rating).length,
  }));
  const workerTotalReviews = workerHouseholdRatings.length;
  const workerRatingTotal = workerHouseholdRatings.reduce((total, review) => total + (reviewScore(review) || 0), 0);
  const workerAverageRating = workerTotalReviews > 0 ? workerRatingTotal / workerTotalReviews : null;
  const workerFiveStarRate =
    workerTotalReviews > 0
      ? Math.round(((workerRatingCounts.find((item) => item.rating === 5)?.count || 0) / workerTotalReviews) * 100)
      : 0;
  useEffect(() => {
    if (view !== "worker-profile" && workerProfilePanel !== "profile") {
      setWorkerProfilePanel("profile");
    }
  }, [view, workerProfilePanel]);
  useEffect(() => {
    if (view === "worker-profile" && workerProfilePanel === "ratings") {
      setWorkerProfilePanel("feedback");
    }
  }, [view, workerProfilePanel]);
  useEffect(() => {
    if (view !== "household-profile" && householdProfileEditing) {
      setHouseholdProfileEditing(false);
    }
  }, [householdProfileEditing, view]);
  useEffect(() => {
    if (view !== "worker-profile" && workerProfileEditing) {
      setWorkerProfileEditing(false);
    }
  }, [view, workerProfileEditing]);
  useEffect(() => {
    setSelectedWorkerRouteDistanceKm(null);
  }, [selectedJob?.id, selectedWorker?.id, selectedWorker?.username]);
  useEffect(() => {
    if (view !== "worker-notifications") {
      setWorkerNotificationPreview(null);
      setWorkerHireRequestPreview(null);
      setWorkerNotificationMenuId(null);
    }
  }, [view]);
  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }
    try {
      const stored = JSON.parse(window.localStorage.getItem(HOUSEHOLD_DISMISSED_NOTIFICATIONS_KEY) || "{}");
      setHouseholdDismissedNotificationIds(stored?.[currentUser?.username] || []);
    } catch {
      setHouseholdDismissedNotificationIds([]);
    }
  }, [currentUser?.username]);
  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }
    try {
      const stored = JSON.parse(window.localStorage.getItem(WORKER_DISMISSED_NOTIFICATIONS_KEY) || "{}");
      setWorkerDismissedNotificationIds(stored?.[currentUser?.username] || []);
    } catch {
      setWorkerDismissedNotificationIds([]);
    }
  }, [currentUser?.username]);
  useEffect(() => {
    const closeNotificationMenu = () => {
      setHouseholdNotificationMenuId(null);
      setWorkerNotificationMenuId(null);
    };
    const closeNotificationMenuOnEscape = (event) => {
      if (event.key === "Escape") {
        closeNotificationMenu();
      }
    };
    document.addEventListener("click", closeNotificationMenu);
    document.addEventListener("keydown", closeNotificationMenuOnEscape);
    return () => {
      document.removeEventListener("click", closeNotificationMenu);
      document.removeEventListener("keydown", closeNotificationMenuOnEscape);
    };
  }, []);
  const submitWorkerProfileForm = (event) => {
    if (!workerProfileEditing) {
      event.preventDefault();
      setWorkerProfileEditing(true);
      return;
    }
    const result = handleWorkerProfileSave(event);
    Promise.resolve(result).then(() => setWorkerProfileEditing(false));
    return result;
  };
  const workerMarketCategories = useMemo(() => {
    const defaultServiceTypes = SKILLS.filter((serviceType) => serviceType !== "Other");
    const knownServiceKeys = new Set(defaultServiceTypes.map((serviceType) => serviceType.trim().toLowerCase()));
    const customServiceTypes = [
      ...new Set(
        workerVisibleJobs
          .map((job) => String(job.serviceType || "").trim())
          .filter((serviceType) => serviceType && !knownServiceKeys.has(serviceType.toLowerCase())),
      ),
    ].sort((first, second) => first.localeCompare(second));
    return [...defaultServiceTypes, ...customServiceTypes].map((serviceType) => {
      const categoryJobs = workerVisibleJobs.filter((job) => job.serviceType === serviceType);
      const matchesWorkerSkills = (currentWorker?.skills || []).includes(serviceType);
      return {
        serviceType,
        openJobs: categoryJobs.reduce((total, job) => total + getWorkersNeeded(job), 0),
        matchesWorkerSkills,
      };
    });
  }, [SKILLS, currentWorker, workerVisibleJobs]);
  const filteredWorkerMarketCategories = useMemo(() => {
    const searchTerm = workerMarketSearch.trim().toLowerCase();
    if (!searchTerm) {
      return workerMarketCategories;
    }
    return workerMarketCategories.filter((category) => category.serviceType.toLowerCase().includes(searchTerm));
  }, [workerMarketCategories, workerMarketSearch]);
  // Categories with open jobs or in the worker's skills come first. On a
  // phone the rest fold behind a "Show more" button (see main.css) so the
  // dashboard isn't a long scroll of empty categories; a search shows all.
  const workerMarketList = useMemo(() => {
    const isPriority = (category) => category.matchesWorkerSkills || category.openJobs > 0;
    const priority = filteredWorkerMarketCategories
      .filter(isPriority)
      .sort((first, second) => second.openJobs - first.openJobs);
    const rest = filteredWorkerMarketCategories.filter((category) => !isPriority(category));
    const foldRest = !workerMarketSearch.trim() && priority.length > 0;
    return {
      categories: [...priority, ...rest.map((category) => ({ ...category, folded: foldRest }))],
      foldedCount: foldRest ? rest.length : 0,
    };
  }, [filteredWorkerMarketCategories, workerMarketSearch]);
  const filteredWorkerVisibleJobs = useMemo(() => {
    return workerVisibleJobs.filter((job) => {
      const matchesJobType = workerJobTypeFilter === "All Types" || job.serviceType === workerJobTypeFilter;
      const matchesBarangay =
        !workerBarangayFilter.trim() ||
        String(job.barangay || "")
          .toLowerCase()
          .includes(workerBarangayFilter.trim().toLowerCase());
      return matchesJobType && matchesBarangay;
    });
  }, [workerBarangayFilter, workerJobTypeFilter, workerVisibleJobs]);
  const stopAiScanAnimation = () => {
    if (scatterJitterIntervalRef.current) {
      clearInterval(scatterJitterIntervalRef.current);
      scatterJitterIntervalRef.current = null;
    }
    if (scatterStatusIntervalRef.current) {
      clearInterval(scatterStatusIntervalRef.current);
      scatterStatusIntervalRef.current = null;
    }
    setScatterTags([]);
    setScatterStatusIndex(0);
  };
  const startAiScanAnimation = () => {
    const skillPool = (currentWorker?.skills || []).filter(Boolean);
    const labels = skillPool.length > 0 ? skillPool.slice(0, 6) : ["Matching your profile"];
    const randomTag = (id, label) => ({
      id,
      label,
      left: Math.random() * 70 + 5,
      top: Math.random() * 55 + 10,
      rotate: Math.random() * 24 - 12,
    });
    setScatterTags(labels.map((label, index) => randomTag(index, label)));
    setScatterStatusIndex(0);
    scatterStatusIntervalRef.current = setInterval(() => {
      setScatterStatusIndex((previous) => (previous + 1) % AI_SCAN_STATUS_PHASES.length);
    }, 900);
    scatterJitterIntervalRef.current = setInterval(() => {
      setScatterTags((previous) =>
        previous.map((tag) => ({
          ...tag,
          left: Math.min(88, Math.max(2, tag.left + (Math.random() * 18 - 9))),
          top: Math.min(78, Math.max(2, tag.top + (Math.random() * 14 - 7))),
          rotate: Math.random() * 22 - 11,
        })),
      );
    }, 420);
  };
  const runAiJobRecommendations = async () => {
    setAiModeActive(true);
    setAiRecommendationsLoading(true);
    setAiRecommendationsError("");
    startAiScanAnimation();
    const minAnimationDelay = new Promise((resolve) => setTimeout(resolve, AI_SCAN_MIN_DURATION_MS));
    try {
      const [results] = await Promise.all([fetchRecommendedJobs(), minAnimationDelay]);
      if (results === null) {
        setAiRecommendationsError("Unable to load AI recommendations right now. Try again in a moment.");
        setAiRecommendedJobs([]);
      } else {
        setAiRecommendedJobs(results);
      }
    } catch (error) {
      setAiRecommendationsError(error?.message || "Unable to load AI recommendations right now.");
      setAiRecommendedJobs([]);
    } finally {
      stopAiScanAnimation();
      setAiRecommendationsLoading(false);
    }
  };
  const exitAiJobRecommendations = () => {
    setAiModeActive(false);
  };
  useEffect(() => {
    if (view !== "household-job-matches") {
      return undefined;
    }
    const labelPool = [
      selectedJob?.serviceType,
      selectedJob?.barangay,
      selectedJob?.scheduleType,
      selectedJob?.offeredRate ? `${formatCurrency(selectedJob.offeredRate)}/day` : "",
      "Nearby workers",
    ].filter(Boolean);
    const labels = labelPool.length > 0 ? labelPool.slice(0, 6) : ["Matching your job"];
    // Lay tags out in bands so they jitter in place instead of piling onto each other.
    const bandFor = (index) => ({
      baseLeft: (index % 3) * 30 + 4,
      baseTop: Math.floor(index / 3) * 34 + 8,
    });
    const makeTag = (id, label) => {
      const { baseLeft, baseTop } = bandFor(id);
      return {
        id,
        label,
        baseLeft,
        baseTop,
        left: baseLeft + Math.random() * 8,
        top: baseTop + Math.random() * 10,
        rotate: Math.random() * 16 - 8,
      };
    };
    setHouseholdScanActive(true);
    setHouseholdScatterTags(labels.map((label, index) => makeTag(index, label)));
    setHouseholdScanStatusIndex(0);
    const statusInterval = setInterval(() => {
      setHouseholdScanStatusIndex((previous) => (previous + 1) % HOUSEHOLD_SCAN_STATUS_PHASES.length);
    }, 900);
    const jitterInterval = setInterval(() => {
      setHouseholdScatterTags((previous) =>
        previous.map((tag) => ({
          ...tag,
          left: tag.baseLeft + Math.random() * 8,
          top: tag.baseTop + Math.random() * 10,
          rotate: Math.random() * 16 - 8,
        })),
      );
    }, 620);
    const startedAt = Date.now();
    const stop = () => {
      clearInterval(statusInterval);
      clearInterval(jitterInterval);
      clearInterval(doneCheck);
      setHouseholdScanActive(false);
      setHouseholdScatterTags([]);
    };
    const doneCheck = setInterval(() => {
      const elapsed = Date.now() - startedAt;
      if (elapsed < AI_SCAN_MIN_DURATION_MS) {
        return;
      }
      if (householdScanLoadingRef.current && elapsed < HOUSEHOLD_SCAN_MAX_DURATION_MS) {
        return;
      }
      stop();
    }, 200);
    return () => {
      clearInterval(statusInterval);
      clearInterval(jitterInterval);
      clearInterval(doneCheck);
      setHouseholdScanActive(false);
      setHouseholdScatterTags([]);
      setHouseholdScanStatusIndex(0);
    };
  }, [view]);
  const openWorkerFindJobsForCategory = (serviceType) => {
    setWorkerJobTypeFilter(serviceType);
    setWorkerBarangayFilter("");
    openWorkerFindJobs();
  };
  const openAllWorkerFindJobs = () => {
    setWorkerJobTypeFilter("All Types");
    setWorkerBarangayFilter("");
    openWorkerFindJobs();
  };
  const renderWorkerJobImages = (job) => {
    const images = Array.isArray(job.images) ? job.images : [];
    if (images.length === 0) {
      return <span className="text-muted">None</span>;
    }
    return (
      <div className="worker-job-image-strip">
        {images.slice(0, 4).map((image, index) => (
          <img key={image.id || image.image || index} src={image.image} alt={`Reference ${index + 1}`} />
        ))}
        {images.length > 4 && <span className="worker-job-image-count">+{images.length - 4}</span>}
      </div>
    );
  };
  const formatWorkerJobPesoRate = (job) => {
    const amount = Number(job?.offeredRate || 0);
    const safeAmount = Number.isFinite(amount) ? amount : 0;
    return `₱${safeAmount.toFixed(2)}${job?.rateType ? ` / ${job.rateType}` : ""}`;
  };
  const renderAiMatchBreakdown = (job) => {
    const skillPart = Number(job.aiSkillContribution) || 0;
    const proximityPart = Number(job.aiProximityContribution) || 0;
    const total = skillPart + proximityPart;
    if (total <= 0) {
      return null;
    }
    const skillSharePct = Math.round((skillPart / total) * 100);
    const proximitySharePct = 100 - skillSharePct;
    return (
      <div className="worker-ai-match-breakdown mb-2">
        <div className="worker-ai-match-breakdown-bar">
          <span className="worker-ai-match-breakdown-skill" style={{ width: `${skillSharePct}%` }} />
          <span className="worker-ai-match-breakdown-proximity" style={{ width: `${proximitySharePct}%` }} />
        </div>
        <p className="small text-muted mb-0">
          Why this match: {skillSharePct}% skill fit, {proximitySharePct}% proximity
          {job.aiExactSkillMatch ? " — exact skill match" : ""}
        </p>
      </div>
    );
  };
  // Shared by the AI match cards and the applicant cards so a worker reads
  // the same way in both places: one ring, one star row, one photo/initials
  // fallback.
  const renderMatchRing = (score, size = 52) => {
    const percent = Math.max(0, Math.min(100, Math.round((Number(score) || 0) * 100)));
    const radius = size / 2 - 4;
    const circumference = 2 * Math.PI * radius;
    const strong = percent >= 85;
    return (
      <span className={`gg-match-ring ${strong ? "strong" : ""}`} style={{ width: size, height: size }}>
        <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
          <circle className="gg-match-ring-track" cx={size / 2} cy={size / 2} r={radius} strokeWidth="4" fill="none" />
          <circle
            className="gg-match-ring-value"
            cx={size / 2}
            cy={size / 2}
            r={radius}
            strokeWidth="4"
            fill="none"
            strokeDasharray={circumference}
            strokeDashoffset={circumference * (1 - percent / 100)}
            transform={`rotate(-90 ${size / 2} ${size / 2})`}
          />
        </svg>
        <span className="gg-match-ring-label">{percent}%</span>
      </span>
    );
  };
  const renderStarRow = (ratingLabel, reviewCount) => {
    const value = parseRatingValue(ratingLabel);
    const rounded = Math.round(value || 0);
    return (
      <span className="gg-star-row">
        {[1, 2, 3, 4, 5].map((star) => (
          <svg
            key={star}
            className={star <= rounded ? "filled" : ""}
            width="13"
            height="13"
            viewBox="0 0 24 24"
            fill="currentColor"
            aria-hidden="true"
          >
            <polygon points="12 2 15 8.5 22 9.5 17 14.5 18.3 21.5 12 18 5.7 21.5 7 14.5 2 9.5 9 8.5 12 2" />
          </svg>
        ))}
        {value ? (
          <>
            <strong>{value}</strong>
            {reviewCount ? <span className="gg-star-count">({reviewCount})</span> : null}
          </>
        ) : (
          <span className="gg-star-count">No ratings yet</span>
        )}
      </span>
    );
  };
  const renderWorkerPhoto = (worker, name, className) => {
    const photo = getWorkerPhoto(worker);
    if (photo) {
      return <img className={className} src={photo} alt={name} loading="lazy" />;
    }
    return (
      <span className={`${className} is-initials`} aria-hidden="true">
        {String(name || "W").slice(0, 2).toUpperCase()}
      </span>
    );
  };
  const filteredHouseholdNotifications = useMemo(() => {
    const visibleNotifications = householdNotificationsWithReadState.filter(
      (notification) => !householdDismissedNotificationIds.includes(notification.id),
    );
    if (!householdNotificationDateFilter) {
      return visibleNotifications;
    }
    return visibleNotifications.filter((notification) => {
      const notificationDate = new Date(notification.date || notification.createdAt || "");
      if (Number.isNaN(notificationDate.getTime())) {
        return false;
      }
      return localDateKey(notificationDate) === householdNotificationDateFilter;
    });
  }, [
    householdDismissedNotificationIds,
    householdNotificationDateFilter,
    householdNotificationsWithReadState,
  ]);
  const rememberDismissedHouseholdNotification = (notificationId) => {
    setHouseholdDismissedNotificationIds((previousIds) => {
      if (previousIds.includes(notificationId)) {
        return previousIds;
      }
      const nextIds = [...previousIds, notificationId];
      if (typeof window !== "undefined" && currentUser?.username) {
        try {
          const stored = JSON.parse(window.localStorage.getItem(HOUSEHOLD_DISMISSED_NOTIFICATIONS_KEY) || "{}");
          window.localStorage.setItem(
            HOUSEHOLD_DISMISSED_NOTIFICATIONS_KEY,
            JSON.stringify({
              ...stored,
              [currentUser.username]: nextIds,
            }),
          );
        } catch {
          // The notification still disappears for the current session.
        }
      }
      return nextIds;
    });
  };
  const deleteHouseholdNotification = async (notification) => {
    setHouseholdNotificationMenuId(null);
    if (!window.confirm("Delete this notification?")) {
      return;
    }
    setHouseholdNotificationDeletingId(notification.id);
    try {
      if (notification.backendId) {
        await deleteBackendNotification(notification.backendId);
      }
      rememberDismissedHouseholdNotification(notification.id);
    } catch (error) {
      window.alert(error.message || "Unable to delete notification.");
    } finally {
      setHouseholdNotificationDeletingId(null);
    }
  };
  const rememberDismissedWorkerNotification = (notificationId) => {
    setWorkerDismissedNotificationIds((previousIds) => {
      if (previousIds.includes(notificationId)) {
        return previousIds;
      }
      const nextIds = [...previousIds, notificationId];
      if (typeof window !== "undefined" && currentUser?.username) {
        try {
          const stored = JSON.parse(window.localStorage.getItem(WORKER_DISMISSED_NOTIFICATIONS_KEY) || "{}");
          window.localStorage.setItem(
            WORKER_DISMISSED_NOTIFICATIONS_KEY,
            JSON.stringify({
              ...stored,
              [currentUser.username]: nextIds,
            }),
          );
        } catch {
          // The notification still disappears for the current session.
        }
      }
      return nextIds;
    });
  };
  const openWorkerNotificationPreview = (notification) => {
    setWorkerNotificationMenuId(null);
    if (notification.id) {
      markNotificationRead(notification.id);
    }
    setWorkerNotificationPreview(notification);
  };
  const deleteWorkerNotification = async (notification) => {
    setWorkerNotificationMenuId(null);
    if (!window.confirm("Delete this notification?")) {
      return;
    }
    const notificationId =
      notification.notificationId || notification.id || `hire-request-${notification.applicationId}`;
    const backendId = notification.notificationBackendId || notification.backendId;
    setWorkerNotificationDeletingId(notificationId);
    try {
      if (backendId) {
        await deleteBackendNotification(backendId);
      }
      rememberDismissedWorkerNotification(notificationId);
      if (
        workerHireRequestPreview?.notificationId === notificationId ||
        workerNotificationPreview?.id === notificationId
      ) {
        setWorkerHireRequestPreview(null);
        setWorkerNotificationPreview(null);
      }
    } catch (error) {
      window.alert(error.message || "Unable to delete notification.");
    } finally {
      setWorkerNotificationDeletingId(null);
    }
  };
  const openStructuredNotificationAction = (notification) => {
    if (!notification?.requiresAction && !notification?.actionType) {
      return false;
    }
    if (notification.id) {
      markNotificationRead(notification.id);
    }
    if (currentUser?.role === "worker" && notification.jobId) {
      openWorkerJobDetail(notification.jobId);
      return true;
    }
    if (currentUser?.role === "household" && notification.jobId) {
      openHouseholdDashboard();
      return true;
    }
    return false;
  };
  const filteredHouseholdWorkerFeedback = useMemo(() => {
    if (!householdFeedbackDateFilter) {
      return householdWorkerFeedback;
    }
    return householdWorkerFeedback.filter((review) => {
      const reviewDate = new Date(review.createdAt || review.date || "");
      if (Number.isNaN(reviewDate.getTime())) {
        return false;
      }
      return localDateKey(reviewDate) === householdFeedbackDateFilter;
    });
  }, [householdFeedbackDateFilter, householdWorkerFeedback]);
  const filteredHouseholdSubmittedReviews = useMemo(() => {
    return householdSubmittedReviews.filter((review) => {
      if (householdReviewDateFilter) {
        const reviewDate = new Date(review.createdAt || review.date || "");
        if (Number.isNaN(reviewDate.getTime()) || localDateKey(reviewDate) !== householdReviewDateFilter) {
          return false;
        }
      }
      if (householdReviewRatingFilter) {
        // The backend sends "4.0", the filter "4": compare the star a review
        // shows (its overall rating, rounded), the same way the summary counts.
        return Math.round(reviewScore(review) || 0) === Number(householdReviewRatingFilter);
      }
      return true;
    });
  }, [householdReviewDateFilter, householdReviewRatingFilter, householdSubmittedReviews]);
  const filteredWorkerHouseholdFeedback = useMemo(() => {
    if (!workerFeedbackDateFilter) {
      return workerHouseholdReviews;
    }
    return workerHouseholdReviews.filter((review) => {
      const reviewDate = new Date(review.createdAt || review.date || "");
      if (Number.isNaN(reviewDate.getTime())) {
        return false;
      }
      return localDateKey(reviewDate) === workerFeedbackDateFilter;
    });
  }, [workerFeedbackDateFilter, workerHouseholdReviews]);
  const filteredWorkerHouseholdRatings = useMemo(() => {
    if (!workerRatingDateFilter) {
      return workerHouseholdRatings;
    }
    return workerHouseholdRatings.filter((review) => {
      const reviewDate = new Date(review.createdAt || review.date || "");
      if (Number.isNaN(reviewDate.getTime())) {
        return false;
      }
      return localDateKey(reviewDate) === workerRatingDateFilter;
    });
  }, [workerHouseholdRatings, workerRatingDateFilter]);
  const hasSentHouseholdFeedbackForReview = (review) =>
    (currentWorker?.givenFeedback || []).some((feedback) => {
      const sameHousehold =
        (feedback.targetUsername && review.authorUsername && feedback.targetUsername === review.authorUsername) ||
        (feedback.targetName && review.authorName && feedback.targetName === review.authorName);
      const sameJob = !review.jobTitle || !feedback.jobTitle || feedback.jobTitle === review.jobTitle;
      return sameHousehold && sameJob;
    });
  const submitHouseholdFeedbackReply = (event, review) => {
    event.preventDefault();
    const draftKey = review.id || `${review.authorUsername}-${review.createdAt}`;
    const draft = workerHouseholdReplyDrafts[draftKey] || { feedback: "", rating: "5" };
    const feedback = typeof draft === "string" ? draft : draft.feedback;
    const rating = typeof draft === "string" ? "5" : draft.rating;
    handleWorkerFeedbackForReviewSubmit(review, feedback, rating);
    setWorkerHouseholdReplyDrafts((prev) => ({
      ...prev,
      [draftKey]: { feedback: "", rating: "5" },
    }));
  };
  // The backend computes this from both the application and the job status
  // (apps/jobs/statuses.py) so web and mobile show the same words. The
  // branches below only cover records not yet refreshed from the API.
  const getWorkerApplicationDisplayStatus = (job) => {
    if (job.applicationStatusLabel) {
      return job.applicationStatusLabel;
    }
    if (job.status === "Completed" || job.applicationStatus === "Completed") {
      return "Completed";
    }
    if (job.status === "Waiting for Household Confirmation") {
      return "Awaiting confirmation";
    }
    if (job.applicationStatus === "Hired") {
      return "In progress";
    }
    if (job.applicationStatus === "Hire Request") {
      return "Awaiting worker response";
    }
    return "Pending";
  };
  // Options come from the statuses actually present, so the filter can never
  // offer a label the list doesn't use (it used to offer "In Progress").
  const workerApplicationStatusOptions = [
    ...new Set(workerApplications.map((job) => getWorkerApplicationDisplayStatus(job))),
  ];
  const visibleWorkerApplications =
    workerApplicationStatusFilter === "All"
      ? workerApplications
      : workerApplications.filter((job) => getWorkerApplicationDisplayStatus(job) === workerApplicationStatusFilter);
  const selectedWorkerJobPoint = getDistancePoint({
    barangay: selectedJob?.barangay || currentHousehold?.barangay,
    latitude: selectedJob?.latitude ?? currentHousehold?.latitude ?? null,
    longitude: selectedJob?.longitude ?? currentHousehold?.longitude ?? null,
  }, true);
  const selectedWorkerPoint = selectedWorker
    ? getDistancePoint({
        barangay: selectedWorker.barangay,
        latitude: selectedWorker.latitude ?? null,
        longitude: selectedWorker.longitude ?? null,
      }, true)
    : null;
  const selectedWorkerJobLatitude = selectedWorkerJobPoint?.latitude ?? null;
  const selectedWorkerJobLongitude = selectedWorkerJobPoint?.longitude ?? null;
  const selectedWorkerJobLocationLabel = selectedWorkerJobPoint?.boundaryBarangay
    ? `Near ${selectedWorkerJobPoint.boundaryBarangay}, Tayabas City`
    : formatLocation(selectedJob?.barangay, selectedJob?.streetAddress);
  const selectedWorkerLocationLabel = selectedWorkerPoint?.boundaryBarangay
    ? `Near ${selectedWorkerPoint.boundaryBarangay}, Tayabas City`
    : formatLocation(selectedWorker?.barangay, selectedWorker?.streetAddress);
  const selectedWorkerDistanceKm =
    selectedWorker?.distanceKm !== null &&
    selectedWorker?.distanceKm !== undefined &&
    selectedWorker?.distanceKm !== "" &&
    Number.isFinite(Number(selectedWorker.distanceKm))
      ? Number(selectedWorker.distanceKm)
      : null;
  const selectedWorkerRouteLabel =
    selectedWorkerRouteDistanceKm !== null && selectedWorkerRouteDistanceKm !== undefined
      ? formatDistance(selectedWorkerRouteDistanceKm)
      : "";
  const selectedWorkerDistanceLabel =
    selectedWorkerRouteLabel ||
    selectedWorker?.distanceLabel ||
    (selectedWorkerDistanceKm !== null ? formatDistance(selectedWorkerDistanceKm) : "Road distance unavailable");
  // Exact location is only sent once this worker is hired for the job.
  const selectedWorkerLocationShared = Boolean(selectedWorkerPoint);
  const selectedWorkerReviews = selectedWorker?.receivedReviews || [];
  const selectedWorkerRatings = selectedWorkerReviews.filter((review) => reviewScore(review) != null);
  const selectedWorkerRatingCounts = [5, 4, 3, 2, 1].map((rating) => ({
    rating,
    count: selectedWorkerRatings.filter((review) => Math.round(reviewScore(review)) === rating).length,
  }));
  const selectedWorkerTotalReviews = selectedWorkerRatings.length;
  const selectedWorkerRatingTotal = selectedWorkerRatings.reduce((total, review) => total + (reviewScore(review) || 0), 0);
  const selectedWorkerAverageRating =
    selectedWorkerTotalReviews > 0 ? selectedWorkerRatingTotal / selectedWorkerTotalReviews : null;
  const selectedWorkerFiveStarRate =
    selectedWorkerTotalReviews > 0
      ? Math.round(
          ((selectedWorkerRatingCounts.find((item) => item.rating === 5)?.count || 0) / selectedWorkerTotalReviews) *
            100,
        )
      : 0;
  // On a job with several hired workers, the one still waiting for this
  // household's review -- the Rate buttons used to always open the first
  // worker, so the others could never be reviewed.
  function getWorkerToReviewForJob(job) {
    return getAssignedWorkerForJob(job, (application) => application.householdCanReview);
  }
  function getAssignedWorkerForJob(job, preferApplication = null) {
    if (!job) {
      return null;
    }
    const applications = job.applications || [];
    const acceptedApplication =
      (preferApplication && applications.find(preferApplication)) ||
      applications.find((application) => ["Completed", "Hired"].includes(application.status)) ||
      null;
    const matchedWorker =
      acceptedApplication &&
      registeredWorkers.find(
        (worker) =>
          String(worker.id) === String(acceptedApplication.workerId) ||
          worker.username === acceptedApplication.workerUsername ||
          getDisplayName(worker.firstName, worker.lastName, worker.username) === acceptedApplication.workerName,
      );
    if (matchedWorker) {
      return matchedWorker;
    }
    const matchedWorkerId = (job.matchedWorkerIds || [])[0];
    return registeredWorkers.find((worker) => String(worker.id) === String(matchedWorkerId)) || null;
  }
  function getHouseholdReviewForJobWorker(job, worker) {
    if (!job || !worker) {
      return null;
    }
    const workerNames = [
      worker.username,
      worker.workerUsername,
      getDisplayName(worker.firstName, worker.lastName, worker.username),
    ].filter(Boolean);
    const jobTitles = [job.jobTitle, job.serviceType].filter(Boolean);
    return (
      (currentHousehold?.givenFeedback || []).find((review) => {
        const sameWorker =
          workerNames.includes(review.targetUsername) ||
          workerNames.includes(review.targetName) ||
          workerNames.includes(review.target);
        // Prefer matching by job id -- two different job postings can share
        // the same title/service type (e.g. hiring the same worker for
        // "House Cleaning" twice), and matching by title alone would treat
        // an old review as if it already covered the new job.
        const sameJob = review.jobId
          ? String(review.jobId) === String(job.id)
          : !review.jobTitle || jobTitles.includes(review.jobTitle);
        return sameWorker && sameJob && reviewScore(review) != null;
      }) || null
    );
  }
  // Dashboard = jobs still in motion; My Jobs = finished history. A job
  // moves from one to the other the moment it's Completed or Cancelled --
  // nothing lives in both places.
  const inProcessHouseholdJobs = useMemo(
    () => householdJobs.filter((job) => job.status !== "Completed" && job.status !== "Cancelled"),
    [householdJobs],
  );
  // A completed job still owes a review, so it also surfaces on the Dashboard
  // under "Completed" as a reminder until it's rated -- it doesn't leave My
  // Jobs though: that page is the complete record, rated or not.
  const pendingHouseholdReviewJobs = useMemo(
    () => householdJobs.filter((job) => job.status === "Completed" && job.canReview),
    [householdJobs],
  );
  const historyHouseholdJobs = useMemo(
    () => householdJobs.filter((job) => job.status === "Completed" || job.status === "Cancelled"),
    [householdJobs],
  );
  const historyCompletedJobs = useMemo(
    () => historyHouseholdJobs.filter((job) => job.status === "Completed"),
    [historyHouseholdJobs],
  );
  const historyCancelledJobs = useMemo(
    () => historyHouseholdJobs.filter((job) => job.status === "Cancelled"),
    [historyHouseholdJobs],
  );
  const householdTotalSpent = useMemo(
    () => historyCompletedJobs.reduce((sum, job) => sum + (Number(job.offeredRate) || 0), 0),
    [historyCompletedJobs],
  );
  const householdRatingsGiven = useMemo(
    () => householdSubmittedReviews.filter((review) => reviewScore(review) != null).map((review) => reviewScore(review)),
    [householdSubmittedReviews],
  );
  const householdAvgRatingGiven = householdRatingsGiven.length
    ? householdRatingsGiven.reduce((sum, value) => sum + value, 0) / householdRatingsGiven.length
    : 0;
  const renderHouseholdStarRatingInput = (labelId) => {
    // Once any metric below is rated, the overall rating is their average
    // and the stars here only show it. They used to stay at the default 5,
    // which was saved beside a 4.5 metric average.
    const metricAverage = getReviewMetricAverage(householdReviewForm);
    const selectedRating = metricAverage ?? Number(householdReviewForm.rating || 0);

    return (
      <div className="household-dashboard-star-rating" id={labelId} role="radiogroup" aria-label="Rate worker">
        {[1, 2, 3, 4, 5].map((ratingValue) => (
          <button
            aria-checked={Math.round(selectedRating) === ratingValue}
            aria-label={`${ratingValue} star${ratingValue > 1 ? "s" : ""}`}
            className={`household-dashboard-star-button ${Math.round(selectedRating) >= ratingValue ? "selected" : ""}`}
            key={ratingValue}
            disabled={metricAverage != null}
            onClick={() => setHouseholdReviewForm((prev) => ({ ...prev, rating: String(ratingValue) }))}
            role="radio"
            type="button"
          />
        ))}
        <span>
          {metricAverage != null
            ? `${metricAverage.toFixed(1)}/5 · average of the metrics below`
            : selectedRating
              ? `${selectedRating}/5`
              : "Select rating"}
        </span>
      </div>
    );
  };
  // Shared by both places a household reviews a worker (My Jobs job detail and
  // the dashboard job panel) so the same metrics are collected either way.
  const renderHouseholdReviewMetricInputs = () => (
    <div className="mt-4 pt-3 border-top household-metric-ratings">
      <p className="small text-muted mb-3">Rate worker on specific metrics (optional):</p>
      {[
        ["quality_of_work", "Quality of Work"],
        ["punctuality", "Punctuality"],
        ["communication", "Communication"],
        ["professionalism", "Professionalism"],
      ].map(([field, label]) => {
        const selectedValue = Number(householdReviewForm[field] || 0);
        return (
          <div className="household-metric-row" key={field}>
            <label className="form-label mb-0">{label}</label>
            <div className="household-metric-stars" role="radiogroup" aria-label={label}>
              {[1, 2, 3, 4, 5].map((val) => (
                <button
                  key={val}
                  type="button"
                  aria-checked={selectedValue === val}
                  aria-label={`${val} star${val > 1 ? "s" : ""}`}
                  role="radio"
                  className={`household-metric-star-button ${selectedValue >= val ? "selected" : ""}`}
                  onClick={() => setHouseholdReviewForm((prev) => ({ ...prev, [field]: val }))}
                />
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
  // Dashboard modals. Both act on whichever job the card belongs to, so the
  // job is put into selectedJobId first and the modal reads from selectedJob.
  const openDashboardApplicantsModal = (job) => {
    setSelectedJobId(job.id);
    setSelectedWorkerId(null);
    setDashboardModal({ type: "applicants", jobId: job.id });
  };
  const openDashboardRateModal = (job, worker) => {
    setSelectedJobId(job.id);
    if (worker) {
      setSelectedWorkerId(worker);
    }
    // Start clean so a previous job's half-filled rating never carries over.
    setHouseholdReviewForm(EMPTY_HOUSEHOLD_REVIEW_FORM);
    setDashboardModal({ type: "rate", jobId: job.id });
  };
  const openDashboardReportModal = (job) => {
    setSelectedJobId(job.id);
    setShowComplaintModal(true);
  };
  const closeDashboardModal = () => setDashboardModal(null);
  // handleHireWorker reads selectedWorker from the render it was created in, so
  // firing it in the same tick as setSelectedWorkerId would hire the previously
  // selected worker. Park the id instead and let the effect below run it once
  // selectedWorker has actually caught up.
  const requestDashboardHire = (worker) => {
    setSelectedWorkerId(worker);
    setPendingHireWorkerId(worker?.id ?? null);
  };
  useEffect(() => {
    if (pendingHireWorkerId == null) {
      return;
    }
    if (String(selectedWorker?.id ?? "") !== String(pendingHireWorkerId)) {
      return;
    }
    setPendingHireWorkerId(null);
    setDashboardModal(null);
    handleHireWorker();
  }, [pendingHireWorkerId, selectedWorker?.id]);
  const handleHouseholdProfileEditSubmit = (event) => {
    if (!householdProfileEditing) {
      event.preventDefault();
      setHouseholdProfileEditing(true);
      return;
    }
    handleHouseholdProfileSave(event);
    setHouseholdProfileEditing(false);
  };

  return (
    <div className="app-shell">
      {!["home", "login", "register-worker", "register-household"].includes(view) && (
        <MobileDashboardTopbar resetKey={view} />
      )}
      <main>
        {(view === "home" || view === "login") && (
          <HomeView
            dashboardMetrics={dashboardMetrics}
            isAdminPortal={isAdminPortalPath}
            initialShowLogin={view === "login"}
            loginError={loginError}
            loginForm={loginForm}
            onLoginChange={handleLoginChange}
            onLoginSubmit={handleLoginSubmit}
            onOpenForgotPassword={openForgotPassword}
            onOpenHouseholdRegister={openHouseholdRegister}
            onOpenWorkerRegister={openWorkerRegister}
          />
        )}
        {view === "register-worker" && (
          <section className="login-section register-page py-5">
            <div className="container login-page-wrap">
              <div className="login-shell shadow-sm">
                <div className="login-topbar d-flex align-items-center px-3">
                  <span className="badge rounded-pill text-bg-light text-primary me-2">GG</span>
                  <span className="small fw-semibold">GawaGo Community Platform</span>
                </div>
                <div className="register-card mx-auto my-4">
                  <div className="register-card-head">
                    <h2 className="h5 mb-0">Register as Worker</h2>
                  </div>
                  <form className="p-3 p-md-4" onSubmit={handleWorkerRegisterSubmit}>
                    <div className="register-form-intro">
                      <h3>Register as Worker</h3>
                      <p>Set up your worker profile to start applying for jobs near you.</p>
                    </div>
                    <div className="row g-3">
                      <div className="col-12">
                        <div className="register-section-label">Personal Information</div>
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">First Name <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="text"
                          name="firstName"
                          className={`form-control${registerErrors?.firstName ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.firstName ? "true" : undefined}
                          aria-describedby={registerErrors?.firstName ? "register-error-firstName" : undefined}
                          placeholder="Juan"
                          value={workerForm.firstName}
                          onChange={handleWorkerChange}
                        />
                        {registerErrors?.firstName && (
                          <div className="invalid-feedback d-block" id="register-error-firstName">{registerErrors.firstName}</div>
                        )}
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Last Name <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="text"
                          name="lastName"
                          className={`form-control${registerErrors?.lastName ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.lastName ? "true" : undefined}
                          aria-describedby={registerErrors?.lastName ? "register-error-lastName" : undefined}
                          placeholder="dela Cruz"
                          value={workerForm.lastName}
                          onChange={handleWorkerChange}
                        />
                        {registerErrors?.lastName && (
                          <div className="invalid-feedback d-block" id="register-error-lastName">{registerErrors.lastName}</div>
                        )}
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Username <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="text"
                          name="username"
                          className={`form-control${registerErrors?.username ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.username ? "true" : undefined}
                          aria-describedby={registerErrors?.username ? "register-error-username" : undefined}
                          placeholder="juandc"
                          value={workerForm.username}
                          onChange={handleWorkerChange}
                        />
                        {registerErrors?.username && (
                          <div className="invalid-feedback d-block" id="register-error-username">{registerErrors.username}</div>
                        )}
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Email <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="email"
                          name="email"
                          className={`form-control${registerErrors?.email ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.email ? "true" : undefined}
                          aria-describedby={registerErrors?.email ? "register-error-email" : undefined}
                          placeholder="juan@email.com"
                          value={workerForm.email}
                          onChange={handleWorkerChange}
                        />
                        {registerErrors?.email && (
                          <div className="invalid-feedback d-block" id="register-error-email">{registerErrors.email}</div>
                        )}
                      </div>
                      <div className="col-12">
                        <div className="register-section-label">Contact & Location</div>
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Phone Number <span className="required-mark" aria-hidden="true">*</span></label>
                        <div className="input-group">
                          <span className="input-group-text">+63</span>
                          <input
                            type="tel"
                            name="phone"
                            className={`form-control${registerErrors?.phone ? " is-invalid" : ""}`}
                            aria-invalid={registerErrors?.phone ? "true" : undefined}
                            aria-describedby={registerErrors?.phone ? "register-error-phone" : undefined}
                            placeholder="9XXXXXXXXX"
                            inputMode="numeric"
                            maxLength={10}
                            value={workerForm.phone}
                            onChange={handleWorkerChange}
                          />
                        </div>
                        {registerErrors?.phone && (
                          <div className="invalid-feedback d-block" id="register-error-phone">{registerErrors.phone}</div>
                        )}
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Barangay <span className="required-mark" aria-hidden="true">*</span></label>
                        <select
                          name="barangay"
                          className={`form-select${registerErrors?.barangay ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.barangay ? "true" : undefined}
                          aria-describedby={registerErrors?.barangay ? "register-error-barangay" : undefined}
                          value={workerForm.barangay}
                          onChange={handleWorkerChange}
                        >
                          <option value="">--- Select Barangay ---</option>
                          {renderBarangayOptions()}
                        </select>
                        {registerErrors?.barangay && (
                          <div className="invalid-feedback d-block" id="register-error-barangay">{registerErrors.barangay}</div>
                        )}
                      </div>
                      <div className="col-12">
                        <label className="form-label fw-semibold">Street / House No. <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="text"
                          name="streetAddress"
                          className={`form-control${registerErrors?.streetAddress ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.streetAddress ? "true" : undefined}
                          aria-describedby={registerErrors?.streetAddress ? "register-error-streetAddress" : undefined}
                          placeholder="e.g. 45 Mabini St."
                          value={workerForm.streetAddress}
                          onChange={handleWorkerChange}
                        />
                        {registerErrors?.streetAddress && (
                          <div className="invalid-feedback d-block" id="register-error-streetAddress">{registerErrors.streetAddress}</div>
                        )}
                        <p className="form-text mb-0">Location coverage: Tayabas City, Quezon only.</p>
                      </div>
                      <div className="col-12">
                        <WorkerLocationPicker
                          form={workerForm}
                          setForm={setWorkerForm}
                          loadLeafletAssets={loadLeafletAssets}
                          error={workerForm.latitude == null ? registerErrors?.location : ""}
                        />
                      </div>
                      <div className="col-12">
                        <div className="register-section-label">Worker Profile</div>
                      </div>
                      <div className="col-12">
                        <label className="form-label fw-semibold">Bio / About Me</label>
                        <textarea
                          name="bio"
                          className="form-control"
                          rows="3"
                          placeholder="Tell households about yourself and your experience..."
                          value={workerForm.bio}
                          onChange={handleWorkerChange}
                        />
                      </div>
                      <div className="col-md-4">
                        <label className="form-label fw-semibold">Hourly Rate (PHP)</label>
                        <input
                          type="number"
                          min="0"
                          step="0.01"
                          name="hourlyRate"
                          className="form-control"
                          placeholder="0.00"
                          value={workerForm.hourlyRate}
                          onChange={handleWorkerChange}
                        />
                      </div>
                      <div className="col-md-4">
                        <label className="form-label fw-semibold">Daily Rate (PHP)</label>
                        <input
                          type="number"
                          min="0"
                          step="0.01"
                          name="dailyRate"
                          className="form-control"
                          placeholder="0.00"
                          value={workerForm.dailyRate}
                          onChange={handleWorkerChange}
                        />
                      </div>
                      <div className="col-md-4">
                        <label className="form-label fw-semibold">Years of Experience</label>
                        <input
                          type="number"
                          min="0"
                          name="yearsExperience"
                          className="form-control"
                          placeholder="0"
                          value={workerForm.yearsExperience}
                          onChange={handleWorkerChange}
                        />
                      </div>
                      <div className="col-12">
                        <div className="register-section-label">
                          Skills <span className="required-mark" aria-hidden="true">*</span>{" "}
                          <span>(choose up to {MAX_WORKER_SKILLS})</span>
                        </div>
                        <div
                          className={`skills-grid${registerErrors?.skills ? " is-invalid" : ""}`}
                          role="group"
                          aria-label="Skills"
                          aria-describedby={registerErrors?.skills ? "register-error-skills" : undefined}
                        >
                          {SKILLS.map((skill, index) => (
                            <label key={skill} className="form-check">
                              <input
                                type="checkbox"
                                className="form-check-input"
                                name={index === 0 ? "skills" : undefined}
                                checked={workerForm.skills.includes(skill)}
                                onChange={() => toggleSkill(skill)}
                              />
                              <span className="form-check-label">{skill === OTHER_SKILL ? "Other (type it below)" : skill}</span>
                            </label>
                          ))}
                        </div>
                        {registerErrors?.skills && (
                          <div className="invalid-feedback d-block" id="register-error-skills">{registerErrors.skills}</div>
                        )}
                      </div>
                      {workerForm.skills.includes(OTHER_SKILL) && (
                        <div className="col-12">
                          <label className="form-label fw-semibold" htmlFor="register-custom-skill">
                            Your other skill <span className="required-mark" aria-hidden="true">*</span>
                          </label>
                          <input
                            id="register-custom-skill"
                            type="text"
                            name="customSkill"
                            maxLength={120}
                            className={`form-control${registerErrors?.customSkill ? " is-invalid" : ""}`}
                            aria-invalid={registerErrors?.customSkill ? "true" : undefined}
                            aria-describedby={registerErrors?.customSkill ? "register-error-customSkill" : undefined}
                            placeholder="e.g. Masonry"
                            value={workerForm.customSkill}
                            onChange={handleWorkerChange}
                          />
                          {registerErrors?.customSkill && (
                            <div className="invalid-feedback d-block" id="register-error-customSkill">{registerErrors.customSkill}</div>
                          )}
                        </div>
                      )}
                      <div className="col-12">
                        <div className="register-section-label">Security</div>
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Password <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="password"
                          name="password"
                          className={`form-control${registerErrors?.password ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.password ? "true" : undefined}
                          aria-describedby={registerErrors?.password ? "register-error-password" : undefined}
                          placeholder="••••••••"
                          value={workerForm.password}
                          onChange={handleWorkerChange}
                        />
                        {registerErrors?.password && (
                          <div className="invalid-feedback d-block" id="register-error-password">{registerErrors.password}</div>
                        )}
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Confirm Password <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="password"
                          name="confirmPassword"
                          className={`form-control${registerErrors?.confirmPassword ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.confirmPassword ? "true" : undefined}
                          aria-describedby={registerErrors?.confirmPassword ? "register-error-confirmPassword" : undefined}
                          placeholder="••••••••"
                          value={workerForm.confirmPassword}
                          onChange={handleWorkerChange}
                        />
                        {registerErrors?.confirmPassword && (
                          <div className="invalid-feedback d-block" id="register-error-confirmPassword">{registerErrors.confirmPassword}</div>
                        )}
                      </div>
                      <div className="col-12">
                        <button type="submit" className="btn btn-primary w-100">
                          {" "}
                          Create Worker Account{" "}
                        </button>
                      </div>
                    </div>
                  </form>
                  <div className="login-card-foot text-center p-3">
                    <p className="small mb-0">
                      {" "}
                      Already have an account?{" "}
                      <button type="button" className="btn btn-link btn-sm align-baseline p-0" onClick={openLogin}>
                        Login here
                      </button>
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </section>
        )}
        {view === "register-household" && (
          <section className="login-section register-page py-5">
            <div className="container login-page-wrap">
              <div className="login-shell shadow-sm">
                <div className="login-topbar d-flex align-items-center px-3">
                  <span className="badge rounded-pill text-bg-light text-primary me-2">GG</span>
                  <span className="small fw-semibold">GawaGo Community Platform</span>
                </div>
                <div className="register-card register-card-sm mx-auto my-4">
                  <div className="register-card-head">
                    <h2 className="h5 mb-0">Register as Household</h2>
                  </div>
                  <form className="p-3 p-md-4" onSubmit={handleHouseholdRegisterSubmit}>
                    <div className="register-form-intro">
                      <h3>Register as Household</h3>
                      <p>Create your account to start finding trusted workers near you.</p>
                    </div>
                    <div className="row g-3">
                      <div className="col-12">
                        <div className="register-section-label">Personal Information</div>
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">First Name <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="text"
                          name="firstName"
                          className={`form-control${registerErrors?.firstName ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.firstName ? "true" : undefined}
                          aria-describedby={registerErrors?.firstName ? "register-error-firstName" : undefined}
                          placeholder="Juan"
                          value={householdForm.firstName}
                          onChange={handleHouseholdChange}
                        />
                        {registerErrors?.firstName && (
                          <div className="invalid-feedback d-block" id="register-error-firstName">{registerErrors.firstName}</div>
                        )}
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Last Name <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="text"
                          name="lastName"
                          className={`form-control${registerErrors?.lastName ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.lastName ? "true" : undefined}
                          aria-describedby={registerErrors?.lastName ? "register-error-lastName" : undefined}
                          placeholder="dela Cruz"
                          value={householdForm.lastName}
                          onChange={handleHouseholdChange}
                        />
                        {registerErrors?.lastName && (
                          <div className="invalid-feedback d-block" id="register-error-lastName">{registerErrors.lastName}</div>
                        )}
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Username <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="text"
                          name="username"
                          className={`form-control${registerErrors?.username ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.username ? "true" : undefined}
                          aria-describedby={registerErrors?.username ? "register-error-username" : undefined}
                          placeholder="juandc"
                          value={householdForm.username}
                          onChange={handleHouseholdChange}
                        />
                        {registerErrors?.username && (
                          <div className="invalid-feedback d-block" id="register-error-username">{registerErrors.username}</div>
                        )}
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Email <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="email"
                          name="email"
                          className={`form-control${registerErrors?.email ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.email ? "true" : undefined}
                          aria-describedby={registerErrors?.email ? "register-error-email" : undefined}
                          placeholder="juan@email.com"
                          value={householdForm.email}
                          onChange={handleHouseholdChange}
                        />
                        {registerErrors?.email && (
                          <div className="invalid-feedback d-block" id="register-error-email">{registerErrors.email}</div>
                        )}
                      </div>
                      <div className="col-12">
                        <div className="register-section-label">Contact & Location</div>
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Phone Number <span className="required-mark" aria-hidden="true">*</span></label>
                        <div className="input-group">
                          <span className="input-group-text">+63</span>
                          <input
                            type="tel"
                            name="phone"
                            className={`form-control${registerErrors?.phone ? " is-invalid" : ""}`}
                            aria-invalid={registerErrors?.phone ? "true" : undefined}
                            aria-describedby={registerErrors?.phone ? "register-error-phone" : undefined}
                            placeholder="9XXXXXXXXX"
                            inputMode="numeric"
                            maxLength={10}
                            value={householdForm.phone}
                            onChange={handleHouseholdChange}
                          />
                        </div>
                        {registerErrors?.phone && (
                          <div className="invalid-feedback d-block" id="register-error-phone">{registerErrors.phone}</div>
                        )}
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Barangay <span className="required-mark" aria-hidden="true">*</span></label>
                        <select
                          name="barangay"
                          className={`form-select${registerErrors?.barangay ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.barangay ? "true" : undefined}
                          aria-describedby={registerErrors?.barangay ? "register-error-barangay" : undefined}
                          value={householdForm.barangay}
                          onChange={handleHouseholdChange}
                        >
                          <option value="">--- Select Barangay ---</option>
                          {renderBarangayOptions()}
                        </select>
                        {registerErrors?.barangay && (
                          <div className="invalid-feedback d-block" id="register-error-barangay">{registerErrors.barangay}</div>
                        )}
                      </div>
                      <div className="col-12">
                        <label className="form-label fw-semibold">Street / House No. <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="text"
                          name="streetAddress"
                          className={`form-control${registerErrors?.streetAddress ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.streetAddress ? "true" : undefined}
                          aria-describedby={registerErrors?.streetAddress ? "register-error-streetAddress" : undefined}
                          placeholder="e.g. 45 Mabini St."
                          value={householdForm.streetAddress}
                          onChange={handleHouseholdChange}
                        />
                        {registerErrors?.streetAddress && (
                          <div className="invalid-feedback d-block" id="register-error-streetAddress">{registerErrors.streetAddress}</div>
                        )}
                        <p className="form-text mb-0">Location coverage: Tayabas City, Quezon only.</p>
                      </div>
                      <div className="col-12">
                        <div className="register-section-label">Security</div>
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Password <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="password"
                          name="password"
                          className={`form-control${registerErrors?.password ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.password ? "true" : undefined}
                          aria-describedby={registerErrors?.password ? "register-error-password" : undefined}
                          placeholder="••••••••"
                          value={householdForm.password}
                          onChange={handleHouseholdChange}
                        />
                        {registerErrors?.password && (
                          <div className="invalid-feedback d-block" id="register-error-password">{registerErrors.password}</div>
                        )}
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Confirm Password <span className="required-mark" aria-hidden="true">*</span></label>
                        <input
                          type="password"
                          name="confirmPassword"
                          className={`form-control${registerErrors?.confirmPassword ? " is-invalid" : ""}`}
                          aria-invalid={registerErrors?.confirmPassword ? "true" : undefined}
                          aria-describedby={registerErrors?.confirmPassword ? "register-error-confirmPassword" : undefined}
                          placeholder="••••••••"
                          value={householdForm.confirmPassword}
                          onChange={handleHouseholdChange}
                        />
                        {registerErrors?.confirmPassword && (
                          <div className="invalid-feedback d-block" id="register-error-confirmPassword">{registerErrors.confirmPassword}</div>
                        )}
                      </div>
                      <div className="col-12">
                        <button type="submit" className="btn btn-primary w-100">
                          {" "}
                          Create Household Account{" "}
                        </button>
                      </div>
                    </div>
                  </form>
                  <div className="login-card-foot text-center p-3">
                    <p className="small mb-0">
                      {" "}
                      Already have an account?{" "}
                      <button type="button" className="btn btn-link btn-sm align-baseline p-0" onClick={openLogin}>
                        Login here
                      </button>
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </section>
        )}
        {view === "worker-dashboard" && (
          <section className="worker-dashboard worker-dashboard-home">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item active">{navIcon("dashboard")}
                    <span>Dashboard</span></button>
                  <button className="worker-nav-item" onClick={openAllWorkerFindJobs}>
                    {navIcon("search")}
                    <span>Find Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerApplications}>
                    {navIcon("applications")}
                    <span>My Applications</span>
                    {workerApplicationUnreadCount > 0 && (
                      <span className="nav-count-badge">{workerApplicationUnreadCount}</span>
                    )}
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openWorkerGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                    {workerUnreadCount > 0 && <span className="nav-count-badge">{workerUnreadCount}</span>}
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <div className="worker-dashboard-welcome-strip">
                  Welcome, {currentUser?.displayName || "Worker"}
                </div>

                <div className="worker-dashboard-stats">
                  <div className="metric-card">
                    <p className="metric-label mb-1">Open Jobs</p>
                    <p className="metric-value mb-0">{workerVisibleJobs.length}</p>
                  </div>
                  <div className="metric-card">
                    <p className="metric-label mb-1">Skill Matches</p>
                    <p className="metric-value mb-0">{workerMatchedJobs.length}</p>
                  </div>
                  <div className="metric-card">
                    <p className="metric-label mb-1">Your Rating</p>
                    <p className="metric-value worker-rating-value mb-0">{currentWorker?.rating || "No ratings yet"}</p>
                  </div>
                  <div className="metric-card">
                    <p className="metric-label mb-1">Verification</p>
                    <span
                      className={`badge ${currentWorker?.verification === "Verified" ? "text-bg-success" : "text-bg-warning"}`}
                    >
                      {currentWorker?.verification || "Pending"}
                    </span>
                  </div>
                </div>

                <section className={`worker-market-panel ${workerMarketExpanded ? "is-expanded" : ""}`}>
                  <div className="worker-market-head">
                    <h2>Job Market Overview</h2>
                    <input
                      className="form-control worker-market-search"
                      type="search"
                      placeholder="Search work category..."
                      value={workerMarketSearch}
                      onChange={(event) => setWorkerMarketSearch(event.target.value)}
                    />
                  </div>
                  <div className="worker-market-grid">
                    {workerMarketList.categories.length > 0 ? (
                      workerMarketList.categories.map((category) => (
                      <article
                        className={`worker-market-card ${category.matchesWorkerSkills ? "worker-market-card-match" : ""} ${
                          category.folded ? "worker-market-card-folded" : ""
                        }`}
                        key={category.serviceType}
                      >
                        <div>
                          <h3>{category.serviceType}</h3>
                          <p>
                            {category.openJobs} open {category.openJobs === 1 ? "job" : "jobs"}
                          </p>
                        </div>
                        <div className="worker-market-card-actions">
                          <span className={`badge ${category.matchesWorkerSkills ? "worker-skill-match" : "worker-skill-neutral"}`}>
                            {category.matchesWorkerSkills ? "Matches your skills" : "Does not match skills"}
                          </span>
                          <button
                            className="btn btn-outline-secondary btn-sm"
                            type="button"
                            onClick={() => openWorkerFindJobsForCategory(category.serviceType)}
                          >
                            View All
                          </button>
                        </div>
                      </article>
                      ))
                    ) : (
                      <article className="worker-market-card worker-market-empty">
                        <div>
                          <h3>No categories found</h3>
                          <p>Try searching another work category.</p>
                        </div>
                      </article>
                    )}
                  </div>
                  {workerMarketList.foldedCount > 0 && (
                    <button
                      className="worker-market-toggle"
                      type="button"
                      aria-expanded={workerMarketExpanded}
                      onClick={() => setWorkerMarketExpanded((expanded) => !expanded)}
                    >
                      {workerMarketExpanded
                        ? "Show fewer categories"
                        : `Show ${workerMarketList.foldedCount} more ${
                            workerMarketList.foldedCount === 1 ? "category" : "categories"
                          }`}
                    </button>
                  )}
                </section>
              </div>
            </div>
          </section>
        )}
        {view === "worker-find-jobs" && (
          <section className="worker-dashboard">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openWorkerDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item active">{navIcon("search")}
                    <span>Find Jobs</span></button>
                  <button className="worker-nav-item" onClick={openWorkerProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerApplications}>
                    {navIcon("applications")}
                    <span>My Applications</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openWorkerGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                    {workerUnreadCount > 0 && <span className="nav-count-badge">{workerUnreadCount}</span>}
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                {aiModeActive && !aiRecommendationsLoading ? (
                  <div className="worker-topbar d-flex justify-content-between align-items-center flex-wrap gap-2">
                    <h1 className="h4 mb-0">
                      {" "}
                      AI Recommended Jobs{" "}
                      <span className="badge text-bg-primary">{(aiRecommendedJobs || []).length}</span>
                    </h1>
                    <button className="btn btn-outline-secondary btn-sm" type="button" onClick={exitAiJobRecommendations}>
                      Back to Browsing
                    </button>
                  </div>
                ) : (
                  <div className="worker-ai-hero">
                    <div className="worker-ai-hero-decor worker-ai-hero-decor-1" />
                    <div className="worker-ai-hero-decor worker-ai-hero-decor-2" />
                    <div className="worker-ai-hero-inner">
                      <div className="worker-ai-hero-top">
                        <div className="worker-ai-hero-left">
                          <div className="worker-ai-hero-eyebrow">FIND JOBS</div>
                          <h1 className="worker-ai-hero-title">Let AI find your next job</h1>
                          <p className="worker-ai-hero-desc">
                            We match open jobs near you to your skills, so you spend less time scrolling and more time earning.
                          </p>
                        </div>
                        <div className="worker-ai-hero-stat">
                          <div className="worker-ai-hero-stat-num">{filteredWorkerVisibleJobs.length}</div>
                          <div className="worker-ai-hero-stat-label">
                            {filteredWorkerVisibleJobs.length === 1 ? "open job nearby" : "open jobs nearby"}
                          </div>
                        </div>
                      </div>
                      {aiRecommendationsLoading ? (
                        <div className="worker-ai-scan-wrap">
                          <div className="worker-ai-scan-stage">
                            {scatterTags.map((tag) => (
                              <span
                                key={tag.id}
                                className="worker-ai-scan-tag"
                                style={{
                                  left: `${tag.left}%`,
                                  top: `${tag.top}%`,
                                  transform: `rotate(${tag.rotate}deg)`,
                                }}
                              >
                                {tag.label}
                              </span>
                            ))}
                          </div>
                          <p className="worker-ai-scan-status">{AI_SCAN_STATUS_PHASES[scatterStatusIndex]}</p>
                        </div>
                      ) : (
                        <div className="worker-ai-hero-bottom">
                          <button className="worker-ai-find-btn" type="button" onClick={runAiJobRecommendations}>
                            <span className="worker-ai-find-btn-icon">✨</span>
                            Find Jobs for Me
                          </button>
                          <span className="worker-ai-manual-link">or browse manually below</span>
                        </div>
                      )}
                    </div>
                  </div>
                )}
                {!aiModeActive && (
                  <div className="jobs-filter-panel mt-3">
                    <div className="row g-2 align-items-end">
                      <div className="col-md-4">
                        <label className="form-label fw-semibold mb-1">Filter by Job Type</label>
                        <select
                          className="form-select"
                          value={workerJobTypeFilter}
                          onChange={(event) => setWorkerJobTypeFilter(event.target.value)}
                        >
                          <option>All Types</option>
                          {workerMarketCategories.map((category) => (
                            <option key={category.serviceType}>{category.serviceType}</option>
                          ))}
                        </select>
                      </div>
                      <div className="col-md-4">
                        <label className="form-label fw-semibold mb-1">Barangay</label>
                        <input
                          className="form-control"
                          placeholder="e.g. Lita"
                          value={workerBarangayFilter}
                          onChange={(event) => setWorkerBarangayFilter(event.target.value)}
                        />
                      </div>
                      <div className="col-md-2">
                        {/* Filters apply as you type; this resets them. A
                            "Filter" button here used to do nothing at all. */}
                        <button
                          className="btn btn-outline-secondary w-100"
                          type="button"
                          disabled={workerJobTypeFilter === "All Types" && !workerBarangayFilter.trim()}
                          onClick={() => {
                            setWorkerJobTypeFilter("All Types");
                            setWorkerBarangayFilter("");
                          }}
                        >
                          Clear
                        </button>
                      </div>
                    </div>
                  </div>
                )}
                {aiModeActive && !aiRecommendationsLoading ? (
                  <p className="small worker-skill-hint fw-semibold mt-3 mb-2">
                    Ranked for you by skill match and distance. Higher score = better fit.
                  </p>
                ) : !aiModeActive ? (
                  <div className="worker-find-jobs-viewbar mt-3 mb-2">
                    <p className="small worker-skill-hint fw-semibold mb-0">
                      {workerFindJobsView === "map"
                        ? "Every household with an open job is pinned, near or far. Tap a pin to see who's hiring."
                        : "Green labels match your skills. Neutral labels are other available jobs."}
                    </p>
                    <div className="worker-find-jobs-toggle" role="group" aria-label="Job view">
                      {[
                        ["list", "List View"],
                        ["map", "Map View"],
                      ].map(([value, label]) => (
                        <button
                          key={value}
                          type="button"
                          className={workerFindJobsView === value ? "active" : ""}
                          aria-pressed={workerFindJobsView === value}
                          onClick={() => setWorkerFindJobsView(value)}
                        >
                          {label}
                        </button>
                      ))}
                    </div>
                  </div>
                ) : null}
                {aiModeActive && !aiRecommendationsLoading && aiRecommendationsError && (
                  <div className="alert alert-warning py-2 small mb-2">{aiRecommendationsError}</div>
                )}
                {!aiModeActive && !aiRecommendationsLoading && workerFindJobsView === "map" && (
                  <WorkerJobsMap
                    jobs={filteredWorkerVisibleJobs}
                    worker={currentWorker}
                    getDistanceLabel={getWorkerJobDistanceLabel}
                    onViewDetails={openWorkerJobDetail}
                    onApply={handleApplyToJob}
                  />
                )}
                {!aiRecommendationsLoading && (aiModeActive || workerFindJobsView === "list") && (
                <div className="row g-3">
                  {(aiModeActive ? aiRecommendedJobs || [] : filteredWorkerVisibleJobs).length > 0 ? (
                    (aiModeActive ? aiRecommendedJobs : filteredWorkerVisibleJobs).map((job) => (
                      <div className="col-lg-6" key={job.id}>
                        <article className="worker-jobcard">
                          <div className="worker-jobcard-head">
                            <div className="worker-jobcard-head-top">
                              {job.householdVerificationStatus === "verified" ? (
                                <span className="worker-jobcard-verified">✓ Verified</span>
                              ) : (
                                <span />
                              )}
                              {aiModeActive ? (
                                <span className="worker-jobcard-pill is-match">
                                  {Math.round((job.aiScore || 0) * 100)}% match
                                </span>
                              ) : (
                                <span
                                  className={`worker-jobcard-pill ${job.matchesSkill ? "is-match" : "is-other"}`}
                                >
                                  {job.matchesSkill ? "Matches Skills" : "Other Job"}
                                </span>
                              )}
                            </div>
                            <div className="worker-jobcard-monogram">
                              {getHouseholdInitials(job.householdName)}
                            </div>
                            <div className="worker-jobcard-household">{job.householdName}</div>
                          </div>
                          <div className="worker-jobcard-body">
                            <div className="worker-jobcard-title-row">
                              <h2 className="worker-jobcard-title">{job.jobTitle || job.serviceType}</h2>
                              <p className="worker-jobcard-rate">
                                <strong>{formatCurrency(job.offeredRate)}</strong>
                                <span>/{(job.rateType || "Per Day").toLowerCase()}</span>
                              </p>
                            </div>
                            <p className="worker-jobcard-location">
                              {formatLocation(job.barangay, job.streetAddress)}
                            </p>
                            <p className="worker-jobcard-when">
                              <span aria-hidden="true">🗓</span>
                              <span>{formatJobDate(job.jobStartDate) || "Schedule not set"}</span>
                              {getWorkerJobDistanceLabel(job) && (
                                <span className="worker-jobcard-distance">
                                  · {getWorkerJobDistanceLabel(job)}
                                </span>
                              )}
                            </p>
                            {aiModeActive && renderAiMatchBreakdown(job)}
                            <div className="worker-jobcard-chips">
                              {job.serviceType && (
                                <span
                                  className={`worker-jobcard-chip ${
                                    job.matchesSkill || job.aiExactSkillMatch ? "is-match" : ""
                                  }`}
                                >
                                  {job.serviceType}
                                </span>
                              )}
                              {job.scheduleType && (
                                <span className="worker-jobcard-chip">
                                  {formatScheduleLabel(job.scheduleType)}
                                </span>
                              )}
                            </div>
                            {(job.jobStartDate || job.jobEndDate) && (
                              <p className="worker-jobcard-period">
                                {formatJobDate(job.jobStartDate) || "Not set"}
                                {job.jobEndDate ? ` to ${formatJobDate(job.jobEndDate)}` : ""}
                                {job.estimatedWorkingDays
                                  ? ` (${job.estimatedWorkingDays} working day${Number(job.estimatedWorkingDays) === 1 ? "" : "s"})`
                                  : ""}
                              </p>
                            )}
                            <div className="worker-jobcard-actions">
                              <button
                                className="worker-jobcard-btn is-ghost"
                                type="button"
                                onClick={() => openWorkerJobDetail(job.id)}
                              >
                                View Details
                              </button>
                              <button
                                className="worker-jobcard-btn is-primary"
                                type="button"
                                disabled={!job.canApply}
                                onClick={() => handleApplyToJob(job.id)}
                              >
                                {job.canApply ? "Apply Now" : "Applied"}
                              </button>
                            </div>
                            {!job.canApply && !job.applicationStatus && (
                              <p className="worker-jobcard-note">
                                Applications are unavailable for this job right now.
                              </p>
                            )}
                          </div>
                        </article>
                      </div>
                    ))
                  ) : (
                    <div className="col-12">
                      <div className="profile-card">
                        <div className="p-4 text-center text-muted">
                          {" "}
                          {aiModeActive
                            ? "No matching jobs found within your job radius right now."
                            : workerJobTypeFilter === "All Types"
                              ? "There are no household job posts available right now."
                              : `Wala pang household job posts para sa ${workerJobTypeFilter}.`}{" "}
                        </div>
                      </div>
                    </div>
                  )}
                </div>
                )}
              </div>
            </div>
          </section>
        )}

        {view === "worker-profile" && workerProfilePanel === "feedback" && (
          <section className="worker-dashboard household-feedback-all-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openWorkerDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openAllWorkerFindJobs}>
                    {navIcon("search")}
                    <span>Find Jobs</span>
                  </button>
                  <button className="worker-nav-item active" onClick={() => setWorkerProfilePanel("profile")}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerApplications}>
                    {navIcon("applications")}
                    <span>My Applications</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openWorkerGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <main className="household-feedback-all-container">
                  <section className="household-feedback-hero">
                    <div>
                      <h1>All Feedback & Ratings by Households</h1>
                      <p>Household ratings and comments about your completed services.</p>
                    </div>
                    <button
                      className="btn btn-outline-secondary btn-sm"
                      type="button"
                      onClick={() => setWorkerProfilePanel("profile")}
                    >
                      Back
                    </button>
                  </section>

                  <section className="household-feedback-list-panel" aria-label="All household feedback and ratings">
                    <div className="household-feedback-filter">
                      <label className="form-label mb-0" htmlFor="worker-feedback-date">
                        Filter Date
                      </label>
                      <input
                        id="worker-feedback-date"
                        type="date"
                        className="form-control"
                        value={workerFeedbackDateFilter}
                        onChange={(event) => setWorkerFeedbackDateFilter(event.target.value)}
                      />
                      {workerFeedbackDateFilter && (
                        <button
                          className="btn btn-outline-secondary btn-sm"
                          type="button"
                          onClick={() => setWorkerFeedbackDateFilter("")}
                        >
                          Clear
                        </button>
                      )}
                    </div>

                    <div className="household-feedback-list">
                      {filteredWorkerHouseholdFeedback.length > 0 ? (
                        filteredWorkerHouseholdFeedback.map((review, index) => {
                          const authorName = review.authorName || review.author || "Household";
                          const initial = authorName.slice(0, 1).toUpperCase() || "H";
                          const draftKey = review.id || `${review.authorUsername}-${review.createdAt}`;
                          const replySent = hasSentHouseholdFeedbackForReview(review);
                          return (
                            <article className="household-feedback-item" key={review.id || `${review.createdAt}-${index}`}>
                              <div className="household-feedback-avatar">{initial}</div>
                              <div className="household-feedback-copy">
                                <div className="household-review-title-row">
                                  <h2>{authorName}</h2>
                                  {review.overallRating != null && <strong>{Number(review.overallRating).toFixed(1)}/5</strong>}
                                  {review.rating != null && review.overallRating == null && <strong>{Number(review.rating).toFixed(1)}/5</strong>}
                                </div>
                                {(review.qualityOfWork || review.punctuality || review.communication || review.professionalism) && (
                                  <div style={{ fontSize: "0.9em", marginBottom: "0.5rem" }}>
                                    <div style={{ display: "flex", gap: "1rem", flexWrap: "wrap", marginBottom: "0.25rem" }}>
                                      {review.qualityOfWork && <span>Quality: <strong>{review.qualityOfWork}⭐</strong></span>}
                                      {review.punctuality && <span>Punctuality: <strong>{review.punctuality}⭐</strong></span>}
                                    </div>
                                    <div style={{ display: "flex", gap: "1rem", flexWrap: "wrap" }}>
                                      {review.communication && <span>Communication: <strong>{review.communication}⭐</strong></span>}
                                      {review.professionalism && <span>Professionalism: <strong>{review.professionalism}⭐</strong></span>}
                                    </div>
                                  </div>
                                )}
                                <p>{review.feedback || review.comment || "No comment provided."}</p>
                                <small>{formatDateTime(review.createdAt || review.date)}</small>
                                {replySent ? (
                                  <p className="small text-muted mb-0 mt-2">Anonymous feedback already sent to household.</p>
                                ) : (
                                  <form
                                    className="d-grid gap-2 mt-3"
                                    onSubmit={(event) => submitHouseholdFeedbackReply(event, review)}
                                  >
                                    <label className="form-label fw-semibold mb-0" htmlFor={`worker-rating-${draftKey}`}>
                                      Rate household
                                    </label>
                                    <select
                                      className="form-select"
                                      id={`worker-rating-${draftKey}`}
                                      value={
                                        typeof workerHouseholdReplyDrafts[draftKey] === "object"
                                          ? workerHouseholdReplyDrafts[draftKey]?.rating || "5"
                                          : "5"
                                      }
                                      onChange={(event) =>
                                        setWorkerHouseholdReplyDrafts((prev) => ({
                                          ...prev,
                                          [draftKey]: {
                                            ...(typeof prev[draftKey] === "object" ? prev[draftKey] : { feedback: prev[draftKey] || "" }),
                                            rating: event.target.value,
                                          },
                                        }))
                                      }
                                    >
                                      <option value="5">5 stars</option>
                                      <option value="4">4 stars</option>
                                      <option value="3">3 stars</option>
                                      <option value="2">2 stars</option>
                                      <option value="1">1 star</option>
                                    </select>
                                    <label className="form-label fw-semibold mb-0" htmlFor={`worker-reply-${draftKey}`}>
                                      Send feedback to household
                                    </label>
                                    <textarea
                                      className="form-control"
                                      id={`worker-reply-${draftKey}`}
                                      rows="3"
                                      placeholder="Write feedback for the household..."
                                      value={
                                        typeof workerHouseholdReplyDrafts[draftKey] === "object"
                                          ? workerHouseholdReplyDrafts[draftKey]?.feedback || ""
                                          : workerHouseholdReplyDrafts[draftKey] || ""
                                      }
                                      onChange={(event) =>
                                        setWorkerHouseholdReplyDrafts((prev) => ({
                                          ...prev,
                                          [draftKey]: {
                                            ...(typeof prev[draftKey] === "object" ? prev[draftKey] : { rating: "5" }),
                                            feedback: event.target.value,
                                          },
                                        }))
                                      }
                                    />
                                    <button className="btn btn-primary btn-sm justify-self-start" type="submit">
                                      Send Feedback
                                    </button>
                                  </form>
                                )}
                              </div>
                            </article>
                          );
                        })
                      ) : (
                        <article className="household-feedback-empty">
                          <h2>No feedback or ratings found</h2>
                          <p>
                            {workerFeedbackDateFilter
                              ? "No household feedback or ratings match the selected date."
                              : "No household feedback or ratings have been submitted for this worker yet."}
                          </p>
                        </article>
                      )}
                    </div>
                  </section>
                </main>
              </div>
            </div>
          </section>
        )}
        {view === "worker-profile" && workerProfilePanel === "ratings" && (
          <section className="worker-dashboard household-feedback-all-page household-reviews-all-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openWorkerDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openAllWorkerFindJobs}>
                    {navIcon("search")}
                    <span>Find Jobs</span>
                  </button>
                  <button className="worker-nav-item active" onClick={() => setWorkerProfilePanel("profile")}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerApplications}>
                    {navIcon("applications")}
                    <span>My Applications</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openWorkerGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <main className="household-feedback-all-container">
                  <section className="household-feedback-hero">
                    <div>
                      <h1>All Ratings by Households</h1>
                      <p>Rating history from households after completed jobs.</p>
                    </div>
                    <button
                      className="btn btn-outline-secondary btn-sm"
                      type="button"
                      onClick={() => setWorkerProfilePanel("profile")}
                    >
                      Back
                    </button>
                  </section>

                  <section className="household-feedback-list-panel" aria-label="All household ratings">
                    <div className="household-feedback-filter">
                      <label className="form-label mb-0" htmlFor="worker-rating-date">
                        Filter Date
                      </label>
                      <input
                        id="worker-rating-date"
                        type="date"
                        className="form-control"
                        value={workerRatingDateFilter}
                        onChange={(event) => setWorkerRatingDateFilter(event.target.value)}
                      />
                      {workerRatingDateFilter && (
                        <button
                          className="btn btn-outline-secondary btn-sm"
                          type="button"
                          onClick={() => setWorkerRatingDateFilter("")}
                        >
                          Clear
                        </button>
                      )}
                    </div>

                    <div className="household-feedback-list">
                      {filteredWorkerHouseholdRatings.length > 0 ? (
                        filteredWorkerHouseholdRatings.map((review, index) => {
                          const authorName = review.authorName || review.author || "Household";
                          const initial = authorName.slice(0, 1).toUpperCase() || "H";
                          return (
                            <article className="household-feedback-item" key={review.id || `${review.createdAt}-${index}`}>
                              <div className="household-feedback-avatar">{initial}</div>
                              <div className="household-feedback-copy">
                                <div className="household-review-title-row">
                                  <h2>{authorName}</h2>
                                  <strong>{reviewScore(review) != null ? `${reviewScore(review).toFixed(1)}/5` : "No rating"}</strong>
                                </div>
                                <p>{review.feedback || review.comment || "No comment provided."}</p>
                                <small>{formatDateTime(review.createdAt || review.date)}</small>
                                <details className="household-feedback-more">
                                  <summary>View more</summary>
                                  <p>This rating came from a household after a completed service.</p>
                                </details>
                              </div>
                            </article>
                          );
                        })
                      ) : (
                        <article className="household-feedback-empty">
                          <h2>No ratings found</h2>
                          <p>
                            {workerRatingDateFilter
                              ? "No household ratings match the selected date."
                              : "No household ratings have been submitted for this worker yet."}
                          </p>
                        </article>
                      )}
                    </div>
                  </section>
                </main>
              </div>
            </div>
          </section>
        )}
        {view === "worker-profile" && workerProfilePanel === "profile" && (
          <section className="worker-dashboard profile-page household-profile-page worker-profile-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openWorkerDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openAllWorkerFindJobs}>
                    {navIcon("search")}
                    <span>Find Jobs</span>
                  </button>
                  <button className="worker-nav-item active">{navIcon("profile")}
                    <span>My Profile</span></button>
                  <button className="worker-nav-item" onClick={openWorkerApplications}>
                    {navIcon("applications")}
                    <span>My Applications</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openWorkerGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <div className="row g-3">
                  <div className="col-lg-4">
                    <div className="profile-card">
                      <div className="profile-card-head">My Profile</div>
                      <div className="p-4 text-center">
                        {workerMiniPhoto ? (
                          <button
                            className="profile-photo-preview-trigger"
                            type="button"
                            onClick={() => setWorkerPhotoModalOpen(true)}
                            aria-label="View profile photo"
                          >
                            <img src={workerMiniPhoto} alt="Worker profile" className="profile-photo-large mb-2" />
                          </button>
                        ) : (
                          <div className="profile-avatar mb-2">
                            {(workerProfileForm.firstName || "W").slice(0, 1).toUpperCase()}
                          </div>
                        )}
                        <h2 className="h5 mb-1">
                          {getDisplayName(
                            workerProfileForm.firstName,
                            workerProfileForm.lastName,
                            workerProfileForm.username,
                          )}
                        </h2>
                        <p className="text-muted mb-2">@{workerProfileForm.username || "worker"}</p>
                        <span className="badge text-bg-primary">Worker</span>
                      </div>
                      <div className="px-4 pb-4">
                        <p className="mb-1 small">
                          <strong>Barangay:</strong> {workerProfileForm.barangay || "Not set"}
                        </p>
                        <p className="mb-1 small">
                          <strong>Phone:</strong> {workerProfileForm.phone || "Not set"}
                        </p>
                        <p className="mb-2 small">
                          <strong>Email:</strong> {workerProfileForm.email || "Not set"}
                        </p>
                        <hr className="my-2" />
                        <p className="mb-1 small">
                          <strong>Verification:</strong>
                          <span
                            className={`badge ${currentWorker?.verification === "Verified" ? "text-bg-success" : "text-bg-warning"}`}
                          >
                            {currentWorker?.verification || "Pending"}
                          </span>
                        </p>
                        <p className="mb-1 small">
                          <strong>Rating:</strong> {currentWorker?.rating || "No ratings yet"}
                        </p>
                        <p className="mb-1 small">
                          <strong>Jobs Done:</strong> {currentWorker?.reviewsDone || 0}
                        </p>
                        <p className="mb-1 small">
                          <strong>Hourly Rate:</strong> {formatWorkerRate(workerProfileForm.hourlyRate)}
                        </p>
                        <p className="mb-2 small">
                          <strong>Daily Rate:</strong> {formatWorkerRate(workerProfileForm.dailyRate)}
                        </p>
                        <div className="d-flex gap-1 flex-wrap">
                          {(workerProfileForm.skills || []).length === 0 ? (
                            <span className="badge text-bg-secondary">No skills selected yet</span>
                          ) : (
                            workerProfileForm.skills.map((skill) => (
                              <span key={skill} className="badge text-bg-primary">
                                {skill}
                              </span>
                            ))
                          )}
                        </div>
                      </div>
                    </div>
                  </div>
                  <div className="col-lg-8">
                    <div className="profile-card">
                      <div className="profile-card-head">
                        <span>Edit Profile Information</span>
                      </div>
                      <form className="p-3" onSubmit={submitWorkerProfileForm}>
                        <fieldset disabled={!workerProfileEditing} className="worker-profile-edit-fieldset">
                          <h3 className="h6 fw-bold mb-2">Profile Photo</h3>
                          <div className="mb-3">
                            <input
                              type="file"
                              className="form-control"
                              name="profilePhoto"
                              accept="image/*"
                              onChange={handleWorkerProfileChange}
                            />
                            <p className="form-text mb-0">Accepted: JPG, PNG. Clear face photo recommended.</p>
                          </div>
                          <h3 className="h6 fw-bold mb-2">Personal Information</h3>
                          <div className="row g-2 mb-3">
                            <div className="col-md-6">
                              <label className="form-label small fw-semibold mb-1">First Name</label>
                              <input
                                name="firstName"
                                className="form-control"
                                value={workerProfileForm.firstName}
                                onChange={handleWorkerProfileChange}
                              />
                            </div>
                            <div className="col-md-6">
                              <label className="form-label small fw-semibold mb-1">Last Name</label>
                              <input
                                name="lastName"
                                className="form-control"
                                value={workerProfileForm.lastName}
                                onChange={handleWorkerProfileChange}
                              />
                            </div>
                            <div className="col-md-6">
                              <label className="form-label small fw-semibold mb-1">Email</label>
                              <input
                                type="email"
                                name="email"
                                className="form-control"
                                value={workerProfileForm.email}
                                onChange={handleWorkerProfileChange}
                              />
                            </div>
                            <div className="col-md-6">
                              <label className="form-label small fw-semibold mb-1">Phone Number</label>
                              <input
                                name="phone"
                                className="form-control"
                                value={workerProfileForm.phone}
                                onChange={handleWorkerProfileChange}
                              />
                            </div>
                            <div className="col-md-6">
                              <label className="form-label small fw-semibold mb-1">Barangay</label>
                              <select
                                name="barangay"
                                className="form-select"
                                value={workerProfileForm.barangay}
                                onChange={handleWorkerProfileChange}
                              >
                                <option value="">---Select Barangay---</option>
                                {renderBarangayOptions()}
                              </select>
                            </div>
                            <div className="col-md-6">
                              <label className="form-label small fw-semibold mb-1">Street / House No.</label>
                              <input
                                name="streetAddress"
                                className="form-control"
                                value={workerProfileForm.streetAddress}
                                onChange={handleWorkerProfileChange}
                              />
                            </div>
                            <div className="col-12">
                              <WorkerLocationPicker
                                form={workerProfileForm}
                                setForm={setWorkerProfileForm}
                                loadLeafletAssets={loadLeafletAssets}
                                compact
                              />
                            </div>
                          </div>
                          <h3 className="h6 fw-bold mb-2">Service Rates</h3>
                          <p className="form-text mt-0 mb-2">
                            Households see these before hiring. Give at least one; leave the other blank if you
                            don't charge that way.
                          </p>
                          <div className="row g-2 mb-3">
                            <div className="col-md-6">
                              <label className="form-label small fw-semibold mb-1" htmlFor="worker-profile-hourly-rate">
                                Hourly Rate (PHP)
                              </label>
                              <input
                                id="worker-profile-hourly-rate"
                                type="number"
                                min="0"
                                step="0.01"
                                name="hourlyRate"
                                className="form-control"
                                placeholder="Not disclosed"
                                value={workerProfileForm.hourlyRate ?? ""}
                                onChange={handleWorkerProfileChange}
                              />
                            </div>
                            <div className="col-md-6">
                              <label className="form-label small fw-semibold mb-1" htmlFor="worker-profile-daily-rate">
                                Daily Rate (PHP)
                              </label>
                              <input
                                id="worker-profile-daily-rate"
                                type="number"
                                min="0"
                                step="0.01"
                                name="dailyRate"
                                className="form-control"
                                placeholder="Not disclosed"
                                value={workerProfileForm.dailyRate ?? ""}
                                onChange={handleWorkerProfileChange}
                              />
                            </div>
                          </div>
                        </fieldset>
                        <div className="d-flex justify-content-end">
                          <button
                            className="btn btn-primary"
                            type={workerProfileEditing ? "submit" : "button"}
                            onClick={(event) => {
                              if (!workerProfileEditing) {
                                event.preventDefault();
                                setWorkerProfileEditing(true);
                              }
                            }}
                          >
                            {" "}
                            {workerProfileEditing ? "Save Changes" : "Edit Profile"}{" "}
                          </button>
                        </div>
                      </form>
                    </div>
                  </div>
                </div>
                <div className="row g-3 mt-2">
                  <div className="col-12">
                    <div className="card border-0 shadow-sm">
                      <div className="card-header bg-success text-white fw-bold d-flex justify-content-between align-items-center">
                        <span>Skills & Expertise</span>
                        {workerProfileEditing && (
                          <button
                            type="button"
                            className="btn btn-sm btn-light"
                            style={{ color: '#4CAF50' }}
                            onClick={() => setShowSkillModal(true)}
                          >
                            Edit Skills
                          </button>
                        )}
                      </div>
                      <div className="card-body">
                        <div className="skills-grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: '1rem' }}>
                          {(workerProfileForm.skills || []).length > 0 ? (
                            workerProfileForm.skills.map((skill) => (
                              <div
                                key={skill}
                                className="p-3 rounded position-relative"
                                style={{ backgroundColor: '#f8f9fa', borderLeft: '4px solid #4CAF50' }}
                              >
                                {workerProfileEditing && (
                                  <button
                                    type="button"
                                    className="btn btn-sm btn-danger position-absolute top-0 end-0 m-1 py-0 px-2"
                                    aria-label={`Remove ${skill}`}
                                    onClick={() => {
                                      // Saved straight away, like the Add Skills dialog.
                                      handleSaveWorkerSkills(
                                        (workerProfileForm.skills || []).filter((item) => item !== skill),
                                      ).catch((error) => window.alert(error.message));
                                    }}
                                  >
                                    ×
                                  </button>
                                )}
                                <div className="fw-600">{skill}</div>
                                {(() => {
                                  const entry = (workerProfileForm.portfolioSkills || []).find(
                                    (item) => item.name.toLowerCase() === String(skill).toLowerCase(),
                                  );
                                  if (!entry) {
                                    return <span className="small text-muted d-block mt-2">Save your profile to set a level</span>;
                                  }
                                  return (
                                    <>
                                      {workerProfileEditing ? (
                                        <select
                                          className="form-select form-select-sm mt-2"
                                          aria-label={`Proficiency in ${skill}`}
                                          value={entry.proficiency}
                                          onChange={(event) => handleSetSkillProficiency(entry.id, event.target.value)}
                                        >
                                          <option value="">Level not set</option>
                                          <option value="beginner">Beginner</option>
                                          <option value="intermediate">Intermediate</option>
                                          <option value="expert">Expert</option>
                                        </select>
                                      ) : entry.proficiency ? (
                                        <span className="badge bg-success mt-2 text-capitalize">{entry.proficiency}</span>
                                      ) : (
                                        <span className="small text-muted d-block mt-2">Level not set</span>
                                      )}
                                      <span className="small text-muted d-block mt-1">
                                        {entry.ratingCount
                                          ? `★ ${Number(entry.averageRating).toFixed(1)} from ${entry.ratingCount} household rating${entry.ratingCount === 1 ? "" : "s"}`
                                          : "Not yet rated"}
                                      </span>
                                    </>
                                  );
                                })()}
                              </div>
                            ))
                          ) : (
                            <p className="text-muted">
                              No skills added yet. {workerProfileEditing && "Click Edit Skills to add one."}
                            </p>
                          )}
                        </div>
                      </div>
                    </div>
                  </div>
                  <div className="col-12">
                    <div className="card border-0 shadow-sm">
                      <div className="card-header bg-success text-white fw-bold d-flex justify-content-between align-items-center">
                        <span>Certifications</span>
                        {workerProfileEditing && (
                          <button type="button" className="btn btn-sm btn-light" style={{ color: '#4CAF50' }} onClick={handleOpenCertificationModal}>+ Add Certificate</button>
                        )}
                      </div>
                      <div className="card-body">
                        {(workerProfileForm.certifications || []).length > 0 ? (
                          <div className="row g-3">
                            {workerProfileForm.certifications.map((cert, index) => (
                              <div key={index} className="col-md-4">
                                <div className="position-relative">
                                  <CertificateThumb cert={cert} height="200px" />
                                  <div className="position-absolute start-0 end-0 bottom-0 d-flex align-items-end justify-content-between p-2 rounded-bottom" style={{ background: 'linear-gradient(transparent, rgba(0,0,0,0.75))' }}>
                                    <div>
                                      <p className="text-white mb-1 small fw-bold">{cert.name}</p>
                                      <CertificateStatusBadge cert={cert} />
                                    </div>
                                    {workerProfileEditing && (
                                      <div className="d-flex gap-1">
                                        <button type="button" className="btn btn-sm btn-light" onClick={() => handleEditCertification(index)}>Edit</button>
                                        <button type="button" className="btn btn-sm btn-danger" onClick={() => handleDeleteCertification(index)}>×</button>
                                      </div>
                                    )}
                                  </div>
                                </div>
                              </div>
                            ))}
                          </div>
                        ) : (
                          <p className="text-muted">No certifications added yet. {workerProfileEditing && "Click the Add Certificate button to add one."}</p>
                        )}
                      </div>
                    </div>
                  </div>
                  <div className="col-12">
                    <div className="card border-0 shadow-sm">
                      <div className="card-header bg-success text-white fw-bold d-flex justify-content-between align-items-center">
                        <span>Work Samples</span>
                        <div className="d-flex gap-2">
                          {(workerProfileForm.workSamples || []).length > 0 && (
                            <button type="button" className="btn btn-sm btn-light" style={{ color: '#4CAF50' }} onClick={() => setPortfolioGalleryOpen(true)}>View More</button>
                          )}
                          {workerProfileEditing && (
                            <button type="button" className="btn btn-sm btn-light" style={{ color: '#4CAF50' }} onClick={handleOpenWorkSampleModal}>+ Add Sample</button>
                          )}
                        </div>
                      </div>
                      <div className="card-body">
                        {(workerProfileForm.workSamples || []).length > 0 ? (
                          <div className="row g-3">
                            {workerProfileForm.workSamples.map((sample, index) => (
                              <div key={index} className="col-md-6">
                                <div className="card border-success h-100">
                                  <div className="card-body p-2">
                                    <h6 className="mb-2">{sample.title}</h6>
                                    <div className="d-flex gap-2" style={{ height: '120px' }}>
                                      <div className="flex-grow-1 position-relative" style={{ cursor: 'pointer' }} onClick={() => setViewingWorkSampleIndex(index)}>
                                        <img src={sample.beforePreview} alt="Before" className="img-fluid rounded" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                                        <small className="position-absolute bottom-1 start-1 bg-dark text-white px-2 py-1 rounded">Before</small>
                                      </div>
                                      <div className="flex-grow-1 position-relative" style={{ cursor: 'pointer' }} onClick={() => setViewingWorkSampleIndex(index)}>
                                        <img src={sample.afterPreview} alt="After" className="img-fluid rounded" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                                        <small className="position-absolute bottom-1 start-1 bg-success text-white px-2 py-1 rounded">After</small>
                                      </div>
                                    </div>
                                  </div>
                                  {workerProfileEditing && (
                                    <div className="card-footer bg-transparent border-top d-flex gap-2">
                                      <button type="button" className="btn btn-sm btn-outline-secondary flex-grow-1" onClick={() => handleEditWorkSample(index)}>Edit</button>
                                      <button type="button" className="btn btn-sm btn-outline-danger flex-grow-1" onClick={() => handleDeleteWorkSample(index)}>Delete</button>
                                    </div>
                                  )}
                                </div>
                              </div>
                            ))}
                          </div>
                        ) : (
                          <p className="text-muted">No work samples uploaded yet. {workerProfileEditing && "Click the Add Sample button to add one."}</p>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
                <div className="row g-3 mt-2">
                  <div className="col-12">
                    <div className="card border-0 shadow-sm">
                      <div className="card-header bg-success text-white fw-bold">Employment History</div>
                      <div className="card-body">
                        {(employmentHistory || []).length > 0 ? (
                          <div className="list-group list-group-flush">
                            {employmentHistory.map((job, index) => {
                              const skillRatings = job.skill_ratings || [];
                              const overallRating = skillRatings.length > 0
                                ? (skillRatings.reduce((sum, sr) => sum + parseFloat(sr.rating || 0), 0) / skillRatings.length).toFixed(1)
                                : 0;
                              return (
                                <div key={index} className="list-group-item px-0 py-3 border-bottom">
                                  <div className="row align-items-start">
                                    <div className="col-md-6">
                                      <h6 className="mb-1 fw-bold">{job.title}</h6>
                                      <p className="text-muted small mb-1">{job.household_name || "Household"}</p>
                                      <p className="text-muted small mb-0">{job.location || ""}</p>
                                    </div>
                                    <div className="col-md-6">
                                      <div className="d-flex justify-content-between align-items-start">
                                        <div className="flex-grow-1">
                                          {skillRatings.length > 0 ? (
                                            <>
                                              <p className="mb-1"><small className="fw-bold">Skill Ratings:</small></p>
                                              {skillRatings.map((sr, idx) => (
                                                <div key={idx} className="d-flex justify-content-between mb-1">
                                                  <small className="text-muted">{sr.skill_name || sr.skill}:</small>
                                                  <small className="fw-bold">
                                                    <span className="badge bg-success">{sr.rating} ⭐</span>
                                                  </small>
                                                </div>
                                              ))}
                                              <div className="d-flex justify-content-between mt-2 pt-2 border-top">
                                                <small className="text-muted"><strong>Overall:</strong></small>
                                                <small className="fw-bold">
                                                  <span className="badge bg-info">{overallRating} ⭐</span>
                                                </small>
                                              </div>
                                            </>
                                          ) : (
                                            <small className="text-muted">No ratings yet</small>
                                          )}
                                        </div>
                                      </div>
                                    </div>
                                  </div>
                                </div>
                              );
                            })}
                          </div>
                        ) : (
                          <p className="text-muted">No completed jobs yet.</p>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
                {workerPhotoModalOpen && workerMiniPhoto && (
                  <div
                    className="profile-photo-modal-backdrop"
                    role="dialog"
                    aria-modal="true"
                    aria-label="Profile photo preview"
                    onClick={() => setWorkerPhotoModalOpen(false)}
                  >
                    <button
                      className="profile-photo-modal-close"
                      type="button"
                      onClick={() => setWorkerPhotoModalOpen(false)}
                      aria-label="Close profile photo preview"
                    >
                      Close
                    </button>
                    <img
                      src={workerMiniPhoto}
                      alt="Worker profile enlarged"
                      className="profile-photo-modal-image"
                      onClick={(event) => event.stopPropagation()}
                    />
                  </div>
                )}
                {showSkillModal && (
                  <WorkerSkillsDialog
                    savedSkills={workerProfileForm.skills || []}
                    onSave={handleSaveWorkerSkills}
                    onClose={() => setShowSkillModal(false)}
                  />
                )}
                {showCertificationModal && (
                  <div className="modal d-block" style={{ backgroundColor: 'rgba(0,0,0,0.5)' }} onClick={() => setShowCertificationModal(false)}>
                    <div className="modal-dialog modal-dialog-centered" onClick={(e) => e.stopPropagation()}>
                      <div className="modal-content">
                        <div className="modal-header bg-success text-white">
                          <h5 className="modal-title">{editingCertificationIndex !== null ? "Edit Certificate" : "Add Certificate"}</h5>
                          <button type="button" className="btn-close btn-close-white" onClick={() => setShowCertificationModal(false)}></button>
                        </div>
                        <div className="modal-body">
                          <div className="mb-3">
                            <label className="form-label">Certificate Type *</label>
                            <select
                              className="form-select"
                              value={certificationForm.certificateType || ""}
                              onChange={(e) => setCertificationForm({ ...certificationForm, certificateType: e.target.value })}
                            >
                              <option value="">Select type...</option>
                              <option value="tesda">TESDA Certificate</option>
                              <option value="license">Professional License</option>
                              <option value="credential">Professional Credential</option>
                              <option value="certification">Professional Certification</option>
                              <option value="other">Other</option>
                            </select>
                          </div>
                          <div className="mb-3">
                            <label className="form-label">Certificate Name *</label>
                            <input
                              type="text"
                              className="form-control"
                              value={certificationForm.name}
                              onChange={(e) => setCertificationForm({ ...certificationForm, name: e.target.value })}
                              placeholder="e.g., AWS Solutions Architect"
                            />
                          </div>
                          <div className="mb-3">
                            <label className="form-label">Issued by</label>
                            <input
                              type="text"
                              className="form-control"
                              value={certificationForm.issuer || ""}
                              onChange={(e) => setCertificationForm({ ...certificationForm, issuer: e.target.value })}
                              placeholder="e.g., TESDA"
                            />
                          </div>
                          <div className="row g-3 mb-3">
                            <div className="col-6">
                              <label className="form-label">Date issued</label>
                              <input
                                type="date"
                                className="form-control"
                                value={certificationForm.issueDate || ""}
                                onChange={(e) => setCertificationForm({ ...certificationForm, issueDate: e.target.value })}
                              />
                            </div>
                            <div className="col-6">
                              <label className="form-label">Expiry date</label>
                              <input
                                type="date"
                                className="form-control"
                                value={certificationForm.expiryDate || ""}
                                min={certificationForm.issueDate || undefined}
                                onChange={(e) => setCertificationForm({ ...certificationForm, expiryDate: e.target.value })}
                              />
                            </div>
                          </div>
                          <div className="mb-3">
                            <label className="form-label">Certificate Image *</label>
                            <input
                              type="file"
                              className="form-control"
                              accept="image/*"
                              onChange={(e) => {
                                if (e.target.files && e.target.files[0]) {
                                  const file = e.target.files[0];
                                  const reader = new FileReader();
                                  reader.onload = (event) => {
                                    setCertificationForm({
                                      ...certificationForm,
                                      certificateImage: file,
                                      certificatePreview: event.target.result,
                                    });
                                  };
                                  reader.readAsDataURL(file);
                                }
                              }}
                            />
                          </div>
                          {certificationForm.certificatePreview && (
                            <div className="mb-3">
                              <CertificateThumb cert={certificationForm} height="200px" />
                            </div>
                          )}
                        </div>
                        <div className="modal-footer">
                          <button type="button" className="btn btn-secondary" onClick={() => setShowCertificationModal(false)}>Cancel</button>
                          <button type="button" className="btn btn-success" disabled={portfolioSaving} onClick={handleAddCertification}>{portfolioSaving ? "Saving…" : "Save Certificate"}</button>
                        </div>
                      </div>
                    </div>
                  </div>
                )}
                {showWorkSampleModal && (
                  <div className="modal d-block" style={{ backgroundColor: 'rgba(0,0,0,0.5)' }} onClick={() => setShowWorkSampleModal(false)}>
                    <div className="modal-dialog modal-lg modal-dialog-centered" onClick={(e) => e.stopPropagation()}>
                      <div className="modal-content">
                        <div className="modal-header bg-success text-white">
                          <h5 className="modal-title">{editingWorkSampleIndex !== null ? "Edit Work Sample" : "Add Work Sample"}</h5>
                          <button type="button" className="btn-close btn-close-white" onClick={() => setShowWorkSampleModal(false)}></button>
                        </div>
                        <div className="modal-body">
                          <div className="mb-3">
                            <label className="form-label">Project Title *</label>
                            <input
                              type="text"
                              className="form-control"
                              value={workSampleForm.title}
                              onChange={(e) => setWorkSampleForm({ ...workSampleForm, title: e.target.value })}
                              placeholder="e.g., House Deep Cleaning"
                            />
                          </div>
                          <div className="row">
                            <div className="col-md-6 mb-3">
                              <label className="form-label">Before Image *</label>
                              <input
                                type="file"
                                className="form-control"
                                accept="image/*"
                                onChange={(e) => {
                                  if (e.target.files && e.target.files[0]) {
                                    const file = e.target.files[0];
                                    const reader = new FileReader();
                                    reader.onload = (event) => {
                                      setWorkSampleForm({
                                        ...workSampleForm,
                                        beforeImage: file,
                                        beforePreview: event.target.result,
                                      });
                                    };
                                    reader.readAsDataURL(file);
                                  }
                                }}
                              />
                              {workSampleForm.beforePreview && (
                                <img src={workSampleForm.beforePreview} alt="Before" className="img-fluid rounded mt-2" style={{ maxHeight: '150px', objectFit: 'cover', width: '100%' }} />
                              )}
                            </div>
                            <div className="col-md-6 mb-3">
                              <label className="form-label">After Image *</label>
                              <input
                                type="file"
                                className="form-control"
                                accept="image/*"
                                onChange={(e) => {
                                  if (e.target.files && e.target.files[0]) {
                                    const file = e.target.files[0];
                                    const reader = new FileReader();
                                    reader.onload = (event) => {
                                      setWorkSampleForm({
                                        ...workSampleForm,
                                        afterImage: file,
                                        afterPreview: event.target.result,
                                      });
                                    };
                                    reader.readAsDataURL(file);
                                  }
                                }}
                              />
                              {workSampleForm.afterPreview && (
                                <img src={workSampleForm.afterPreview} alt="After" className="img-fluid rounded mt-2" style={{ maxHeight: '150px', objectFit: 'cover', width: '100%' }} />
                              )}
                            </div>
                          </div>
                        </div>
                        <div className="modal-footer">
                          <button type="button" className="btn btn-secondary" onClick={() => setShowWorkSampleModal(false)}>Cancel</button>
                          <button type="button" className="btn btn-success" disabled={portfolioSaving} onClick={handleAddWorkSample}>{portfolioSaving ? "Saving…" : "Save Sample"}</button>
                        </div>
                      </div>
                    </div>
                  </div>
                )}
                {viewingWorkSampleIndex !== null && (workerProfileForm.workSamples || [])[viewingWorkSampleIndex] && (
                  <div className="modal d-block" style={{ backgroundColor: 'rgba(0,0,0,0.7)' }} onClick={() => setViewingWorkSampleIndex(null)}>
                    <div className="modal-dialog modal-xl modal-dialog-centered" onClick={(e) => e.stopPropagation()}>
                      <div className="modal-content">
                        <div className="modal-header bg-success text-white">
                          <h5 className="modal-title">{(workerProfileForm.workSamples || [])[viewingWorkSampleIndex]?.title}</h5>
                          <button type="button" className="btn-close btn-close-white" onClick={() => setViewingWorkSampleIndex(null)}></button>
                        </div>
                        <div className="modal-body p-4">
                          <div className="row g-4">
                            <div className="col-md-6">
                              <div className="position-relative">
                                <img src={(workerProfileForm.workSamples || [])[viewingWorkSampleIndex]?.beforePreview} alt="Before" className="img-fluid rounded" style={{ width: '100%', maxHeight: '400px', objectFit: 'cover' }} />
                                <div className="position-absolute top-50 start-50 translate-middle">
                                  <span className="bg-dark text-white px-4 py-3 rounded fw-bold" style={{ fontSize: '18px' }}>Before</span>
                                </div>
                              </div>
                            </div>
                            <div className="col-md-6">
                              <div className="position-relative">
                                <img src={(workerProfileForm.workSamples || [])[viewingWorkSampleIndex]?.afterPreview} alt="After" className="img-fluid rounded" style={{ width: '100%', maxHeight: '400px', objectFit: 'cover' }} />
                                <div className="position-absolute top-50 start-50 translate-middle">
                                  <span className="bg-success text-white px-4 py-3 rounded fw-bold" style={{ fontSize: '18px' }}>After</span>
                                </div>
                              </div>
                            </div>
                          </div>
                        </div>
                        <div className="modal-footer">
                          <button type="button" className="btn btn-secondary" onClick={() => setViewingWorkSampleIndex(null)}>Close</button>
                        </div>
                      </div>
                    </div>
                  </div>
                )}
                {portfolioGalleryOpen && (
                  <section className="worker-dashboard" style={{ position: 'fixed', top: 0, left: 0, width: '100%', height: '100%', zIndex: 1000, backgroundColor: '#f8f9fa', overflowY: 'auto' }}>
                    <div className="container-fluid p-4">
                      <div className="d-flex justify-content-between align-items-center mb-4">
                        <h2>Portfolio Gallery</h2>
                        <button type="button" className="btn btn-secondary" onClick={() => setPortfolioGalleryOpen(false)}>Close</button>
                      </div>

                      <div className="mb-5">
                        <h4 className="mb-3 fw-bold text-dark">Certifications</h4>
                        {(workerProfileForm.certifications || []).length > 0 ? (
                          <div className="row g-3">
                            {workerProfileForm.certifications.map((cert, index) => (
                              <div key={index} className="col-md-4">
                                <div className="position-relative rounded overflow-hidden" style={{ height: '300px' }}>
                                  <CertificateThumb cert={cert} height="100%" />
                                  <div className="position-absolute bottom-0 start-0 end-0 p-2" style={{ background: 'linear-gradient(transparent, rgba(0,0,0,0.75))' }}>
                                    <div className="d-flex justify-content-between align-items-end gap-2">
                                      <p className="text-white mb-0 fw-bold small">{cert.name}</p>
                                      <CertificateStatusBadge cert={cert} />
                                    </div>
                                  </div>
                                </div>
                              </div>
                            ))}
                          </div>
                        ) : (
                          <p className="text-muted">No certifications added yet.</p>
                        )}
                      </div>

                      <div>
                        <h4 className="mb-4 fw-bold text-dark">Work Samples</h4>
                        {(workerProfileForm.workSamples || []).length > 0 ? (
                          <div className="row g-4">
                            {workerProfileForm.workSamples.map((sample, index) => (
                              <div key={index} className="col-12">
                                <div className="card border-0 shadow-sm">
                                  <div className="card-body p-3">
                                    <h5 className="mb-4 fw-bold text-dark">{sample.title}</h5>
                                    <div className="row g-3">
                                      <div className="col-md-6">
                                        <div className="position-relative rounded overflow-hidden" style={{ height: '300px' }}>
                                          <img src={sample.beforePreview} alt="Before" className="img-fluid" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                                          <small className="position-absolute bottom-2 start-2 bg-dark text-white px-2 py-1 rounded">Before</small>
                                        </div>
                                      </div>
                                      <div className="col-md-6">
                                        <div className="position-relative rounded overflow-hidden" style={{ height: '300px' }}>
                                          <img src={sample.afterPreview} alt="After" className="img-fluid" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                                          <small className="position-absolute bottom-2 start-2 bg-success text-white px-2 py-1 rounded">After</small>
                                        </div>
                                      </div>
                                    </div>
                                  </div>
                                </div>
                              </div>
                            ))}
                          </div>
                        ) : (
                          <p className="text-muted">No work samples added yet.</p>
                        )}
                      </div>
                    </div>
                  </section>
                )}
              </div>
            </div>
          </section>
        )}
        {view === "worker-my-jobs" && (
          <section className="worker-dashboard">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openWorkerDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openAllWorkerFindJobs}>
                    {navIcon("search")}
                    <span>Find Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerApplications}>
                    {navIcon("applications")}
                    <span>My Applications</span>
                    {workerApplicationUnreadCount > 0 && (
                      <span className="nav-count-badge">{workerApplicationUnreadCount}</span>
                    )}
                  </button>
                  <button className="worker-nav-item active">
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openWorkerGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <div className="profile-card p-3 p-md-4">
                  <h1 className="h4 mb-1">My Jobs</h1>
                  <p className="text-muted mb-0">
                    The work you were hired for, and everything you have finished.
                  </p>
                </div>

                <p className="household-process-section-label">
                  In progress &middot; {workerInProgressJobs.length}
                </p>
                {workerInProgressJobs.length === 0 ? (
                  <div className="profile-card p-4 text-center text-muted">
                    No active jobs right now.{" "}
                    <button type="button" className="btn btn-link p-0 align-baseline" onClick={openAllWorkerFindJobs}>
                      Find work
                    </button>{" "}
                    to get started.
                  </div>
                ) : (
                  <div className="household-process-grid">
                    {workerInProgressJobs.map((job) => {
                      return (
                        <article className="household-process-card" key={`worker-job-${job.id}`}>
                          <div className="household-process-card-top">
                            <div className="household-process-status-icon assigned">{navIcon("jobs")}</div>
                            <div className="household-process-card-top-text">
                              <h3>{job.jobTitle || job.serviceType}</h3>
                              <span className="household-process-status-line assigned">
                                <i aria-hidden="true" />
                                {getWorkerApplicationDisplayStatus(job)}
                              </span>
                            </div>
                          </div>
                          <div className="household-process-worker-row">
                            <div className="household-process-mini-avatar">
                              {String(job.householdName || job.householdUsername || "H").slice(0, 2).toUpperCase()}
                            </div>
                            <div>
                              <span>{job.householdName || job.householdUsername || "Household"}</span>
                              <small>{formatLocation(job.barangay, job.streetAddress)}</small>
                            </div>
                          </div>
                          <p className="household-process-meta">
                            {formatRate(job.offeredRate, job.rateType)}
                            {job.jobStartDate
                              ? ` · ${job.jobStartDate > todayIsoDate ? "Starts" : "Started"} ${formatJobDate(job.jobStartDate)}`
                              : ""}
                          </p>
                          {/* The household marks a job done (AGENTS.md I.A). */}
                          <div className="household-process-note">
                            {job.householdName || job.householdUsername || "The household"} will mark this job as
                            done when the work is finished.
                          </div>
                        </article>
                      );
                    })}
                  </div>
                )}

                <p className="household-process-section-label">
                  Completed &middot; {workerCompletedJobs.length}
                </p>
                {workerCompletedJobs.length === 0 ? (
                  <div className="profile-card p-4 text-center text-muted">
                    Your finished jobs will appear here.
                  </div>
                ) : (
                  <div className="household-process-grid">
                    {workerCompletedJobs.map((job) => {
                      const review = getWorkerReviewForJob(job.id);
                      return (
                        <article className="household-process-card" key={`worker-done-${job.id}`}>
                          <div className="household-process-card-top">
                            <div className="household-process-status-icon review">{navIcon("jobs")}</div>
                            <div className="household-process-card-top-text">
                              <h3>{job.jobTitle || job.serviceType}</h3>
                              <span className="household-process-status-line review">
                                <i aria-hidden="true" />
                                {job.completedAt ? `Completed ${formatDateTime(job.completedAt)}` : "Completed"}
                              </span>
                            </div>
                          </div>
                          <div className="household-process-worker-row">
                            <div className="household-process-mini-avatar">
                              {String(job.householdName || job.householdUsername || "H").slice(0, 2).toUpperCase()}
                            </div>
                            <div>
                              <span>{job.householdName || job.householdUsername || "Household"}</span>
                              <small>{formatRate(job.offeredRate, job.rateType)}</small>
                            </div>
                          </div>
                          <p className="household-process-meta">
                            {review
                              ? `Rating received: ${Number(review.overallRating ?? review.rating).toFixed(1)} / 5`
                              : "No rating yet"}
                          </p>
                          {hasRatedHouseholdForJob(job.id) ? (
                            <div className="household-process-note">You rated this household.</div>
                          ) : (
                            <button
                              type="button"
                              className="btn btn-success household-process-cta"
                              onClick={() => {
                                setWorkerRateHouseholdDraft({ rating: "", feedback: "" });
                                setWorkerRateHouseholdJob(job);
                              }}
                            >
                              Rate household
                            </button>
                          )}
                        </article>
                      );
                    })}
                  </div>
                )}
              </div>
            </div>
            {workerRateHouseholdJob && (
              <div
                className="gg-modal-backdrop"
                role="dialog"
                aria-modal="true"
                aria-labelledby="worker-rate-household-title"
                onClick={() => setWorkerRateHouseholdJob(null)}
              >
                <form
                  className="gg-modal-panel"
                  onClick={(event) => event.stopPropagation()}
                  onSubmit={async (event) => {
                    event.preventDefault();
                    const sent = await handleWorkerRateHousehold(
                      workerRateHouseholdJob,
                      workerRateHouseholdDraft.rating,
                      workerRateHouseholdDraft.feedback,
                    );
                    if (sent) {
                      setWorkerRateHouseholdJob(null);
                    }
                  }}
                >
                  <div className="gg-modal-head">
                    <div>
                      <p className="gg-modal-kicker">Rate household</p>
                      <h2 id="worker-rate-household-title">
                        {workerRateHouseholdJob.householdName || workerRateHouseholdJob.householdUsername || "Household"}
                      </h2>
                    </div>
                  </div>
                  <div className="gg-modal-body">
                    <p className="small text-muted">
                      For {workerRateHouseholdJob.jobTitle || workerRateHouseholdJob.serviceType}. The household sees
                      your rating without your name.
                    </p>
                    <label className="form-label fw-semibold" htmlFor="worker-rate-household-stars">
                      Rating
                    </label>
                    <select
                      id="worker-rate-household-stars"
                      className="form-select mb-3"
                      required
                      value={workerRateHouseholdDraft.rating}
                      onChange={(event) =>
                        setWorkerRateHouseholdDraft((prev) => ({ ...prev, rating: event.target.value }))
                      }
                    >
                      <option value="">Choose a rating</option>
                      <option value="5">5 stars</option>
                      <option value="4">4 stars</option>
                      <option value="3">3 stars</option>
                      <option value="2">2 stars</option>
                      <option value="1">1 star</option>
                    </select>
                    <label className="form-label fw-semibold" htmlFor="worker-rate-household-feedback">
                      Feedback (optional)
                    </label>
                    <textarea
                      id="worker-rate-household-feedback"
                      className="form-control"
                      rows="3"
                      maxLength={1000}
                      placeholder="How was working for this household?"
                      value={workerRateHouseholdDraft.feedback}
                      onChange={(event) =>
                        setWorkerRateHouseholdDraft((prev) => ({ ...prev, feedback: event.target.value }))
                      }
                    />
                  </div>
                  <div className="gg-modal-foot">
                    <button type="button" className="gg-modal-foot-btn" onClick={() => setWorkerRateHouseholdJob(null)}>
                      Cancel
                    </button>
                    <button
                      type="submit"
                      className="btn btn-success"
                      disabled={isActionPending?.(`worker-rate-household-${workerRateHouseholdJob.id}`)}
                    >
                      Send rating
                    </button>
                  </div>
                </form>
              </div>
            )}
          </section>
        )}
        {view === "worker-applications" && (
          <section className="worker-dashboard">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openWorkerDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openAllWorkerFindJobs}>
                    {navIcon("search")}
                    <span>Find Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item active">
                    {navIcon("applications")}
                    <span>My Applications</span>
                    {workerApplicationUnreadCount > 0 && (
                      <span className="nav-count-badge">{workerApplicationUnreadCount}</span>
                    )}
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openWorkerGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <div className="worker-topbar">
                  <h1 className="h4 mb-0">My Applications</h1>
                </div>
                <div className="applications-filter mt-3">
                  <div className="row g-2 align-items-center">
                    <div className="col-md-4">
                      <label className="visually-hidden" htmlFor="worker-application-status-filter">
                        Filter by status
                      </label>
                      <select
                        id="worker-application-status-filter"
                        className="form-select"
                        value={workerApplicationStatusFilter}
                        onChange={(event) => setWorkerApplicationStatusFilter(event.target.value)}
                      >
                        <option value="All">All Status</option>
                        {workerApplicationStatusOptions.map((status) => (
                          <option key={status} value={status}>
                            {status}
                          </option>
                        ))}
                      </select>
                    </div>
                    <div className="col-md-8 small text-muted">
                      Showing {visibleWorkerApplications.length} of {workerApplications.length}
                    </div>
                  </div>
                </div>
                <div className="card border-0 shadow-sm mt-3">
                  {visibleWorkerApplications.length === 0 ? (
                    // Outside the table on purpose: inside a horizontally
                    // scrolling table on a phone, this message was cut off.
                    <p className="text-center text-muted py-4 px-3 mb-0">
                      {workerApplications.length === 0
                        ? "No applications yet."
                        : "No applications with this status."}
                    </p>
                  ) : (
                  <div className="table-responsive">
                    <table className="table align-middle mb-0">
                      <thead>
                        <tr>
                          <th>Job</th>
                          <th>Household</th>
                          <th>Schedule</th>
                          <th>Location</th>
                          <th>Rate</th>
                          <th>Status</th>
                          <th>Applied</th>
                        </tr>
                      </thead>
                      <tbody>
                        {visibleWorkerApplications.map((job) => (
                            <tr key={`${job.id}-${job.appliedAt}`}>
                              <td>
                                <div className="fw-semibold">{job.jobTitle || job.serviceType}</div>
                                <div className="small text-muted">{job.serviceType || "Service not specified"}</div>
                                {job.description && (
                                  <div className="small text-muted">
                                    {job.description.length > 90 ? `${job.description.slice(0, 90)}...` : job.description}
                                  </div>
                                )}
                              </td>
                              <td>{job.householdName || "Household"}</td>
                              <td>
                                {formatScheduleLabel(job.scheduleType) || "Not set"}
                                {job.jobStartDate && (
                                  <div className="small text-muted">{formatJobDate(job.jobStartDate)}</div>
                                )}
                              </td>
                              <td>{formatLocation(job.barangay, job.streetAddress)}</td>
                              <td>{formatRate(job.offeredRate, job.rateType)}</td>
                              <td>{getWorkerApplicationDisplayStatus(job)}</td>
                              <td>{formatDateTime(job.appliedAt)}</td>
                            </tr>
                          ))}
                      </tbody>
                    </table>
                  </div>
                  )}
                </div>
              </div>
            </div>
          </section>
        )}
        {(view === "worker-get-verified" || view === "household-get-verified") && (
          <section className="worker-dashboard worker-get-verified-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  {/* Same items and order as every other page of each role. */}
                  {isHouseholdVerification ? (
                    <>
                      <button className="worker-nav-item" onClick={openHouseholdDashboard}>
                        {navIcon("dashboard")}
                        <span>Dashboard</span>
                      </button>
                      <button className="worker-nav-item" onClick={openHouseholdPostJob}>
                        {navIcon("post-job")}
                        <span>Post a Job</span>
                      </button>
                      <button className="worker-nav-item" onClick={openHouseholdMyJobs}>
                        {navIcon("jobs")}
                        <span>My Jobs</span>
                      </button>
                      <button className="worker-nav-item" onClick={openMyComplaints}>
                        {navIcon("flag")}
                        <span>My Complaints</span>
                      </button>
                      <span className="worker-nav-section">Account</span>
                      <button className="worker-nav-item" onClick={openHouseholdProfile}>
                        {navIcon("profile")}
                        <span>My Profile</span>
                      </button>
                    </>
                  ) : (
                    <>
                      <button className="worker-nav-item" onClick={openWorkerDashboard}>
                        {navIcon("dashboard")}
                        <span>Dashboard</span>
                      </button>
                      <button className="worker-nav-item" onClick={openAllWorkerFindJobs}>
                        {navIcon("search")}
                        <span>Find Jobs</span>
                      </button>
                      <button className="worker-nav-item" onClick={openWorkerProfile}>
                        {navIcon("profile")}
                        <span>My Profile</span>
                      </button>
                      <button className="worker-nav-item" onClick={openWorkerApplications}>
                        {navIcon("applications")}
                        <span>My Applications</span>
                        {workerApplicationUnreadCount > 0 && (
                          <span className="nav-count-badge">{workerApplicationUnreadCount}</span>
                        )}
                      </button>
                      <button className="worker-nav-item" onClick={openWorkerMyJobs}>
                        {navIcon("jobs")}
                        <span>My Jobs</span>
                      </button>
                      <button className="worker-nav-item" onClick={openMyComplaints}>
                        {navIcon("flag")}
                        <span>My Complaints</span>
                      </button>
                      <span className="worker-nav-section">Account</span>
                    </>
                  )}
                  <button className="worker-nav-item active">{navIcon("verified")}
                    <span>{verificationNavLabel}</span></button>
                  <button
                    className="worker-nav-item"
                    onClick={isHouseholdVerification ? openHouseholdNotifications : openWorkerNotifications}
                  >
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                {verificationAccount?.verification === "Verified" ? (
                  <div className="verification-wrap verification-approved-wrap">
                    <div className="verification-card verification-approved-card">
                      <div className="verification-card-head">{verificationNavLabel}</div>
                      <div className="verification-approved-body">
                        <section className="verification-approved-banner">
                          <h2>You're already verified</h2>
                          <p>Your verification is already approved by the admin, so the details below are now read-only.</p>
                        </section>

                        <div className="verification-approved-grid">
                          <article className="verification-approved-box">
                            <p className="verification-approved-label">Primary ID</p>
                            <p className="verification-approved-value">
                              {verificationAccount.verificationSubmission?.primaryIdName || "Primary ID"}
                            </p>
                            {verificationAccount.verificationSubmission?.primaryIdPreview ? (
                              <button
                                type="button"
                                className="verification-file-button"
                                onClick={() => openFilePreview(verificationAccount.verificationSubmission.primaryIdPreview)}
                              >
                                View Primary ID
                              </button>
                            ) : (
                              <span className="verification-file-button disabled">Primary ID</span>
                            )}
                          </article>

                          <article className="verification-approved-box">
                            <p className="verification-approved-label">Supporting Documents</p>
                            <p className="verification-approved-value">
                              {verificationAccount.verificationSubmission?.secondaryDocName || "Supporting document"}
                            </p>
                            {verificationAccount.verificationSubmission?.secondaryDocPreview ? (
                              <button
                                type="button"
                                className="verification-file-button"
                                onClick={() => openFilePreview(verificationAccount.verificationSubmission.secondaryDocPreview)}
                              >
                                View Supporting Document
                              </button>
                            ) : (
                              <span className="verification-file-button disabled">Supporting Document</span>
                            )}
                          </article>
                        </div>

                        <section className="verification-approved-box verification-approved-note">
                          <p className="verification-approved-label">Admin Note</p>
                          <p className="verification-approved-value mb-0">
                            {verificationAccount.verificationSubmission?.reviewNote ||
                              (verificationAccount.verificationReviewedBy
                                ? `Verified by ${verificationAccount.verificationReviewedBy} on ${verificationAccount.verificationReviewedAt}.`
                                : "Verified by admin.")}
                          </p>
                        </section>
                      </div>
                    </div>
                  </div>
                ) : pendingVerificationSubmission ? (
                  <div className="verification-wrap verification-approved-wrap">
                    <div className="verification-card verification-approved-card">
                      <div className="verification-card-head">Verification Under Review</div>
                      <div className="verification-approved-body">
                        <section className="verification-approved-banner verification-pending-banner">
                          <span className="gg-status-badge gg-status-pending">Under Review</span>
                          <h2>Your documents have been submitted</h2>
                          <p>
                            The verification form is locked while an admin reviews your documents.
                            You will receive a notification after a decision is made.
                          </p>
                        </section>

                        <div className="verification-approved-grid">
                          <article className="verification-approved-box">
                            <p className="verification-approved-label">Primary ID</p>
                            <p className="verification-approved-value">
                              {verificationAccount.verificationSubmission.primaryIdName || "Primary ID submitted"}
                            </p>
                          </article>
                          <article className="verification-approved-box">
                            <p className="verification-approved-label">Supporting Document</p>
                            <p className="verification-approved-value">
                              {verificationAccount.verificationSubmission.secondaryDocName ||
                                "Supporting document submitted"}
                            </p>
                          </article>
                        </div>

                        <section className="verification-approved-box verification-approved-note">
                          <p className="verification-approved-label">Submission Status</p>
                          <p className="verification-approved-value mb-0">
                            Submitted {formatTimestamp(verificationAccount.verificationSubmission.submittedAt, "for admin review")}.
                            You can submit new documents only if this request is rejected.
                          </p>
                        </section>
                      </div>
                    </div>
                  </div>
                ) : (
                  <div className="verification-wrap">
                    <div className="verification-card">
                      <div className="verification-card-head">Submit Verification Documents</div>
                      <form className="p-3 p-md-4" onSubmit={handleVerificationSubmit}>
                        <div className="verification-note mb-3">
                          <p className="mb-0 small">
                            <strong>Why get verified?</strong>{" "}
                            {isHouseholdVerification
                              ? "Verification helps workers trust that job postings come from a reviewed household account."
                              : "Verified workers appear higher in smart matching and help households trust your profile faster."}
                          </p>
                        </div>
                        <div className="mb-3">
                          <label className="form-label fw-semibold" htmlFor="primaryIdType">
                            Which government ID are you uploading?
                          </label>
                          <select
                            id="primaryIdType"
                            name="primaryIdType"
                            className="form-select"
                            value={verificationForm.primaryIdType || ""}
                            onChange={handleVerificationChange}
                          >
                            <option value="">---Select ID Type---</option>
                            {GOVERNMENT_ID_TYPES.map(({ value, label }) => (
                              <option key={value} value={value}>
                                {label}
                              </option>
                            ))}
                          </select>
                          {verificationForm.primaryIdType === "other" && (
                            <div className="mt-2">
                              <label className="form-label fw-semibold" htmlFor="primaryIdOtherName">
                                Name the ID
                              </label>
                              <input
                                id="primaryIdOtherName"
                                type="text"
                                name="primaryIdOtherName"
                                className="form-control"
                                placeholder="e.g. PRC Professional ID"
                                maxLength={255}
                                value={verificationForm.primaryIdOtherName || ""}
                                onChange={handleVerificationChange}
                              />
                            </div>
                          )}
                        </div>
                        <div className="mb-3">
                          <label className="form-label fw-semibold">Primary ID Document</label>
                          <input
                            type="file"
                            className="form-control"
                            name="primaryId"
                            onChange={handleVerificationChange}
                          />
                          <p className="form-text mb-0">Upload a clear photo or scan of the ID you chose above.</p>
                          {verificationForm.primaryIdName && (
                            <p className="small text-muted mt-1 mb-0">Selected: {verificationForm.primaryIdName}</p>
                          )}
                        </div>
                        <div className="mb-3">
                          <label className="form-label fw-semibold">Supporting Document</label>
                          <input
                            type="file"
                            className="form-control"
                            name="secondaryDoc"
                            onChange={handleVerificationChange}
                          />
                          <p className="form-text mb-0">
                            {" "}
                            Accepted: Barangay clearance, NBI clearance, certificate of employment, etc.{" "}
                          </p>
                          {verificationForm.secondaryDocName && (
                            <p className="small text-muted mt-1 mb-0">Selected: {verificationForm.secondaryDocName}</p>
                          )}
                        </div>
                        <div className="mb-3">
                          <label className="form-label fw-semibold">Additional Notes (Optional)</label>
                          <textarea
                            className="form-control"
                            rows="3"
                            name="notes"
                            placeholder="Add any notes about your submitted documents..."
                            value={verificationForm.notes}
                            onChange={handleVerificationChange}
                          />
                        </div>
                        <div className="d-flex gap-2">
                          <button type="submit" className="btn btn-primary">
                            {" "}
                            Submit Documents{" "}
                          </button>
                          <button
                            type="button"
                            className="btn btn-outline-secondary"
                            onClick={isHouseholdVerification ? openHouseholdDashboard : openWorkerDashboard}
                          >
                            {" "}
                            Cancel{" "}
                          </button>
                        </div>
                      </form>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </section>
        )}
        {view === "worker-notifications" && (
          <section className="worker-dashboard worker-notifications-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openWorkerDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openAllWorkerFindJobs}>
                    {navIcon("search")}
                    <span>Find Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerApplications}>
                    {navIcon("applications")}
                    <span>My Applications</span>
                    {workerApplicationUnreadCount > 0 && (
                      <span className="nav-count-badge">{workerApplicationUnreadCount}</span>
                    )}
                  </button>
                  <button className="worker-nav-item" onClick={openWorkerMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openWorkerGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item active">{navIcon("notifications")}
                    <span>Notifications</span></button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <div className="worker-notifications-header">
                  <h1>Notifications</h1>
                  <button
                    className="btn btn-outline-secondary worker-mark-read-button"
                    type="button"
                    onClick={() => markAllNotificationsRead(workerNotificationsWithReadState)}
                  >
                    {" "}
                    Mark all as read{" "}
                  </button>
                </div>
                {currentWorker?.verification !== "Verified" && (
                  <div className="alert alert-warning mt-3 mb-0 py-2">
                    Your account is not verified yet. Please complete verification to become eligible for hiring and
                    priority matching.
                  </div>
                )}
                <div className="worker-notifications-list">
                  {workerHireRequestCards.map((job) => (
                    <article
                      className={`notification-card worker-hire-request-card ${job.unread ? "unread" : ""}`}
                      key={`hire-request-${job.applicationId || job.notificationId || job.id}`}
                    >
                      <div className="worker-hire-request-head">
                        <div>
                          <p className="small text-muted mb-1">
                            {formatDateTime(job.updatedAt || job.appliedAt)}
                          </p>
                          <h2 className="h6 mb-1">Hire request</h2>
                          <p className="mb-0">
                            {job.notificationMessage || (
                              <>
                                {job.householdName || "A household"} wants to hire you for{" "}
                                <strong>{job.jobTitle || job.serviceType}</strong>.
                              </>
                            )}
                          </p>
                        </div>
                        <div className="worker-notification-head-actions">
                          <span className="badge text-bg-warning">Needs your response</span>
                          <div
                            className="household-notification-menu-wrap"
                            onClick={(event) => event.stopPropagation()}
                          >
                            <button
                              aria-expanded={
                                workerNotificationMenuId ===
                                (job.notificationId || `hire-request-${job.applicationId || job.id}`)
                              }
                              aria-haspopup="menu"
                              aria-label="Actions for hire request"
                              className="household-notification-menu-button"
                              disabled={
                                workerNotificationDeletingId ===
                                (job.notificationId || `hire-request-${job.applicationId || job.id}`)
                              }
                              type="button"
                              onClick={(event) => {
                                event.stopPropagation();
                                const menuId = job.notificationId || `hire-request-${job.applicationId || job.id}`;
                                setWorkerNotificationMenuId((currentId) =>
                                  currentId === menuId ? null : menuId,
                                );
                              }}
                            >
                              <span aria-hidden="true">⋮</span>
                            </button>
                            {workerNotificationMenuId ===
                              (job.notificationId || `hire-request-${job.applicationId || job.id}`) && (
                              <div className="household-notification-menu" role="menu">
                                <button
                                  role="menuitem"
                                  type="button"
                                  onClick={() => {
                                    setWorkerNotificationMenuId(null);
                                    if (job.notificationId) {
                                      markNotificationRead(job.notificationId);
                                    }
                                    setWorkerHireRequestPreview(job);
                                  }}
                                >
                                  View details
                                </button>
                                <button
                                  className="danger"
                                  role="menuitem"
                                  type="button"
                                  onClick={() => deleteWorkerNotification(job)}
                                >
                                  Delete
                                </button>
                              </div>
                            )}
                          </div>
                        </div>
                      </div>
                      <div className="worker-hire-request-details">
                        <div>
                          <span>Job type</span>
                          <strong>{job.serviceType || "Service"}</strong>
                        </div>
                        <div>
                          <span>Schedule</span>
                          <strong>{formatJobDate(job.jobStartDate) || job.scheduleType || "Not set"}</strong>
                        </div>
                        <div>
                          <span>Location</span>
                          <strong>{formatLocation(job.barangay, job.streetAddress) || "Not set"}</strong>
                        </div>
                        <div>
                          <span>Distance</span>
                          <strong>{getWorkerJobDistanceLabel(job) || "Not available"}</strong>
                        </div>
                        <div>
                          <span>Rate</span>
                          <strong>{formatRate(job.offeredRate, job.rateType)}</strong>
                        </div>
                        <div>
                          <span>Household</span>
                          <strong>{job.householdName || job.householdUsername || "Household"}</strong>
                        </div>
                      </div>
                      {job.description && (
                        <div className="worker-hire-request-description">
                          <span>Description</span>
                          <p>{job.description}</p>
                        </div>
                      )}
                    </article>
                  ))}
                  {workerGeneralNotifications.map((item) => (
                    <article
                      className={`notification-card worker-notification-item ${item.unread ? "unread" : ""}`}
                      key={item.id}
                    >
                      <div className="worker-notification-copy">
                        <p className="small text-muted mb-1">{formatDateTime(item.date)}</p>
                        <h2 className="h6 mb-1">{item.title}</h2>
                        <p className="mb-0">{item.message}</p>
                      </div>
                      <div
                        className="household-notification-menu-wrap"
                        onClick={(event) => event.stopPropagation()}
                      >
                        <button
                          aria-expanded={workerNotificationMenuId === item.id}
                          aria-haspopup="menu"
                          aria-label={`Actions for ${item.title}`}
                          title="Notification actions"
                          className="household-notification-menu-button"
                          disabled={workerNotificationDeletingId === item.id}
                          type="button"
                          onClick={(event) => {
                            event.stopPropagation();
                            setWorkerNotificationMenuId((currentId) =>
                              currentId === item.id ? null : item.id,
                            );
                          }}
                        >
                          <span aria-hidden="true">⋮</span>
                        </button>
                        {workerNotificationMenuId === item.id && (
                          <div className="household-notification-menu" role="menu">
                            <button
                              role="menuitem"
                              type="button"
                              onClick={() => openWorkerNotificationPreview(item)}
                            >
                              View details
                            </button>
                            <button
                              className="danger"
                              role="menuitem"
                              type="button"
                              onClick={() => deleteWorkerNotification(item)}
                            >
                              Delete
                            </button>
                          </div>
                        )}
                      </div>
                    </article>
                  ))}
                  {workerHireRequestCards.length === 0 && workerGeneralNotifications.length === 0 && (
                    <article className="notification-card">
                      <h2 className="h6 mb-1">No notifications yet</h2>
                      <p className="mb-0 text-muted">Hire requests and job updates will appear here.</p>
                    </article>
                  )}
                </div>
                {workerNotificationPreview && (
                  <div
                    className="worker-hire-request-modal-backdrop"
                    role="presentation"
                    onClick={() => setWorkerNotificationPreview(null)}
                  >
                    <section
                      className="worker-hire-request-modal worker-notification-modal"
                      role="dialog"
                      aria-modal="true"
                      aria-labelledby="worker-notification-modal-title"
                      onClick={(event) => event.stopPropagation()}
                    >
                      <div className="worker-hire-request-modal-head">
                        <div>
                          <p className="small text-muted mb-1">
                            {formatDateTime(workerNotificationPreview.date)}
                          </p>
                          <h2 id="worker-notification-modal-title">
                            {workerNotificationPreview.title || "Notification"}
                          </h2>
                        </div>
                        <button
                          className="btn btn-outline-secondary btn-sm"
                          type="button"
                          onClick={() => setWorkerNotificationPreview(null)}
                        >
                          Close
                        </button>
                      </div>
                      <p className="worker-notification-modal-message">{workerNotificationPreview.message}</p>
                      {workerNotificationPreview.jobId && (
                        <div className="worker-hire-request-actions">
                          <button
                            className="btn btn-outline-secondary btn-sm"
                            type="button"
                            onClick={() => {
                              const notification = workerNotificationPreview;
                              setWorkerNotificationPreview(null);
                              if (!openStructuredNotificationAction(notification)) {
                                openWorkerJobDetail(notification.jobId);
                              }
                            }}
                          >
                            View Job Details
                          </button>
                        </div>
                      )}
                    </section>
                  </div>
                )}
                {workerHireRequestPreviewJob && (
                  <div
                    className="worker-hire-request-modal-backdrop"
                    role="presentation"
                    onClick={() => setWorkerHireRequestPreview(null)}
                  >
                    <section
                      className="worker-hire-request-modal"
                      role="dialog"
                      aria-modal="true"
                      aria-labelledby="worker-hire-request-modal-title"
                      onClick={(event) => event.stopPropagation()}
                    >
                      <div className="worker-hire-request-modal-head">
                        <div>
                          <p className="small text-muted mb-1">
                            {formatDateTime(
                              workerHireRequestPreviewJob.updatedAt || workerHireRequestPreviewJob.appliedAt,
                            )}
                          </p>
                          <h2 id="worker-hire-request-modal-title">Hire request details</h2>
                          <p>
                            {workerHireRequestPreviewJob.householdName || "A household"} wants to hire you for{" "}
                            <strong>{workerHireRequestPreviewJob.jobTitle || workerHireRequestPreviewJob.serviceType}</strong>.
                          </p>
                        </div>
                        <button
                          className="btn btn-outline-secondary btn-sm"
                          type="button"
                          onClick={() => setWorkerHireRequestPreview(null)}
                        >
                          Close
                        </button>
                      </div>
                      <div className="worker-hire-request-details">
                        <div>
                          <span>Job title</span>
                          <strong>{workerHireRequestPreviewJob.jobTitle || "Job request"}</strong>
                        </div>
                        <div>
                          <span>Job type</span>
                          <strong>{workerHireRequestPreviewJob.serviceType || "Service"}</strong>
                        </div>
                        <div>
                          <span>Schedule</span>
                          <strong>
                            {formatJobDate(workerHireRequestPreviewJob.jobStartDate) || workerHireRequestPreviewJob.scheduleType || "Not set"}
                          </strong>
                        </div>
                        <div>
                          <span>Location</span>
                          <strong>
                            {formatLocation(workerHireRequestPreviewJob.barangay, workerHireRequestPreviewJob.streetAddress) ||
                              "Not set"}
                          </strong>
                        </div>
                        <div>
                          <span>Distance</span>
                          <strong>{getWorkerJobDistanceLabel(workerHireRequestPreviewJob) || "Not available"}</strong>
                        </div>
                        <div>
                          <span>Rate</span>
                          <strong>{formatRate(workerHireRequestPreviewJob.offeredRate, workerHireRequestPreviewJob.rateType)}</strong>
                        </div>
                        <div>
                          <span>Household</span>
                          <strong>
                            {workerHireRequestPreviewJob.householdName ||
                              workerHireRequestPreviewJob.householdUsername ||
                              "Household"}
                          </strong>
                        </div>
                      </div>
                      {workerHireRequestPreviewJob.description && (
                        <div className="worker-hire-request-description">
                          <span>Description</span>
                          <p>{workerHireRequestPreviewJob.description}</p>
                        </div>
                      )}
                      <div className="worker-hire-request-description">
                        <span>Reference images</span>
                        <div className="worker-hire-request-images">
                          {renderWorkerJobImages(workerHireRequestPreviewJob)}
                        </div>
                      </div>
                      <div className="worker-hire-request-actions">
                        <button
                          className="btn btn-outline-secondary btn-sm"
                          type="button"
                          onClick={() => {
                            const jobId = workerHireRequestPreviewJob.id;
                            setWorkerHireRequestPreview(null);
                            openWorkerJobDetail(jobId);
                          }}
                        >
                          View Details
                        </button>
                      </div>
                    </section>
                  </div>
                )}
              </div>
            </div>
          </section>
        )}
        {view === "admin-dashboard" && (
          <section className="worker-dashboard admin-dashboard-page">
            <div className="worker-layout">
              <DashboardSidebar
                brand="Admin Panel"
                items={buildAdminNavItems({ adminSection, openAdminDashboard, openAdminWorkersHistory })}
                footerAction={{ label: "Log Out", onClick: handleLogout }}
              />
              <div className="worker-content">
                <div className="worker-topbar">
                  <h1 className="h4 mb-0">
                    {adminSection === "history" ? "Workers History" : "Verification Dashboard"}
                  </h1>
                  <div className="worker-user-meta d-flex align-items-center gap-2">
                    <span className="badge text-bg-dark">Admin</span>
                    <button className="btn btn-outline-secondary btn-sm" type="button" onClick={goBack}>
                      {" "}
                      Back{" "}
                    </button>
                    <button className="btn btn-outline-secondary btn-sm" type="button" onClick={handleLogout}>
                      {" "}
                      Log Out{" "}
                    </button>
                  </div>
                </div>
                {adminSection === "verification" ? (
                  <React.Fragment>
                    <div className="row g-3 mt-1">
                      <div className="col-md-6 col-xl-3">
                        <div className="metric-card">
                          <p className="metric-label mb-1">Pending</p>
                          <p className="metric-value mb-0">{pendingVerificationRequests.length}</p>
                        </div>
                      </div>
                      <div className="col-md-6 col-xl-3">
                        <div className="metric-card">
                          <p className="metric-label mb-1">Under Review</p>
                          <p className="metric-value mb-0">
                            {verificationRequests.filter((item) => item.status === "Under Review").length}
                          </p>
                        </div>
                      </div>
                      <div className="col-md-6 col-xl-3">
                        <div className="metric-card">
                          <p className="metric-label mb-1">Approved</p>
                          <p className="metric-value mb-0">{approvedVerificationRequests.length}</p>
                        </div>
                      </div>
                      <div className="col-md-6 col-xl-3">
                        <div className="metric-card">
                          <p className="metric-label mb-1">Rejected</p>
                          <p className="metric-value mb-0">{rejectedVerificationRequests.length}</p>
                        </div>
                      </div>
                    </div>
                    <div className="card border-0 shadow-sm mt-4">
                      <div className="card-header bg-white d-flex justify-content-between align-items-center">
                        <h2 className="h6 mb-0 fw-bold">Account Verification Requests</h2>
                        <span className="small text-muted">{verificationRequests.length} total</span>
                      </div>
                      <div className="px-3 pt-3">
                        <VerificationRoleTabs
                          requests={verificationRequests}
                          value={adminVerificationRoleFilter}
                          onChange={setAdminVerificationRoleFilter}
                        />
                      </div>
                      {selectedVerificationRequest && (
                        <div className="p-3 border-bottom bg-light">
                          <div className="d-flex justify-content-between align-items-start gap-3 flex-wrap">
                            <div>
                              <h3 className="h6 mb-1">{selectedVerificationRequest.workerName}</h3>
                              <p className="small text-muted mb-0">@{selectedVerificationRequest.workerUsername}</p>
                              <span className="badge text-bg-secondary mt-2 text-capitalize">
                                {selectedVerificationRequest.accountRole}
                              </span>
                            </div>
                            <span
                              className={`badge ${selectedVerificationRequest.status === "Approved" ? "text-bg-success" : selectedVerificationRequest.status === "Rejected" ? "text-bg-danger" : "text-bg-warning"}`}
                            >
                              {selectedVerificationRequest.status}
                            </span>
                          </div>
                          <div className="row g-2 mt-2">
                            {selectedVerificationRequest.primaryIdPreview && (
                              <div className="col-md-6">
                                <div className="verification-note h-100">
                                  <p className="small fw-semibold mb-2">Primary ID</p>
                                  <button
                                    type="button"
                                    className="btn btn-outline-primary btn-sm"
                                    onClick={() => openFilePreview(selectedVerificationRequest.primaryIdPreview)}
                                  >
                                    Open Primary ID
                                  </button>
                                </div>
                              </div>
                            )}
                            {selectedVerificationRequest.secondaryDocPreview && (
                              <div className="col-md-6">
                                <div className="verification-note h-100">
                                  <p className="small fw-semibold mb-2">Supporting Document</p>
                                  <button
                                    type="button"
                                    className="btn btn-outline-primary btn-sm"
                                    onClick={() => openFilePreview(selectedVerificationRequest.secondaryDocPreview)}
                                  >
                                    Open Supporting Document
                                  </button>
                                </div>
                              </div>
                            )}
                          </div>
                        </div>
                      )}
                      <div className="p-3 d-grid gap-3">
                        {visibleAdminVerificationRequests.length > 0 ? (
                          visibleAdminVerificationRequests.map((request) => (
                            <article
                              className={`verification-admin-card ${selectedVerificationRequestId === request.id ? "selected" : ""}`}
                              key={request.id}
                              role="button"
                              tabIndex={0}
                              onClick={() => openVerificationRequest(request.id)}
                              onKeyDown={(event) => {
                                if (event.key === "Enter" || event.key === " ") {
                                  openVerificationRequest(request.id);
                                }
                              }}
                            >
                              <div className="d-flex justify-content-between align-items-start gap-3 flex-wrap">
                                <div>
                                  <h3 className="h6 mb-1">{request.workerName}</h3>
                                  <p className="small text-muted mb-1">@{request.workerUsername}</p>
                                  <p className="small mb-1 text-capitalize">
                                    <strong>Account:</strong> {request.accountRole}
                                  </p>
                                  <p className="small mb-1">
                                    <strong>Status:</strong> {request.status}
                                  </p>
                                  <p className="small mb-1">
                                    <strong>Submitted:</strong> {formatTimestamp(request.submittedAt)}
                                  </p>
                                  {request.reviewedAt && (
                                    <p className="small mb-1">
                                      <strong>Reviewed:</strong> {formatTimestamp(request.reviewedAt)}
                                    </p>
                                  )}
                                  {request.reviewNote && (
                                    <p className="small mb-0">
                                      <strong>Admin Note:</strong> {request.reviewNote}
                                    </p>
                                  )}
                                </div>
                                <span
                                  className={`badge ${request.status === "Approved" ? "text-bg-success" : request.status === "Rejected" ? "text-bg-danger" : "text-bg-warning"}`}
                                >
                                  {request.status}
                                </span>
                              </div>
                              <div className="row g-2 mt-2">
                                <div className="col-md-4">
                                  <div className="verification-note h-100">
                                    <p className="small fw-semibold mb-1">Primary ID</p>
                                    <p className="mb-0 small">{request.primaryIdName}</p>
                                  </div>
                                </div>
                                <div className="col-md-4">
                                  <div className="verification-note h-100">
                                    <p className="small fw-semibold mb-1">Supporting Doc</p>
                                    <p className="mb-0 small">{request.secondaryDocName}</p>
                                  </div>
                                </div>
                                <div className="col-md-4">
                                  <div className="verification-note h-100">
                                    <p className="small fw-semibold mb-1">Notes</p>
                                    <p className="mb-0 small">{request.notes || "No additional notes provided."}</p>
                                  </div>
                                </div>
                              </div>
                              {request.status === "Pending" || request.status === "Under Review" ? (
                                <div className="d-flex gap-2 mt-3 flex-wrap">
                                  <button
                                    type="button"
                                    className="btn btn-success btn-sm"
                                    onClick={() => handleAdminApproveVerification(request.id)}
                                  >
                                    {" "}
                                    Approve{" "}
                                  </button>
                                  <button
                                    type="button"
                                    className="btn btn-outline-danger btn-sm"
                                    onClick={() => handleAdminRejectVerification(request.id)}
                                  >
                                    {" "}
                                    Reject{" "}
                                  </button>
                                </div>
                              ) : null}
                            </article>
                          ))
                        ) : (
                          <div className="text-center text-muted py-4">
                            {verificationRequests.length > 0
                              ? `No ${adminVerificationRoleFilter === "household" ? "household" : "worker"} verification requests.`
                              : "No verification requests yet."}
                          </div>
                        )}
                      </div>
                    </div>
                  </React.Fragment>
                ) : (
                  <div className="card border-0 shadow-sm mt-4">
                    <div className="card-header bg-white d-flex justify-content-between align-items-center">
                      <h2 className="h6 mb-0 fw-bold">Workers History</h2>
                      <span className="small text-muted">Verified and submitted workers</span>
                    </div>
                    <div className="table-responsive">
                      <table className="table align-middle mb-0">
                        <thead>
                          <tr>
                            <th>Worker</th>
                            <th>Verification</th>
                            <th>Submitted</th>
                            <th>Reviewed By</th>
                          </tr>
                        </thead>
                        <tbody>
                          {adminVisibleWorkers.length > 0 ? (
                            adminVisibleWorkers.map((worker) => (
                              <tr key={worker.id}>
                                <td>{getDisplayName(worker.firstName, worker.lastName, worker.username)}</td>
                                <td>
                                  <span
                                    className={`badge ${worker.verification === "Verified" ? "text-bg-success" : worker.verification === "Under Review" ? "text-bg-warning" : "text-bg-secondary"}`}
                                  >
                                    {worker.verification || "Not Yet Verified"}
                                  </span>
                                </td>
                                <td>{formatTimestamp(worker.verificationSubmission?.submittedAt, "None")}</td>
                                <td>{worker.verificationReviewedBy || "None"}</td>
                              </tr>
                            ))
                          ) : (
                            <tr>
                              <td colSpan="4" className="text-center text-muted py-4">
                                {" "}
                                No verified or registered workers to display.{" "}
                              </td>
                            </tr>
                          )}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </section>
        )}
        {view === "household-post-job" && (
          <section className="worker-dashboard household-post-job-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openHouseholdDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item active">{navIcon("post-job")}
                    <span>Post a Job</span></button>
                  <button className="worker-nav-item" onClick={openHouseholdMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openHouseholdProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <div className="profile-card household-post-job-card">
                  <h1 className="household-post-job-title">Post a New Job</h1>
                  <form className="p-3 p-md-4 household-job-form-shell" onSubmit={handleHouseholdJobSubmit}>
                    <div className="row g-3 household-job-fields">
                      <div className="col-12">
                        <label className="form-label fw-semibold">Job Title</label>
                        <input
                          type="text"
                          name="jobTitle"
                          className="form-control"
                          placeholder="e.g. House Cleaning - 3 Bedroom"
                          value={householdJobForm.jobTitle}
                          onChange={handleHouseholdJobChange}
                        />
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Service Type</label>
                        <select
                          name="serviceType"
                          className="form-select"
                          value={householdJobForm.serviceType}
                          onChange={handleHouseholdJobChange}
                        >
                          <option value="">---Select Service---</option>
                          {SKILLS.map((skill) => (
                            <option key={skill} value={skill}>
                              {skill}
                            </option>
                          ))}
                        </select>
                        {householdJobForm.serviceType === "Other" && (
                          <div className="mt-2">
                            <label className="form-label fw-semibold" htmlFor="customServiceType">
                              Specify Service Type
                            </label>
                            <input
                              id="customServiceType"
                              type="text"
                              name="customServiceType"
                              className="form-control"
                              placeholder="e.g. Pet Grooming, Massage, etc."
                              maxLength={100}
                              required
                              value={householdJobForm.customServiceType || ""}
                              onChange={handleHouseholdJobChange}
                            />
                            <div className="form-text text-end">
                              {(householdJobForm.customServiceType || "").length}/100
                            </div>
                          </div>
                        )}
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Schedule Type</label>
                        <select
                          name="scheduleType"
                          className="form-select"
                          value={householdJobForm.scheduleType}
                          onChange={handleHouseholdJobChange}
                        >
                          <option>One-Time</option>
                          <option>Part-Time</option>
                          <option>Full-Time</option>
                        </select>
                      </div>
                      <div className="col-12">
                        <label className="form-label fw-semibold">Job Description</label>
                        <textarea
                          name="description"
                          className="form-control"
                          rows="3"
                          placeholder="Describe the job in detail..."
                          value={householdJobForm.description}
                          onChange={handleHouseholdJobChange}
                        />
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Barangay</label>
                        <select
                          name="barangay"
                          className="form-select"
                          value={householdJobForm.barangay}
                          onChange={handleHouseholdJobChange}
                        >
                          <option value="">---Select Barangay---</option>
                          {renderBarangayOptions()}
                        </select>
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Street / House No.</label>
                        <input
                          type="text"
                          name="streetAddress"
                          className="form-control"
                          value={householdJobForm.streetAddress}
                          onChange={handleHouseholdJobChange}
                        />
                      </div>
                      <div className="col-6">
                        <label className="form-label fw-semibold">Workers Needed</label>
                        <input
                          type="number"
                          min="1"
                          max="50"
                          step="1"
                          name="workersNeeded"
                          className="form-control"
                          value={householdJobForm.workersNeeded}
                          onChange={handleHouseholdJobChange}
                        />
                      </div>
                      <div className="col-6">
                        <label className="form-label fw-semibold">Offered Rate</label>
                        <input
                          type="number"
                          min="0"
                          step="0.01"
                          name="offeredRate"
                          className="form-control"
                          value={householdJobForm.offeredRate}
                          onChange={handleHouseholdJobChange}
                        />
                      </div>
                      <div className="col-md-6">
                        <label className="form-label fw-semibold">Rate Type</label>
                        <select
                          name="rateType"
                          className="form-select"
                          value={householdJobForm.rateType}
                          onChange={handleHouseholdJobChange}
                        >
                          <option>Per Day</option>
                          <option>Per Hour</option>
                          <option>Fixed Rate</option>
                        </select>
                      </div>
                      <div className="col-6">
                        <label className="form-label fw-semibold">Job Start Date</label>
                        <input
                          type="date"
                          min={todayIsoDate}
                          name="jobStartDate"
                          className="form-control"
                          required
                          value={householdJobForm.jobStartDate || ""}
                          onChange={handleHouseholdJobChange}
                        />
                      </div>
                      <div className="col-6">
                        <label className="form-label fw-semibold">Job End Date</label>
                        <input
                          type="date"
                          min={todayIsoDate}
                          name="jobEndDate"
                          className="form-control"
                          value={householdJobForm.jobEndDate || ""}
                          onChange={handleHouseholdJobChange}
                        />
                      </div>
                      <div className="col-6">
                        <label className="form-label fw-semibold">Estimated Working Days</label>
                        <input
                          type="number"
                          min="1"
                          max="366"
                          step="1"
                          name="estimatedWorkingDays"
                          className="form-control"
                          placeholder="e.g. 5"
                          value={householdJobForm.estimatedWorkingDays || ""}
                          onChange={handleHouseholdJobChange}
                        />
                      </div>
                      <div className="col-6">
                        <label className="form-label fw-semibold">Search Radius</label>
                        <select
                          name="geographicBoundary"
                          className="form-select"
                          value={householdJobForm.geographicBoundary || "1km"}
                          onChange={handleHouseholdJobChange}
                        >
                          <option value="1km">1 Kilometer</option>
                          <option value="2km">2 Kilometers</option>
                          <option value="5km">5 Kilometers</option>
                          <option value="10km">10 Kilometers</option>
                          <option value="unlimited">Unlimited</option>
                        </select>
                      </div>
                    </div>
                    <HouseholdJobMapPanel
                      captureHouseholdJobLocation={captureHouseholdJobLocation}
                      householdJobCoordinates={householdJobCoordinates}
                      householdJobLocationPreview={householdJobLocationPreview}
                      householdJobMapMode={householdJobMapMode}
                      householdJobMapRef={householdJobMapRef}
                      householdJobMapViewRef={householdJobMapViewRef}
                      loadLeafletAssets={loadLeafletAssets}
                      placeHouseholdJobPin={placeHouseholdJobPin}
                      setHouseholdJobMapMode={setHouseholdJobMapMode}
                    />
                    <div className="household-reference-images">
                      <label className="form-label fw-semibold">Reference Images</label>
                      <JobImageUpload maxImages={5} maxFileSize={5 * 1024 * 1024} onImagesChange={householdJobImages.onChange} />
                    </div>
                    <div className="household-post-actions">
                      <button type="submit" className="btn btn-primary" disabled={isSubmittingJob}>
                        {isSubmittingJob ? "Posting..." : "Post Job"}
                      </button>
                      <button
                        type="button"
                        className="btn btn-outline-secondary"
                        onClick={openHouseholdDashboard}
                        disabled={isSubmittingJob}
                      >
                        Cancel
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            </div>
          </section>
        )}
        {view === "household-profile" && (
          <section className="worker-dashboard profile-page household-profile-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openHouseholdDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdPostJob}>
                    {navIcon("post-job")}
                    <span>Post a Job</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item active">{navIcon("profile")}
                    <span>My Profile</span></button>
                  <button className="worker-nav-item" onClick={openHouseholdGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <main className="profile-container" aria-labelledby="household-profile-title">
                  <h1 className="household-profile-page-title">My Profile Household</h1>
                  <div className="profile-row">
                  <section className="profile-column" aria-labelledby="household-profile-title">
                    <div className="profile-card profile-summary-card">
                      <header className="profile-card-header" id="household-profile-title">My Profile</header>
                      <div className="profile-summary-body text-center">
                        {householdProfileForm.profilePhotoPreview ? (
                          <img
                            src={householdProfileForm.profilePhotoPreview}
                            alt="Household profile"
                            className="profile-photo-large mb-2"
                          />
                        ) : (
                          <div className="profile-avatar mb-2">
                            {(householdProfileForm.firstName || "H").slice(0, 1).toUpperCase()}
                          </div>
                        )}
                        <h2 className="h5 mb-1">
                          {getDisplayName(
                            householdProfileForm.firstName,
                            householdProfileForm.lastName,
                            householdProfileForm.username,
                          )}
                        </h2>
                        <p className="text-muted mb-2">@{householdProfileForm.username || "household"}</p>
                        <div className="d-flex justify-content-center gap-2 flex-wrap">
                          <span className="badge text-bg-primary">Household</span>
                          <span
                            className={`badge ${currentHousehold?.verification === "Verified" ? "text-bg-success" : currentHousehold?.verification === "Rejected" ? "text-bg-danger" : "text-bg-warning"}`}
                          >
                            {currentHousehold?.verification || "Not Yet Verified"}
                          </span>
                        </div>
                      </div>
                      <div className="profile-summary-list">
                        <p><strong>Account Type:</strong> Household</p>
                        <p><strong>Barangay:</strong> {householdProfileForm.barangay || "Not set"}</p>
                        <p><strong>Phone Number:</strong> {householdProfileForm.phone || "Not set"}</p>
                        <p><strong>Email:</strong> {householdProfileForm.email || "Not set"}</p>
                      </div>
                    </div>
                  </section>
                  <section className="profile-edit-card" aria-labelledby="household-edit-profile-title">
                    <header className="profile-card-header" id="household-edit-profile-title">Edit Profile Information</header>
                      <form className="profile-edit-form" onSubmit={handleHouseholdProfileEditSubmit}>
                        <div className="profile-form-field profile-form-field-full">
                          <label className="form-label fw-semibold" htmlFor="household-profile-photo">Profile Photo</label>
                          <input
                            id="household-profile-photo"
                            type="file"
                            className="form-control"
                            name="profilePhoto"
                            accept="image/*"
                            disabled={!householdProfileEditing}
                            onChange={handleHouseholdProfileChange}
                          />
                          <p className="form-text mb-0">Accepted: JPG, PNG. Use a clear profile photo.</p>
                          {householdProfileForm.profilePhotoPreview && (
                            <img
                              src={householdProfileForm.profilePhotoPreview}
                              alt="Household profile preview"
                              className="img-fluid rounded border mt-2"
                            />
                          )}
                        </div>
                        <div className="profile-form-grid">
                          <div className="profile-form-field">
                            <label className="form-label fw-semibold" htmlFor="household-first-name">First Name</label>
                            <input
                              id="household-first-name"
                              type="text"
                              name="firstName"
                              className="form-control"
                              value={householdProfileForm.firstName}
                              disabled={!householdProfileEditing}
                              onChange={handleHouseholdProfileChange}
                            />
                          </div>
                          <div className="profile-form-field">
                            <label className="form-label fw-semibold" htmlFor="household-last-name">Last Name</label>
                            <input
                              id="household-last-name"
                              type="text"
                              name="lastName"
                              className="form-control"
                              value={householdProfileForm.lastName}
                              disabled={!householdProfileEditing}
                              onChange={handleHouseholdProfileChange}
                            />
                          </div>
                          <div className="profile-form-field">
                            <label className="form-label fw-semibold" htmlFor="household-username">Username</label>
                            <input
                              id="household-username"
                              type="text"
                              name="username"
                              className="form-control"
                              value={householdProfileForm.username}
                              disabled
                            />
                          </div>
                          <div className="profile-form-field">
                            <label className="form-label fw-semibold" htmlFor="household-email">Email</label>
                            <input
                              id="household-email"
                              type="email"
                              name="email"
                              className="form-control"
                              value={householdProfileForm.email}
                              disabled={!householdProfileEditing}
                              onChange={handleHouseholdProfileChange}
                            />
                          </div>
                          <div className="profile-form-field">
                            <label className="form-label fw-semibold" htmlFor="household-phone">Phone Number</label>
                            <input
                              id="household-phone"
                              type="text"
                              name="phone"
                              className="form-control"
                              value={householdProfileForm.phone}
                              disabled={!householdProfileEditing}
                              onChange={handleHouseholdProfileChange}
                            />
                          </div>
                          <div className="profile-form-field">
                            <label className="form-label fw-semibold" htmlFor="household-barangay">Barangay</label>
                            <select
                              id="household-barangay"
                              name="barangay"
                              className="form-select"
                              value={householdProfileForm.barangay}
                              disabled={!householdProfileEditing}
                              onChange={handleHouseholdProfileChange}
                            >
                              <option value="">---Select Barangay---</option>
                              {renderBarangayOptions()}
                            </select>
                          </div>
                          <div className="profile-form-field profile-form-field-full">
                            <label className="form-label fw-semibold" htmlFor="household-street">Street / House No.</label>
                            <input
                              id="household-street"
                              type="text"
                              name="streetAddress"
                              className="form-control"
                              value={householdProfileForm.streetAddress}
                              disabled={!householdProfileEditing}
                              onChange={handleHouseholdProfileChange}
                            />
                          </div>
                        </div>
                        <div className="profile-form-actions">
                          <button className="btn btn-primary profile-save-button" type="submit">
                            {householdProfileEditing ? "Save Changes" : "Edit Profile"}
                          </button>
                        </div>
                      </form>
                  </section>
                  </div>
                <section className="profile-footer" aria-labelledby="household-profile-feedback-title">
                  <h2 className="household-profile-feedback-title" id="household-profile-feedback-title">Feedback & Rating</h2>
                  <div className="profile-feedback-grid">
                    <article className="profile-feedback-card">
                      <header className="profile-card-header feedback-header">
                        <span>Feedback from Workers</span>
                        <button
                          type="button"
                          className="btn btn-light btn-sm rounded-pill"
                          onClick={openHouseholdFeedbackAll}
                        >
                          View All
                        </button>
                      </header>
                      <div className="p-3 d-grid gap-2">
                        {(currentHousehold?.receivedFeedback || []).slice(0, 2).length > 0 ? (
                          (currentHousehold?.receivedFeedback || []).slice(0, 2).map((review) => (
                            <div className="review-item" key={review.id || `${review.authorName}-${review.createdAt}`}>
                              <div className="d-flex justify-content-between gap-2">
                                <div>
                                  <p className="mb-1 fw-semibold">{review.authorName || "Masked Worker"}</p>
                                  <p className="mb-1 small text-muted">{review.feedback || review.comment || "No comment provided."}</p>
                                  <p className="mb-0 small text-muted">
                                    {formatDateTime(review.createdAt || review.date)}
                                  </p>
                                </div>
                                <strong>{reviewScore(review) != null ? `${reviewScore(review).toFixed(1)}/5` : "Feedback"}</strong>
                              </div>
                            </div>
                          ))
                        ) : (
                          <div className="review-item">
                            <p className="mb-0 text-muted">No worker feedback yet.</p>
                          </div>
                        )}
                      </div>
                    </article>
                    <article className="profile-feedback-card">
                      <header className="profile-card-header feedback-header">
                        <span>Reviews You Submitted</span>
                        <button
                          type="button"
                          className="btn btn-light btn-sm rounded-pill"
                          onClick={openHouseholdReviewsAll}
                        >
                          View All
                        </button>
                      </header>
                      <div className="p-3 d-grid gap-2">
                        {(currentHousehold?.givenFeedback || []).slice(0, 2).length > 0 ? (
                          (currentHousehold?.givenFeedback || []).slice(0, 2).map((review) => (
                            <div className="review-item" key={review.id || `${review.targetName}-${review.createdAt}`}>
                              <div className="d-flex justify-content-between gap-2">
                                <div>
                                  <p className="mb-1 fw-semibold">{review.targetName || review.target || "Worker"}</p>
                                  <p className="mb-1 small text-muted">{review.feedback || review.comment || "No comment provided."}</p>
                                  <p className="mb-0 small text-muted">
                                    {formatDateTime(review.createdAt || review.date)}
                                  </p>
                                </div>
                                <strong>{reviewScore(review) != null ? `${reviewScore(review).toFixed(1)}/5` : "Feedback"}</strong>
                              </div>
                            </div>
                          ))
                        ) : (
                          <div className="review-item">
                            <p className="mb-0 text-muted">No submitted reviews yet.</p>
                          </div>
                        )}
                      </div>
                    </article>
                  </div>
                </section>
                </main>
              </div>
            </div>
          </section>
        )}
        {view === "household-feedback-all" && (
          <section className="worker-dashboard household-feedback-all-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openHouseholdDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdPostJob}>
                    {navIcon("post-job")}
                    <span>Post a Job</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item active" onClick={openHouseholdProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <main className="household-feedback-all-container">
                  <p className="household-feedback-eyebrow">All Household Feedback</p>
                  <section className="household-feedback-hero">
                    <div>
                      <h1>All Feedback by Workers</h1>
                      <p>Worker names are partially masked for privacy.</p>
                    </div>
                    <button className="btn btn-outline-secondary btn-sm" type="button" onClick={openHouseholdProfile}>
                      Back
                    </button>
                  </section>

                  <section className="household-feedback-list-panel" aria-label="All worker feedback">
                    <div className="household-feedback-filter">
                      <label className="form-label mb-0" htmlFor="household-feedback-date">
                        Filter Date
                      </label>
                      <input
                        id="household-feedback-date"
                        type="date"
                        className="form-control"
                        value={householdFeedbackDateFilter}
                        onChange={(event) => setHouseholdFeedbackDateFilter(event.target.value)}
                      />
                      {householdFeedbackDateFilter && (
                        <button
                          className="btn btn-outline-secondary btn-sm"
                          type="button"
                          onClick={() => setHouseholdFeedbackDateFilter("")}
                        >
                          Clear
                        </button>
                      )}
                    </div>

                    <div className="household-feedback-list">
                      {filteredHouseholdWorkerFeedback.length > 0 ? (
                        filteredHouseholdWorkerFeedback.map((review, index) => {
                          const maskedAuthorName = review.authorName || "Masked Worker";
                          return (
                          <article className="household-feedback-item" key={review.id || `${review.createdAt}-${index}`}>
                            <div className="household-feedback-avatar">
                              {maskedAuthorName.slice(0, 1).toUpperCase()}
                            </div>
                            <div className="household-feedback-copy">
                              <div className="household-review-title-row">
                                <h2>{maskedAuthorName}</h2>
                                {reviewScore(review) != null && <strong>{reviewScore(review).toFixed(1)}/5</strong>}
                              </div>
                              <p>{review.feedback || review.comment || "No comment provided."}</p>
                              <small>{formatDateTime(review.createdAt || review.date)}</small>
                              <details className="household-feedback-more">
                                <summary>View more</summary>
                                <p>
                                  This feedback was submitted by a worker after a household interaction. Most letters in
                                  the worker's name are hidden to protect their privacy.
                                </p>
                              </details>
                            </div>
                          </article>
                          );
                        })
                      ) : (
                        <article className="household-feedback-empty">
                          <h2>No feedback found</h2>
                          <p>
                            {householdFeedbackDateFilter
                              ? "No worker feedback matches the selected date."
                              : "No worker feedback has been submitted for this household yet."}
                          </p>
                        </article>
                      )}
                    </div>
                  </section>
                </main>
              </div>
            </div>
          </section>
        )}
        {view === "household-reviews-all" && (
          <section className="worker-dashboard household-feedback-all-page household-reviews-all-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openHouseholdDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdPostJob}>
                    {navIcon("post-job")}
                    <span>Post a Job</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item active" onClick={openHouseholdProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <main className="household-feedback-all-container">
                  <p className="household-feedback-eyebrow">View all Reviews Household</p>
                  <section className="household-feedback-hero">
                    <div>
                      <h1>All Reviews you Submitted</h1>
                      <p>Review history for workers you rated through GawaGo.</p>
                    </div>
                    <button className="btn btn-outline-secondary btn-sm" type="button" onClick={openHouseholdProfile}>
                      Back
                    </button>
                  </section>

                  <section className="household-feedback-list-panel" aria-label="All submitted reviews">
                    <div className="household-feedback-filter household-reviews-filter">
                      <label className="form-label mb-0" htmlFor="household-review-date">
                        Filter Date
                      </label>
                      <input
                        id="household-review-date"
                        type="date"
                        className="form-control"
                        value={householdReviewDateFilter}
                        onChange={(event) => setHouseholdReviewDateFilter(event.target.value)}
                      />
                      <label className="form-label mb-0" htmlFor="household-review-rating">
                        Rating
                      </label>
                      <select
                        id="household-review-rating"
                        className="form-select"
                        value={householdReviewRatingFilter}
                        onChange={(event) => setHouseholdReviewRatingFilter(event.target.value)}
                      >
                        <option value="">All ratings</option>
                        <option value="5">5 stars</option>
                        <option value="4">4 stars</option>
                        <option value="3">3 stars</option>
                        <option value="2">2 stars</option>
                        <option value="1">1 star</option>
                      </select>
                      {(householdReviewDateFilter || householdReviewRatingFilter) && (
                        <button
                          className="btn btn-outline-secondary btn-sm"
                          type="button"
                          onClick={() => {
                            setHouseholdReviewDateFilter("");
                            setHouseholdReviewRatingFilter("");
                          }}
                        >
                          Clear
                        </button>
                      )}
                    </div>

                    <div className="household-feedback-list">
                      {filteredHouseholdSubmittedReviews.length > 0 ? (
                        filteredHouseholdSubmittedReviews.map((review, index) => {
                          const targetName = review.targetName || review.target || "Worker";
                          const initial = targetName.slice(0, 1).toUpperCase() || "W";
                          return (
                            <article className="household-feedback-item" key={review.id || `${review.createdAt}-${index}`}>
                              <div className="household-feedback-avatar">{initial}</div>
                              <div className="household-feedback-copy">
                                <div className="household-review-title-row">
                                  <h2>{targetName}</h2>
                                  <strong>{reviewScore(review) != null ? `${reviewScore(review).toFixed(1)}/5` : "No rating"}</strong>
                                </div>
                                <p>{review.feedback || review.comment || "No comment provided."}</p>
                                <small>{formatDateTime(review.createdAt || review.date)}</small>
                                <details className="household-feedback-more">
                                  <summary>View more</summary>
                                  <p>
                                    This is the review you submitted for {targetName}. It remains visible in your review
                                    history for transparency and follow-up reference.
                                  </p>
                                </details>
                              </div>
                            </article>
                          );
                        })
                      ) : (
                        <article className="household-feedback-empty">
                          <h2>No reviews found</h2>
                          <p>
                            {householdReviewDateFilter || householdReviewRatingFilter
                              ? "No submitted reviews match the selected filters."
                              : "You have not submitted any worker reviews yet."}
                          </p>
                        </article>
                      )}
                    </div>
                  </section>
                </main>
              </div>
            </div>
          </section>
        )}
        {view === "household-job-matches" && (
          <section className="worker-dashboard household-job-matches-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item active" onClick={openHouseholdDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdPostJob}>
                    {navIcon("post-job")}
                    <span>Post a Job</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openHouseholdProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                {householdScanActive ? (
                  <div className="worker-ai-hero">
                    <div className="worker-ai-hero-decor worker-ai-hero-decor-1" />
                    <div className="worker-ai-hero-decor worker-ai-hero-decor-2" />
                    <div className="worker-ai-hero-inner">
                      <div className="worker-ai-hero-top">
                        <div className="worker-ai-hero-left">
                          <div className="worker-ai-hero-eyebrow">JOB POSTED</div>
                          <h1 className="worker-ai-hero-title">Finding workers for your job</h1>
                          <p className="worker-ai-hero-desc">
                            {selectedJob?.jobTitle || "Your job"} is live. We&apos;re matching it to available
                            workers nearby by skill fit and travel distance.
                          </p>
                        </div>
                        <div className="worker-ai-hero-stat">
                          <div className="worker-ai-hero-stat-num">{selectedJob?.workersNeeded || 1}</div>
                          <div className="worker-ai-hero-stat-label">
                            {(selectedJob?.workersNeeded || 1) === 1 ? "worker needed" : "workers needed"}
                          </div>
                        </div>
                      </div>
                      <div className="worker-ai-scan-wrap">
                        <div className="worker-ai-scan-stage">
                          {householdScatterTags.map((tag) => (
                            <span
                              key={tag.id}
                              className="worker-ai-scan-tag"
                              style={{
                                left: `${tag.left}%`,
                                top: `${tag.top}%`,
                                transform: `rotate(${tag.rotate}deg)`,
                              }}
                            >
                              {tag.label}
                            </span>
                          ))}
                        </div>
                        <p className="worker-ai-scan-status">
                          {HOUSEHOLD_SCAN_STATUS_PHASES[householdScanStatusIndex]}
                        </p>
                      </div>
                    </div>
                  </div>
                ) : (
                  <>
                <div className="gg-matches-topbar">
                  <button type="button" className="gg-matches-back" onClick={openHouseholdDashboard}>
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                      <polyline points="15 18 9 12 15 6" />
                    </svg>
                    Back to Dashboard
                  </button>
                  <div className="gg-matches-heading">
                    <div>
                      <p className="gg-matches-eyebrow">{smartMatchRanking ? "Smart Matched Workers" : "AI Matched Workers"}</p>
                      <h1>{selectedJob?.jobTitle || "Your job is live"}</h1>
                      <p className="gg-matches-sub">
                        {smartMatchRanking ? (
                          "Ranked by Smart Matching: matching skill first, then verified workers, then road distance, then rating and rate."
                        ) : (
                          <>
                            Ranked by skill fit ({Math.round(AI_SKILL_WEIGHT * 100)}%) and travel distance (
                            {Math.round((1 - AI_SKILL_WEIGHT) * 100)}%).
                          </>
                        )}
                      </p>
                      <div className="worker-find-jobs-toggle mt-2" role="group" aria-label="How matches are ranked">
                        {[
                          ["ai", "AI match"],
                          ["smart", "Smart Matching"],
                        ].map(([value, label]) => (
                          <button
                            key={value}
                            type="button"
                            className={householdMatchRank === value ? "active" : ""}
                            aria-pressed={householdMatchRank === value}
                            onClick={() => setHouseholdMatchRank(value)}
                          >
                            {label}
                          </button>
                        ))}
                      </div>
                    </div>
                    <span className="gg-matches-live">
                      <i aria-hidden="true" />
                      Live matches
                    </span>
                  </div>
                  <div className="gg-matches-filters" role="group" aria-label="Filter matches by skill">
                    {matchedSkillOptions.map((skill) => (
                      <button
                        type="button"
                        key={skill}
                        className={`gg-matches-chip ${matchedSkillFilter === skill ? "active" : ""}`}
                        aria-pressed={matchedSkillFilter === skill}
                        onClick={() => setMatchedSkillFilter(skill)}
                      >
                        {skill}
                      </button>
                    ))}
                  </div>
                  <div className="worker-find-jobs-viewbar mt-3 mb-0">
                    <p className="small worker-skill-hint fw-semibold mb-0">
                      {householdMatchesView === "map"
                        ? "Every matched worker is pinned by their general area. Tap a pin to see who's available there."
                        : "Best matches first. Open a profile to compare rates, ratings and experience before you decide."}
                    </p>
                    <div className="worker-find-jobs-toggle" role="group" aria-label="Matched worker view">
                      {[
                        ["list", "List View"],
                        ["map", "Map View"],
                      ].map(([value, label]) => (
                        <button
                          key={value}
                          type="button"
                          className={householdMatchesView === value ? "active" : ""}
                          aria-pressed={householdMatchesView === value}
                          onClick={() => setHouseholdMatchesView(value)}
                        >
                          {label}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>

                <section className="gg-matches-body">
                  {householdMatchesView === "map" && (
                    <HouseholdWorkersMap
                      workers={visibleMatchedWorkers}
                      job={selectedJob}
                      onViewProfile={(worker) => openMatchedWorkerProfile(worker, selectedJob.id)}
                      onHire={requestDashboardHire}
                    />
                  )}
                  {householdMatchesView === "list" && (
                  <>
                  {visibleMatchedWorkers.length > 0 ? (
                    <div className="gg-match-grid">
                      {visibleMatchedWorkers.map((worker) => {
                        const workerName = getDisplayName(worker.firstName, worker.lastName, worker.username);
                        const extraSkills = Math.max(0, (worker.skills || []).length - 2);
                        return (
                          <article className="gg-match-card" key={worker.username || worker.id}>
                            <div className="gg-match-photo">
                              {renderWorkerPhoto(worker, workerName, "gg-match-photo-img")}
                              <span className="gg-match-photo-shade" aria-hidden="true" />
                              {worker.verification === "Verified" && (
                                <span className="gg-match-verified">&#10003; Verified</span>
                              )}
                              {!smartMatchRanking && (
                                <span className="gg-match-ring-slot">{renderMatchRing(worker.aiScore)}</span>
                              )}
                              <div className="gg-match-photo-ident">
                                <h3>{workerName}</h3>
                                <p>{worker.barangay || "Location not set"}</p>
                              </div>
                              <span className="gg-match-rate">{formatWorkerRate(worker.dailyRate, "/day")}</span>
                            </div>
                            <div className="gg-match-info">
                              <div className="gg-match-meta">
                                {renderStarRow(worker.rating, worker.reviewsDone)}
                                <span>&middot; {worker.distanceLabel || formatDistance(worker.distanceKm)}</span>
                                <span>
                                  &middot; {worker.completedJobs || 0}{" "}
                                  {(worker.completedJobs || 0) === 1 ? "job" : "jobs"}
                                </span>
                              </div>
                              {!smartMatchRanking && renderAiMatchBreakdown(worker)}
                              <div className="gg-match-skills">
                                {(worker.skills || []).slice(0, 2).map((skill) => (
                                  <span key={`${worker.id}-${skill}`}>{skill}</span>
                                ))}
                                {extraSkills > 0 && <span className="muted">+{extraSkills}</span>}
                              </div>
                              {worker.bio && <p className="gg-match-bio">{worker.bio}</p>}
                              <div className="gg-match-actions">
                                <button
                                  type="button"
                                  className="gg-match-profile"
                                  onClick={() => openMatchedWorkerProfile(worker, selectedJob.id)}
                                >
                                  View Profile
                                </button>
                                <button
                                  type="button"
                                  className="gg-match-hire"
                                  onClick={() => requestDashboardHire(worker)}
                                >
                                  Send a Request to Worker
                                </button>
                              </div>
                            </div>
                          </article>
                        );
                      })}
                    </div>
                  ) : (
                    <div className="household-applicant-empty">
                      {aiMatchedWorkersForSelectedJob.length > 0
                        ? `No matched worker lists ${matchedSkillFilter} yet. Pick another category to see the rest.`
                        : "No workers matched this job yet. Workers need listed skills, a saved location, and must fall inside the job's search radius."}
                      {aiMatchedWorkersForSelectedJob.length === 0 && selectedJob?.status === "Open" && (
                        <div className="mt-2">
                          <button type="button" className="btn btn-outline-secondary btn-sm" onClick={() => setEditingJob(selectedJob)}>
                            Edit job to widen its search radius
                          </button>
                        </div>
                      )}
                    </div>
                  )}
                  </>
                  )}
                  <div className="d-flex gap-2 flex-wrap mt-3">
                    <button type="button" className="btn btn-outline-secondary" onClick={openHouseholdMyJobs}>
                      Go to My Jobs
                    </button>
                  </div>
                </section>
                  </>
                )}
              </div>
            </div>
          </section>
        )}
        {view === "household-my-jobs" && (
          <section className="worker-dashboard household-my-jobs-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openHouseholdDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdPostJob}>
                    {navIcon("post-job")}
                    <span>Post a Job</span>
                  </button>
                  <button className="worker-nav-item active">{navIcon("jobs")}
                    <span>My Jobs</span></button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openHouseholdProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <div className="household-history-topline">
                  <h1 className="household-my-jobs-title">My Jobs</h1>
                  <p>Your complete job history &mdash; every completed and cancelled job in one place.</p>
                </div>

                <div className="household-history-stats">
                  <div className="household-history-stat completed">
                    <div className="household-history-stat-icon">
                      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                        <polyline points="20 6 9 17 4 12"></polyline>
                      </svg>
                    </div>
                    <div>
                      <strong>{historyCompletedJobs.length}</strong>
                      <span>Jobs Completed</span>
                    </div>
                  </div>
                  <div className="household-history-stat spent">
                    <div className="household-history-stat-icon">
                      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                        <line x1="12" y1="1" x2="12" y2="23"></line>
                        <path d="M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6"></path>
                      </svg>
                    </div>
                    <div>
                      <strong>{formatCurrency(householdTotalSpent)}</strong>
                      <span>Total Spent</span>
                    </div>
                  </div>
                  <div className="household-history-stat rating">
                    <div className="household-history-stat-icon">
                      <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                        <polygon points="12 2 15 8.5 22 9.5 17 14.5 18.3 21.5 12 18 5.7 21.5 7 14.5 2 9.5 9 8.5 12 2" />
                      </svg>
                    </div>
                    <div>
                      <strong>{householdRatingsGiven.length ? householdAvgRatingGiven.toFixed(1) : "—"}</strong>
                      <span>Avg Rating Given</span>
                    </div>
                  </div>
                </div>

                {historyHouseholdJobs.length === 0 ? (
                  <div className="profile-card p-4 text-center text-muted mt-3">
                    No finished jobs yet. Once a job is completed or cancelled, it&rsquo;ll show up here. Still-active
                    jobs live on your{" "}
                    <button type="button" className="btn btn-link p-0 align-baseline" onClick={openHouseholdDashboard}>
                      Dashboard
                    </button>
                    .
                  </div>
                ) : (
                  <>
                    <div className="household-history-tabs">
                      {[
                        ["all", "All Jobs", historyHouseholdJobs.length],
                        ["completed", "Completed", historyCompletedJobs.length],
                        ["cancelled", "Cancelled", historyCancelledJobs.length],
                      ].map(([key, label, count]) => (
                        <button
                          type="button"
                          key={key}
                          className={`household-history-tab ${myJobsFilter === key ? "active" : ""}`}
                          onClick={() => setMyJobsFilter(key)}
                        >
                          {label}
                          {count > 0 && <span className="household-history-tab-count">{count}</span>}
                        </button>
                      ))}
                    </div>

                    <div className="household-history-list">
                      {(myJobsFilter === "completed"
                        ? historyCompletedJobs
                        : myJobsFilter === "cancelled"
                          ? historyCancelledJobs
                          : historyHouseholdJobs
                      ).map((job) => {
                        const worker = getWorkerToReviewForJob(job);
                        const workerName = worker
                          ? getDisplayName(worker.firstName, worker.lastName, worker.username)
                          : null;
                        const review = getHouseholdReviewForJobWorker(job, worker);
                        const isCancelled = job.status === "Cancelled";
                        const starRating = Math.round((review && reviewScore(review)) || 0);
                        return (
                          <article key={job.id} className={`household-history-card ${isCancelled ? "cancelled" : ""}`}>
                            <div className="household-history-top">
                              <h3>{job.jobTitle || job.serviceType}</h3>
                              <span className={`household-history-pill ${isCancelled ? "cancelled" : "completed"}`}>
                                {job.statusLabel || job.status}
                              </span>
                            </div>
                            <p className="household-history-meta">
                              {job.serviceType} &middot; {formatJobDate(job.jobStartDate) || "Date not set"}
                              {" "}&middot;{" "}
                              {job.barangay || "Location not set"}
                            </p>

                            {isCancelled ? (
                              <div className="household-history-cancelled-note">
                                <span className="household-history-x">&times;</span>
                                <div>
                                  <strong>No worker was hired</strong>
                                  <p>Job was cancelled before a worker was assigned.</p>
                                  {(job.applications || []).length > 0 && (
                                    <button
                                      type="button"
                                      className="household-history-report-link"
                                      onClick={() => openDashboardReportModal(job)}
                                    >
                                      File a Complaint
                                    </button>
                                  )}
                                </div>
                              </div>
                            ) : (
                              <div className="household-history-body">
                                <div className="household-history-worker">
                                  <div className="household-history-worker-avatar">
                                    {worker ? String(workerName).slice(0, 2).toUpperCase() : "?"}
                                  </div>
                                  <div className="household-history-worker-info">
                                    <p className="household-history-worker-name">
                                      {worker ? workerName : "Worker record unavailable"}
                                      {worker?.verification === "Verified" && <span className="household-history-check">&#10003;</span>}
                                    </p>
                                    {worker && (
                                      <p className="household-history-worker-rating">
                                        <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                                          <polygon points="12 2 15 8.5 22 9.5 17 14.5 18.3 21.5 12 18 5.7 21.5 7 14.5 2 9.5 9 8.5 12 2" />
                                        </svg>
                                        {Number.parseFloat(worker.rating) ? Number.parseFloat(worker.rating).toFixed(1) : "New"}
                                        {" · "}
                                        {worker.reviewsDone || 0} {Number(worker.reviewsDone) === 1 ? "review" : "reviews"}
                                      </p>
                                    )}
                                    {worker && (
                                      <div className="household-history-worker-tags">
                                        {(worker.skills || []).slice(0, 1).map((skill) => (
                                          <span key={skill}>{skill}</span>
                                        ))}
                                        <span className="verified">{worker.verification || "Not Yet Verified"}</span>
                                      </div>
                                    )}
                                  </div>
                                </div>

                                <div className="household-history-side">
                                  <div className="household-history-rate-block">
                                    <span className="household-history-rate">{formatRate(job.offeredRate, job.rateType)}</span>
                                  </div>
                                  {review ? (
                                    <div className="household-history-review">
                                      <p className="household-history-review-label">Your Rating</p>
                                      <div className="household-history-stars">
                                        {[1, 2, 3, 4, 5].map((starValue) => (
                                          <svg
                                            key={starValue}
                                            width="13"
                                            height="13"
                                            viewBox="0 0 24 24"
                                            fill="currentColor"
                                            className={starValue > starRating ? "empty" : ""}
                                            aria-hidden="true"
                                          >
                                            <polygon points="12 2 15 8.5 22 9.5 17 14.5 18.3 21.5 12 18 5.7 21.5 7 14.5 2 9.5 9 8.5 12 2" />
                                          </svg>
                                        ))}
                                        <strong>{(reviewScore(review) || 0).toFixed(1)}/5</strong>
                                      </div>
                                      {review.feedback && (
                                        <p className="household-history-quote">&ldquo;{review.feedback}&rdquo;</p>
                                      )}
                                      <button
                                        type="button"
                                        className="household-history-report-link mt-2"
                                        onClick={() => openDashboardReportModal(job)}
                                      >
                                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                          <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"></path>
                                          <line x1="4" y1="22" x2="4" y2="15"></line>
                                        </svg>
                                        File a Complaint
                                      </button>
                                    </div>
                                  ) : (
                                    <div className="household-history-actions">
                                      <button
                                        type="button"
                                        className="household-history-rate-btn"
                                        disabled={!worker}
                                        onClick={() => openDashboardRateModal(job, worker)}
                                      >
                                        <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                                          <polygon points="12 2 15 8.5 22 9.5 17 14.5 18.3 21.5 12 18 5.7 21.5 7 14.5 2 9.5 9 8.5 12 2" />
                                        </svg>
                                        Rate Worker
                                      </button>
                                      <button
                                        type="button"
                                        className="household-history-report-link"
                                        onClick={() => openDashboardReportModal(job)}
                                      >
                                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                          <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"></path>
                                          <line x1="4" y1="22" x2="4" y2="15"></line>
                                        </svg>
                                        File a Complaint
                                      </button>
                                    </div>
                                  )}
                                </div>
                              </div>
                            )}
                          </article>
                        );
                      })}
                    </div>
                  </>
                )}
              </div>
            </div>
          </section>
        )}
        {view === "household-worker-profile" && !selectedWorker && (
          <section className="worker-dashboard">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item active" onClick={openHouseholdDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdPostJob}>
                    {navIcon("post-job")}
                    <span>Post a Job</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openHouseholdProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                    {householdUnreadCount > 0 && <span className="nav-count-badge">{householdUnreadCount}</span>}
                  </button>
                </nav>
              </aside>
              <div className="worker-content">
                <div className="profile-card p-4">
                  <div className="profile-card-head">Worker Profile</div>
                  <div className="p-3">
                    <p className="mb-3 text-muted">
                      Worker profile is not available yet. Please go back to the job details and try again.
                    </p>
                    <button className="btn btn-outline-secondary" type="button" onClick={openHouseholdDashboard}>
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </section>
        )}
        {view === "household-worker-profile" && selectedWorker && (
          <section className="worker-dashboard household-smart-match-profile">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item active" onClick={openHouseholdDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdPostJob}>
                    {navIcon("post-job")}
                    <span>Post a Job</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
	                  <button className="worker-nav-item" onClick={openHouseholdProfile}>
	                    {navIcon("profile")}
	                    <span>My Profile</span>
	                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
	                  <button className="worker-nav-item" onClick={openHouseholdNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                    {householdUnreadCount > 0 && <span className="nav-count-badge">{householdUnreadCount}</span>}
                  </button>
                </nav>
              </aside>
              <div className="worker-content">
                <div className="row g-3">
                  <div className="col-lg-4">
                    <div className="profile-card">
                      <div className="p-3 text-center">
                        {selectedWorkerPhoto ? (
                          <img
                            className="profile-photo-large mb-2"
                            src={selectedWorkerPhoto}
                            alt={`${getDisplayName(selectedWorker.firstName, selectedWorker.lastName, selectedWorker.username)} profile`}
                          />
                        ) : (
                          <div className="profile-avatar mb-2">
                            {(selectedWorker.avatar || selectedWorker.firstName || "W").slice(0, 1).toUpperCase()}
                          </div>
                        )}
                        <h2 className="h5 mb-1">
                          {getDisplayName(selectedWorker.firstName, selectedWorker.lastName, selectedWorker.username)}
                        </h2>
                        <p className="small text-muted mb-2">{selectedWorkerLocationLabel}</p>
                        <div className="mb-2">
                          <span
                            className={`badge ${selectedWorker.verification === "Verified" ? "text-bg-success" : "text-bg-warning"}`}
                          >
                            {selectedWorker.verification || "Not Yet Verified"}
                          </span>
                          {selectedWorker.reputationTier && (
                            <span className="badge text-bg-info ms-1">
                              {selectedWorker.reputationTier === "elite" && "⭐ Elite"}
                              {selectedWorker.reputationTier === "trusted" && "✓ Trusted"}
                              {selectedWorker.reputationTier === "established" && "◆ Established"}
                              {selectedWorker.reputationTier === "new" && "◇ New"}
                            </span>
                          )}
                          {selectedWorker.ratingTrend && selectedWorker.ratingTrend !== "neutral" && (
                            <span className={`badge ms-1 ${selectedWorker.ratingTrend === "improving" ? "text-bg-success" : "text-bg-warning"}`}>
                              {selectedWorker.ratingTrend === "improving" && "📈 Improving"}
                              {selectedWorker.ratingTrend === "declining" && "📉 Declining"}
                            </span>
                          )}
                        </div>
                      </div>
                      <div className="px-3 pb-3">
                        <p className="mb-1 small d-flex justify-content-between">
                          <span>Rating</span>
                          <strong>{selectedWorker.rating || "No ratings yet"}</strong>
                        </p>
                        <p className="mb-1 small d-flex justify-content-between">
                          <span>Jobs Done</span>
                          <strong>{selectedWorker.reviewsDone || 0}</strong>
                        </p>
                        <p className="mb-1 small d-flex justify-content-between">
                          <span>Experience</span>
                          <strong>{formatExperience(selectedWorker.yearsExperience)}</strong>
                        </p>
                        <p className="mb-1 small d-flex justify-content-between">
                          <span>Status</span>
                          <strong>{selectedWorker.status || "Available"}</strong>
                        </p>
                        <p className="mb-1 small d-flex justify-content-between">
                          <span>Driving Distance</span>
                          <strong>{selectedWorkerDistanceLabel || "Distance unavailable"}</strong>
                        </p>
                        <p className="mb-1 small d-flex justify-content-between">
                          <span>Hourly Rate</span>
                          <strong>{formatWorkerRate(selectedWorker.hourlyRate)}</strong>
                        </p>
                        <p className="mb-3 small d-flex justify-content-between">
                          <span>Daily Rate</span>
                          <strong>{formatWorkerRate(selectedWorker.dailyRate)}</strong>
                        </p>
                        <button
                          className="btn btn-primary w-100 mb-2"
                          type="button"
                          disabled={selectedWorkerHireButtonDisabled}
                          onClick={handleHireWorker}
                        >
                          {selectedWorkerHireButtonLabel}
                        </button>
                        {canRejectSelectedWorkerApplication && (
                          <button
                            className="btn btn-outline-danger w-100 mb-2"
                            type="button"
                            onClick={() => {
                              if (window.confirm("Reject this application? This can't be undone.")) {
                                handleRejectApplication(selectedWorker.id, selectedJob.id);
                              }
                            }}
                          >
                            Reject Application
                          </button>
                        )}
                        <button className="btn btn-outline-secondary w-100" type="button" onClick={openHouseholdDashboard}>
                          {" "}
                          Go Back{" "}
                        </button>
                      </div>
                    </div>
                  </div>
                  <div className="col-lg-8">
                    <div className="profile-card mb-3">
                      <div className="profile-card-head">About</div>
                      <div className="p-3">
                        <p className="mb-0">{selectedWorker.bio || "No description provided yet."}</p>
                      </div>
                    </div>
                    <div className="profile-card mb-3" data-distance-location-map="true">
                      <div className="profile-card-head d-flex justify-content-between align-items-center gap-3">
                        <span>Distance & Location</span>
                        <span className="badge text-bg-light">
                          {selectedWorkerDistanceLabel || "Distance unavailable"}
                        </span>
                      </div>
                      <div className="p-3">
                        {selectedWorkerLocationShared ? (
                          <LocationDistanceMap
                            userLatitude={selectedWorkerJobLatitude}
                            userLongitude={selectedWorkerJobLongitude}
                            targetLatitude={selectedWorkerPoint.latitude}
                            targetLongitude={selectedWorkerPoint.longitude}
                            userLocation={selectedWorkerJobLocationLabel}
                            targetLocation={selectedWorkerLocationLabel}
                            distanceKm={selectedWorkerDistanceKm}
                            routePoints={selectedWorker.routePoints || []}
                            formatDistanceFn={formatDistance}
                            onRouteDistanceChange={setSelectedWorkerRouteDistanceKm}
                          />
                        ) : (
                          <div className="worker-location-private" data-testid="worker-location-private">
                            <strong>{selectedWorkerDistanceLabel}</strong>
                            <span>
                              {selectedWorkerDistanceLabel === "Road distance unavailable"
                                ? "Road distance from your job site could not be calculated."
                                : "Road distance from your job site."}{" "}
                              This worker hasn't pinned a location on their profile yet, so there's nothing
                              to show on the map.
                            </span>
                          </div>
                        )}
                      </div>
                    </div>
                    {selectedWorkerVerificationRequest && (
                      <div className="profile-card mb-3">
                        <div className="profile-card-head">Verification Details</div>
                        <div className="p-3">
                          <div className="d-grid gap-2">
                            {[
                              ["Status", selectedWorkerVerificationRequest.status || selectedWorker.verification || "Pending"],
                              ["Primary ID", selectedWorkerVerificationRequest.primaryIdName],
                              ["Secondary Document", selectedWorkerVerificationRequest.secondaryDocName],
                              ["Submitted", formatTimestamp(selectedWorkerVerificationRequest.submittedAt)],
                              ["Reviewed", formatTimestamp(selectedWorkerVerificationRequest.reviewedAt)],
                              ["Worker Notes", selectedWorkerVerificationRequest.notes],
                              ["Admin Note", selectedWorkerVerificationRequest.reviewNote],
                            ]
                              .filter(([, value]) => value)
                              .map(([label, value]) => (
                                <p className="mb-0 small d-flex justify-content-between gap-3" key={label}>
                                  <span className="text-muted">{label}</span>
                                  <strong className="text-end">{value || "Not provided"}</strong>
                                </p>
                              ))}
                          </div>
                          {(selectedWorkerVerificationRequest.primaryIdPreview ||
                            selectedWorkerVerificationRequest.secondaryDocPreview) && (
                            <div className="d-flex flex-wrap gap-2 mt-3">
                              {selectedWorkerVerificationRequest.primaryIdPreview && (
                                <button
                                  className="btn btn-outline-secondary btn-sm"
                                  type="button"
                                  onClick={() => openFilePreview(selectedWorkerVerificationRequest.primaryIdPreview)}
                                >
                                  View Primary ID
                                </button>
                              )}
                              {selectedWorkerVerificationRequest.secondaryDocPreview && (
                                <button
                                  className="btn btn-outline-secondary btn-sm"
                                  type="button"
                                  onClick={() => openFilePreview(selectedWorkerVerificationRequest.secondaryDocPreview)}
                                >
                                  View Secondary Document
                                </button>
                              )}
                            </div>
                          )}
                        </div>
                      </div>
                    )}
                  </div>
                </div>
                <div className="row g-3">
                  <div className="col-12">
                    <WorkerPortfolioViewPublic
                      workerId={selectedWorker.id}
                      workerName={getDisplayName(selectedWorker.firstName, selectedWorker.lastName, selectedWorker.username)}
                      currentUser={currentUser}
                    />
                  </div>
                </div>
              </div>
            </div>
          </section>
        )}
        {view === "household-notifications" && (
          <section className="worker-dashboard household-notifications-page">
            <div className="worker-layout">
              <aside className="worker-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item" onClick={openHouseholdDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdPostJob}>
                    {navIcon("post-job")}
                    <span>Post a Job</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openHouseholdProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item active" onClick={openHouseholdNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                    {householdUnreadCount > 0 && <span className="nav-count-badge">{householdUnreadCount}</span>}
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="worker-content">
                <main className="household-notifications-container">
                  <h1 className="household-notifications-title">
                    Notifications
                    {householdUnreadCount > 0 && <span className="nav-count-badge">{householdUnreadCount}</span>}
                  </h1>

                  <section className="household-notifications-panel">
                    <div className="household-notifications-toolbar">
                      <div className="household-notifications-filter">
                        <label className="form-label mb-0" htmlFor="household-notification-date">
                          Filter Date
                        </label>
                        <input
                          id="household-notification-date"
                          type="date"
                          className="form-control"
                          value={householdNotificationDateFilter}
                          onChange={(event) => setHouseholdNotificationDateFilter(event.target.value)}
                        />
                        {householdNotificationDateFilter && (
                          <button
                            className="btn btn-outline-secondary btn-sm"
                            type="button"
                            onClick={() => setHouseholdNotificationDateFilter("")}
                          >
                            Clear
                          </button>
                        )}
                      </div>
                      <button
                        className="btn btn-outline-secondary household-notifications-read-button"
                        type="button"
                        onClick={() => markAllNotificationsRead(householdNotificationsWithReadState)}
                      >
                        Mark all as read
                      </button>
                    </div>

                    <div className="household-notifications-list">
                      {filteredHouseholdNotifications.length > 0 ? (
                        filteredHouseholdNotifications.map((item) => (
                          <article
                            className={`notification-card household-notification-item ${item.unread ? "unread" : ""}`}
                            key={item.id}
	                          >
	                            <div className="household-notification-copy">
	                              <p className="small text-muted mb-1">{formatDateTime(item.date)}</p>
	                              <h2 className="h6 mb-1">{item.title}</h2>
	                              <p className="mb-0">{item.message}</p>
	                            </div>
                              <div
                                className="household-notification-menu-wrap"
                                onClick={(event) => event.stopPropagation()}
                              >
                                <button
                                  aria-expanded={householdNotificationMenuId === item.id}
                                  aria-haspopup="menu"
                                  aria-label={`Actions for ${item.title}`}
                                  title="Notification actions"
                                  className="household-notification-menu-button"
                                  disabled={householdNotificationDeletingId === item.id}
                                  type="button"
                                  onClick={(event) => {
                                    event.stopPropagation();
                                    setHouseholdNotificationMenuId((currentId) =>
                                      currentId === item.id ? null : item.id,
                                    );
                                  }}
                                >
                                  <span aria-hidden="true">⋮</span>
                                </button>
                                {householdNotificationMenuId === item.id && (
                                  <div className="household-notification-menu" role="menu">
                                    <button
                                      className="danger"
                                      role="menuitem"
                                      type="button"
                                      onClick={() => deleteHouseholdNotification(item)}
                                    >
                                      Delete
                                    </button>
                                  </div>
                                )}
                              </div>
	                          </article>
                        ))
                      ) : (
                        <article className="notification-card household-notification-item household-notification-empty">
                          <div>
                            <h2 className="h6 mb-1">No notifications found</h2>
                            <p className="mb-0">
                              {householdNotificationDateFilter
                                ? "No household notifications match the selected date."
                                : "There are no applications or updates for this household account yet."}
                            </p>
                          </div>
                        </article>
                      )}
                    </div>
                  </section>
                </main>
              </div>
            </div>
          </section>
        )}
        {view === "household-dashboard" && (
          <section className="worker-dashboard household-dashboard-wireframe">
            <div className="household-dashboard-shell">
              <aside className="worker-sidebar household-dashboard-sidebar">
                <div className="worker-sidebar-head">
                  <div className="worker-logo">GG</div>
                  <p className="worker-brand mb-0">GawaGo Community Platform</p>
                </div>
                <nav className="worker-nav">
                  <button className="worker-nav-item active" onClick={openHouseholdDashboard}>
                    {navIcon("dashboard")}
                    <span>Dashboard</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdPostJob}>
                    {navIcon("post-job")}
                    <span>Post a Job</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdMyJobs}>
                    {navIcon("jobs")}
                    <span>My Jobs</span>
                  </button>
                  <button className="worker-nav-item" onClick={openMyComplaints}>
                    {navIcon("flag")}
                    <span>My Complaints</span>
                  </button>
                  <span className="worker-nav-section">Account</span>
                  <button className="worker-nav-item" onClick={openHouseholdProfile}>
                    {navIcon("profile")}
                    <span>My Profile</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdGetVerified}>
                    {navIcon("verified")}
                    <span>{verificationNavLabel}</span>
                  </button>
                  <button className="worker-nav-item" onClick={openHouseholdNotifications}>
                    {navIcon("notifications")}
                    <span>Notifications</span>
                    {householdUnreadCount > 0 && <span className="nav-count-badge">{householdUnreadCount}</span>}
                  </button>
                </nav>
                <div className="worker-sidebar-footer">
                  <button className="worker-sidebar-logout" type="button" onClick={handleLogout}>
                    {navIcon("logout")}
                    <span>Log Out</span>
                  </button>
                </div>
              </aside>
              <div className="household-dashboard-main">
                <div className="household-process-topline">
                  <div>
                    <h1>Welcome, {currentUser?.displayName || "Household"}</h1>
                    <p>Jobs that are still in motion &mdash; waiting on applicants, in progress, or waiting on you.</p>
                  </div>
                  <button type="button" className="btn btn-primary household-process-post-btn" onClick={openHouseholdPostJob}>
                    + Post a New Job
                  </button>
                </div>

                <p className="household-process-section-label">In Process &middot; {inProcessHouseholdJobs.length}</p>

                {inProcessHouseholdJobs.length === 0 ? (
                  <div className="profile-card p-4 text-center text-muted">
                    No jobs in process right now.{" "}
                    <button type="button" className="btn btn-link p-0 align-baseline" onClick={openHouseholdPostJob}>
                      Post a new job
                    </button>{" "}
                    to get started.
                  </div>
                ) : (
                  <div className="household-process-grid">
                    {inProcessHouseholdJobs.map((job) => {
                      const worker = getAssignedWorkerForJob(job);
                      const workerName = worker
                        ? getDisplayName(worker.firstName, worker.lastName, worker.username)
                        : null;
                      const pendingCount = getPendingApplicationCount(job);
                      // A sent hire request is still an open thread on this job:
                      // without its own state the card would claim nobody applied
                      // the moment the household asked someone.
                      const requestedCount = (job.applications || []).filter(
                        (application) => application.status === "Hire Request",
                      ).length;
                      // In progress, including jobs a worker marked done
                      // before the household took over marking jobs done.
                      const isAssigned =
                        job.status === "Already found a worker" || job.status === "Waiting for Household Confirmation";
                      const hasApplicants = !isAssigned && pendingCount > 0;
                      const awaitingReply = !isAssigned && !hasApplicants && requestedCount > 0;
                      const toneClass = isAssigned
                        ? "assigned"
                        : hasApplicants
                          ? "applicants"
                          : awaitingReply
                            ? "assigned"
                            : "open";
                      return (
                        <article key={job.id} className="household-process-card">
                          <div className="household-process-card-top">
                            <div className={`household-process-status-icon ${toneClass}`}>
                              {isAssigned || awaitingReply ? (
                                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                  <circle cx="12" cy="12" r="10"></circle>
                                  <polyline points="12 6 12 12 16 14"></polyline>
                                </svg>
                              ) : hasApplicants ? (
                                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                  <path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"></path>
                                  <circle cx="9" cy="7" r="4"></circle>
                                  <path d="M23 21v-2a4 4 0 00-3-3.87"></path>
                                  <path d="M16 3.13a4 4 0 010 7.75"></path>
                                </svg>
                              ) : (
                                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                  <circle cx="11" cy="11" r="8"></circle>
                                  <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
                                </svg>
                              )}
                            </div>
                            <div className="household-process-card-top-text">
                              <h3>{job.jobTitle || job.serviceType}</h3>
                              <span className={`household-process-status-line ${toneClass}`}>
                                <i aria-hidden="true" />
                                {isAssigned
                                    ? "In progress"
                                    : hasApplicants
                                      ? `${pendingCount} applicant${pendingCount === 1 ? "" : "s"} waiting`
                                      : awaitingReply
                                        ? `${requestedCount} request${requestedCount === 1 ? "" : "s"} sent — waiting for a reply`
                                        : "Just posted — no applicants yet"}
                              </span>
                            </div>
                          </div>
                          <div className={`household-process-worker-row ${worker ? "" : "empty"}`}>
                            <div className="household-process-mini-avatar">
                              {worker ? String(workerName).slice(0, 2).toUpperCase() : "?"}
                            </div>
                            <div>
                              <span>{worker ? workerName : "No worker hired yet"}</span>
                              {worker && <small>{worker.verification || "Verified"}</small>}
                            </div>
                          </div>
                          <p className="household-process-meta">
                            {formatRate(job.offeredRate, job.rateType)} &middot; {job.barangay || "Location not set"}
                            {job.jobStartDate && (
                              <>
                                {" "}&middot; {formatJobDate(job.jobStartDate)}
                                {job.jobEndDate ? ` to ${formatJobDate(job.jobEndDate)}` : ""}
                              </>
                            )}
                          </p>
                          {isAssigned && (
                            <button
                              type="button"
                              className="btn btn-success household-process-cta"
                              disabled={!job.canMarkDone || isActionPending(`complete-${job.id}`)}
                              onClick={() => {
                                if (isActionPending(`complete-${job.id}`)) {
                                  return;
                                }
                                if (
                                  window.confirm(
                                    `Mark this job as done? ${workerName || "The worker"} will be notified and you can both leave a review. This can't be undone.`,
                                  )
                                ) {
                                  handleConfirmJobCompleted(job.id);
                                }
                              }}
                            >
                              Mark as done
                            </button>
                          )}
                          {isAssigned && job.markDoneNote && (
                            <div className="household-process-note">{job.markDoneNote}</div>
                          )}
                          {worker && isAssigned && (
                            <button
                              type="button"
                              className="household-process-outline-cta"
                              onClick={() => openMatchedWorkerProfile(worker, job.id)}
                            >
                              View Worker &amp; Route
                            </button>
                          )}
                          {(hasApplicants || awaitingReply) && (
                            <button
                              type="button"
                              className="household-process-outline-cta"
                              onClick={() => openDashboardApplicantsModal(job)}
                            >
                              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                <path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"></path>
                                <circle cx="9" cy="7" r="4"></circle>
                                <path d="M23 21v-2a4 4 0 00-3-3.87"></path>
                              </svg>
                              View Applicants
                            </button>
                          )}
                          {!isAssigned && (
                            <button
                              type="button"
                              className="household-process-outline-cta"
                              onClick={() => openHouseholdJobMatches(job.id)}
                            >
                              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                <circle cx="11" cy="11" r="8"></circle>
                                <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
                              </svg>
                              Browse Workers
                            </button>
                          )}
                          {!isAssigned && pendingCount === 0 && (
                            <div className="household-process-note">
                              {awaitingReply
                                ? "We’ll let you know as soon as they accept or decline."
                                : "We’ll notify you as soon as a worker applies."}
                            </div>
                          )}
                          {job.status === "Open" && (
                            <button
                              type="button"
                              className="household-process-outline-cta"
                              onClick={() => setEditingJob(job)}
                            >
                              Edit Job
                            </button>
                          )}
                          {!isAssigned && (
                            <button
                              type="button"
                              className="household-process-cancel-link"
                              onClick={() => {
                                if (window.confirm("Cancel this job? This can't be undone.")) {
                                  handleCancelJob(job.id);
                                }
                              }}
                            >
                              Cancel Job
                            </button>
                          )}
                          {(job.applications || []).length > 0 && (
                            <button
                              type="button"
                              className="household-history-report-link household-process-report-link"
                              onClick={() => openDashboardReportModal(job)}
                            >
                              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"></path>
                                <line x1="4" y1="22" x2="4" y2="15"></line>
                              </svg>
                              File a Complaint
                            </button>
                          )}
                        </article>
                      );
                    })}
                  </div>
                )}

                {pendingHouseholdReviewJobs.length > 0 && (
                  <>
                    <p className="household-process-section-label household-process-section-label-spaced">
                      Completed &middot; {pendingHouseholdReviewJobs.length}
                    </p>
                    <div className="household-process-grid">
                      {pendingHouseholdReviewJobs.map((job) => {
                        const worker = getWorkerToReviewForJob(job);
                        const workerName = worker
                          ? getDisplayName(worker.firstName, worker.lastName, worker.username)
                          : null;
                        return (
                          <article key={job.id} className="household-process-card">
                            <div className="household-process-card-top">
                              <div className="household-process-status-icon review">
                                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                  <polyline points="20 6 9 17 4 12"></polyline>
                                </svg>
                              </div>
                              <div className="household-process-card-top-text">
                                <h3>{job.jobTitle || job.serviceType}</h3>
                                <span className="household-process-status-line review">
                                  <i aria-hidden="true" />
                                  Completed &middot; Rate your worker
                                </span>
                              </div>
                            </div>
                            <div className={`household-process-worker-row ${worker ? "" : "empty"}`}>
                              <div className="household-process-mini-avatar">
                                {worker ? String(workerName).slice(0, 2).toUpperCase() : "?"}
                              </div>
                              <div>
                                <span>{worker ? workerName : "Worker record unavailable"}</span>
                                {worker && <small>{worker.verification || "Verified"}</small>}
                              </div>
                            </div>
                            <p className="household-process-meta">
                              {formatRate(job.offeredRate, job.rateType)} &middot; {job.barangay || "Location not set"}
                            </p>
                            <div className="household-process-card-actions">
                              <button
                                type="button"
                                className="household-process-rate-btn"
                                disabled={!worker}
                                onClick={() => openDashboardRateModal(job, worker)}
                              >
                                <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                                  <polygon points="12 2 15 8.5 22 9.5 17 14.5 18.3 21.5 12 18 5.7 21.5 7 14.5 2 9.5 9 8.5 12 2" />
                                </svg>
                                Rate &amp; Review
                              </button>
                              <button
                                type="button"
                                className="household-process-report-btn"
                                onClick={() => openDashboardReportModal(job)}
                              >
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                  <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"></path>
                                  <line x1="4" y1="22" x2="4" y2="15"></line>
                                </svg>
                                Report
                              </button>
                            </div>
                          </article>
                        );
                      })}
                    </div>
                  </>
                )}

              </div>
            </div>
          </section>
        )}

        {/* Rendered outside any single view so it can be triggered from the
            Dashboard's cards and from My Jobs' cards alike. */}
        {dashboardModal?.type === "applicants" && selectedJob && (
          <div className="gg-modal-backdrop" role="dialog" aria-modal="true" onClick={closeDashboardModal}>
            <div className="gg-modal-panel applicants" onClick={(event) => event.stopPropagation()}>
              <div className="gg-modal-head">
                <div>
                  <p className="gg-modal-kicker">Applicants</p>
                  <h2>{selectedJob.jobTitle || selectedJob.serviceType}</h2>
                  <p className="gg-modal-sub">
                    {selectedJobApplicantWorkers.length} applicant
                    {selectedJobApplicantWorkers.length === 1 ? "" : "s"} waiting &middot; review and respond below
                  </p>
                </div>
                <button type="button" className="gg-modal-close" aria-label="Close" onClick={closeDashboardModal}>
                  &times;
                </button>
              </div>
              {selectedJobApplicantWorkers.length > 0 && (
                <div className="gg-applicant-strip">
                  {selectedJobApplicantWorkers.map((applicant, index) => {
                    const stripName = getDisplayName(applicant.firstName, applicant.lastName, applicant.username);
                    return (
                      <span className="gg-applicant-strip-item" key={`strip-${applicant.id || applicant.username}`}>
                        {index > 0 && <i className="gg-applicant-strip-dot" aria-hidden="true" />}
                        {renderWorkerPhoto(applicant, stripName, "gg-applicant-strip-photo")}
                        <span>{String(stripName).split(" ")[0]}</span>
                      </span>
                    );
                  })}
                </div>
              )}
              <div className="gg-modal-body">
                {selectedJobApplicantWorkers.length === 0 ? (
                  <p className="text-muted mb-0">No workers have applied to this job yet.</p>
                ) : (
                  selectedJobApplicantWorkers.map((applicant) => {
                    const applicantName = getDisplayName(
                      applicant.firstName,
                      applicant.lastName,
                      applicant.username,
                    );
                    const isHired = ["Hired", "Completed"].includes(applicant.applicationStatus);
                    const isRequested = applicant.applicationStatus === "Hire Request";
                    const extraSkills = Math.max(0, (applicant.skills || []).length - 3);
                    return (
                      <article className="gg-applicant-card" key={applicant.id || applicant.username}>
                        <div className="gg-applicant-head">
                          {renderWorkerPhoto(applicant, applicantName, "gg-applicant-avatar")}
                          <div className="gg-applicant-ident">
                            <h3>{applicantName}</h3>
                            <p>{applicant.locationLabel || applicant.barangay || "Location not set"}</p>
                          </div>
                          {applicant.aiScore != null && (
                            <span className="gg-applicant-ring">
                              {renderMatchRing(applicant.aiScore, 58)}
                              <small>match</small>
                            </span>
                          )}
                        </div>
                        <div className="gg-applicant-stats">
                          {applicant.verification === "Verified" && (
                            <span className="gg-applicant-check" title="Verified worker">
                              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                                <polyline points="20 6 9 17 4 12" />
                              </svg>
                            </span>
                          )}
                          {renderStarRow(applicant.rating, applicant.reviewsDone)}
                          <span className="gg-applicant-rate">{formatWorkerRate(applicant.dailyRate, "/day")}</span>
                          <span className="gg-applicant-jobs">
                            {applicant.completedJobs || 0}{" "}
                            {(applicant.completedJobs || 0) === 1 ? "job" : "jobs"}
                          </span>
                        </div>
                        <div className="gg-applicant-tags">
                          {(applicant.skills || []).slice(0, 3).map((skill) => (
                            <span key={`${applicant.id}-${skill}`}>{skill}</span>
                          ))}
                          {extraSkills > 0 && <span className="muted">+{extraSkills}</span>}
                        </div>
                        {applicant.bio && <p className="gg-applicant-bio">{applicant.bio}</p>}
                        <div className="gg-applicant-footnote">
                          <span>{applicant.appliedAt ? `Applied ${formatTimeAgo(applicant.appliedAt)}` : "Applied"}</span>
                          {applicant.applicationStatusLabel && (
                            <span className="gg-applicant-stage">{applicant.applicationStatusLabel}</span>
                          )}
                          {topApplicantKey &&
                            String(applicant.id || applicant.username) === topApplicantKey && (
                              <span className="gg-applicant-top" title="Highest AI match score among these applicants">Top AI match</span>
                            )}
                        </div>
                        <div className="gg-applicant-actions">
                          {!isHired && (
                            <button
                              type="button"
                              className="gg-applicant-decline"
                              onClick={() => {
                                if (!window.confirm("Decline this application? This can't be undone.")) {
                                  return;
                                }
                                closeDashboardModal();
                                handleRejectApplication(applicant.id, selectedJob.id);
                              }}
                            >
                              Decline
                            </button>
                          )}
                          <button
                            type="button"
                            className="gg-applicant-portfolio"
                            onClick={() => {
                              closeDashboardModal();
                              openMatchedWorkerProfile(applicant, selectedJob.id);
                            }}
                          >
                            View Profile
                          </button>
                          <button
                            type="button"
                            className="gg-applicant-hire"
                            disabled={isHired || isRequested || isActionPending(`hire-${selectedJob?.id}-${applicant.id}`)}
                            onClick={() => {
                              if (pendingHireWorkerId != null || isActionPending(`hire-${selectedJob?.id}-${applicant.id}`)) {
                                return;
                              }
                              if (
                                !window.confirm(
                                  `Accept ${applicantName} for this job? They will be hired and the job moves to In progress.`,
                                )
                              ) {
                                return;
                              }
                              requestDashboardHire(applicant);
                            }}
                          >
                            {isHired ? "Hired" : isRequested ? "Waiting for worker" : "Accept"}
                          </button>
                        </div>
                      </article>
                    );
                  })
                )}
              </div>
              <div className="gg-modal-foot">
                <button type="button" className="gg-modal-foot-btn" onClick={closeDashboardModal}>
                  Close
                </button>
              </div>
            </div>
          </div>
        )}

        {dashboardModal?.type === "rate" && selectedJob && selectedWorker && (
          <div className="gg-modal-backdrop" role="dialog" aria-modal="true" onClick={closeDashboardModal}>
            <div className="gg-modal-panel rate" onClick={(event) => event.stopPropagation()}>
              <aside className="gg-rate-aside">
                <button
                  type="button"
                  className="gg-rate-close"
                  aria-label="Close"
                  onClick={closeDashboardModal}
                >
                  &times;
                </button>
                <div className="gg-rate-avatar">
                  {String(
                    getDisplayName(selectedWorker.firstName, selectedWorker.lastName, selectedWorker.username),
                  )
                    .slice(0, 2)
                    .toUpperCase()}
                </div>
                <h3>
                  {getDisplayName(selectedWorker.firstName, selectedWorker.lastName, selectedWorker.username)}
                </h3>
                <p className="gg-rate-verified">
                  {selectedWorker.verification === "Verified" ? "✓ Verified" : selectedWorker.verification || "Not Yet Verified"}
                </p>
                <div className="gg-rate-score">
                  <strong>{Number.parseFloat(selectedWorker.rating) ? Number.parseFloat(selectedWorker.rating).toFixed(2) : "—"}</strong>
                  <span>
                    {Number.parseFloat(selectedWorker.rating)
                      ? `${selectedWorker.reviewsDone || 0} ${Number(selectedWorker.reviewsDone) === 1 ? "review" : "reviews"}`
                      : "No ratings yet"}
                  </span>
                </div>
                <dl className="gg-rate-facts">
                  <div>
                    <dt>Skills</dt>
                    <dd>{(selectedWorker.skills || []).join(", ") || selectedJob.serviceType}</dd>
                  </div>
                  <div>
                    <dt>Location</dt>
                    <dd>{selectedWorker.barangay || "Not set"}</dd>
                  </div>
                  <div>
                    <dt>Rate</dt>
                    <dd>{formatWorkerRate(selectedWorker.dailyRate, " / Per Day")}</dd>
                  </div>
                  <div>
                    <dt>Job</dt>
                    <dd>{selectedJob.jobTitle || selectedJob.serviceType}</dd>
                  </div>
                </dl>
              </aside>
              <div className="gg-rate-main">
                <p className="gg-modal-kicker">Rate &amp; Review</p>
                <h2>How was your experience?</h2>
                <form
                  className="gg-rate-form"
                  onSubmit={async (event) => {
                    const ratedJob = selectedJob;
                    const ratedWorker = selectedWorker;
                    const submitted = await handleHouseholdReviewSubmit(event);
                    if (submitted) {
                      closeDashboardModal();
                      if (ratedJob && ratedWorker?.id) {
                        setSkillRatingTarget({
                          jobId: ratedJob.id,
                          workerId: ratedWorker.id,
                          workerName: getDisplayName(ratedWorker.firstName, ratedWorker.lastName, ratedWorker.username),
                          jobTitle: ratedJob.jobTitle || ratedJob.serviceType,
                          jobSkill: ratedJob.requiredSkill || ratedJob.serviceType,
                        });
                      }
                    }
                  }}
                >
                  <label className="form-label fw-semibold" htmlFor="dashboard-rate-stars">
                    Overall Rating
                  </label>
                  {renderHouseholdStarRatingInput("dashboard-rate-stars")}
                  {renderHouseholdReviewMetricInputs()}
                  <label className="form-label fw-semibold mt-3">Feedback (optional)</label>
                  <textarea
                    className="form-control"
                    rows="4"
                    placeholder="Share details about the worker's performance..."
                    value={householdReviewForm.feedback}
                    onChange={(event) =>
                      setHouseholdReviewForm((prev) => ({ ...prev, feedback: event.target.value }))
                    }
                  />
                  <div className="gg-rate-actions">
                    <button className="btn btn-success gg-rate-submit" type="submit">
                      Submit Rating
                    </button>
                    <button
                      className="btn btn-link gg-rate-cancel"
                      type="button"
                      onClick={closeDashboardModal}
                    >
                      Cancel
                    </button>
                  </div>
                </form>
              </div>
            </div>
          </div>
        )}

        {skillRatingTarget && (
          <div className="gg-modal-backdrop" role="dialog" aria-modal="true" aria-label="Rate skills">
            <div className="gg-skill-rating-panel" onClick={(event) => event.stopPropagation()}>
              <SkillRatingForm
                key={`${skillRatingTarget.jobId}-${skillRatingTarget.workerId}`}
                jobId={skillRatingTarget.jobId}
                workerId={skillRatingTarget.workerId}
                workerName={skillRatingTarget.workerName}
                jobTitle={skillRatingTarget.jobTitle}
                jobSkill={skillRatingTarget.jobSkill}
                onSubmitSuccess={() => {
                  setSkillRatingTarget(null);
                  addToast("Skill ratings saved.", "success");
                }}
                onCancel={() => setSkillRatingTarget(null)}
              />
            </div>
          </div>
        )}

        {editingJob && (
          <EditJobDialog
            job={editingJob}
            todayIsoDate={todayIsoDate}
            onSave={(form) => handleUpdateJob(editingJob, form)}
            onClose={() => setEditingJob(null)}
          />
        )}

        {showComplaintModal && selectedJob && (
          <ComplaintModal
            isOpen={showComplaintModal}
            onClose={() => setShowComplaintModal(false)}
            onSubmitted={() => addToast("Complaint submitted. Our admin team will review it.", "success")}
            job={selectedJob}
            role="household"
            applicants={(selectedJob.applications || []).map((application) => ({
              id: application.workerId,
              username: application.workerUsername,
              name: application.workerName,
            }))}
          />
        )}
      </main>
    </div>
  );
}
