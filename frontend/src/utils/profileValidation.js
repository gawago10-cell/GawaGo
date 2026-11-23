import { isValidEmailAddress } from "./locationServices";

// The worker My Profile form's checks, shown under each field. Its phone and
// rate errors only ever came back from the server as a toast that vanished
// in five seconds, away from the field (full audit, 2026-11-16). The rules
// match the backend's (accounts/serializers.py).

export const PHONE_FORMAT_MESSAGE = "Enter a Philippine mobile number, like 0912 345 6789.";
export const SERVICE_RATE_MESSAGE = "Give an hourly or a daily rate above PHP 0.";

/** True for a blank number or one the backend's clean_mobile_number takes. */
export function isValidMobileNumber(value) {
  const raw = String(value ?? "").trim();
  if (!raw) {
    return true;
  }
  let digits = raw.replace(/\D/g, "");
  if (digits.length === 12 && digits.startsWith("63")) {
    digits = digits.slice(2);
  } else if (digits.length === 11 && digits.startsWith("0")) {
    digits = digits.slice(1);
  }
  return /^9\d{9}$/.test(digits);
}

const isPositiveRate = (value) => String(value ?? "").trim() !== "" && Number(value) > 0;

export function workerProfileFieldErrors(form) {
  const errors = {};
  if (!String(form?.email ?? "").trim() || !isValidEmailAddress(form.email)) {
    errors.email = "Enter a complete email address, e.g. juan@example.com.";
  }
  if (!isValidMobileNumber(form?.phone)) {
    errors.phone = PHONE_FORMAT_MESSAGE;
  }
  // The server's RATE_LIMITS (mobile worker audit, 2026-11-23): blank or 0
  // means not given; a given rate is PHP 1 up to a sanity ceiling.
  for (const [field, max] of [["hourlyRate", 10000], ["dailyRate", 100000]]) {
    const text = String(form?.[field] ?? "").trim();
    if (text === "") {
      continue;
    }
    const value = Number(text);
    if (!Number.isFinite(value)) {
      errors[field] = "Enter the rate as a number.";
    } else if (value < 0) {
      errors[field] = "A rate can't be negative.";
    } else if (value > 0 && value < 1) {
      errors[field] = "Enter at least PHP 1, or leave it blank.";
    } else if (value > max) {
      errors[field] = `Enter PHP ${max.toLocaleString("en-US")} or less.`;
    }
  }
  if (!errors.hourlyRate && !errors.dailyRate && !isPositiveRate(form?.hourlyRate) && !isPositiveRate(form?.dailyRate)) {
    errors.dailyRate = SERVICE_RATE_MESSAGE;
  }
  return errors;
}

// The form field each of the server's profile errors belongs under.
const SERVER_PROFILE_FIELDS = {
  first_name: "firstName",
  last_name: "lastName",
  email: "email",
  phone: "phone",
  bio: "bio",
  hourly_rate: "hourlyRate",
  daily_rate: "dailyRate",
  service_rate: "dailyRate",
  current_password: "currentPassword",
  years_experience: "yearsExperience",
};

/** The server's field errors on a profile save, keyed by form field. */
export function serverProfileFieldErrors(data) {
  const errors = {};
  if (!data || typeof data !== "object") {
    return errors;
  }
  for (const [serverField, formField] of Object.entries(SERVER_PROFILE_FIELDS)) {
    const value = data[serverField];
    const message = Array.isArray(value) ? value.find(Boolean) : value;
    if (message && !errors[formField]) {
      errors[formField] = String(message);
    }
  }
  return errors;
}
