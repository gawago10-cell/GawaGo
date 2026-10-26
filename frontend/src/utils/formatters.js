export function getDisplayName(firstName, lastName, username) {
  const fullName = `${firstName || ""} ${lastName || ""}`.trim();
  return fullName || username || "User";
}

export function formatCurrency(amount) {
  const value = Number(amount || 0);
  return `PHP ${value.toFixed(2)}`;
}

/** A worker's disclosed rate, or "Not disclosed": an unset rate used to
 * show as "PHP 0.00", which reads as a free service (AGENTS.md II.B). */
export function formatWorkerRate(amount, suffix = "") {
  const value = Number(amount);
  if (amount === null || amount === undefined || amount === "" || !Number.isFinite(value) || value <= 0) {
    return "Not disclosed";
  }
  return `${formatCurrency(value)}${suffix}`;
}

export function formatRate(amount, rateType) {
  return `${formatCurrency(amount)} / ${rateType || "Per Day"}`;
}

export function isImagePreviewUrl(url) {
  const normalizedUrl = String(url || "").trim();
  return /^data:image\//i.test(normalizedUrl) || /\.(png|jpe?g|gif|webp|bmp)$/i.test(normalizedUrl.split("?")[0]);
}

/** A job date ("2026-10-04") as "Oct 4, 2026", matching the mobile app's
 * formatting. Non-date text (a schedule description, "Not set") passes
 * through unchanged rather than being mangled. */
export function formatJobDate(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed) {
    return "";
  }
  if (!/^\d{4}-\d{2}-\d{2}/.test(trimmed)) {
    return trimmed;
  }
  const parsed = new Date(trimmed.length === 10 ? `${trimmed}T00:00:00` : trimmed);
  if (Number.isNaN(parsed.getTime())) {
    return trimmed;
  }
  return parsed.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

export function formatScheduleLabel(scheduleType) {
  if (typeof scheduleType !== "string") {
    return "";
  }
  return scheduleType.replace(/\s*-\s*/g, "-");
}

/** A backend timestamp ("2026-10-26T02:10:09.887+08:00") in the app's
 * date style; anything that is not one (e.g. "Recently") is shown as is. */
export function formatTimestamp(value, fallback = "") {
  if (!value) {
    return fallback;
  }
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(String(value)) ? formatDateTime(value) : String(value);
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

/**
 * "Santos Residence" -> "SR". Falls back to the first two characters when the
 * name is a single word, so a bare username still reads as a monogram.
 */
export function getHouseholdInitials(name) {
  const parts = String(name || "")
    .trim()
    .split(/[\s_-]+/)
    .filter(Boolean);
  if (parts.length === 0) {
    return "H";
  }
  if (parts.length === 1) {
    const single = parts[0];
    return (single.length === 1 ? single : single.slice(0, 2)).toUpperCase();
  }
  return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
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

export function formatTimeAgo(value) {
  if (!value) {
    return "";
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return "";
  }
  const seconds = Math.max(0, Math.floor((Date.now() - parsed.getTime()) / 1000));
  if (seconds < 60) {
    return "just now";
  }
  const units = [
    ["minute", 60],
    ["hour", 60],
    ["day", 24],
    ["month", 30],
    ["year", 12],
  ];
  let amount = seconds;
  let label = "second";
  for (const [nextLabel, size] of units) {
    if (amount < size) {
      break;
    }
    amount = Math.floor(amount / size);
    label = nextLabel;
  }
  return `${amount} ${label}${amount === 1 ? "" : "s"} ago`;
}

/** The numeric part of a display_rating ("4.90" -> 4.9), or null when the
 * worker has no ratings yet -- star rows need a number, not the label. */
export function parseRatingValue(ratingLabel) {
  const match = String(ratingLabel ?? "").match(/\d+(\.\d+)?/);
  if (!match) {
    return null;
  }
  const value = Number(match[0]);
  return Number.isFinite(value) && value > 0 ? value : null;
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
