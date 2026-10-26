import React, { useState } from "react";

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
    estimatedWorkingDays: job.estimatedWorkingDays == null ? "" : String(job.estimatedWorkingDays),
    geographicBoundary: job.geographicBoundary || "1km",
  });
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const update = (name) => (event) => {
    setError("");
    setForm((prev) => ({ ...prev, [name]: event.target.value }));
  };

  const submit = async (event) => {
    event.preventDefault();
    if (!form.jobStartDate) {
      setError("A job needs a start date.");
      return;
    }
    if (form.jobEndDate && form.jobEndDate < form.jobStartDate) {
      setError("The end date can't be before the start date.");
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

  // A start date already in the past may stay as it is, but can't be picked.
  const minStartDate = job.jobStartDate && job.jobStartDate < todayIsoDate ? job.jobStartDate : todayIsoDate;

  return (
    <div className="gg-modal-backdrop" role="presentation" onClick={saving ? undefined : onClose}>
      <form
        className="gg-modal-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="edit-job-title"
        onClick={(event) => event.stopPropagation()}
        onSubmit={submit}
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
                min="0"
                step="0.01"
                className="form-control"
                value={form.offeredRate}
                onChange={update("offeredRate")}
              />
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
                className="form-control"
                min={minStartDate}
                required
                value={form.jobStartDate}
                onChange={update("jobStartDate")}
              />
            </div>
            <div className="col-6">
              <label className="form-label fw-semibold" htmlFor="edit-job-end">End date (optional)</label>
              <input
                id="edit-job-end"
                type="date"
                className="form-control"
                min={form.jobStartDate || todayIsoDate}
                value={form.jobEndDate}
                onChange={update("jobEndDate")}
              />
            </div>
            <div className="col-6">
              <label className="form-label fw-semibold" htmlFor="edit-job-days">Working days (optional)</label>
              <input
                id="edit-job-days"
                type="number"
                min="1"
                className="form-control"
                value={form.estimatedWorkingDays}
                onChange={update("estimatedWorkingDays")}
              />
            </div>
            <div className="col-6">
              <label className="form-label fw-semibold" htmlFor="edit-job-workers">Workers needed</label>
              <input
                id="edit-job-workers"
                type="number"
                min="1"
                className="form-control"
                value={form.workersNeeded}
                onChange={update("workersNeeded")}
              />
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
