import React, { useCallback, useEffect, useMemo, useState } from "react";

import {
  fetchAdminCertificates,
  fetchAdminVerificationDocuments,
  reviewCertificate,
  reviewVerificationDocument,
} from "../services/backendDataService";

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

function isImageFile(url) {
  return /\.(png|jpe?g|gif|webp)(\?|$)/i.test(url || "");
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
 * Admin review of worker credentials: TESDA/licence certificates (roadmap
 * item #11) and government ID documents (#12). Both backends shipped with
 * tests but no screen, so neither approval workflow was reachable until now.
 */
export default function AdminCredentialsQueue() {
  const [tab, setTab] = useState("certificates");
  const [statusFilter, setStatusFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [certificates, setCertificates] = useState([]);
  const [documents, setDocuments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [savingKey, setSavingKey] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [certs, docs] = await Promise.all([
        fetchAdminCertificates("all"),
        fetchAdminVerificationDocuments("all"),
      ]);
      if (certs === null || docs === null) {
        setError("Unable to load this queue. Check that you're signed in as an admin.");
      }
      setCertificates(certs || []);
      setDocuments(docs || []);
    } catch (loadError) {
      setError(loadError.message || "Unable to load this queue.");
      setCertificates([]);
      setDocuments([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  // Both tabs' records are reshaped into one card view-model so the grid
  // below doesn't need to branch on kind everywhere it reads a field.
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
        status: record.verificationStatus,
        verifiedAt: record.verifiedAt,
      })),
    [certificates],
  );

  const documentCards = useMemo(
    () =>
      documents.map((record) => ({
        kind: "document",
        id: record.id,
        recordKey: `document-${record.id}`,
        displayName: record.displayName,
        username: record.username,
        locationLabel: record.locationLabel,
        memberSince: record.memberSince,
        title: record.idTypeLabel || "Government ID",
        typeLabel: "Government ID",
        detailLines: [
          `Submitted: ${formatFullDate(record.createdAt) || "—"}`,
          ...(record.idNumber ? [`ID Number: ${record.idNumber}`] : []),
        ],
        fileUrl: record.fileUrl,
        status: record.verificationStatus,
        verifiedAt: record.verifiedAt,
      })),
    [documents],
  );

  const stats = useMemo(() => {
    const today = new Date();
    const combined = [...certificateCards, ...documentCards];
    return {
      pending: combined.filter((card) => card.status === "pending").length,
      approvedToday: combined.filter((card) => card.status === "approved" && isSameLocalDay(card.verifiedAt, today))
        .length,
      rejected: combined.filter((card) => card.status === "rejected").length,
      total: combined.length,
    };
  }, [certificateCards, documentCards]);

  const isCertificates = tab === "certificates";
  const activeCards = isCertificates ? certificateCards : documentCards;

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
      const notes =
        decision === "rejected"
          ? window.prompt("Reason for rejecting (shown to the worker, optional):", "") || ""
          : "";
      if (card.kind === "certificate") {
        const updated = await reviewCertificate(card.id, { status: decision, notes });
        setCertificates((prev) => prev.map((item) => (item.id === card.id ? updated : item)));
      } else {
        const updated = await reviewVerificationDocument(card.id, { status: decision, notes });
        setDocuments((prev) => prev.map((item) => (item.id === card.id ? updated : item)));
      }
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
          <p>Review and verify certificates and government IDs submitted by workers.</p>
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
          <button
            type="button"
            className={`household-history-tab ${isCertificates ? "active" : ""}`}
            onClick={() => setTab("certificates")}
          >
            Certificates <span className="household-history-tab-count">{certificateCards.length}</span>
          </button>
          <button
            type="button"
            className={`household-history-tab ${isCertificates ? "" : "active"}`}
            onClick={() => setTab("documents")}
          >
            Government IDs <span className="household-history-tab-count">{documentCards.length}</span>
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
          No {isCertificates ? "certificates" : "ID documents"} match this filter.
          {!isCertificates && (
            <p className="small text-muted mb-0 mt-2">
              Worker identity is currently collected through the Verification Queue tab. This queue covers the
              separate multi-ID-type submissions.
            </p>
          )}
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
          {card.fileUrl && isImageFile(card.fileUrl) ? (
            <img src={card.fileUrl} alt={card.title} />
          ) : (
            <span className="admin-credential-preview-icon">PDF</span>
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
          <a className="admin-credential-btn ghost" href={card.fileUrl} target="_blank" rel="noreferrer">
            View Document
          </a>
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
