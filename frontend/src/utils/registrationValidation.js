import { isValidEmailAddress } from "./locationServices";
import { validateWorkerSkills } from "./skillUtils";

// Fields both registration forms require, in the order they appear on screen
// so the first error is also the topmost one.
export const REQUIRED_REGISTRATION_FIELDS = [
  ["firstName", "First name"],
  ["lastName", "Last name"],
  ["username", "Username"],
  ["email", "Email"],
  ["phone", "Phone number"],
  ["barangay", "Barangay"],
  ["streetAddress", "Street / house no."],
  ["password", "Password"],
  ["confirmPassword", "Confirm password"],
];

// The worker form's checked fields in on-screen order: the pin sits under
// the address, and the skills come before the password.
export const WORKER_REGISTRATION_FIELD_ORDER = [
  "firstName",
  "lastName",
  "username",
  "email",
  "phone",
  "barangay",
  "streetAddress",
  "location",
  "hourlyRate",
  "dailyRate",
  "yearsExperience",
  "skills",
  "customSkill",
  "password",
  "confirmPassword",
];

export const WORKER_PIN_REQUIRED_MESSAGE =
  "Pin where you live on the map, or use your current location. Households see your distance from this point.";

/**
 * Per-field errors for a registration form: `{ fieldName: "message" }`, empty
 * when the form is valid. Replaces a single "complete all required fields"
 * alert, which said something was missing without saying what.
 */
export function validateRegistration(form) {
  const errors = {};
  for (const [name, label] of REQUIRED_REGISTRATION_FIELDS) {
    if (!String(form?.[name] ?? "").trim()) {
      errors[name] = `${label} is required.`;
    }
  }
  if (!errors.email && !isValidEmailAddress(form.email)) {
    errors.email = "Enter a complete email address, e.g. juan@example.com.";
  }
  if (!errors.password && String(form.password).length < 8) {
    errors.password = "Password must be at least 8 characters.";
  }
  if (!errors.confirmPassword && !errors.password && form.password !== form.confirmPassword) {
    errors.confirmPassword = "Passwords do not match.";
  }
  return errors;
}

/** validateRegistration plus what only a worker needs: a map pin (matching
 * measures road distance from it) and at least one skill. */
export function validateWorkerRegistration(form) {
  const errors = validateRegistration(form);
  if (form?.latitude == null || form?.longitude == null) {
    errors.location = WORKER_PIN_REQUIRED_MESSAGE;
  }
  const skillErrors = validateWorkerSkills(form?.skills, form?.customSkill);
  return { ...errors, ...skillErrors };
}

/** Scrolls to and focuses the first invalid field so it can't be missed. */
export function focusFirstInvalidField(errors, formElement, fieldOrder = REQUIRED_REGISTRATION_FIELDS.map(([name]) => name)) {
  const first = fieldOrder.find((name) => errors[name]);
  if (!first || typeof document === "undefined") return;
  const scope = formElement || document;
  const element = scope.querySelector(`[name="${first}"], [data-field="${first}"]`);
  if (element?.focus) {
    element.focus({ preventScroll: false });
    element.scrollIntoView?.({ block: "center", behavior: "smooth" });
  }
}

// The sign-up form field each server field's error belongs under.
const SERVER_REGISTRATION_FIELDS = {
  username: "username",
  email: "email",
  password: "password",
  phone: "phone",
  first_name: "firstName",
  last_name: "lastName",
  skills: "skills",
  hourly_rate: "hourlyRate",
  daily_rate: "dailyRate",
  service_rate: "dailyRate",
  years_experience: "yearsExperience",
};

/**
 * The server's field errors on a sign-up, keyed by form field, so "That
 * username is already taken" or "This password is too common" shows under
 * the field rather than only in a toast that disappears (full audit,
 * 2026-11-16). Empty when the server named no field this form shows.
 */
export function serverRegistrationErrors(data) {
  const errors = {};
  if (!data || typeof data !== "object") {
    return errors;
  }
  for (const [serverField, formField] of Object.entries(SERVER_REGISTRATION_FIELDS)) {
    const value = data[serverField];
    const message = Array.isArray(value) ? value.find(Boolean) : value;
    if (message && !errors[formField]) {
      errors[formField] = String(message);
    }
  }
  return errors;
}
