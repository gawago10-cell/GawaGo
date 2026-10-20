import { DEMO_DATA_VERSION, DEMO_VERSION_KEY, STORAGE_KEYS } from "../constants/appConstants";
import { stripTransientBlobUrls } from "./mediaUtils";

export function clearDemoStorage() {
  if (typeof window === "undefined") {
    return;
  }
  Object.values(STORAGE_KEYS).forEach((key) => {
    window.localStorage.removeItem(key);
  });
  window.localStorage.setItem(DEMO_VERSION_KEY, DEMO_DATA_VERSION);
}

export function ensureDemoVersion() {
  if (typeof window === "undefined") {
    return;
  }
  const savedVersion = window.localStorage.getItem(DEMO_VERSION_KEY);
  if (savedVersion !== DEMO_DATA_VERSION) {
    clearDemoStorage();
  }
}

export function getStoredCollection(key, fallback) {
  if (typeof window === "undefined") {
    return fallback;
  }
  const storedValue = window.localStorage.getItem(key);
  if (!storedValue) {
    return fallback;
  }
  try {
    const parsedValue = JSON.parse(storedValue);
    return Array.isArray(parsedValue) ? stripTransientBlobUrls(parsedValue) : fallback;
  } catch (error) {
    return fallback;
  }
}

export function mergeDemoRecords(records, demoRecords, key = "username") {
  const currentRecords = Array.isArray(records) ? records : [];
  const demoByKey = new Map(demoRecords.map((record) => [String(record?.[key] || "").toLowerCase(), record]));
  const existingKeys = new Set(currentRecords.map((record) => String(record?.[key] || "").toLowerCase()));
  const missingDemoRecords = demoRecords.filter((record) => !existingKeys.has(String(record?.[key] || "").toLowerCase()));
  const syncedRecords = currentRecords.map((record) => {
    const matchingDemo = demoByKey.get(String(record?.[key] || "").toLowerCase());
    const isDemoRecord = String(record?.id || "").startsWith("demo-") || String(matchingDemo?.id || "").startsWith("demo-");
    if (!matchingDemo || !isDemoRecord) {
      return record;
    }
    return {
      ...record,
      barangay: matchingDemo.barangay ?? record.barangay,
      streetAddress: matchingDemo.streetAddress ?? record.streetAddress,
      latitude: matchingDemo.latitude ?? record.latitude,
      longitude: matchingDemo.longitude ?? record.longitude,
    };
  });
  return [...missingDemoRecords, ...syncedRecords];
}

export function getStoredObject(key, fallback) {
  if (typeof window === "undefined") {
    return fallback;
  }
  const storedValue = window.localStorage.getItem(key);
  if (!storedValue) {
    return fallback;
  }
  try {
    const parsedValue = JSON.parse(storedValue);
    return parsedValue && typeof parsedValue === "object" && !Array.isArray(parsedValue)
      ? stripTransientBlobUrls(parsedValue)
      : fallback;
  } catch (error) {
    return fallback;
  }
}

export function getNotificationReadState() {
  return getStoredObject(STORAGE_KEYS.notificationReads, {});
}
