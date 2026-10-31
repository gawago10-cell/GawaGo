import React, { useMemo, useState } from "react";

import { APPLICATION_STATUS_TONE, JOB_STATUS_TONE, appCode, formatMoney, jobCode } from "../utils/adminReportFormatting";

const JOB_STATUS_OPTIONS = ["Open", "Already found a worker", "Waiting for Household Confirmation", "Completed", "Cancelled"];
const APPLICATION_STATUS_OPTIONS = ["Pending", "Hire Request", "Hired", "Rejected", "Completed", "Closed"];

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

function StatusPill({ status, tone }) {
  return <span className={`admin-report-status-pill ${tone || "submitted"}`}>{status}</span>;
}

function StatCard({ tone, label, value, note }) {
  return (
    <div className="admin-report-stat-card">
      <p className="admin-report-stat-label">
        <i className={`admin-report-stat-dot ${tone}`} aria-hidden="true" />
        {label}
      </p>
      <p className="admin-report-stat-value">{value}</p>
      <p className="admin-report-stat-note">{note}</p>
    </div>
  );
}

/**
 * Full platform records for admins: every job ever posted and every
 * application ever filed, searchable and filterable. Reads the same
 * postedJobs/registeredWorkers state the rest of the superadmin dashboard
 * already loads (which the backend serves unfiltered to staff), so this
 * view needs no dedicated API calls of its own.
 */
