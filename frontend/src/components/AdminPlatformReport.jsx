import React, { useCallback, useEffect, useState } from "react";

import { downloadPlatformReportCsv, fetchPlatformReport } from "../services/backendDataService";
import { formatMoney } from "../utils/adminReportFormatting";

// Label and format for each platform-report summary key (apps.reports.services).
const SUMMARY_FIELDS = [
  ["totalAccounts", "Member accounts"],
  ["totalWorkers", "Workers"],
  ["totalHouseholds", "Households"],
  ["jobsPosted", "Jobs posted"],
  ["completedJobs", "Completed jobs"],
  ["cancelledJobs", "Cancelled jobs"],
  ["activeApplications", "Applications awaiting a decision"],
  ["hiringSuccessRate", "Hiring success rate", "percent"],
  ["jobMatchRate", "Job match rate", "percent"],
  ["verifiedUsers", "Verified users"],
  ["pendingVerifications", "Pending verifications"],
  ["rejectedVerifications", "Rejected verifications"],
  ["averageWorkerRating", "Average worker rating", "rating"],
  ["completedJobValue", "Value of completed jobs", "money"],
];

function formatValue(value, kind) {
  if (value === null || value === undefined || value === "") {
    return kind === "rating" ? "No ratings yet" : "—";
  }
  if (kind === "percent") return `${Number(value).toFixed(1)}%`;
  if (kind === "rating") return Number(value).toFixed(2);
  if (kind === "money") return formatMoney(value);
  return String(value);
}

function isoDaysAgo(days) {
  const date = new Date();
  date.setDate(date.getDate() - days);
  return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

/**
 * The admin activity report (AGENTS.md IV.B): a date-bounded, platform-wide
 * report built by the backend, with the same CSV export. Money is the agreed
 * rate of jobs that reached Completed -- GawaGo processes no payments.
 */
export default function AdminPlatformReport() {
  const [start, setStart] = useState(() => isoDaysAgo(180));
  const [end, setEnd] = useState(() => isoDaysAgo(0));
  const [report, setReport] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [downloading, setDownloading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const data = await fetchPlatformReport({ start, end });
      if (!data) {
        setError("Unable to load the report. Check that you're signed in as an admin.");
      }
      setReport(data);
    } catch (loadError) {
      setError(loadError.message || "Unable to load the report.");
      setReport(null);
    } finally {
      setLoading(false);
    }
  }, [start, end]);

  useEffect(() => {
    load();
  }, [load]);

  async function handleDownload() {
    if (downloading) return;
    setDownloading(true);
    try {
      await downloadPlatformReportCsv({ start, end });
    } catch (downloadError) {
      setError(downloadError.message || "Unable to download the report.");
    } finally {
      setDownloading(false);
    }
  }

  const summary = report?.summary || {};
  return (
    <div className="admin-reports-page admin-platform-report">
      <div className="admin-reports-header">
        <div>
          <h2>Platform Activity Report</h2>
          <p>
            What happened over a period, across all households and workers. Money is the agreed rate of completed
            jobs; GawaGo does not process payments.
          </p>
        </div>
        <div className="admin-reports-header-actions">
          <label className="admin-reports-filter">
            <span>From</span>
            <input type="date" value={start} max={end} onChange={(event) => setStart(event.target.value)} />
          </label>
          <label className="admin-reports-filter">
            <span>To</span>
            <input type="date" value={end} min={start} onChange={(event) => setEnd(event.target.value)} />
          </label>
          <button type="button" className="btn btn-success" disabled={downloading || loading} onClick={handleDownload}>
            {downloading ? "Preparing…" : "Export CSV"}
          </button>
        </div>
      </div>

      {error && <div className="alert alert-warning">{error}</div>}

      {loading ? (
        <div className="admin-reports-empty">Loading report…</div>
      ) : report ? (
        <>
          <div className="admin-platform-report-summary">
            {SUMMARY_FIELDS.map(([key, label, kind]) => (
              <div className="admin-report-stat-card" key={key}>
                <p className="admin-report-stat-label">{label}</p>
                <p className="admin-report-stat-value">{formatValue(summary[key], kind)}</p>
              </div>
            ))}
          </div>
          {(report.sections || []).map((section) => (
            <div className="admin-reports-table-card" key={section.title}>
              <div className="admin-platform-report-section-head">
                <h3>{section.title}</h3>
                {section.description && <p>{section.description}</p>}
              </div>
              {section.rows?.length ? (
                <table className="admin-reports-table">
                  <thead>
                    <tr>
                      {section.columns.map((column) => (
                        <th key={column}>{column}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {section.rows.map((row, index) => (
                      <tr key={`${section.title}-${index}`}>
                        {row.map((cell, cellIndex) => (
                          <td key={cellIndex}>{cell}</td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
              ) : (
                <div className="admin-reports-empty">No activity in this period.</div>
              )}
            </div>
          ))}
        </>
      ) : null}
    </div>
  );
}
