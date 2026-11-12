export function getDisplayName(firstName, lastName, username) {
  const fullName = `${firstName || ""} ${lastName || ""}`.trim();
  return fullName || username || "User";
}

/** Whether `worker` is the worker an application (or other record with
 * workerUsername / workerName / workerId) refers to. The username is unique,
 * so when the record has one it decides alone: falling back to the display
 * name picked whichever of two same-named workers came first, which showed a
 * household the wrong person (2026-11-05). */
export function isSameWorker(worker, record) {
  if (!worker || !record) {
    return false;
  }
  const username = record.workerUsername || "";
  if (username) {
    return worker.username === username || worker.workerUsername === username;
  }
  return (
    getDisplayName(worker.firstName, worker.lastName, worker.username) === record.workerName ||
    (record.workerId != null && (String(worker.id) === String(record.workerId) || String(worker.workerId) === String(record.workerId)))
  );
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

// Same wording as the Find Jobs cards ("PHP 600.00/per day"); "PHP 600.00 /
// Per Day" wrapped onto two lines in table cells.
export function formatRate(amount, rateType) {
  return `${formatCurrency(amount)}/${(rateType || "Per Day").toLowerCase()}`;
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

/** The Post a Job hint under the dates, now that the days are no longer
 * typed in: "5 days, Nov 10 to Nov 14, 2026." A job with no end date (or an
 * end before its start) is a one-day job, the same rule the backend's
 * job_days uses. */
export function describeJobSpan(startValue, endValue) {
  const start = String(startValue || "").trim();
  const end = String(endValue || "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(start)) {
    return "Pick the dates the job starts and ends.";
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(end) || end <= start) {
    return `One-day job on ${formatJobDate(start)}. Set an end date if it runs longer.`;
  }
  const days = Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86400000) + 1;
  return `${days} days, ${formatJobDate(start)} to ${formatJobDate(end)}.`;
}

/** A job date with its day of the week: "2026-10-30" as "Fri, Oct 30, 2026".
 * The job schedule box shows this so both sides see which day work starts. */
export function formatJobDay(value) {
  const trimmed = String(value || "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return formatJobDate(trimmed);
  }
  const parsed = new Date(`${trimmed}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) {
    return trimmed;
  }
  return parsed.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", year: "numeric" });
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

function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

function parseNotificationDate(value) {
  if (!value) return null;
  const parsed = new Date(String(value).trim());
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/** "Today", "Yesterday" or "Earlier": the heading a notification sits under
 * (anything that isn't a timestamp, e.g. "Recently", counts as earlier). */
export function notificationDayGroup(value, now = new Date()) {
  const date = parseNotificationDate(value);
  if (!date) return "Earlier";
  const days = Math.round((startOfDay(now) - startOfDay(date)) / 86_400_000);
  if (days <= 0) return "Today";
  if (days === 1) return "Yesterday";
  return "Earlier";
}

/** When a notification arrived, in the app's short date style:
 * "Today · 8:13 PM", "Yesterday · 3:14 AM", "Nov 1, 2026 · 3:14 AM".
 * `timeOnly` drops the day under a "Today"/"Yesterday" heading. */
export function formatNotificationTime(value, { now = new Date(), timeOnly = false } = {}) {
  const date = parseNotificationDate(value);
  if (!date) return value ? String(value) : "";
  const time = date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
  const group = notificationDayGroup(date, now);
  if (group !== "Earlier") {
    return timeOnly ? time : `${group} · ${time}`;
  }
  const day = date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
  return `${day} · ${time}`;
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
    // Same words as the backend's distance_label, which used to disagree
    // ("1 meters away" beside "Within 1 km" on one card).
    if (numericDistance < 1) {
      return "Within 1 km";
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
