import { isValidGmailAddress } from "./locationServices";

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
  if (!errors.email && !isValidGmailAddress(form.email)) {
    errors.email = "Enter a complete Gmail address, e.g. example@gmail.com.";
  }
  if (!errors.password && String(form.password).length < 8) {
    errors.password = "Password must be at least 8 characters.";
  }
  if (!errors.confirmPassword && !errors.password && form.password !== form.confirmPassword) {
    errors.confirmPassword = "Passwords do not match.";
  }
  return errors;
}

/** Scrolls to and focuses the first invalid field so it can't be missed. */
export function focusFirstInvalidField(errors, formElement) {
  const first = REQUIRED_REGISTRATION_FIELDS.map(([name]) => name).find((name) => errors[name]);
  if (!first || typeof document === "undefined") return;
  const scope = formElement || document;
  const element = scope.querySelector(`[name="${first}"]`);
  if (element?.focus) {
    element.focus({ preventScroll: false });
    element.scrollIntoView?.({ block: "center", behavior: "smooth" });
  }
}
