import React, { useMemo } from "react";

import { APPLICATION_STATUS_TONE, JOB_STATUS_TONE, appCode, formatMoney, jobCode } from "../utils/adminReportFormatting";
import WorkerPortfolioViewPublic from "./WorkerPortfolioViewPublic";

function HistoryStatusPill({ status, tone }) {
  return <span className={`admin-report-status-pill ${tone || "submitted"}`}>{status}</span>;
}

/**
 * The "Portfolio" + job/application history block shown inside an admin's
 * per-user profile modal. Originally built only for the Reported Issues
 * queue's "View profile & history" action (AdminComplaintsQueue.jsx);
 * shared here so User Management's per-user modal shows the same portfolio
 * and history instead of a second, thinner implementation.
 */
export default function AdminUserHistorySection({ role, fullRecord, postedJobs, currentUser }) {
  const householdJobs = useMemo(() => {
    if (role !== "household" || !fullRecord?.username) return [];
    return (postedJobs || [])
      .filter((job) => job.householdUsername?.toLowerCase() === fullRecord.username.toLowerCase())
      .sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
  }, [postedJobs, fullRecord, role]);

  const workerApplications = useMemo(() => {
    if (role !== "worker" || !fullRecord?.username) return [];
    const rows = [];
    (postedJobs || []).forEach((job) => {
      (job.applications || []).forEach((application) => {
        if (application.workerUsername?.toLowerCase() === fullRecord.username.toLowerCase()) {
          rows.push({ ...application, job });
        }
      });
    });
    return rows.sort((a, b) => new Date(b.appliedAt || 0) - new Date(a.appliedAt || 0));
  }, [postedJobs, fullRecord, role]);

  return (
    <>
      {role === "worker" && fullRecord?.id && (
        <>
          <p className="admin-report-section-label">Portfolio</p>
          <WorkerPortfolioViewPublic
            workerId={fullRecord.id}
            workerName={fullRecord.displayName || fullRecord.username}
            currentUser={currentUser}
          />
        </>
      )}

      <p className="admin-report-section-label">
        {role === "household" ? `Jobs Posted (${householdJobs.length})` : `Job Applications (${workerApplications.length})`}
      </p>

      <div className="admin-reports-table-card">
        <div className="table-responsive">
          {role === "household" ? (
            <table className="admin-reports-table">
              <thead>
                <tr>
                  <th>Job ID</th>
                  <th>Title</th>
                  <th>Barangay</th>
                  <th>Date Posted</th>
                  <th>Budget</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {householdJobs.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="admin-reports-empty-row">
                      No jobs posted yet.
                    </td>
                  </tr>
                ) : (
                  householdJobs.map((job) => (
                    <tr key={job.id}>
                      <td className="admin-reports-id">{jobCode(job.id)}</td>
                      <td>{job.jobTitle}</td>
                      <td className="text-muted">{job.barangay || "—"}</td>
                      <td className="text-muted">{job.createdAt?.slice(0, 10)}</td>
                      <td>{formatMoney(job.offeredRate)}</td>
                      <td>
                        <HistoryStatusPill status={job.statusLabel || job.status} tone={JOB_STATUS_TONE[job.status]} />
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          ) : (
            <table className="admin-reports-table">
              <thead>
                <tr>
                  <th>App ID</th>
                  <th>Job</th>
                  <th>Barangay</th>
                  <th>Date Applied</th>
                  <th>Offered Rate</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {workerApplications.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="admin-reports-empty-row">
                      No applications yet.
                    </td>
                  </tr>
                ) : (
                  workerApplications.map((application) => (
                    <tr key={application.id}>
                      <td className="admin-reports-id">{appCode(application.id)}</td>
                      <td>
                        {application.job?.jobTitle}{" "}
                        <span className="text-muted small">({jobCode(application.job?.id)})</span>
                      </td>
                      <td className="text-muted">{application.job?.barangay || "—"}</td>
                      <td className="text-muted">{application.appliedAt?.slice(0, 10)}</td>
                      <td>{formatMoney(application.job?.offeredRate)}</td>
                      <td>
                        <HistoryStatusPill
                          status={application.status}
                          tone={APPLICATION_STATUS_TONE[application.status]}
                        />
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </>
  );
}
