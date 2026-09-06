export function getDisplayName(firstName, lastName, username) {
  const fullName = `${firstName || ""} ${lastName || ""}`.trim();
  return fullName || username || "User";
}

export function formatCurrency(amount) {
  const value = Number(amount || 0);
  return `PHP ${value.toFixed(2)}`;
}

export function formatRate(amount, rateType) {
  return `${formatCurrency(amount)} / ${rateType || "Per Day"}`;
}

export function isImagePreviewUrl(url) {
  const normalizedUrl = String(url || "").trim();
  return /^data:image\//i.test(normalizedUrl) || /\.(png|jpe?g|gif|webp|bmp)$/i.test(normalizedUrl.split("?")[0]);
}

export function formatScheduleLabel(scheduleType) {
  if (typeof scheduleType !== "string") {
    return "";
  }
  return scheduleType.replace(/\s*-\s*/g, "-");
}

export function formatDateTime(dateValue, timeValue) {
  if (!dateValue) {
    return "Schedule not set";
  }
  const rawDate = String(dateValue).trim();
  const hasEmbeddedTime = /[T ]\d{2}:\d{2}/.test(rawDate);
  const parsedDate = new Date(hasEmbeddedTime ? rawDate : `${rawDate}T${timeValue || "00:00"}`);
  if (Number.isNaN(parsedDate.getTime())) {
    return rawDate;
  }
  return parsedDate.toLocaleString("en-PH", {
    month: "long",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

export function formatExperience(years) {
  const numericYears = Number(years || 0);
  return `${numericYears} ${numericYears === 1 ? "year" : "years"}`;
}

export function formatLocation(barangay, streetAddress) {
  return [barangay, streetAddress].filter(Boolean).join(", ") || "Location not set";
}

export function formatDistance(distanceKm, fallbackLabel = "") {
  if (distanceKm === null || distanceKm === undefined || distanceKm === "") {
    return fallbackLabel || "Distance not available";
  }
  const numericDistance = Number(distanceKm);
  if (Number.isFinite(numericDistance) && numericDistance >= 0) {
    if (numericDistance < 1) {
      return `${Math.max(1, Math.round(numericDistance * 1000))} meters away`;
    }
    return `${numericDistance.toFixed(1)} km away`;
  }
  return fallbackLabel || "Distance not available";
}

export function getWorkerPhoto(worker) {
  const preview = worker?.profilePhotoPreview || "";
  return /^blob:/i.test(String(preview || "")) ? "" : preview;
}

export function getHouseholdPhoto(household) {
  const preview = household?.profilePhotoPreview || "";
  return /^blob:/i.test(String(preview || "")) ? "" : preview;
}

export function getDisplayRating(ratingCount, averageRating) {
  if (!ratingCount || averageRating == null) {
    return "No ratings yet";
  }
  return `${Number(averageRating).toFixed(2)} / 5`;
}

export function sanitizePhilippinesPhone(value) {
  return String(value || "").replace(/[^0-9]/g, "").replace(/^0+/, "").slice(0, 10);
}
