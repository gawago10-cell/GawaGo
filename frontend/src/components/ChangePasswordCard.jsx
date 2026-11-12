import React, { useState } from "react";
import { setAuthToken } from "../api/apiClient";
import { changePassword } from "../services/backendDataService";

const EMPTY = { current: "", next: "", confirm: "" };

/**
 * Change the signed-in account's password. There was no way to do this
 * except Forgot password, though Add Admin tells a new admin to change the
 * temporary one (third scan, 2026-11-01).
 */
export default function ChangePasswordCard({
  className = "profile-card",
  headClassName = "profile-card-head",
  // False inside a dialog that carries its own "Change Password" title.
  showHeading = true,
}) {
  const [form, setForm] = useState(EMPTY);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [saving, setSaving] = useState(false);

  const update = (field) => (event) => {
    setForm((prev) => ({ ...prev, [field]: event.target.value }));
    setError("");
    setNotice("");
  };

  async function handleSubmit(event) {
    event.preventDefault();
    if (form.next.length < 8) {
      setError("Use at least 8 characters for the new password.");
      return;
    }
    if (form.next !== form.confirm) {
      setError("The new passwords don't match.");
      return;
    }
    setSaving(true);
    try {
      const data = await changePassword(form.current, form.next);
      // Other devices are signed out; this one keeps going on the new token.
      if (data?.access) {
        setAuthToken(data.access);
      }
      setForm(EMPTY);
      setNotice(data?.detail || "Your password was updated.");
    } catch (submitError) {
      setError(submitError.message || "Unable to change your password.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <section
      className={`${className} change-password-card`}
      aria-labelledby={showHeading ? "change-password-title" : undefined}
    >
      {showHeading && (
        <div className={headClassName} id="change-password-title">
          Change Password
        </div>
      )}
      <form className="change-password-form" onSubmit={handleSubmit}>
        <label className="form-label fw-semibold" htmlFor="change-password-current">
          Current password
        </label>
        <input
          id="change-password-current"
          type="password"
          className="form-control"
          autoComplete="current-password"
          value={form.current}
          onChange={update("current")}
          required
        />
        <label className="form-label fw-semibold" htmlFor="change-password-new">
          New password
        </label>
        <input
          id="change-password-new"
          type="password"
          className="form-control"
          autoComplete="new-password"
          placeholder="At least 8 characters"
          value={form.next}
          onChange={update("next")}
          required
        />
        <label className="form-label fw-semibold" htmlFor="change-password-confirm">
          Confirm new password
        </label>
        <input
          id="change-password-confirm"
          type="password"
          className="form-control"
          autoComplete="new-password"
          value={form.confirm}
          onChange={update("confirm")}
          required
        />
        {error && (
          <div className="alert alert-danger small py-2 mb-0" role="alert">
            {error}
          </div>
        )}
        {notice && (
          <div className="alert alert-success small py-2 mb-0" role="status">
            {notice}
          </div>
        )}
        <button className="btn btn-success change-password-submit" type="submit" disabled={saving}>
          {saving ? "Updating..." : "Update Password"}
        </button>
      </form>
    </section>
  );
}