export default function ReportsView({ postedJobs = [], registeredWorkers = [] }) {
  const [tab, setTab] = useState("jobs");
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("");

  const workerByUsername = useMemo(() => {
    const map = {};
    registeredWorkers.forEach((worker) => {
      if (worker.username) map[worker.username.toLowerCase()] = worker;
    });
    return map;
  }, [registeredWorkers]);

  const allApplications = useMemo(() => {
    const rows = [];
    postedJobs.forEach((job) => {
      (job.applications || []).forEach((application) => {
        rows.push({ ...application, job });
      });
    });
    return rows.sort((a, b) => new Date(b.appliedAt || 0) - new Date(a.appliedAt || 0));
  }, [postedJobs]);

  const totalApplications = allApplications.length;
  const pendingApplications = allApplications.filter((application) => application.status === "Pending").length;
  const openJobs = postedJobs.filter((job) => job.status === "Open").length;
  const completedJobs = postedJobs.filter((job) => job.status === "Completed").length;
  const cancelledJobs = postedJobs.filter((job) => job.status === "Cancelled").length;

  const filteredJobs = useMemo(() => {
    const query = search.trim().toLowerCase();
    return postedJobs.filter((job) => {
      if (statusFilter && job.status !== statusFilter) return false;
      if (!query) return true;
      return (
        jobCode(job.id).toLowerCase().includes(query) ||
        (job.jobTitle || "").toLowerCase().includes(query) ||
        (job.householdName || "").toLowerCase().includes(query)
      );
    });
  }, [postedJobs, search, statusFilter]);

  const filteredApplications = useMemo(() => {
    const query = search.trim().toLowerCase();
    return allApplications.filter((application) => {
      if (statusFilter && application.status !== statusFilter) return false;
      if (!query) return true;
      return (
        appCode(application.id).toLowerCase().includes(query) ||
        (application.workerName || "").toLowerCase().includes(query) ||
        (application.workerUsername || "").toLowerCase().includes(query) ||
        (application.job?.jobTitle || "").toLowerCase().includes(query) ||
        jobCode(application.job?.id).toLowerCase().includes(query)
      );
    });
  }, [allApplications, search, statusFilter]);

  function switchTab(nextTab) {
    setTab(nextTab);
    setStatusFilter("");
  }

  return (
    <div className="admin-reports-page">
      <div className="admin-reports-header">
        <div>
          <h2>Reports</h2>
          <p>Full records of all platform jobs and worker applications</p>
        </div>
        <div className="admin-reports-header-actions">
          <span className="admin-reports-updated">
            Last updated: <strong>{new Date().toISOString().slice(0, 10)}</strong>
          </span>
        </div>
      </div>

      <div className="admin-report-stats-scroll">
        <StatCard tone="neutral" label="Total Jobs Posted" value={postedJobs.length} note="all time" />
        <StatCard tone="resolved" label="Open Jobs" value={openJobs} note="accepting applicants" />
        <StatCard tone="closed" label="Completed Jobs" value={completedJobs} note="successfully finished" />
        <StatCard tone="review" label="Total Applications" value={totalApplications} note="across all jobs" />
        <StatCard tone="submitted" label="Pending Applications" value={pendingApplications} note="awaiting review" />
        <StatCard tone="closed" label="Cancelled Jobs" value={cancelledJobs} note="did not go through" />
      </div>

      <div className="admin-reports-toolbar">
        <div className="admin-reports-tabs">
          <button
            type="button"
            className={`admin-reports-tab ${tab === "jobs" ? "active" : ""}`}
            onClick={() => switchTab("jobs")}
          >
            Posted Jobs ({postedJobs.length})
          </button>
          <button
            type="button"
            className={`admin-reports-tab ${tab === "applications" ? "active" : ""}`}
            onClick={() => switchTab("applications")}
          >
            Worker Applications ({allApplications.length})
          </button>
        </div>
        <input
          type="text"
          className="admin-reports-search"
          placeholder={tab === "jobs" ? "Search by ID, title, household..." : "Search by ID, worker, job..."}
          value={search}
          onChange={(event) => setSearch(event.target.value)}
        />
        <select
          className="admin-reports-status-select"
          value={statusFilter}
          onChange={(event) => setStatusFilter(event.target.value)}
        >
          <option value="">All Statuses</option>
          {(tab === "jobs" ? JOB_STATUS_OPTIONS : APPLICATION_STATUS_OPTIONS).map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
        </select>
      </div>

      {tab === "jobs" ? (
        <div className="admin-reports-table-card">
          <div className="table-responsive">
            {/* Short headers: their width sets the column's, and long ones left
                the title ~100px and pushed Status off the card. */}
            <table className="admin-reports-table admin-reports-list">
              <thead>
                <tr>
                  <th>Job ID</th>
                  <th>Title</th>
                  <th>Posted By</th>
                  <th>Service</th>
                  <th>Barangay</th>
                  <th>Posted</th>
                  <th>Budget</th>
                  <th>Applied</th>
                  <th>Hired</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {filteredJobs.length === 0 ? (
                  <tr>
                    <td colSpan={10} className="admin-reports-empty-row">
                      No jobs match this search.
                    </td>
                  </tr>
                ) : (
                  filteredJobs.map((job) => (
                    <tr key={job.id}>
                      <td className="admin-reports-id">{jobCode(job.id)}</td>
                      <td className="admin-reports-wrap admin-reports-title">{job.jobTitle}</td>
                      <td className="admin-reports-wrap">
                        <div className="admin-report-party-cell">
                          <span className="admin-report-party-avatar">{initials(job.householdName)}</span>
                          <span>{job.householdName}</span>
                        </div>
                      </td>
                      <td className="text-muted admin-reports-wrap">{job.serviceType}</td>
                      <td className="text-muted admin-reports-wrap">{job.barangay || "—"}</td>
                      <td className="text-muted">{job.createdAt?.slice(0, 10)}</td>
                      <td>{formatMoney(job.offeredRate)}</td>
                      <td className="text-muted">{(job.applications || []).length}</td>
                      <td className="text-muted">
                        {job.hiredCount}/{job.workersNeeded}
                      </td>
                      <td>
                        <StatusPill status={job.statusLabel || job.status} tone={JOB_STATUS_TONE[job.status]} />
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      ) : (
        <div className="admin-reports-table-card">
          <div className="table-responsive">
            <table className="admin-reports-table admin-reports-list">
              <thead>
                <tr>
                  <th>App ID</th>
                  <th>Worker</th>
                  <th>Rating</th>
                  <th>Job ID</th>
                  <th>Job Title</th>
                  <th>Barangay</th>
                  <th>Applied</th>
                  <th>Rate</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {filteredApplications.length === 0 ? (
                  <tr>
                    <td colSpan={9} className="admin-reports-empty-row">
                      No applications match this search.
                    </td>
                  </tr>
                ) : (
                  filteredApplications.map((application) => {
                    const worker = workerByUsername[String(application.workerUsername).toLowerCase()];
                    const ratingValue = Number(worker?.rating);
                    return (
                      <tr key={application.id}>
                        <td className="admin-reports-id">{appCode(application.id)}</td>
                        <td className="admin-reports-wrap">
                          <div className="admin-report-party-cell">
                            <span className="admin-report-party-avatar">{initials(application.workerName)}</span>
                            <span>{application.workerName}</span>
                          </div>
                        </td>
                        <td>
                          {Number.isFinite(ratingValue) ? (
                            <span className="admin-reports-rating">★ {ratingValue.toFixed(1)}</span>
                          ) : (
                            <span className="text-muted">—</span>
                          )}
                        </td>
                        <td className="admin-reports-id">{jobCode(application.job?.id)}</td>
                        <td className="admin-reports-wrap admin-reports-title">{application.job?.jobTitle}</td>
                        <td className="text-muted admin-reports-wrap">{application.job?.barangay || "—"}</td>
                        <td className="text-muted">{application.appliedAt?.slice(0, 10)}</td>
                        <td>{formatMoney(application.job?.offeredRate)}</td>
                        <td>
                          <StatusPill status={application.status} tone={APPLICATION_STATUS_TONE[application.status]} />
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
