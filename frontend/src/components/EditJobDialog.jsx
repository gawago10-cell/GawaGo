import React, { useState } from "react";
import { MAX_WORKERS_NEEDED } from "../utils/jobFormValidation";

const RADIUS_OPTIONS = [
  ["1km", "1 km"],
  ["2km", "2 km"],
  ["5km", "5 km"],
  ["10km", "10 km"],
  ["unlimited", "Unlimited"],
];

/**
 * Edits an open job: its wording, rate, dates, worker count and search
 * radius. The API already allowed this until someone is hired; without a
 * screen for it, the empty AI Matched Workers page told households to widen
 * a radius they had no way to change. The site itself is fixed once posted.
 */
export default function EditJobDialog({ job, onSave, onClose, todayIsoDate }) {
  const [form, setForm] = useState({
    jobTitle: job.jobTitle || "",
    description: job.description || "",
    offeredRate: job.offeredRate || "",
    rateType: job.rateType || "Per Day",
    workersNeeded: String(job.workersNeeded || 1),
    jobStartDate: job.jobStartDate || "",
    jobEndDate: job.jobEndDate || "",
    geographicBoundary: job.geographicBoundary || "1km",
  });
  const [error, setError] = useState("");
  const [fieldErrors, setFieldErrors] = useState({});
  const [saving, setSaving] = useState(false);
  const update = (name) => (event) => {
    setError("");
    setFieldErrors((prev) => ({ ...prev, [name]: "" }));
    setForm((prev) => ({ ...prev, [name]: event.target.value }));
  };

  // A start date already in the past may stay as it is, but can't be picked.
  const minStartDate = job.jobStartDate && job.jobStartDate < todayIsoDate ? job.jobStartDate : todayIsoDate;

  // The app's own checks, under each field. The browser's built-in ones
  // blocked Save with no message the app could show, and min="0" let a
  // PHP 0.50 rate through, though a job pays at least PHP 1 (full audit,
  // 2026-11-16). Same rules as Post a Job and the mobile Edit Job.
  const validate = () => {
    const errors = {};
    if (String(form.offeredRate ?? "").trim() === "") {
      errors.offeredRate = "Enter the rate you'll pay.";
    } else if (!(Number(form.offeredRate) >= 1)) {
      errors.offeredRate = "Enter a rate of at least PHP 1.00.";
    }
    const workers = Number(form.workersNeeded);
    if (!Number.isInteger(workers) || workers < 1 || workers > MAX_WORKERS_NEEDED) {
      errors.workersNeeded = `Enter how many workers you need, from 1 to ${MAX_WORKERS_NEEDED}.`;
    }
    if (!form.jobStartDate) {
      errors.jobStartDate = "A job needs a start date.";
    } else if (minStartDate && form.jobStartDate < minStartDate) {
      errors.jobStartDate = "Choose today or a later date.";
    }
    if (form.jobEndDate && form.jobStartDate && form.jobEndDate < form.jobStartDate) {
      errors.jobEndDate = "The end date can't be before the start date.";
    }
    return errors;
  };

  const submit = async (event) => {
    event.preventDefault();
    const errors = validate();
    setFieldErrors(errors);
    if (Object.keys(errors).length > 0) {
      return;
    }
    setSaving(true);
    try {
      await onSave(form);
      onClose();
    } catch (saveError) {
      setError(saveError.message || "Unable to save this job.");
      setSaving(false);
    }
  };

  const fieldError = (name) =>
    fieldErrors[name] ? (
      <div id={`edit-job-${name}-error`} className="invalid-feedback d-block">
        {fieldErrors[name]}
      </div>
    ) : null;
  const invalidProps = (name) =>
    fieldErrors[name] ? { "aria-invalid": true, "aria-describedby": `edit-job-${name}-error` } : {};

  return (
    <div className="gg-modal-backdrop" role="presentation" onClick={saving ? undefined : onClose}>
      <form
        className="gg-modal-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="edit-job-title"
        onClick={(event) => event.stopPropagation()}
        onSubmit={submit}
        noValidate
      >
        <div className="gg-modal-head">
          <div>
            <p className="gg-modal-kicker">Edit job</p>
            <h2 id="edit-job-title">{job.jobTitle || job.serviceType}</h2>
          </div>
        </div>
        <div className="gg-modal-body">
          <div className="row g-2">
            <div className="col-12">
              <label className="form-label fw-semibold" htmlFor="edit-job-name">Job title</label>
              <input id="edit-job-name" className="form-control" maxLength={255} value={form.jobTitle} onChange={update("jobTitle")} />
            </div>
            <div className="col-12">
              <label className="form-label fw-semibold" htmlFor="edit-job-description">Description</label>
              <textarea
                id="edit-job-description"
                className="form-control"
                rows="3"
                value={form.description}
                onChange={update("description")}
              />
            </div>
            <div className="col-6">
              <label className="form-label fw-semibold" htmlFor="edit-job-rate">Offered rate (PHP)</label>
              <input
                id="edit-job-rate"
                type="number"
                min="1"
                step="0.01"
                className={`form-control ${fieldErrors.offeredRate ? "is-invalid" : ""}`}
                value={form.offeredRate}
                onChange={update("offeredRate")}
                {...invalidProps("offeredRate")}
              />
              {fieldError("offeredRate")}
            </div>
            <div className="col-6">
              <label className="form-label fw-semibold" htmlFor="edit-job-rate-type">Rate type</label>
              <select id="edit-job-rate-type" className="form-select" value={form.rateType} onChange={update("rateType")}>
                <option>Per Day</option>
                <option>Per Hour</option>
                <option>Fixed Rate</option>
              </select>
            </div>
            <div className="col-6">
              <label className="form-label fw-semibold" htmlFor="edit-job-start">Start date</label>
              <input
                id="edit-job-start"
                type="date"
                className={`form-control ${fieldErrors.jobStartDate ? "is-invalid" : ""}`}
                min={minStartDate}
                required
                value={form.jobStartDate}
                onChange={update("jobStartDate")}
                {...invalidProps("jobStartDate")}
              />
              {fieldError("jobStartDate")}
            </div>
            <div className="col-6">
              <label className="form-label fw-semibold" htmlFor="edit-job-end">End date (optional)</label>
              <input
                id="edit-job-end"
                type="date"
                className={`form-control ${fieldErrors.jobEndDate ? "is-invalid" : ""}`}
                min={form.jobStartDate || todayIsoDate}
                value={form.jobEndDate}
                onChange={update("jobEndDate")}
                {...invalidProps("jobEndDate")}
              />
              {fieldError("jobEndDate")}
            </div>
            <div className="col-6">
              <label className="form-label fw-semibold" htmlFor="edit-job-workers">Workers needed</label>
              <input
                id="edit-job-workers"
                type="number"
                min="1"
                max={MAX_WORKERS_NEEDED}
                className={`form-control ${fieldErrors.workersNeeded ? "is-invalid" : ""}`}
                value={form.workersNeeded}
                onChange={update("workersNeeded")}
                {...invalidProps("workersNeeded")}
              />
              {fieldError("workersNeeded")}
            </div>
            <div className="col-12">
              <label className="form-label fw-semibold" htmlFor="edit-job-radius">Search radius</label>
              <select
                id="edit-job-radius"
                className="form-select"
                value={form.geographicBoundary}
                onChange={update("geographicBoundary")}
              >
                {RADIUS_OPTIONS.map(([value, label]) => (
                  <option key={value} value={value}>{label}</option>
                ))}
              </select>
              <p className="form-text mb-0">Workers farther than this by road are not matched to the job.</p>
            </div>
          </div>
          <p className="small text-muted mt-3 mb-0">
            The job site can't be moved after posting. Cancel and repost the job to change it.
          </p>
          {error && <div className="invalid-feedback d-block mt-2" role="alert">{error}</div>}
        </div>
        <div className="gg-modal-foot">
          <button type="button" className="gg-modal-foot-btn" onClick={onClose} disabled={saving}>
            Cancel
          </button>
          <button type="submit" className="btn btn-success" disabled={saving}>
            {saving ? "Saving..." : "Save changes"}
          </button>
        </div>
      </form>
    </div>
  );
}
