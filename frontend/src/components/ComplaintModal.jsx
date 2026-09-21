import React, { useEffect, useState } from "react";

import { createComplaint } from "../services/backendDataService";

const COMPLAINT_TYPES = [
  { value: "payment_issue", label: "Payment Issue" },
  { value: "quality_of_work", label: "Quality of Work" },
  { value: "no_show", label: "No Show" },
  { value: "safety_concern", label: "Safety Concern" },
  { value: "behavior", label: "Inappropriate Behavior" },
  { value: "other", label: "Other" },
];

/**
 * "Report an Issue" -- an incident filed against a specific job's other
 * party, reviewed by admin. Always tied to one job: a household reports
 * one of that job's applicants, a worker's report always targets the
 * job's household (unambiguous, so no picker is shown).
 */
const MAX_EVIDENCE = 5;

export default function ComplaintModal({ isOpen, onClose, onSubmitted, job, role, applicants = [] }) {
  const isHousehold = role === "household";
  const [complaintType, setComplaintType] = useState("");
  const [respondentId, setRespondentId] = useState("");
  const [description, setDescription] = useState("");
  const [evidence, setEvidence] = useState([]);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!isOpen) return;
    setComplaintType("");
    setRespondentId("");
    setDescription("");
    setEvidence([]);
    setError("");
  }, [isOpen, job?.id]);

  if (!isOpen) return null;

  async function handleSubmit() {
    if (!complaintType) {
      setError("Please select a report type.");
      return;
    }
    if (!description.trim()) {
      setError("Please describe what happened.");
      return;
    }
    if (isHousehold && !respondentId) {
      setError("Select which worker this report is about.");
      return;
    }

    setSubmitting(true);
    setError("");
    try {
      await createComplaint({
        jobId: job.id,
        respondentId: isHousehold ? Number(respondentId) : undefined,
        complaintType,
        description: description.trim(),
        evidence,
      });
      onSubmitted?.();
      onClose();
    } catch (submitError) {
      setError(submitError.message || "Unable to submit this report.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="modal d-block" style={{ backgroundColor: "rgba(0,0,0,0.5)" }}>
      <div className="modal-dialog modal-dialog-centered">
        <div className="modal-content">
          <div className="modal-header">
            <h5 className="modal-title">Report an Issue</h5>
            <button type="button" className="btn-close" aria-label="Close" onClick={onClose} />
          </div>
          <div className="modal-body">
            <p className="small text-muted mb-3">
              Reporting on <strong>{job?.jobTitle || job?.serviceType || "this job"}</strong>. Your report goes
              directly to our admin team for review.
            </p>

            {isHousehold && (
              <div className="mb-3">
                <label className="form-label fw-bold">Who is this about? *</label>
                <select
                  className="form-select"
                  value={respondentId}
                  onChange={(event) => setRespondentId(event.target.value)}
                >
                  <option value="">Select a worker...</option>
                  {applicants.map((applicant) => (
                    <option key={applicant.id} value={applicant.id}>
                      {applicant.name || applicant.username}
                    </option>
                  ))}
                </select>
                {applicants.length === 0 && (
                  <small className="text-muted">No workers have applied to this job yet.</small>
                )}
              </div>
            )}

            <div className="mb-3">
              <label className="form-label fw-bold">Report Type *</label>
              <select
                className="form-select"
                value={complaintType}
                onChange={(event) => setComplaintType(event.target.value)}
              >
                <option value="">Select a type...</option>
                {COMPLAINT_TYPES.map((type) => (
                  <option key={type.value} value={type.value}>
                    {type.label}
                  </option>
                ))}
              </select>
            </div>

            <div className="mb-3">
              <label className="form-label fw-bold">Description *</label>
              <textarea
                className="form-control"
                rows={5}
                placeholder="Please provide details about what happened..."
                value={description}
                onChange={(event) => setDescription(event.target.value)}
              />
              <small className="text-muted">
                Be specific and include dates, times, and any relevant details that help us understand the issue.
              </small>
            </div>

            <div className="mb-3">
              <label className="form-label fw-bold">Photo evidence (optional)</label>
              <input
                type="file"
                className="form-control"
                accept="image/*"
                multiple
                onChange={(event) => {
                  const picked = Array.from(event.target.files || []).slice(0, MAX_EVIDENCE);
                  setEvidence(picked);
                  setError("");
                }}
              />
              <small className="text-muted">
                Up to {MAX_EVIDENCE} photos. Attaching a photo helps the admin see what happened.
              </small>
              {evidence.length > 0 && (
                <div className="d-flex gap-2 flex-wrap mt-2">
                  {evidence.map((file, index) => (
                    <div key={`${file.name}-${index}`} className="position-relative">
                      <img
                        src={URL.createObjectURL(file)}
                        alt={file.name}
                        style={{
                          width: 72,
                          height: 72,
                          objectFit: "cover",
                          borderRadius: 6,
                          border: "1px solid var(--gg-border)",
                        }}
                      />
                      <button
                        type="button"
                        className="btn-close position-absolute top-0 end-0 bg-white rounded-circle"
                        style={{ transform: "scale(0.7)" }}
                        aria-label={`Remove ${file.name}`}
                        onClick={() => setEvidence((prev) => prev.filter((_, i) => i !== index))}
                      />
                    </div>
                  ))}
                </div>
              )}
            </div>

            {error && <div className="alert alert-danger small py-2 mb-0">{error}</div>}

            <div className="alert alert-info small mt-3 mb-0">
              <strong>Your Privacy:</strong> Reports are reviewed by our admin team and handled confidentially. The
              person you report is not notified that a report was filed.
            </div>
          </div>

          <div className="modal-footer">
            <button type="button" className="btn btn-secondary" onClick={onClose} disabled={submitting}>
              Cancel
            </button>
            <button type="button" className="btn btn-danger" onClick={handleSubmit} disabled={submitting}>
              {submitting ? "Submitting..." : "Submit Report"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
