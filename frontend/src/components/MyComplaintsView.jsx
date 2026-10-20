import React, { useEffect, useMemo, useState } from "react";
import { getVerificationNavLabel } from "../utils/normalizers";

import { fetchMyComplaints } from "../services/backendDataService";
import AuthImage from "./AuthImage";
import { getUserRole, ROLES } from "../utils/roles";
import { DashboardSidebar, MobileDashboardTopbar } from "./DashboardLayout";

const STATUS_LABELS = {
  submitted: "Submitted",
  under_review: "Under Review",
  resolved: "Resolved",
  closed: "Closed",
};

const STATUS_FILTERS = ["all", "submitted", "under_review", "resolved", "closed"];

const TYPE_LABELS = {
  payment_issue: "Payment Issue",
  quality_of_work: "Quality of Work",
  no_show: "No Show",
  safety_concern: "Safety Concern",
  behavior: "Inappropriate Behavior",
  other: "Other",
};

function TypeIcon({ type }) {
  const commonProps = {
    width: 19,
    height: 19,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 2,
    strokeLinecap: "round",
    strokeLinejoin: "round",
    "aria-hidden": "true",
  };
  switch (type) {
    case "payment_issue":
      return (
        <svg {...commonProps}>
          <rect x="1" y="4" width="22" height="16" rx="2" />
          <line x1="1" y1="10" x2="23" y2="10" />
        </svg>
      );
    case "quality_of_work":
      return (
        <svg {...commonProps}>
          <polygon points="12 2 15 8.5 22 9.5 17 14.5 18.3 21.5 12 18 5.7 21.5 7 14.5 2 9.5 9 8.5 12 2" />
        </svg>
      );
    case "no_show":
      return (
        <svg {...commonProps}>
          <circle cx="12" cy="12" r="10" />
          <polyline points="12 6 12 12 16 14" />
        </svg>
      );
    case "safety_concern":
      return (
        <svg {...commonProps}>
          <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z" />
          <line x1="12" y1="9" x2="12" y2="13" />
          <line x1="12" y1="17" x2="12.01" y2="17" />
        </svg>
      );
    case "behavior":
      return (
        <svg {...commonProps}>
          <path d="M21 11.5a8.38 8.38 0 01-.9 3.8 8.5 8.5 0 01-7.6 4.7 8.38 8.38 0 01-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 01-.9-3.8 8.5 8.5 0 014.7-7.6 8.38 8.38 0 013.8-.9h.5a8.48 8.48 0 018 8v.5z" />
        </svg>
      );
    default:
      return (
        <svg {...commonProps}>
          <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z" />
          <line x1="4" y1="22" x2="4" y2="15" />
        </svg>
      );
  }
}

function ResolutionIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <circle cx="12" cy="12" r="10" />
      <polyline points="9 12 11 14 15 10" />
    </svg>
  );
}

function EvidenceIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M23 19a2 2 0 01-2 2H3a2 2 0 01-2-2V8a2 2 0 012-2h4l2-3h6l2 3h4a2 2 0 012 2z" />
      <circle cx="12" cy="13" r="4" />
    </svg>
  );
}

function buildHouseholdNavItems({
  openHouseholdDashboard,
  openHouseholdPostJob,
  openHouseholdMyJobs,
  openHouseholdProfile,
  openHouseholdGetVerified,
  openHouseholdNotifications,
  verificationNavLabel,
}) {
  return [
    { id: "dashboard", label: "Dashboard", onClick: openHouseholdDashboard },
    { id: "post-job", label: "Post a Job", onClick: openHouseholdPostJob },
    { id: "jobs", label: "My Jobs", onClick: openHouseholdMyJobs },
    { id: "flag", label: "My Reports", active: true },
    { id: "profile", label: "My Profile", section: "Account", onClick: openHouseholdProfile },
    { id: "verified", label: verificationNavLabel, onClick: openHouseholdGetVerified },
    { id: "notifications", label: "Notifications", onClick: openHouseholdNotifications },
  ];
}

function buildWorkerNavItems({
  openWorkerDashboard,
  openWorkerFindJobs,
  openWorkerProfile,
  openWorkerApplications,
  openWorkerMyJobs,
  openWorkerGetVerified,
  openWorkerNotifications,
  workerApplicationUnreadCount,
  verificationNavLabel,
}) {
  return [
    { id: "dashboard", label: "Dashboard", onClick: openWorkerDashboard },
    { id: "search", label: "Find Jobs", onClick: openWorkerFindJobs },
    { id: "profile", label: "My Profile", onClick: openWorkerProfile },
    { id: "applications", label: "My Applications", count: workerApplicationUnreadCount, onClick: openWorkerApplications },
    { id: "jobs", label: "My Jobs", onClick: openWorkerMyJobs },
    { id: "flag", label: "My Reports", active: true },
    { id: "verified", label: verificationNavLabel, section: "Account", onClick: openWorkerGetVerified },
    { id: "notifications", label: "Notifications", onClick: openWorkerNotifications },
  ];
}

/**
 * "My Reports" -- issues the signed-in user has filed. Reports about the
 * user are never shown: a report stays confidential from the person it
 * names, and the API only returns reports the caller filed.
 */
