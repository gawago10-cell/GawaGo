import React, { useCallback, useEffect, useMemo, useState } from "react";

import AuthImage from "./AuthImage";
import { fetchAdminCertificates, reviewCertificate } from "../services/backendDataService";
import { openProtectedFile } from "../utils/protectedFiles";

const STATUS_FILTERS = [
  { value: "all", label: "All" },
  { value: "pending", label: "Pending" },
  { value: "approved", label: "Approved" },
  { value: "rejected", label: "Rejected" },
];

const STATUS_BADGE_LABEL = {
  pending: "Pending Review",
  approved: "Approved",
  rejected: "Rejected",
};

function initials(name) {
  const parts = (name || "").trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) {
    return "?";
  }
  if (parts.length === 1) {
    return parts[0].slice(0, 2).toUpperCase();
  }
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function formatMonthYear(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleDateString("en-US", { month: "short", year: "numeric" });
}

function formatFullDate(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function isSameLocalDay(value, reference) {
  if (!value) return false;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return false;
  return (
    date.getFullYear() === reference.getFullYear() &&
    date.getMonth() === reference.getMonth() &&
    date.getDate() === reference.getDate()
  );
}

/**
 * Admin review of worker credentials: TESDA/licence certificates. Identity
 * documents are not reviewed here -- government IDs go through the
 * Verification Queue, which is the flow whose approval actually marks the
 * account verified.
 */
export default function AdminCredentialsQueue() {
  const [statusFilter, setStatusFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [certificates, setCertificates] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [savingKey, setSavingKey] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const certs = await fetchAdminCertificates("all");
      if (certs === null) {
        setError("Unable to load this queue. Check that you're signed in as an admin.");
      }
      setCertificates(certs || []);
    } catch (loadError) {
      setError(loadError.message || "Unable to load this queue.");
      setCertificates([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  // Records are reshaped into a card view-model so the grid below doesn't
  // need to know the record's shape everywhere it reads a field.
  const certificateCards = useMemo(
    () =>
      certificates.map((record) => ({
        kind: "certificate",
        id: record.id,
        recordKey: `certificate-${record.id}`,
        displayName: record.workerName,
        username: record.workerUsername,
        locationLabel: record.workerLocationLabel,
        memberSince: record.workerMemberSince,
        title: record.certificateName || "Untitled certificate",
        typeLabel: record.certificateTypeLabel,
        detailLines: [
          `Submitted: ${formatFullDate(record.createdAt) || "—"}`,
          ...(record.expiryDate ? [`Expires: ${formatFullDate(record.expiryDate)}`] : []),
        ],
        fileUrl: record.fileUrl,
        fileType: record.fileType,
        status: record.verificationStatus,
        verifiedAt: record.verifiedAt,
      })),
    [certificates],
  );

  const stats = useMemo(() => {
    const today = new Date();
    return {
      pending: certificateCards.filter((card) => card.status === "pending").length,
      approvedToday: certificateCards.filter(
        (card) => card.status === "approved" && isSameLocalDay(card.verifiedAt, today),
      ).length,
      rejected: certificateCards.filter((card) => card.status === "rejected").length,
      total: certificateCards.length,
    };
  }, [certificateCards]);

  const activeCards = certificateCards;

  const chipCounts = useMemo(
    () => ({
      all: activeCards.length,
      pending: activeCards.filter((card) => card.status === "pending").length,
      approved: activeCards.filter((card) => card.status === "approved").length,
      rejected: activeCards.filter((card) => card.status === "rejected").length,
    }),
    [activeCards],
  );

  const searchTerm = search.trim().toLowerCase();
  const visibleCards = activeCards.filter((card) => {
    if (statusFilter !== "all" && card.status !== statusFilter) {
      return false;
    }
    if (!searchTerm) {
      return true;
    }
    return (
      card.displayName.toLowerCase().includes(searchTerm) ||
      card.username.toLowerCase().includes(searchTerm) ||
      card.title.toLowerCase().includes(searchTerm)
    );
  });

  async function applyDecision(card, decision) {
    setSavingKey(card.recordKey);
    try {
      let notes = "";
      if (decision === "rejected") {
        const answer = window.prompt("Reason for rejecting (shown to the worker, optional):", "");
        // Cancel means "don't reject", not "reject with no reason".
        if (answer === null) {
          return;
        }
        notes = answer;
      }
      const updated = await reviewCertificate(card.id, { status: decision, notes });
      setCertificates((prev) => prev.map((item) => (item.id === card.id ? updated : item)));
    } catch (decisionError) {
      window.alert(decisionError.message || "Unable to save this decision.");
    } finally {
      setSavingKey(null);
    }
  }

  return (
    <div className="admin-credentials-page">
      <div className="admin-reports-header">
        <div>
          <h2>Worker Credentials</h2>
          <p>Review and verify TESDA certificates, licences and other credentials submitted by workers.</p>
        </div>
      </div>

      <div className="admin-credentials-stats">
        <div className="admin-credentials-stat pending">
          <div className="admin-credentials-stat-head">
            <span>Pending Review</span>
            <span className="admin-credentials-stat-icon" aria-hidden="true">
              ⏳
            </span>
          </div>
          <strong>{stats.pending}</strong>
        </div>
        <div className="admin-credentials-stat approved">
          <div className="admin-credentials-stat-head">
            <span>Approved Today</span>
            <span className="admin-credentials-stat-icon" aria-hidden="true">
              ✓
            </span>
          </div>
          <strong>{stats.approvedToday}</strong>
        </div>
        <div className="admin-credentials-stat rejected">
          <div className="admin-credentials-stat-head">
            <span>Rejected</span>
            <span className="admin-credentials-stat-icon" aria-hidden="true">
              ✕
            </span>
          </div>
          <strong>{stats.rejected}</strong>
        </div>
        <div className="admin-credentials-stat total">
          <div className="admin-credentials-stat-head">
            <span>Total Submitted</span>
            <span className="admin-credentials-stat-icon" aria-hidden="true">
              📄
            </span>
          </div>
          <strong>{stats.total}</strong>
        </div>
      </div>

      <div className="admin-credentials-toolbar">
        <div className="household-history-tabs mb-0">
          <button type="button" className="household-history-tab active" aria-current="page">
            Certificates <span className="household-history-tab-count">{certificateCards.length}</span>
          </button>
        </div>
        <input
          type="search"
          className="admin-credentials-search"
          placeholder="Search worker or credential…"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
        />
      </div>

      <div className="admin-credentials-chips">
        {STATUS_FILTERS.map((option) => (
          <button
            key={option.value}
            type="button"
            className={`admin-credentials-chip ${statusFilter === option.value ? "active" : ""}`}
            onClick={() => setStatusFilter(option.value)}
          >
            {option.label} <span>{chipCounts[option.value]}</span>
          </button>
        ))}
      </div>

      {error && <div className="alert alert-warning">{error}</div>}

      {loading ? (
        <div className="admin-reports-empty">Loading…</div>
      ) : visibleCards.length === 0 ? (
        <div className="admin-reports-empty">
          No certificates match this filter.
          <p className="small text-muted mb-0 mt-2">
            Government IDs are reviewed in the Verification Queue, not here.
          </p>
        </div>
      ) : (
        <div className="admin-credentials-grid">
          {visibleCards.map((card) => (
            <CredentialCard
              key={card.recordKey}
              card={card}
              saving={savingKey === card.recordKey}
              onApprove={() => applyDecision(card, "approved")}
              onReject={() => applyDecision(card, "rejected")}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function CredentialCard({ card, saving, onApprove, onReject }) {
  return (
    <div className={`admin-credential-card status-${card.status}`}>
      <div className="admin-credential-card-head">
        <span className="admin-credential-avatar">{initials(card.displayName)}</span>
        <div className="admin-credential-identity">
          <strong>{card.displayName || card.username || "Unknown user"}</strong>
          <span>
            {[card.locationLabel, card.memberSince ? `Member since ${formatMonthYear(card.memberSince)}` : ""]
              .filter(Boolean)
              .join(" · ") || `@${card.username}`}
          </span>
        </div>
        <span className={`admin-credential-status-badge ${card.status}`}>
          {STATUS_BADGE_LABEL[card.status] || card.status}
        </span>
      </div>

      <div className="admin-credential-body">
        <div className="admin-credential-preview">
          {card.fileUrl && card.fileType === "image" ? (
            // The file route is permission-checked, so a plain <img> can't
            // load it: the bytes are fetched with the admin's token.
            <AuthImage src={card.fileUrl} alt={card.title} />
          ) : (
            <span className="admin-credential-preview-icon">{card.fileType === "pdf" ? "PDF" : "FILE"}</span>
          )}
        </div>
        <div className="admin-credential-details">
          <div className="admin-credential-title-row">
            <strong>{card.title}</strong>
            {card.typeLabel && <span className="admin-credential-type-badge">{card.typeLabel}</span>}
          </div>
          {card.detailLines.map((line) => (
            <p key={line}>{line}</p>
          ))}
        </div>
      </div>

      <div className="admin-credential-actions">
        {card.fileUrl ? (
          <button type="button" className="admin-credential-btn ghost" onClick={() => openProtectedFile(card.fileUrl)}>
            View Document
          </button>
        ) : (
          <span className="admin-credential-btn ghost disabled">No file</span>
        )}
        <button type="button" className="admin-credential-btn approve" disabled={saving} onClick={onApprove}>
          Approve
        </button>
        <button type="button" className="admin-credential-btn reject" disabled={saving} onClick={onReject}>
          Reject
        </button>
      </div>
    </div>
  );
}
