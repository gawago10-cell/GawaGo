import React from "react";

/** Whether a form value counts as answered: non-blank text, or a non-empty list. */
export function hasAnswer(value) {
  if (Array.isArray(value)) {
    return value.length > 0;
  }
  return String(value ?? "").trim() !== "";
}

/**
 * The red asterisk on a required field's label. It shows only while the field
 * is still unanswered, so the person can see at a glance what is left; a wrong
 * answer is flagged by the field's red border and message instead.
 */
export default function RequiredMark({ filled = false }) {
  if (filled) {
    return null;
  }
  return (
    <span className="required-mark" aria-hidden="true">
      *
    </span>
  );
}
