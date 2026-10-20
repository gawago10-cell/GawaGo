import { useEffect } from "react";
import { STORAGE_KEYS } from "../constants/appConstants";
import { stripTransientBlobUrls } from "../utils/mediaUtils";

const SENSITIVE_STORAGE_FIELDS = new Set(["password", "confirmPassword"]);

function stripSensitiveFields(value) {
  if (Array.isArray(value)) {
    return value.map(stripSensitiveFields);
  }
  if (!value || typeof value !== "object") {
    return value;
  }
  return Object.fromEntries(
    Object.entries(value)
      .filter(([key]) => !SENSITIVE_STORAGE_FIELDS.has(key))
      .map(([key, entry]) => [key, stripSensitiveFields(entry)]),
  );
}

export function useGawaGoPersistence({
  isDemoMode = false,
  notificationReads,
  postedJobs,
  registeredHouseholds,
  registeredWorkers,
  verificationRequests,
}) {
  function saveStoredValue(key, value) {
    try {
      window.localStorage.setItem(key, JSON.stringify(stripSensitiveFields(stripTransientBlobUrls(value))));
    } catch (error) {
      return;
    }
  }

  useEffect(() => {
    if (!isDemoMode) {
      return;
    }
    saveStoredValue(STORAGE_KEYS.workers, registeredWorkers);
  }, [isDemoMode, registeredWorkers]);

  useEffect(() => {
    if (!isDemoMode) {
      return;
    }
    saveStoredValue(STORAGE_KEYS.households, registeredHouseholds);
  }, [isDemoMode, registeredHouseholds]);

  useEffect(() => {
    if (!isDemoMode) {
      return;
    }
    saveStoredValue(STORAGE_KEYS.verificationRequests, verificationRequests);
  }, [isDemoMode, verificationRequests]);

  useEffect(() => {
    if (!isDemoMode) {
      return;
    }
    saveStoredValue(STORAGE_KEYS.jobs, postedJobs);
  }, [isDemoMode, postedJobs]);

  useEffect(() => {
    saveStoredValue(STORAGE_KEYS.notificationReads, notificationReads);
  }, [notificationReads]);
}
