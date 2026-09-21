import React, { useEffect, useMemo, useState } from "react";

import {
  fetchAdminComplaints,
  setComplaintRespondentBlocked,
  updateComplaintAdmin,
} from "../services/backendDataService";
import { parseLocationLabel } from "../utils/locationUtils";
import AdminUserHistorySection from "./AdminUserHistorySection";

const STATUS_OPTIONS = [
  { value: "", label: "All Statuses" },
  { value: "submitted", label: "Submitted" },
  { value: "under_review", label: "Under Review" },
  { value: "resolved", label: "Resolved" },
  { value: "closed", label: "Closed" },
];

const TYPE_LABELS = {
  payment_issue: "Payment Issue",
  quality_of_work: "Quality of Work",
  no_show: "No-Show",
  safety_concern: "Safety Concern",
  behavior: "Inappropriate Behavior",
  other: "Other",
};

const STATUS_META = {
  submitted: { label: "Submitted", tone: "submitted" },
  under_review: { label: "Under Review", tone: "review" },
  resolved: { label: "Resolved", tone: "resolved" },
  closed: { label: "Closed", tone: "closed" },
};

const STATUS_ORDER = ["submitted", "under_review", "resolved", "closed"];

const ROLE_LABELS = {
  household: "Household",
  worker: "Worker",
};

function reportCode(id) {
  return `RPT-${String(id).padStart(3, "0")}`;
}

function initials(name) {
  const trimmed = String(name || "").trim();
  if (!trimmed) return "?";
  return trimmed
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();
}

function StatusPill({ status }) {
  const meta = STATUS_META[status] || { label: status, tone: "submitted" };
  return <span className={`admin-report-status-pill ${meta.tone}`}>{meta.label}</span>;
}

function PartyCell({ username, detail }) {
  const label = detail?.displayName || username || "—";
  return (
    <div className="admin-report-party-cell">
      <span className="admin-report-party-avatar">{initials(label)}</span>
      <span>{username || label}</span>
    </div>
  );
}

function AccountCard({ tone, kicker, roleLabel, detail, username, onOpenProfile }) {
  const displayName = detail?.displayName || username || "Unknown user";
  const barangay = detail?.locationLabel ? parseLocationLabel(detail.locationLabel).barangay : "";
  const canOpen = Boolean(username && onOpenProfile);
  return (
    <button
      type="button"
      className={`admin-report-account-card ${tone} ${canOpen ? "clickable" : ""}`}
      onClick={
        canOpen
          ? () => onOpenProfile(username, detail, detail?.role || (tone === "reporter" ? "household" : "worker"))
          : undefined
      }
      disabled={!canOpen}
    >
      <div className="admin-report-account-head">
        <span>{kicker}</span>
        <span className="admin-report-account-role-badge">{roleLabel}</span>
      </div>
      <div className="admin-report-account-body">
        <div className="admin-report-account-ident">
          <span className="admin-report-account-avatar">{initials(displayName)}</span>
          <div>
            <h4>{displayName}</h4>
            <p>@{username || "unknown"}</p>
          </div>
        </div>
        {detail && (
          <p className="admin-report-account-rating">
            <span className="admin-report-account-stars" aria-hidden="true">
              {"★".repeat(Math.round(detail.averageRating || 0)).padEnd(5, "☆")}
            </span>
            <strong>{detail.averageRating != null ? detail.averageRating.toFixed(1) : "No rating"}</strong>
            <span className="text-muted">({detail.ratingCount} jobs)</span>
          </p>
        )}
        <div className="admin-report-account-facts">
          <div>
            <span>Barangay</span>
            <strong>{barangay || "Not set"}</strong>
          </div>
          <div>
            <span>Member Since</span>
            <strong>{detail?.memberSince || "—"}</strong>
          </div>
          <div>
            <span>Phone</span>
            <strong>{detail?.phone || "Not provided"}</strong>
          </div>
          <div>
            <span>Email</span>
            <strong>{detail?.email || "Not provided"}</strong>
          </div>
        </div>
        {canOpen && <p className="admin-report-account-cta">View profile &amp; history →</p>}
      </div>
    </button>
  );
}