export default function MyComplaintsView({
  currentUser,
  currentHousehold,
  currentWorker,
  handleLogout,
  openHouseholdDashboard,
  openHouseholdPostJob,
  openHouseholdMyJobs,
  openHouseholdProfile,
  openHouseholdGetVerified,
  openHouseholdNotifications,
  openWorkerDashboard,
  openWorkerFindJobs,
  openWorkerProfile,
  openWorkerApplications,
  openWorkerMyJobs,
  openWorkerGetVerified,
  openWorkerNotifications,
  workerApplicationUnreadCount,
}) {
  const [complaints, setComplaints] = useState(null);
  const [status, setStatus] = useState("loading");
  const [statusFilter, setStatusFilter] = useState("all");

  useEffect(() => {
    let cancelled = false;
    setStatus("loading");
    fetchMyComplaints().then((data) => {
      if (cancelled) return;
      if (data === null) {
        setStatus("error");
        return;
      }
      setComplaints(data);
      setStatus("ready");
    });
    return () => {
      cancelled = true;
    };
  }, []);

  // Households and workers only (the App-level role guard keeps admins out);
  // an unknown role gets no menu rather than falling back to the worker one.
  const role = getUserRole(currentUser);
  const isHousehold = role === ROLES.HOUSEHOLD;
  const verificationAccount = isHousehold ? currentHousehold : currentWorker;
  const verificationNavLabel = getVerificationNavLabel(verificationAccount);

  const navItems = isHousehold
    ? buildHouseholdNavItems({
        openHouseholdDashboard,
        openHouseholdPostJob,
        openHouseholdMyJobs,
        openHouseholdProfile,
        openHouseholdGetVerified,
        openHouseholdNotifications,
        verificationNavLabel,
      })
    : role === ROLES.WORKER
      ? buildWorkerNavItems({
          openWorkerDashboard,
          openWorkerFindJobs,
          openWorkerProfile,
          openWorkerApplications,
          openWorkerMyJobs,
          openWorkerGetVerified,
          openWorkerNotifications,
          workerApplicationUnreadCount,
          verificationNavLabel,
        })
      : [];

  const visibleComplaints = useMemo(() => {
    if (!complaints) return [];
    if (statusFilter === "all") return complaints;
    return complaints.filter((complaint) => complaint.status === statusFilter);
  }, [complaints, statusFilter]);

  return (
    <>
    <MobileDashboardTopbar resetKey="my-reports" />
    <section className="worker-dashboard my-reports-page">
      <div className="worker-layout">
        <DashboardSidebar
          items={navItems}
          footerAction={{ label: "Log Out", onClick: handleLogout }}
        />
        <div className="worker-content">
          <div className="profile-card p-3 p-md-4 my-reports-header">
            <div className="my-reports-header-icon">
              <TypeIcon type="other" />
            </div>
            <div>
              <h1 className="h4 mb-1">My Reports</h1>
              <p className="text-muted small mb-0">
                Issues you have reported. Our admin team reviews each one confidentially and updates its status
                here.
              </p>
            </div>
          </div>

          {status === "ready" && complaints.length > 0 && (
            <div className="my-reports-filters">
              {STATUS_FILTERS.map((filterValue) => (
                <button
                  type="button"
                  key={filterValue}
                  className={`my-reports-filter ${statusFilter === filterValue ? "active" : ""}`}
                  onClick={() => setStatusFilter(filterValue)}
                >
                  {filterValue === "all" ? "All" : STATUS_LABELS[filterValue]}
                </button>
              ))}
            </div>
          )}

          {status === "loading" && (
            <div className="profile-card p-4 mt-3 text-center">
              <div className="spinner-border text-success" role="status" aria-label="Loading reports" />
            </div>
          )}

          {status === "error" && (
            <div className="alert alert-warning mt-3">Unable to load your reports right now.</div>
          )}

          {status === "ready" && complaints.length === 0 && (
            <div className="profile-card p-4 mt-3 text-center text-muted">
              You haven't reported any issues. You can report an issue from a job's detail page.
            </div>
          )}

          {status === "ready" && complaints.length > 0 && visibleComplaints.length === 0 && (
            <div className="profile-card p-4 text-center text-muted">No reports match this filter.</div>
          )}

          {status === "ready" && visibleComplaints.length > 0 && (
            <div className="my-reports-list">
              {visibleComplaints.map((complaint) => {
                return (
                  <article className="profile-card p-3 p-md-4" key={complaint.id}>
                    <div className="my-report-card-top">
                      <div className="my-report-type">
                        <div className="my-report-type-icon">
                          <TypeIcon type={complaint.complaintType} />
                        </div>
                        <div className="my-report-type-title">
                          <span className="my-report-type-name">
                            {TYPE_LABELS[complaint.complaintType] || complaint.complaintType}
                          </span>
                          {complaint.respondentUsername && (
                            <span className="my-report-direction by-you">About {complaint.respondentUsername}</span>
                          )}
                        </div>
                      </div>
                      <span className={`my-report-status ${complaint.status}`}>
                        <span className="dot" />
                        {STATUS_LABELS[complaint.status] || complaint.status}
                      </span>
                    </div>

                    <p className="my-report-meta">
                      {complaint.jobTitle || "Job report"} &middot; {complaint.createdAt?.slice(0, 10)}
                    </p>

                    {complaint.description && <p className="my-report-desc">{complaint.description}</p>}

                    {complaint.evidence.length > 0 && (
                      <div className="my-report-evidence">
                        <span className="my-report-evidence-label">
                          <EvidenceIcon />
                          Evidence ({complaint.evidence.length})
                        </span>
                        {complaint.evidence.map((item) => (
                          <AuthImage
                            key={item.id}
                            className="my-report-thumb"
                            src={item.imageUrl}
                            alt={`Evidence for report ${complaint.id}`}
                          />
                        ))}
                      </div>
                    )}

                    {complaint.resolution && (
                      <div className="my-report-resolution">
                        <ResolutionIcon />
                        <div>
                          <p className="my-report-resolution-label">Resolution</p>
                          <p className="my-report-resolution-text">{complaint.resolution}</p>
                        </div>
                      </div>
                    )}
                  </article>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </section>
    </>
  );
}
