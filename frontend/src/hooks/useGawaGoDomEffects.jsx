import { useEffect } from "react";
import { readResponseData } from "../utils/apiUtils";
export function useGawaGoDomEffects({
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
}) {
  useEffect(() => {
    if (verificationRequests.length === 0) {
      setSelectedVerificationRequestId(null);
      return;
    }
    if (!verificationRequests.some((item) => item.id === selectedVerificationRequestId)) {
      setSelectedVerificationRequestId(verificationRequests[0].id);
    }
  }, [verificationRequests, selectedVerificationRequestId]);
  useEffect(() => {
    if (currentUser?.role !== "household") {
      return;
    }
    if (!householdJobs.length) {
      setSelectedJobId(null);
      return;
    }
    if (!householdJobs.some((item) => String(item.id) === String(selectedJobId))) {
      setSelectedJobId(householdJobs[0].id);
    }
  }, [currentUser?.role, householdJobs, selectedJobId]);
  useEffect(() => {
    if (view !== "household-post-job") {
      return;
    }
    const savedLocation = getSavedHouseholdLocation(currentHousehold, currentUser);
    if (!savedLocation.barangay && !savedLocation.streetAddress) {
      return;
    }
    setHouseholdJobForm((prev) => {
      if (prev.barangay && prev.streetAddress) {
        return prev;
      }
      return {
        ...prev,
        barangay: prev.barangay || savedLocation.barangay,
        streetAddress: prev.streetAddress || savedLocation.streetAddress,
      };
    });
  }, [
    view,
    currentHousehold?.barangay,
    currentHousehold?.streetAddress,
    currentUser?.profile?.location_label,
    currentUser?.profile?.locationLabel,
  ]);
  useEffect(() => {
    setUnauthorizedHandler((response) => {
      const finishLogout = (message) => {
        clearAuthToken();
        setCurrentUser(null);
        setSelectedWorkerId(null);
        setSelectedJobId(null);
        setLoginForm({
          username: "",
          password: "",
          role: "worker",
        });
        setView("login");
        if (message) {
          window.alert(message);
        }
      };
      // The server explains *why* the session ended (blocked account, revoked
      // token, expired session) in the response body -- without reading it,
      // every 401 looked identical to the user: a silent bounce to login.
      readResponseData(response)
        .then((data) => finishLogout(data?.detail))
        .catch(() => finishLogout());
    });
    return () => setUnauthorizedHandler(null);
  }, []);
}