/**
 * Admin's incident-report queue. Distinct from the household/worker
 * activity report: this is a work queue to review and resolve, not a
 * personal summary, so it gets its own tab rather than living under
 * "Reports".
 */
export default function AdminComplaintsQueue({
  currentUser,
  postedJobs = [],
  registeredHouseholds = [],
  registeredWorkers = [],
}) {
  const [complaints, setComplaints] = useState(null);
  const [status, setStatus] = useState("loading");
  const [statusFilter, setStatusFilter] = useState("");
  const [selectedId, setSelectedId] = useState(null);
  const [notesDraft, setNotesDraft] = useState("");
  const [savingId, setSavingId] = useState(null);
  const [profileTarget, setProfileTarget] = useState(null);

  function load() {
    setStatus("loading");
    fetchAdminComplaints({ status: statusFilter || undefined }).then((data) => {
      if (data === null) {
        setStatus("error");
        return;
      }
      setComplaints(data);
      setStatus("ready");
    });
  }

  useEffect(load, [statusFilter]);

  const selected = complaints?.find((item) => item.id === selectedId) || null;

  function openDetail(complaint) {
    setSelectedId(complaint.id);
    setNotesDraft(complaint.adminNotes || complaint.resolution || "");
  }

  function openUserProfile(username, detail, roleHint) {
    setProfileTarget({ username, detail, role: roleHint });
  }

  const profileFullRecord = useMemo(() => {
    if (!profileTarget?.username) return null;
    const pool = profileTarget.role === "household" ? registeredHouseholds : registeredWorkers;
    return (
      pool.find((item) => item.username?.toLowerCase() === profileTarget.username.toLowerCase()) || null
    );
  }, [profileTarget, registeredHouseholds, registeredWorkers]);


  async function applyStatus(complaint, nextStatus) {
    setSavingId(complaint.id);
    try {
      const updated = await updateComplaintAdmin(complaint.id, { status: nextStatus });
      setComplaints((prev) => prev.map((item) => (item.id === complaint.id ? updated : item)));
    } catch (error) {
      window.alert(error.message || "Unable to update this report.");
    } finally {
      setSavingId(null);
    }
  }

  async function suspendRespondent(complaint, durationDays) {
    const durationLabel = durationDays ? `for ${durationDays} days` : "permanently";
    const confirmed = window.confirm(
      `Suspend ${complaint.respondentUsername} ${durationLabel}? They will be signed out immediately and cannot log back in until restored.`,
    );
    if (!confirmed) return;
    const reason = window.prompt("Reason for suspending (shown to the user):", "");
    if (reason === null) return;

    setSavingId(complaint.id);
    try {
      const updated = await setComplaintRespondentBlocked(complaint.id, {
        blocked: true,
        reason: reason || "",
        durationDays,
      });
      setComplaints((prev) => prev.map((item) => (item.id === complaint.id ? updated : item)));
    } catch (error) {
      window.alert(error.message || "Unable to update this account.");
    } finally {
      setSavingId(null);
    }
  }

  async function restoreRespondent(complaint) {
    setSavingId(complaint.id);
    try {
      const updated = await setComplaintRespondentBlocked(complaint.id, { blocked: false });
      setComplaints((prev) => prev.map((item) => (item.id === complaint.id ? updated : item)));
    } catch (error) {
      window.alert(error.message || "Unable to update this account.");
    } finally {
      setSavingId(null);
    }
  }

  async function saveNotes(complaint) {
    setSavingId(complaint.id);
    try {
      const updated = await updateComplaintAdmin(complaint.id, { adminNotes: notesDraft.trim() });
      setComplaints((prev) => prev.map((item) => (item.id === complaint.id ? updated : item)));
    } catch (error) {
      window.alert(error.message || "Unable to save notes.");
    } finally {
      setSavingId(null);
    }
  }

  async function markResolved(complaint) {
    setSavingId(complaint.id);
    try {
      const updated = await updateComplaintAdmin(complaint.id, {
        status: "resolved",
        resolution: notesDraft.trim(),
      });
      setComplaints((prev) => prev.map((item) => (item.id === complaint.id ? updated : item)));
    } catch (error) {
      window.alert(error.message || "Unable to resolve this report.");
    } finally {
      setSavingId(null);
    }
  }

  async function closeReport(complaint) {
    setSavingId(complaint.id);
    try {
      const updated = await updateComplaintAdmin(complaint.id, {
        status: "closed",
        adminNotes: notesDraft.trim(),
      });
      setComplaints((prev) => prev.map((item) => (item.id === complaint.id ? updated : item)));
    } catch (error) {
      window.alert(error.message || "Unable to close this report.");
    } finally {
      setSavingId(null);
    }
  }

  return (
    <div className="admin-reports-page">
      <div className="admin-reports-header">
        <div>
          <h2>Reported Issues</h2>
          <p>Review and resolve user-submitted complaints</p>
        </div>
        <div className="admin-reports-header-actions">
          <label className="admin-reports-filter">
            <span>Filter:</span>
            <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
              {STATUS_OPTIONS.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>
          <span className="admin-reports-count-badge">{complaints?.length ?? 0} reports</span>
        </div>
      </div>

      {status === "loading" && (
        <div className="text-center py-4">
          <div className="spinner-border text-success" role="status" aria-label="Loading reports" />
        </div>
      )}
      {status === "error" && <div className="alert alert-warning">Unable to load reports right now.</div>}
      {status === "ready" && complaints.length === 0 && (
        <div className="admin-reports-table-card admin-reports-empty">No reports match this filter.</div>
      )}

      {status === "ready" && complaints.length > 0 && (
        <div className="admin-reports-table-card">
          <div className="table-responsive">
            <table className="admin-reports-table">
              <thead>
                <tr>
                  <th>Report ID</th>
                  <th>Type</th>
                  <th>Complainant</th>
                  <th>Respondent</th>
                  <th>Job</th>
                  <th>Filed</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {complaints.map((complaint) => (
                  <tr key={complaint.id} onClick={() => openDetail(complaint)}>
                    <td className="admin-reports-id">{reportCode(complaint.id)}</td>
                    <td>{TYPE_LABELS[complaint.complaintType] || complaint.complaintType}</td>
                    <td>
                      <PartyCell username={complaint.complainantUsername} detail={complaint.complainantDetail} />
                    </td>
                    <td>
                      <PartyCell username={complaint.respondentUsername} detail={complaint.respondentDetail} />
                    </td>
                    <td className="text-muted">{complaint.jobName || complaint.jobTitle || "—"}</td>
                    <td className="text-muted">{complaint.createdAt?.slice(0, 10)}</td>
                    <td>
                      <StatusPill status={complaint.status} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {selected && (
        <div className="gg-modal-backdrop" role="presentation" onClick={() => setSelectedId(null)}>
          <div
            className="gg-modal-panel admin-report-modal"
            role="dialog"
            aria-modal="true"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="gg-modal-head admin-report-modal-head">
              <div>
                <p className="gg-modal-kicker">{reportCode(selected.id)}</p>
                <h2>
                  {TYPE_LABELS[selected.complaintType] || selected.complaintType} —{" "}
                  {selected.jobName || selected.jobTitle || "Report"}
                </h2>
              </div>
              <div className="d-flex align-items-center gap-3">
                <StatusPill status={selected.status} />
                <button
                  type="button"
                  className="gg-modal-close"
                  onClick={() => setSelectedId(null)}
                  aria-label="Close"
                >
                  ×
                </button>
              </div>
            </div>

            <div className="gg-modal-body admin-report-modal-body">
              <div className="admin-report-top-grid">
                <div className="admin-report-info-card">
                  <p className="admin-report-info-kicker">Job Details</p>
                  <h3>{selected.jobName || selected.jobTitle || "Job not available"}</h3>
                  <p className="admin-report-info-meta">
                    <span>📍 {selected.jobBarangay || "Location not set"}</span>
                    <span>🗓️ Filed {selected.createdAt?.slice(0, 10)}</span>
                  </p>
                </div>
                <div className="admin-report-info-card">
                  <p className="admin-report-info-kicker">Update Status</p>
                  <div className="admin-report-status-grid">
                    {STATUS_ORDER.map((option) => (
                      <button
                        key={option}
                        type="button"
                        className={`admin-report-status-btn ${STATUS_META[option].tone} ${
                          selected.status === option ? "active" : ""
                        }`}
                        disabled={savingId === selected.id}
                        onClick={() => applyStatus(selected, option)}
                      >
                        <i aria-hidden="true" />
                        {STATUS_META[option].label}
                      </button>
                    ))}
                  </div>
                </div>
              </div>

              <p className="admin-report-section-label">Involved Accounts</p>
              <div className="admin-report-accounts-grid">
                <AccountCard
                  tone="reporter"
                  kicker="Reporter (Complainant)"
                  roleLabel={ROLE_LABELS[selected.complainantDetail?.role] || "Household"}
                  detail={selected.complainantDetail}
                  username={selected.complainantUsername}
                  onOpenProfile={openUserProfile}
                />
                <AccountCard
                  tone="reported"
                  kicker="Reported (Respondent)"
                  roleLabel={ROLE_LABELS[selected.respondentDetail?.role] || "Worker"}
                  detail={selected.respondentDetail}
                  username={selected.respondentUsername}
                  onOpenProfile={openUserProfile}
                />
              </div>

              <div className="admin-report-info-card">
                <p className="admin-report-info-kicker">Description</p>
                <p className="mb-0">{selected.description}</p>
              </div>

              <div className="admin-report-info-card">
                <p className="admin-report-info-kicker">Photo Evidence</p>
                {selected.evidence?.length > 0 ? (
                  <div className="d-flex gap-2 flex-wrap">
                    {selected.evidence.map((item) => (
                      <a key={item.id} href={item.imageUrl} target="_blank" rel="noreferrer">
                        <img
                          src={item.imageUrl}
                          alt={`Evidence for report ${selected.id}`}
                          className="admin-report-evidence-thumb"
                        />
                      </a>
                    ))}
                  </div>
                ) : (
                  <p className="small text-muted mb-0">No photos were attached to this report.</p>
                )}
              </div>

              <div className="admin-report-info-card">
                <p className="admin-report-info-kicker">Account Action</p>
                <div className="d-flex align-items-center gap-2 flex-wrap">
                  {selected.respondentIsBlocked ? (
                    <>
                      <button
                        type="button"
                        className="btn btn-sm btn-outline-success"
                        disabled={savingId === selected.id || !selected.respondentUsername}
                        onClick={() => restoreRespondent(selected)}
                      >
                        Restore {selected.respondentUsername}
                      </button>
                      <span className="badge text-bg-danger">
                        {selected.respondentBlockedUntil
                          ? `Suspended until ${new Date(selected.respondentBlockedUntil).toLocaleString()}`
                          : "Account blocked (permanent)"}
                      </span>
                    </>
                  ) : (
                    <>
                      <button
                        type="button"
                        className="btn btn-sm btn-outline-warning"
                        disabled={savingId === selected.id || !selected.respondentUsername}
                        onClick={() => suspendRespondent(selected, 3)}
                      >
                        Suspend {selected.respondentUsername || "user"} 3 Days
                      </button>
                      <button
                        type="button"
                        className="btn btn-sm btn-outline-warning"
                        disabled={savingId === selected.id || !selected.respondentUsername}
                        onClick={() => suspendRespondent(selected, 7)}
                      >
                        Suspend 7 Days
                      </button>
                      <button
                        type="button"
                        className="btn btn-sm btn-outline-danger"
                        disabled={savingId === selected.id || !selected.respondentUsername}
                        onClick={() => suspendRespondent(selected, null)}
                      >
                        Block Permanently
                      </button>
                    </>
                  )}
                </div>
              </div>

              <div className="admin-report-info-card">
                <p className="admin-report-info-kicker">Notes</p>
                <textarea
                  className="form-control"
                  rows={3}
                  value={notesDraft}
                  onChange={(event) => setNotesDraft(event.target.value)}
                  placeholder="Internal notes about what action was taken..."
                />
              </div>
            </div>

            <div className="gg-modal-foot admin-report-modal-foot">
              <button type="button" className="btn btn-outline-secondary" onClick={() => setSelectedId(null)}>
                Close
              </button>
              <div className="d-flex gap-2">
                <button
                  type="button"
                  className="btn btn-outline-secondary"
                  disabled={savingId === selected.id}
                  onClick={() => saveNotes(selected)}
                >
                  Save Notes
                </button>
                <button
                  type="button"
                  className="btn admin-report-resolve-btn"
                  disabled={savingId === selected.id}
                  onClick={() => markResolved(selected)}
                >
                  Mark Resolved
                </button>
                <button
                  type="button"
                  className="btn admin-report-close-btn"
                  disabled={savingId === selected.id}
                  onClick={() => closeReport(selected)}
                >
                  Close Report
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {profileTarget && (
        <div
          className="gg-modal-backdrop admin-profile-modal-backdrop"
          role="presentation"
          onClick={() => setProfileTarget(null)}
        >
          <div
            className="gg-modal-panel admin-report-modal"
            role="dialog"
            aria-modal="true"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="gg-modal-head admin-report-modal-head">
              <div className="d-flex align-items-center gap-3">
                <span className="admin-report-account-avatar admin-profile-modal-avatar">
                  {initials(profileFullRecord?.displayName || profileTarget.detail?.displayName || profileTarget.username)}
                </span>
                <div>
                  <p className="gg-modal-kicker">{ROLE_LABELS[profileTarget.role] || "User"} Profile</p>
                  <h2>{profileFullRecord?.displayName || profileTarget.detail?.displayName || profileTarget.username}</h2>
                </div>
              </div>
              <button
                type="button"
                className="gg-modal-close"
                onClick={() => setProfileTarget(null)}
                aria-label="Close"
              >
                ×
              </button>
            </div>

            <div className="gg-modal-body admin-report-modal-body">
              <div className="admin-report-info-card">
                <p className="admin-report-info-kicker">Profile</p>
                <div className="admin-report-account-facts">
                  <div>
                    <span>Username</span>
                    <strong>@{profileTarget.username}</strong>
                  </div>
                  <div>
                    <span>Verification</span>
                    <strong>{profileFullRecord?.verification || "Unknown"}</strong>
                  </div>
                  <div>
                    <span>Rating</span>
                    <strong>
                      {profileFullRecord?.rating ??
                        (profileTarget.detail?.averageRating != null
                          ? profileTarget.detail.averageRating.toFixed(1)
                          : "No ratings yet")}{" "}
                      ({profileFullRecord?.reviewsDone ?? profileTarget.detail?.ratingCount ?? 0} jobs)
                    </strong>
                  </div>
                  <div>
                    <span>Barangay</span>
                    <strong>
                      {profileFullRecord?.barangay ||
                        (profileTarget.detail?.locationLabel
                          ? parseLocationLabel(profileTarget.detail.locationLabel).barangay
                          : "") ||
                        "Not set"}
                    </strong>
                  </div>
                  <div>
                    <span>Phone</span>
                    <strong>{profileFullRecord?.phone || profileTarget.detail?.phone || "Not provided"}</strong>
                  </div>
                  <div>
                    <span>Email</span>
                    <strong>{profileFullRecord?.email || profileTarget.detail?.email || "Not provided"}</strong>
                  </div>
                </div>
                {profileTarget.role === "worker" && profileFullRecord?.skills?.length > 0 && (
                  <div className="mt-3">
                    <span className="small text-muted d-block mb-1">Skills</span>
                    <div className="d-flex gap-2 flex-wrap">
                      {profileFullRecord.skills.map((skill) => (
                        <span className="badge text-bg-light border text-dark" key={skill}>
                          {skill}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </div>

              <AdminUserHistorySection
                role={profileTarget.role}
                fullRecord={profileFullRecord}
                postedJobs={postedJobs}
                currentUser={currentUser}
              />
            </div>

            <div className="gg-modal-foot">
              <button type="button" className="btn btn-outline-secondary" onClick={() => setProfileTarget(null)}>
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
