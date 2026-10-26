import React, { useState } from "react";

/**
 * Asks for the reason before suspending an account. The suspended user is
 * told this reason (AGENTS.md II.D), so it can't be left blank; a browser
 * prompt used to accept an empty answer and the email then said "No reason
 * was recorded".
 */
export default function SuspendAccountDialog({ username, durationDays, onConfirm, onCancel }) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const durationLabel = durationDays ? `for ${durationDays} days` : "permanently";

  const submit = async (event) => {
    event.preventDefault();
    const trimmed = reason.replace(/\s+/g, " ").trim();
    if (!trimmed) {
      setError("Give a reason. The user will see it.");
      return;
    }
    setSaving(true);
    setError("");
    try {
      await onConfirm(trimmed);
    } catch (confirmError) {
      setError(confirmError.message || "Unable to update this account.");
      setSaving(false);
    }
  };

  return (
    <div className="gg-modal-backdrop" role="presentation" onClick={saving ? undefined : onCancel}>
      <form
        className="gg-modal-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="suspend-account-title"
        onClick={(event) => event.stopPropagation()}
        onSubmit={submit}
      >
        <div className="gg-modal-head">
          <div>
            <p className="gg-modal-kicker">{durationDays ? `Suspend ${durationDays} days` : "Block permanently"}</p>
            <h2 id="suspend-account-title">Suspend {username} {durationLabel}?</h2>
          </div>
        </div>
        <div className="gg-modal-body">
          <p className="small text-muted">
            They are signed out at once and can't log in until{" "}
            {durationDays ? "the suspension ends or you restore them" : "you restore them"}. They will be told the
            reason below.
          </p>
          <label className="form-label fw-semibold" htmlFor="suspend-account-reason">
            Reason (shown to the user)
          </label>
          <textarea
            id="suspend-account-reason"
            className={`form-control${error ? " is-invalid" : ""}`}
            rows="3"
            maxLength={500}
            required
            autoFocus
            value={reason}
            onChange={(event) => {
              setReason(event.target.value);
              setError("");
            }}
            placeholder="e.g. Repeated no-shows on booked jobs."
          />
          {error && <div className="invalid-feedback d-block" role="alert">{error}</div>}
        </div>
        <div className="gg-modal-foot">
          <button type="button" className="gg-modal-foot-btn" onClick={onCancel} disabled={saving}>
            Cancel
          </button>
          <button type="submit" className="btn btn-danger" disabled={saving}>
            {saving ? "Suspending..." : durationDays ? `Suspend ${durationDays} days` : "Block permanently"}
          </button>
        </div>
      </form>
    </div>
  );
}
