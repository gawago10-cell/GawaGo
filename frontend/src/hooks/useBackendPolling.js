import { useEffect } from "react";

export function useBackendPolling({
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
}) {
  useEffect(() => {
    if (!currentUser?.username) {
      return;
    }
    refreshProfilesFromBackend();
  }, [currentUser?.username]);

  useEffect(() => {
    if (currentUser?.role !== "household" || !selectedJob?.id) {
      return;
    }
    // The post-a-job matches screen explicitly fetches rank="ai" right
    // after posting; without matching that here, this poll (which re-fires
    // on every registeredWorkers.length change) would overwrite it with the
    // default "smart" ranking moments later. Everywhere else (the regular
    // job detail view), the default must stay "smart" -- AGENTS.md I.B/I.C
    // documents that Smart Matching's priority order is not to be silently
    // replaced by AI ranking.
    const rank = view === "household-job-matches" ? "ai" : undefined;
    refreshRecommendedWorkers(selectedJob.id, rank);
  }, [currentUser?.role, selectedJob?.id, registeredWorkers.length, view]);

  useEffect(() => {
    if (currentUser?.role !== "worker" || !currentWorkerVerificationLabel) {
      return;
    }
    const normalizedProfileStatus =
      currentWorkerVerificationLabel === "Verified"
        ? "verified"
        : currentWorkerVerificationLabel === "Rejected"
          ? "rejected"
          : currentWorkerVerificationLabel === "Under Review"
            ? "pending"
            : "unverified";
    if (currentUser?.profile?.verification_status === normalizedProfileStatus) {
      return;
    }
    setCurrentUser((prev) => {
      if (!prev || prev.role !== "worker") {
        return prev;
      }
      return {
        ...prev,
        profile: {
          ...(prev.profile || {}),
          verification_status: normalizedProfileStatus,
          verification_request: currentWorkerVerificationRequest || prev.profile?.verification_request || null,
        },
      };
    });
  }, [
    currentUser?.role,
    currentUser?.profile?.verification_status,
    currentWorkerVerificationLabel,
    currentWorkerVerificationRequest,
  ]);

  useEffect(() => {
    let cancelled = false;
    let intervalId = null;

    async function syncVerificationState() {
      if (!currentUser?.username) {
        return;
      }
      if (!cancelled) {
        await refreshVerificationStateFromBackend();
      }
    }

    syncVerificationState();
    if (currentUser?.username) {
      intervalId = window.setInterval(syncVerificationState, currentUser.role === "worker" ? 3000 : 5000);
    }
    return () => {
      cancelled = true;
      if (intervalId) {
        window.clearInterval(intervalId);
      }
    };
  }, [
    currentUser?.username,
    currentUser?.role,
    currentUser?.profile?.verification_status,
    currentUser?.profile?.verification_request?.id,
    currentUser?.profile?.verification_request?.reviewed_at,
    currentUser?.profile?.verification_request?.status,
  ]);

  useEffect(() => {
    let cancelled = false;
    let intervalId = null;

    async function syncJobs() {
      if (cancelled) {
        return;
      }
      await refreshJobsFromBackend();
    }

    syncJobs();
    intervalId = window.setInterval(syncJobs, currentUser?.username ? 5000 : 10000);
    return () => {
      cancelled = true;
      if (intervalId) {
        window.clearInterval(intervalId);
      }
    };
  }, [currentUser?.username, currentUser?.role]);

  useEffect(() => {
    let cancelled = false;
    let intervalId = null;

    async function syncBackendActivity() {
      if (cancelled) {
        return;
      }
      if (!currentUser?.username) {
        setBackendNotifications([]);
        return;
      }
      await refreshNotificationsFromBackend();
      await refreshReviewsFromBackend();
    }

    syncBackendActivity();
    if (currentUser?.username) {
      intervalId = window.setInterval(syncBackendActivity, 5000);
    }
    return () => {
      cancelled = true;
      if (intervalId) {
        window.clearInterval(intervalId);
      }
    };
  }, [currentUser?.username, currentUser?.role, selectedWorker?.username]);
}
