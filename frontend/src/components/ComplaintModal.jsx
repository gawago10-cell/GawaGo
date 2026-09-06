import React from "react";

const COMPLAINT_TYPES = [
  { value: "payment_issue", label: "Payment Issue" },
  { value: "quality_of_work", label: "Quality of Work" },
  { value: "no_show", label: "No Show" },
  { value: "safety_concern", label: "Safety Concern" },
  { value: "behavior", label: "Inappropriate Behavior" },
  { value: "other", label: "Other" },
];

export default function ComplaintModal({ isOpen, complaint, onClose, onChange, onSubmit, isWorker, postedJobs }) {
  if (!isOpen) return null;

  const completedJobs = postedJobs?.filter((job) =>
    job.applications?.some((app) => app.status === "Hired" || app.status === "Completed")
  ) || [];

  return (
    <div className="modal d-block" style={{ backgroundColor: "rgba(0,0,0,0.5)" }}>
      <div className="modal-dialog modal-dialog-centered">
        <div className="modal-content">
          <div className="modal-header">
            <h5 className="modal-title">File a Complaint</h5>
            <button
              type="button"
              className="btn-close"
              aria-label="Close"
              onClick={onClose}
            />
          </div>
          <div className="modal-body">
            <div className="mb-3">
              <label className="form-label fw-bold">Complaint Type *</label>
              <select
                className="form-select"
                value={complaint.complaint_type}
                onChange={(e) => onChange({ ...complaint, complaint_type: e.target.value })}
              >
                <option value="">Select a type...</option>
                {COMPLAINT_TYPES.map((type) => (
                  <option key={type.value} value={type.value}>
                    {type.label}
                  </option>
                ))}
              </select>
            </div>

            {completedJobs.length > 0 && (
              <div className="mb-3">
                <label className="form-label">Related Job (Optional)</label>
                <select
                  className="form-select"
                  value={complaint.job || ""}
                  onChange={(e) => onChange({ ...complaint, job: e.target.value ? parseInt(e.target.value) : null })}
                >
                  <option value="">No specific job</option>
                  {completedJobs.map((job) => (
                    <option key={job.id} value={job.id}>
                      {job.serviceType} - {job.barangay}
                    </option>
                  ))}
                </select>
              </div>
            )}

            <div className="mb-3">
              <label className="form-label fw-bold">Description *</label>
              <textarea
                className="form-control"
                rows={5}
                placeholder="Please provide details about your complaint..."
                value={complaint.description}
                onChange={(e) => onChange({ ...complaint, description: e.target.value })}
              />
              <small className="text-muted">
                Be specific and include dates, times, and any relevant details that help us understand the issue.
              </small>
            </div>

            <div className="alert alert-info small">
              <strong>Your Privacy:</strong> All complaints are reviewed by our admin team and handled confidentially.
            </div>
          </div>

          <div className="modal-footer">
            <button type="button" className="btn btn-secondary" onClick={onClose}>
              Cancel
            </button>
            <button type="button" className="btn btn-danger" onClick={onSubmit}>
              Submit Complaint
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
