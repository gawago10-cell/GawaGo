import { useEffect, useRef, useState } from "react";
import { clearAuthToken, getAuthToken } from "../api/apiClient";
import {
  fetchCurrentAccount,
  fetchJobs,
  fetchNotifications,
  fetchProfiles,
  fetchRecommendedWorkers,
  fetchReviews,
  fetchVerificationRequests,
} from "../services/backendDataService";
import { formatDistance } from "../utils/formatters";
import { getWorkerVerificationLabel } from "../utils/normalizers";
export function useBackendSync({
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
}) {
  const [recommendedWorkersLoading, setRecommendedWorkersLoading] = useState(false);
  // The polling hook re-fires these refreshes every few seconds. Each async
  // function below closes over the `currentUser` from whichever render
  // started it, so if the user logs out or switches accounts while a
  // request is still in flight, that stale closure has no way to see the
  // change -- it would apply a previous account's data on top of the new
  // session once the request resolves. A ref (kept current on every render,
  // unlike the closure) lets each refresh check the *live* identity right
  // before it commits, and skip the write if it's no longer current.
  const currentUserRef = useRef(currentUser);
  const recommendedRequestSeqRef = useRef({});
  useEffect(() => {
    currentUserRef.current = currentUser;
  }, [currentUser]);
  function mergeBackendWorkerIntoState(backendWorker) {
    if (!backendWorker) {
      return;
    }
    setRegisteredWorkers((prev) => {
      const existingIndex = prev.findIndex(
        (item) =>
          item.id === backendWorker.id || item.username?.toLowerCase() === backendWorker.username?.toLowerCase(),
      );
      if (existingIndex < 0) {
        return [backendWorker, ...prev];
      }
      return prev.map((item, index) =>
        index === existingIndex
          ? {
              ...item,
              ...backendWorker,
              receivedReviews:
                item.receivedReviews?.length ? item.receivedReviews : backendWorker.receivedReviews || [],
              givenFeedback:
                item.givenFeedback?.length ? item.givenFeedback : backendWorker.givenFeedback || [],
            }
          : item,
      );
    });
  }
  async function refreshVerificationStateFromBackend() {
    if (!currentUser?.username) {
      return;
    }
    const requestedUsername = currentUser.username;
    try {
      const normalizedRequests = await fetchVerificationRequests();
      if (currentUserRef.current?.username !== requestedUsername) {
        return;
      }
      if (normalizedRequests) {
        setVerificationRequests(normalizedRequests);
        setSelectedVerificationRequestId((prevSelectedId) => {
          if (normalizedRequests.some((item) => item.id === prevSelectedId)) {
            return prevSelectedId;
          }
          if (currentUser.role === "worker" || currentUser.role === "household") {
            return (
              normalizedRequests.find((item) => item.workerUsername === currentUser.username)?.id ||
              normalizedRequests[0]?.id ||
              null
            );
          }
          return normalizedRequests[0]?.id || null;
        });
        if (currentUser.role === "worker" || currentUser.role === "household") {
          const matchingRequest = normalizedRequests.find((item) => item.workerUsername === currentUser.username);
          if (!getAuthToken() && matchingRequest) {
            const nextVerificationStatus =
              matchingRequest.status === "Approved"
                ? "approved"
                : matchingRequest.status === "Rejected"
                  ? "rejected"
                  : "pending";
            setCurrentUser((prev) =>
              prev
                ? {
                    ...prev,
                    profile: {
                      ...(prev.profile || {}),
                      verification_status: nextVerificationStatus,
                      verification_request: matchingRequest,
                    },
                  }
                : prev,
            );
          }
          if (matchingRequest && currentUser.role === "worker") {
            const nextVerificationLabel =
              matchingRequest.status === "Approved"
                ? "Verified"
                : matchingRequest.status === "Rejected"
                  ? "Rejected"
                  : "Under Review";
            setRegisteredWorkers((prev) =>
              prev.map((worker) =>
                worker.username === currentUser.username
                  ? {
                      ...worker,
                      verification: nextVerificationLabel,
                      verificationRequestId: matchingRequest.id,
                      verificationSubmission: matchingRequest,
                      verificationReviewedAt: matchingRequest.reviewedAt || worker.verificationReviewedAt || "",
                      verificationReviewedBy: matchingRequest.reviewedBy || worker.verificationReviewedBy || "",
                      verificationRejectionNote: matchingRequest.reviewNote || worker.verificationRejectionNote || "",
                    }
                  : worker,
              ),
            );
          } else if (currentUser.role === "worker") {
            setRegisteredWorkers((prev) =>
              prev.map((worker) =>
                worker.username === currentUser.username
                  ? {
                      ...worker,
                      verificationSubmission: null,
                      verificationRequestId: null,
                    }
                  : worker,
              ),
            );
          }
          if (matchingRequest && currentUser.role === "household") {
            const nextVerificationLabel =
              matchingRequest.status === "Approved"
                ? "Verified"
                : matchingRequest.status === "Rejected"
                  ? "Rejected"
                  : "Under Review";
            setRegisteredHouseholds((prev) =>
              prev.map((household) =>
                household.username === currentUser.username
                  ? {
                      ...household,
                      verification: nextVerificationLabel,
                      verificationRequestId: matchingRequest.id,
                      verificationSubmission: matchingRequest,
                      verificationReviewedAt:
                        matchingRequest.reviewedAt || household.verificationReviewedAt || "",
                      verificationReviewedBy:
                        matchingRequest.reviewedBy || household.verificationReviewedBy || "",
                      verificationRejectionNote:
                        matchingRequest.reviewNote || household.verificationRejectionNote || "",
                    }
                  : household,
              ),
            );
          }
        }
      }
      if (getAuthToken()) {
        const accountData = await fetchCurrentAccount(currentUser);
        if (accountData) {
          setCurrentUser((prev) =>
            prev
              ? {
                  ...prev,
                  ...accountData.refreshedUser,
                }
              : prev,
          );
          if (currentUser.role === "worker") {
            mergeBackendWorkerIntoState(accountData.worker);
          }
        }
      }
    } catch (error) {
      return;
    }
  }
  async function refreshJobsFromBackend() {
    // Per-job fields like can_apply/current_worker_application depend on
    // whichever auth token was active when the request went out, so a
    // response for a since-logged-out (or since-switched) identity must not
    // be applied on top of the new session.
    const requestedUsername = currentUser?.username;
    try {
      const normalizedJobs = await fetchJobs();
      if (!normalizedJobs) return;
      if (currentUserRef.current?.username !== requestedUsername) return;
      setPostedJobs(normalizedJobs);
      if (normalizedJobs.length === 0) {
        setMatchedWorkersByJob({});
      }
    } catch (error) {
      return;
    }
  }
  async function refreshProfilesFromBackend() {
    try {
      const profilesData = await fetchProfiles();
      if (!profilesData) return;
      const { normalizedProfiles, workerProfiles, householdProfiles } = profilesData;
      setRegisteredWorkers((prev) =>
        workerProfiles.map((workerProfile) => {
          const existing = prev.find(
            (item) =>
              item.username?.toLowerCase() === workerProfile.username?.toLowerCase() ||
              String(item.id) === String(workerProfile.id),
          );
          return {
            ...existing,
            ...workerProfile,
            verificationSubmission: existing?.verificationSubmission || null,
            verificationNotifications: existing?.verificationNotifications || [],
            applicationNotifications: existing?.applicationNotifications || [],
            receivedReviews: existing?.receivedReviews || [],
            givenFeedback: existing?.givenFeedback || [],
            avatar:
              existing?.avatar || (workerProfile.firstName || workerProfile.username || "W").slice(0, 1).toUpperCase(),
            bio: workerProfile.bio || existing?.bio || "",
            phone: workerProfile.phone || existing?.phone || "",
            yearsExperience: workerProfile.yearsExperience ?? existing?.yearsExperience ?? "0",
            status: existing?.status || "Available",
            distanceKm: existing?.distanceKm ?? null,
            distanceLabel: existing?.distanceLabel || "",
          };
        }),
      );
      setRegisteredHouseholds((prev) =>
        householdProfiles.map((householdProfile) => {
          const existing = prev.find(
            (item) =>
              item.username?.toLowerCase() === householdProfile.username?.toLowerCase() ||
              String(item.id) === String(householdProfile.id),
          );
          return {
            ...existing,
            ...householdProfile,
            avatar:
              existing?.avatar ||
              (householdProfile.firstName || householdProfile.username || "H").slice(0, 1).toUpperCase(),
            phone: householdProfile.phone || existing?.phone || "",
            receivedFeedback: existing?.receivedFeedback || [],
            givenFeedback: existing?.givenFeedback || [],
          };
        }),
      );
      const isPlatformAdmin = currentUser?.role === "admin" || currentUser?.role === "superadmin";
      if (currentUser?.role && !isPlatformAdmin) {
        const userStillExists = normalizedProfiles.some((profile) => profile.username === currentUser.username);
        if (!userStillExists) {
          clearAuthToken();
          setCurrentUser(null);
          setSelectedJobId(null);
          setSelectedWorkerId(null);
          setMatchedWorkersByJob({});
          setView("login");
          window.alert("Your account data was removed from the backend, so the local session has been cleared.");
        }
      }
    } catch (error) {
      return;
    }
  }
  async function refreshRecommendedWorkers(jobId, rank) {
    if (!jobId) {
      return;
    }
    // The AI ranking takes ~10s on a job's first call, so a Smart Matching
    // request sent later can finish first -- or the other way round. Only the
    // newest request for a job may write its results, otherwise a late
    // "smart" reply zeroes the AI breakdown on the AI matches screen.
    const requestSeq = (recommendedRequestSeqRef.current[jobId] || 0) + 1;
    recommendedRequestSeqRef.current[jobId] = requestSeq;
    const isLatest = () => recommendedRequestSeqRef.current[jobId] === requestSeq;
    setRecommendedWorkersLoading(true);
    try {
      const results = await fetchRecommendedWorkers(jobId, rank);
      if (results === null || !isLatest()) return;
      setMatchedWorkersByJob((prev) => ({
        ...prev,
        [jobId]: results.map((result) => {
          const existingWorker = registeredWorkers.find(
            (worker) => String(worker.id) === String(result.worker_id) || worker.username === result.worker_username,
          );
          const distanceLabel = result.distance_label || formatDistance(result.distance_km);
          return {
            ...existingWorker,
            id: existingWorker?.id || result.worker_id,
            username: existingWorker?.username || result.worker_username,
            firstName: existingWorker?.firstName || "",
            lastName: existingWorker?.lastName || "",
            // The match endpoint now carries the profile fields the match
            // cards render, so they no longer depend on the worker also
            // being present in the separately fetched registeredWorkers.
            displayName: result.worker_name || existingWorker?.displayName || "",
            profilePhotoPreview: result.worker_profile_photo_url || existingWorker?.profilePhotoPreview || "",
            barangay: existingWorker?.barangay || result.worker_location_label || "",
            bio: result.worker_bio || existingWorker?.bio || "",
            completedJobs: result.worker_completed_jobs ?? 0,
            skills: result.skills || existingWorker?.skills || [],
            verification: getWorkerVerificationLabel(result.verification_status),
            rating: result.rating_label || existingWorker?.rating || "No ratings yet",
            reviewsDone: result.worker_rating_count ?? existingWorker?.reviewsDone ?? 0,
            hourlyRate: existingWorker?.hourlyRate || "0.00",
            dailyRate: existingWorker?.dailyRate || result.worker_rate || "0.00",
            status: existingWorker?.status || "Available",
            avatar: existingWorker?.avatar || (result.worker_username || "W").slice(0, 1).toUpperCase(),
            // Match candidates are never hired yet, so the API sends no exact
            // coordinates and no route to plot -- only a rounded distance and
            // a ~1 km grid-snapped point for the matches map.
            latitude: null,
            longitude: null,
            approximateLatitude: result.worker_approximate_latitude ?? null,
            approximateLongitude: result.worker_approximate_longitude ?? null,
            matchesSkill: Boolean(result.matches_skill),
            distanceKm:
              result.distance_km !== null &&
              result.distance_km !== undefined &&
              result.distance_km !== "" &&
              Number.isFinite(Number(result.distance_km))
                ? Number(result.distance_km)
                : null,
            distanceLabel,
            routePoints: [],
            matchScore: result.match_score,
            availableAtRequestedTime: result.available_at_requested_time,
            aiScore: result.ai_score,
            aiSkillContribution: result.skill_contribution,
            aiProximityContribution: result.proximity_contribution,
            aiExactSkillMatch: result.exact_skill_match,
          };
        }),
      }));
    } catch (error) {
      return;
    } finally {
      if (isLatest()) {
        setRecommendedWorkersLoading(false);
      }
    }
  }
  async function refreshNotificationsFromBackend() {
    if (!currentUser?.username) {
      setBackendNotifications([]);
      return;
    }
    if (!getAuthToken()) {
      setBackendNotifications([]);
      return;
    }
    const requestedUsername = currentUser.username;
    try {
      const notifications = await fetchNotifications(currentUser.username);
      if (!notifications) return;
      if (currentUserRef.current?.username !== requestedUsername) return;
      setBackendNotifications(notifications);
    } catch (error) {
      return;
    }
  }
  async function refreshReviewsFromBackend() {
    if (!currentUser?.username) {
      return;
    }
    const requestedUsername = currentUser.username;
    try {
      const payloads = await fetchReviews({
        username: currentUser.username,
        role: currentUser.role,
        selectedWorkerUsername: selectedWorker?.username || "",
      });
      if (currentUserRef.current?.username !== requestedUsername) return;
      // null means that list failed to load: keep what is already shown.
      const [receivedReviews, authoredReviews] = payloads;
      if (currentUser.role === "worker") {
        setRegisteredWorkers((prev) =>
          prev.map((worker) =>
            worker.username === currentUser.username
              ? {
                  ...worker,
                  ...(receivedReviews ? { receivedReviews } : {}),
                  ...(authoredReviews ? { givenFeedback: authoredReviews } : {}),
                }
              : worker,
          ),
        );
      }
      if (currentUser.role === "household") {
        setRegisteredHouseholds((prev) =>
          prev.map((household) =>
            household.username === currentUser.username
              ? {
                  ...household,
                  ...(receivedReviews ? { receivedFeedback: receivedReviews } : {}),
                  ...(authoredReviews ? { givenFeedback: authoredReviews } : {}),
                }
              : household,
          ),
        );
        if (selectedWorker?.username && payloads[2]) {
          const selectedWorkerReviews = payloads[2];
          setRegisteredWorkers((prev) =>
            prev.map((worker) =>
              worker.username === selectedWorker.username
                ? {
                    ...worker,
                    receivedReviews: selectedWorkerReviews,
                  }
                : worker,
            ),
          );
        }
      }
    } catch (error) {
      return;
    }
  }
  return {
    mergeBackendWorkerIntoState,
    refreshVerificationStateFromBackend,
    refreshJobsFromBackend,
    refreshProfilesFromBackend,
    refreshRecommendedWorkers,
    refreshNotificationsFromBackend,
    refreshReviewsFromBackend,
    recommendedWorkersLoading,
  };
}
