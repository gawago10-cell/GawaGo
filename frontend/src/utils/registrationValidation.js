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
