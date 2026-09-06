import React from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { DashboardSidebar, MetricCard } from "./DashboardLayout";
import SuperAdminHeatMap from "./SuperAdminHeatMap";
import {
  ANALYTICS_CHART_COLORS,
  PHILIPPINES_MAP_CENTER,
} from "../constants/appConstants";
import { formatCurrency, getDisplayName, isImagePreviewUrl } from "../utils/formatters";
import { loadLeafletAssets } from "../utils/mapAssets";

export default function SuperAdminDashboardView({
  currentUser,
  dashboardMetrics,
  handleAdminApproveVerification,
  handleAdminRejectVerification,
  handleLogout,
  heatMapMetric,
  openFilePreview,
  openVerificationRequest,
  pendingVerificationRequests,
  postedJobs,
  registeredHouseholds,
  registeredWorkers,
  rejectedVerificationRequests,
  selectedVerificationRequest,
  setHeatMapMetric,
  setSuperAdminSection,
  superAdminSection,
  verificationRequests,
}) {
  const [verificationModalRequestId, setVerificationModalRequestId] = React.useState(null);
  const analytics = dashboardMetrics?.analytics || {};
  const analyticsSummary = analytics.summary || {};
  const totalUsers = analyticsSummary.totalUsers ?? registeredWorkers.length + registeredHouseholds.length;
  const totalWorkers = analyticsSummary.totalWorkers ?? registeredWorkers.length;
  const householdCount = analyticsSummary.households ?? registeredHouseholds.length;
  const totalJobPostings = analyticsSummary.totalJobPostings ?? postedJobs.length;
  const activeJobs = analyticsSummary.activeJobs ?? postedJobs.filter((job) => job.status === "Open").length;
  const activeApplications = analyticsSummary.activeApplications ?? postedJobs.reduce(
    (sum, job) =>
      sum +
      (job.applications || []).filter(
        (application) => !["Rejected", "Completed", "Cancelled"].includes(application.status),
      ).length,
    0,
  );
  const completedServices = analyticsSummary.completedServices ?? postedJobs.filter((job) => job.status === "Completed").length;
  const cancelledRequests = analyticsSummary.cancelledRequests ?? postedJobs.filter((job) => job.status === "Cancelled").length;
  const ongoingMatches = analyticsSummary.ongoingMatches ?? postedJobs.filter((job) =>
    (job.applications || []).some((application) => application.status === "Hired"),
  ).length;
  const verifiedUsers = analyticsSummary.verifiedUsers ?? analyticsSummary.verifiedWorkers ?? registeredWorkers.filter((worker) => worker.verification === "Verified").length;
  const verifiedWorkers = analyticsSummary.verifiedWorkers ?? registeredWorkers.filter((worker) => worker.verification === "Verified").length;
  const verifiedPercent = analyticsSummary.verifiedPercent ?? (registeredWorkers.length ? Math.round((verifiedWorkers / registeredWorkers.length) * 100) : 0);
  const pendingVerificationCount = analyticsSummary.pendingVerifications ?? pendingVerificationRequests.length;
  const rejectedVerificationCount = analyticsSummary.rejectedVerifications ?? rejectedVerificationRequests.length;
  const rejectedWorkerVerifications = analyticsSummary.rejectedWorkers ?? registeredWorkers.filter((worker) => worker.verification === "Rejected").length;
  const monthlyJobRequests = analytics.monthlyJobRequests || [];
  const serviceAnalytics = analytics.serviceAnalytics || [];
  const geographicAnalytics = analytics.geographicAnalytics || {};
  const barangayJobAnalytics = geographicAnalytics.barangayDemand || analytics.barangayJobAnalytics || [];
  const barangayWorkerAnalytics = geographicAnalytics.workerAvailability || analytics.barangayWorkerAnalytics || [];
  const ratingDistribution = analytics.ratingDistribution || [];
  const rateTransparency = analytics.rateTransparency || {};
  const jobCategories = rateTransparency.averageRatesByCategory || analytics.serviceRateSummary || [];
  const pricingTrends = rateTransparency.pricingTrends || [];
  const averageWorkerRating = analyticsSummary.averageWorkerRating || "No ratings yet";
  const ratedWorkerCount = analyticsSummary.ratedWorkerCount ?? 0;
  const heatMapOptions = [
    {
      id: "jobs",
      label: "Job Demand",
    },
    {
      id: "workers",
      label: "Worker Availability",
    },
    {
      id: "completed",
      label: "Completed Services",
    },
    {
      id: "verification",
      label: "Pending Verifications",
    },
  ];
  const selectedHeatMapOption = heatMapOptions.find((option) => option.id === heatMapMetric) || heatMapOptions[0];
  const heatMapData = (analytics.heatMapData || []).map((item) => ({
    ...item,
    value:
      selectedHeatMapOption.id === "workers"
        ? item.workers
        : selectedHeatMapOption.id === "completed"
          ? item.completed
          : selectedHeatMapOption.id === "verification"
            ? item.pendingVerifications
            : item.jobs,
  }));
  const analyticsOverviewGroups = [
    {
      title: "Account Overview",
      note: "Registered users by role",
      items: [
        { label: "Total Users", value: totalUsers },
        { label: "Workers", value: totalWorkers },
        { label: "Households", value: householdCount },
      ],
    },
    {
      title: "Employment Activity",
      note: "Posting, application, and service status",
      items: [
        { label: "Total Postings", value: totalJobPostings },
        { label: "Active Jobs", value: activeJobs },
        { label: "Active Applications", value: activeApplications },
        { label: "Ongoing Matches", value: ongoingMatches },
        { label: "Completed Services", value: completedServices },
        { label: "Cancelled Requests", value: cancelledRequests },
      ],
    },
    {
      title: "Trust and Verification",
      note: "Worker verification and reputation",
      items: [
        { label: "Verified Users", value: verifiedUsers },
        { label: "Pending", value: pendingVerificationCount, tone: pendingVerificationCount > 0 ? "warning" : "neutral" },
        { label: "Rejected", value: rejectedVerificationCount, tone: rejectedVerificationCount > 0 ? "danger" : "neutral" },
        { label: "Average Rating", value: averageWorkerRating, wide: true },
      ],
    },
  ];
  const recentAuditLogs = [
    ...verificationRequests.slice(0, 6).map((request) => ({
      id: `verification-${request.id}`,
      timestamp: request.reviewedAt || request.submittedAt || "Recently",
      admin: request.reviewedBy || currentUser?.displayName || "Super Admin",
      action: `${request.status} verification`,
      target: request.workerName || request.workerUsername,
      status: request.status,
    })),
    {
      id: "system-login",
      timestamp: "Current session",
      admin: currentUser?.displayName || "Super Admin",
      action: "superadmin_login",
      target: "GawaGo frontend",
      status: "Success",
    },
  ];
  const tabs = [
    {
      id: "verification",
      label: "Verification Queue",
    },
    {
      id: "analytics",
      label: "Analytics",
    },
    {
      id: "adminmgmt",
      label: "Admin Management",
      section: "Account",
    },
    {
      id: "audit",
      label: "Audit Logs",
    },
  ];
  const renderStatusBadge = (status) => {
    const badgeClass =
      status === "Approved" || status === "Success"
        ? "text-bg-success"
        : status === "Rejected"
          ? "text-bg-danger"
          : "text-bg-warning";
    return <span className={`badge ${badgeClass}`}>{status}</span>;
  };
  const verificationModalRequest =
    verificationRequests.find((request) => String(request.id) === String(verificationModalRequestId)) || null;
  const verificationModalWorker =
    verificationModalRequest &&
    registeredWorkers.find(
      (worker) =>
        String(worker.id) === String(verificationModalRequest.workerId) ||
        worker.username === verificationModalRequest.workerUsername ||
        getDisplayName(worker.firstName, worker.lastName, worker.username) === verificationModalRequest.workerName,
    );
  const verificationModalWorkerDetails = verificationModalRequest
    ? {
        id: verificationModalWorker?.id || verificationModalRequest.workerId,
        username: verificationModalWorker?.username || verificationModalRequest.workerUsername,
        firstName: verificationModalWorker?.firstName || "",
        lastName: verificationModalWorker?.lastName || "",
        displayName:
          verificationModalWorker?.displayName ||
          (verificationModalWorker
            ? getDisplayName(
                verificationModalWorker.firstName,
                verificationModalWorker.lastName,
                verificationModalWorker.username,
              )
            : verificationModalRequest.workerName || verificationModalRequest.workerUsername || "Worker"),
        phone: verificationModalWorker?.phone || verificationModalRequest.workerPhone || "",
        email: verificationModalWorker?.email || verificationModalRequest.workerEmail || "",
        barangay: verificationModalWorker?.barangay || verificationModalRequest.workerBarangay || "",
        streetAddress: verificationModalWorker?.streetAddress || verificationModalRequest.workerStreetAddress || "",
        skills: verificationModalWorker?.skills?.length ? verificationModalWorker.skills : verificationModalRequest.workerSkills || [],
        dailyRate: verificationModalWorker?.dailyRate ?? verificationModalRequest.workerDailyRate,
        yearsExperience:
          verificationModalWorker?.yearsExperience ?? verificationModalRequest.workerYearsExperience ?? 0,
      }
    : null;
  const openVerificationModal = (request) => {
    openVerificationRequest(request.id);
    setVerificationModalRequestId(request.id);
  };
  const closeVerificationModal = () => {
    setVerificationModalRequestId(null);
  };
  const approveVerificationRequest = (requestId) => {
    handleAdminApproveVerification(requestId);
    closeVerificationModal();
  };
  const rejectVerificationRequest = (requestId) => {
    handleAdminRejectVerification(requestId);
    closeVerificationModal();
  };
  return (
    <div className="app-shell">
      <main>
        <section className="worker-dashboard superadmin-dashboard">
          <div className="worker-layout">
            <DashboardSidebar
              brand="SuperAdmin Panel"
              items={tabs.map((tab) => ({
                ...tab,
                active: superAdminSection === tab.id,
                onClick: () => setSuperAdminSection(tab.id),
              }))}
              footerAction={{
                label: "Log Out",
                onClick: handleLogout,
              }}
            />
            <div className="worker-content">
              {superAdminSection === "analytics" && (
                <div className="profile-card mt-3">
                  <div className="profile-card-head">Enhanced Dashboard Analytics</div>
                  <div className="p-4">
                    {/* Metric Cards */}
                    <div className="row g-3 mb-4">
                      <div className="col-md-3">
                        <div className="card border-0 shadow-sm bg-success text-white">
                          <div className="card-body">
                            <h6 className="card-title text-white-50">Hiring Success Rate</h6>
                            <h2 className="mb-0">{dashboardMetrics.analytics?.enhancedAnalytics?.hiringSuccessRate || 0}%</h2>
                            <small>Applications → Hires</small>
                          </div>
                        </div>
                      </div>
                      <div className="col-md-3">
                        <div className="card border-0 shadow-sm bg-info text-white">
                          <div className="card-body">
                            <h6 className="card-title text-white-50">Job Match Rate</h6>
                            <h2 className="mb-0">{dashboardMetrics.analytics?.enhancedAnalytics?.jobMatchRate || 0}%</h2>
                            <small>Jobs Successfully Matched</small>
                          </div>
                        </div>
                      </div>
                      <div className="col-md-3">
                        <div className="card border-0 shadow-sm bg-warning text-white">
                          <div className="card-body">
                            <h6 className="card-title text-white-50">Hired Workers</h6>
                            <h2 className="mb-0">{dashboardMetrics.analytics?.enhancedAnalytics?.workerHiringStats?.hiredWorkers || 0}</h2>
                            <small>{dashboardMetrics.analytics?.enhancedAnalytics?.workerHiringStats?.hirePercentage || 0}% of total workers</small>
                          </div>
                        </div>
                      </div>
                      <div className="col-md-3">
                        <div className="card border-0 shadow-sm bg-primary text-white">
                          <div className="card-body">
                            <h6 className="card-title text-white-50">Repeat Hires</h6>
                            <h2 className="mb-0">{dashboardMetrics.analytics?.enhancedAnalytics?.workerHiringStats?.repeatHires || 0}</h2>
                            <small>Workers Hired Multiple Times</small>
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* Application Trends Chart */}
                    <div className="row g-3">
                      <div className="col-12">
                        <div className="card border-0 shadow-sm">
                          <div className="card-header bg-light fw-bold">Application Trends (Last 12 Months)</div>
                          <div className="card-body">
                            {(dashboardMetrics.analytics?.enhancedAnalytics?.applicationTrends || []).length > 0 ? (
                              <ResponsiveContainer width="100%" height={300}>
                                <LineChart data={dashboardMetrics.analytics.enhancedAnalytics.applicationTrends}>
                                  <CartesianGrid strokeDasharray="3 3" />
                                  <XAxis dataKey="month" />
                                  <YAxis />
                                  <Tooltip />
                                  <Line type="monotone" dataKey="applications" stroke="#4CAF50" strokeWidth={2} />
                                </LineChart>
                              </ResponsiveContainer>
                            ) : (
                              <p className="text-muted">No application data available</p>
                            )}
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* Service Type Breakdown */}
                    <div className="row g-3 mt-3">
                      <div className="col-lg-6">
                        <div className="card border-0 shadow-sm">
                          <div className="card-header bg-light fw-bold">Service Type Distribution</div>
                          <div className="card-body">
                            {(dashboardMetrics.analytics?.serviceAnalytics || []).length > 0 ? (
                              <ResponsiveContainer width="100%" height={300}>
                                <BarChart data={dashboardMetrics.analytics.serviceAnalytics}>
                                  <CartesianGrid strokeDasharray="3 3" />
                                  <XAxis dataKey="serviceType" angle={-45} textAnchor="end" height={100} />
                                  <YAxis />
                                  <Tooltip />
                                  <Bar dataKey="count" fill="#4CAF50" />
                                </BarChart>
                              </ResponsiveContainer>
                            ) : (
                              <p className="text-muted">No service data available</p>
                            )}
                          </div>
                        </div>
                      </div>

                      {/* Monthly Job Requests */}
                      <div className="col-lg-6">
                        <div className="card border-0 shadow-sm">
                          <div className="card-header bg-light fw-bold">Monthly Job Postings</div>
                          <div className="card-body">
                            {(dashboardMetrics.analytics?.monthlyJobRequests || []).length > 0 ? (
                              <ResponsiveContainer width="100%" height={300}>
                                <BarChart data={dashboardMetrics.analytics.monthlyJobRequests}>
                                  <CartesianGrid strokeDasharray="3 3" />
                                  <XAxis dataKey="month" />
                                  <YAxis />
                                  <Tooltip />
                                  <Bar dataKey="count" fill="#2196F3" />
                                </BarChart>
                              </ResponsiveContainer>
                            ) : (
                              <p className="text-muted">No monthly data available</p>
                            )}
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              )}
              {superAdminSection === "verification" && (
                <div className="profile-card mt-3">
                  <div className="profile-card-head d-flex justify-content-between align-items-center gap-3 flex-wrap">
                    <span>Worker Verification Queue</span>
                    <span className="small text-muted">{verificationRequests.length} total requests</span>
                  </div>
                  <div className="table-responsive">
                    <table className="table align-middle mb-0">
                      <thead>
                        <tr>
                          <th>Worker</th>
                          <th>Submitted</th>
                          <th>Submitted Files</th>
                          <th>Review Note</th>
                          <th>Status</th>
                        </tr>
                      </thead>
                      <tbody>
                        {verificationRequests.length > 0 ? (
                          verificationRequests.map((request) => (
                            <tr
                              className="verification-queue-row"
                              key={request.id}
                              role="button"
                              tabIndex={0}
                              onClick={() => openVerificationModal(request)}
                              onKeyDown={(event) => {
                                if (event.key === "Enter" || event.key === " ") {
                                  event.preventDefault();
                                  openVerificationModal(request);
                                }
                              }}
                            >
                              <td>
                                <strong>{request.workerName}</strong>
                                <br />
                                <span className="small text-muted">@{request.workerUsername}</span>
                              </td>
                              <td>{request.submittedAt || "Recently"}</td>
                              <td>
                                {[request.primaryIdName || "Primary ID", request.secondaryDocName || "Supporting Doc"]
                                  .filter(Boolean)
                                  .join(", ")}
                              </td>
                              <td>{request.reviewNote || request.notes || "No notes yet"}</td>
                              <td>{renderStatusBadge(request.status)}</td>
                            </tr>
                          ))
                        ) : (
                          <tr>
                            <td colSpan="5" className="text-center text-muted py-4">
                              No verification requests yet.
                            </td>
                          </tr>
                        )}
                      </tbody>
                    </table>
                  </div>
                  {verificationModalRequest && (
                    <div className="superadmin-verification-modal-backdrop" role="presentation" onClick={closeVerificationModal}>
                      <section
                        aria-modal="true"
                        className="superadmin-verification-modal"
                        role="dialog"
                        onClick={(event) => event.stopPropagation()}
                      >
                        <header className="superadmin-verification-modal-header">
                          <div className="superadmin-verification-identity">
                            <div className="superadmin-verification-avatar">
                              {String(verificationModalRequest.workerName || verificationModalRequest.workerUsername || "W")
                                .slice(0, 2)
                                .toUpperCase()}
                            </div>
                            <div>
                              <div className="superadmin-verification-profile-name">
                                <h3>{verificationModalRequest.workerName || "Worker"}</h3>
                                {renderStatusBadge(verificationModalRequest.status)}
                              </div>
                              <p>@{verificationModalRequest.workerUsername || "worker"}</p>
                            </div>
                          </div>
                          <p className="superadmin-verification-submitted">
                            <span>Submitted:</span> {verificationModalRequest.submittedAt || "Recently"}
                          </p>
                        </header>
                        <div className="superadmin-verification-modal-body">
                          <div className="superadmin-verification-worker-profile">
                            <h4>Worker Details</h4>
                            <div className="superadmin-verification-profile-facts">
                              <div>
                                <strong>Full Name</strong>
                                <span>
                                  {verificationModalWorkerDetails?.displayName || "Not available"}
                                </span>
                              </div>
                              <div>
                                <strong>Phone</strong>
                                <span>{verificationModalWorkerDetails?.phone || "Not set"}</span>
                              </div>
                              <div>
                                <strong>Email</strong>
                                <span>{verificationModalWorkerDetails?.email || "Not set"}</span>
                              </div>
                              <div>
                                <strong>Barangay</strong>
                                <span>{verificationModalWorkerDetails?.barangay || "Not set"}</span>
                              </div>
                              <div>
                                <strong>Address</strong>
                                <span>{verificationModalWorkerDetails?.streetAddress || "Not set"}</span>
                              </div>
                              <div>
                                <strong>Skills</strong>
                                <span>{(verificationModalWorkerDetails?.skills || []).join(", ") || "No skills listed"}</span>
                              </div>
                              <div>
                                <strong>Rate</strong>
                                <span>
                                  {verificationModalWorkerDetails?.dailyRate
                                    ? `${formatCurrency(verificationModalWorkerDetails.dailyRate)}/day`
                                    : "Not set"}
                                </span>
                              </div>
                              <div>
                                <strong>Experience</strong>
                                        <span>
                                          {Number(verificationModalWorkerDetails?.yearsExperience || 0)}{" "}
                                          {Number(verificationModalWorkerDetails?.yearsExperience || 0) === 1
                                            ? "year"
                                            : "years"}
                                        </span>
                              </div>
                              <div>
                                <strong>Worker Notes</strong>
                                <span>{verificationModalRequest.notes || "No notes submitted."}</span>
                              </div>
                              <div>
                                <strong>Admin Note</strong>
                                <span>{verificationModalRequest.reviewNote || "No admin note yet."}</span>
                              </div>
                            </div>
                          </div>
                          <div className="superadmin-verification-documents h-100">
                            <h4>Submitted Documents</h4>
                            {[
                              {
                                label: "Primary ID",
                                name: verificationModalRequest.primaryIdName,
                                preview: verificationModalRequest.primaryIdPreview,
                              },
                              {
                                label: "Supporting Document",
                                name: verificationModalRequest.secondaryDocName,
                                preview: verificationModalRequest.secondaryDocPreview,
                              },
                            ].map((documentItem) => (
                              <div className="superadmin-verification-document-item" key={documentItem.label}>
                                <p className="small text-muted mb-1">{documentItem.label}</p>
                                <p className="fw-semibold mb-2">{documentItem.name || "No file name"}</p>
                                {documentItem.preview ? (
                                  isImagePreviewUrl(documentItem.preview) ? (
                                    <button
                                      type="button"
                                      className="verification-document-preview"
                                      onClick={() => openFilePreview(documentItem.preview)}
                                    >
                                      <img src={documentItem.preview} alt={`${documentItem.label} preview`} />
                                    </button>
                                  ) : (
                                    <button
                                      type="button"
                                      className="btn btn-outline-secondary btn-sm superadmin-document-open"
                                      onClick={() => openFilePreview(documentItem.preview)}
                                    >
                                      Open Document
                                    </button>
                                  )
                                ) : (
                                  <p className="small text-muted mb-0">
                                    Preview file is not stored for this backend record.
                                  </p>
                                )}
                              </div>
                            ))}
                          </div>
                        </div>

                        <div className="superadmin-verification-modal-actions">
                          <p className="superadmin-verification-review-note">
                            Review the submitted documents before approving.
                          </p>
                          {!["Approved", "Rejected"].includes(verificationModalRequest.status) ? (
                            <>
                              <button
                                className="btn btn-outline-danger"
                                type="button"
                                onClick={() => rejectVerificationRequest(verificationModalRequest.id)}
                              >
                                Reject
                              </button>
                              <button
                                className="btn btn-success"
                                type="button"
                                onClick={() => approveVerificationRequest(verificationModalRequest.id)}
                              >
                                Approve
                              </button>
                            </>
                          ) : (
                            <button className="btn btn-primary" type="button" onClick={closeVerificationModal}>
                              Done
                            </button>
                          )}
                        </div>
                      </section>
                    </div>
                  )}
                </div>
              )}

              {superAdminSection === "analytics" && (
                <>
                  <div className="superadmin-analytics mt-3">
                    <section className="analytics-overview" aria-label="Analytics overview">
                      <div className="analytics-overview-head">
                        <div>
                          <span>Platform Analytics</span>
                          <h2>Operational snapshot</h2>
                        </div>
                        <p>
                          Monitor account growth, employment activity, verification status, and worker reputation.
                        </p>
                      </div>

                      <div className="analytics-overview-grid">
                        {analyticsOverviewGroups.map((group) => (
                          <article className="analytics-overview-panel" key={group.title}>
                            <div className="analytics-overview-panel-head">
                              <h3>{group.title}</h3>
                              <p>{group.note}</p>
                            </div>
                            <div className="analytics-overview-metrics">
                              {group.items.map((item) => (
                                <div
                                  className={`analytics-overview-metric ${
                                    item.wide ? "wide" : ""
                                  } ${item.tone ? `tone-${item.tone}` : ""}`}
                                  key={`${group.title}-${item.label}`}
                                >
                                  <span>{item.label}</span>
                                  <strong>{item.value}</strong>
                                </div>
                              ))}
                            </div>
                          </article>
                        ))}
                      </div>
                    </section>

                    <div className="profile-card analytics-card">
                      <div className="profile-card-head analytics-heatmap-head">
                        <span>Barangay Heat Map</span>
                        <div
                          className="btn-group btn-group-sm analytics-heatmap-tabs"
                          role="group"
                          aria-label="Heat map metric"
                        >
                          {heatMapOptions.map((option) => (
                            <button
                              key={option.id}
                              type="button"
                              className={`btn ${heatMapMetric === option.id ? "btn-primary" : "btn-outline-primary"}`}
                              onClick={() => setHeatMapMetric(option.id)}
                            >
                              {option.label}
                            </button>
                          ))}
                        </div>
                      </div>
                      <SuperAdminHeatMap
                        data={heatMapData}
                        metricLabel={selectedHeatMapOption.label}
                        mapCenter={PHILIPPINES_MAP_CENTER}
                        loadLeafletAssets={loadLeafletAssets}
                      />
                    </div>

                    <div className="row g-3 mt-1 analytics-chart-grid">
                      <div className="col-xl-6">
                        <div className="profile-card analytics-card h-100">
                          <div className="profile-card-head">Monthly Job Requests</div>
                          <div className="analytics-chart-wrap">
                            <ResponsiveContainer width="100%" height={280}>
                              <LineChart
                                data={monthlyJobRequests}
                                margin={{
                                  top: 16,
                                  right: 18,
                                  left: 0,
                                  bottom: 4,
                                }}
                              >
                                <CartesianGrid strokeDasharray="3 3" stroke="#d9e2ff" />
                                <XAxis
                                  dataKey="month"
                                  tick={{
                                    fill: "#5f6b7b",
                                    fontSize: 12,
                                  }}
                                />
                                <YAxis
                                  allowDecimals={false}
                                  tick={{
                                    fill: "#5f6b7b",
                                    fontSize: 12,
                                  }}
                                />
                                <Tooltip />
                                <Line
                                  type="monotone"
                                  dataKey="requests"
                                  stroke="#667eea"
                                  strokeWidth={3}
                                  dot={{
                                    r: 4,
                                  }}
                                  activeDot={{
                                    r: 6,
                                  }}
                                />
                              </LineChart>
                            </ResponsiveContainer>
                          </div>
                        </div>
                      </div>
                      <div className="col-xl-6">
                        <div className="profile-card analytics-card h-100">
                          <div className="profile-card-head">Most Requested Services</div>
                          <div className="analytics-chart-wrap">
                            <ResponsiveContainer width="100%" height={280}>
                              <BarChart
                                data={serviceAnalytics}
                                margin={{
                                  top: 16,
                                  right: 18,
                                  left: 0,
                                  bottom: 4,
                                }}
                              >
                                <CartesianGrid strokeDasharray="3 3" stroke="#d9e2ff" />
                                <XAxis
                                  dataKey="service"
                                  tick={{
                                    fill: "#5f6b7b",
                                    fontSize: 12,
                                  }}
                                />
                                <YAxis
                                  allowDecimals={false}
                                  tick={{
                                    fill: "#5f6b7b",
                                    fontSize: 12,
                                  }}
                                />
                                <Tooltip />
                                <Bar dataKey="requests" radius={[8, 8, 0, 0]}>
                                  {serviceAnalytics.map((entry, index) => (
                                    <Cell
                                      key={entry.service}
                                      fill={ANALYTICS_CHART_COLORS[index % ANALYTICS_CHART_COLORS.length]}
                                    />
                                  ))}
                                </Bar>
                              </BarChart>
                            </ResponsiveContainer>
                          </div>
                        </div>
                      </div>
                    </div>

                    <div className="profile-card analytics-card analytics-geographic-card mt-3">
                      <div className="profile-card-head analytics-section-title">Geographic Analytics</div>
                      <div className="row g-3">
                      <div className="col-xl-6">
                        <div className="analytics-subcard h-100">
                          <div className="profile-card-head">Barangays with High Job Demand</div>
                          <div className="table-responsive">
                            <table className="table align-middle mb-0 analytics-table">
                              <thead>
                                <tr>
                                  <th>Barangay</th>
                                  <th>Job Requests</th>
                                  <th>Demand</th>
                                </tr>
                              </thead>
                              <tbody>
                                {barangayJobAnalytics.length > 0 ? (
                                  barangayJobAnalytics.map((item) => (
                                    <tr key={item.barangay}>
                                      <td>{item.barangay}</td>
                                      <td>{item.jobs}</td>
                                      <td>
                                        <div className="analytics-meter">
                                          <span
                                            style={{
                                              width: `${Math.max(8, (item.jobs / Math.max(...barangayJobAnalytics.map((row) => row.jobs), 1)) * 100)}%`,
                                            }}
                                          />
                                        </div>
                                      </td>
                                    </tr>
                                  ))
                                ) : (
                                  <tr>
                                    <td colSpan="3" className="text-center text-muted py-4">
                                      No barangay job data yet.
                                    </td>
                                  </tr>
                                )}
                              </tbody>
                            </table>
                          </div>
                        </div>
                      </div>
                      <div className="col-xl-6">
                        <div className="analytics-subcard h-100">
                          <div className="profile-card-head">Barangays with Worker Availability</div>
                          <div className="table-responsive">
                            <table className="table align-middle mb-0 analytics-table">
                              <thead>
                                <tr>
                                  <th>Barangay</th>
                                  <th>Workers</th>
                                  <th>Availability</th>
                                </tr>
                              </thead>
                              <tbody>
                                {barangayWorkerAnalytics.length > 0 ? (
                                  barangayWorkerAnalytics.map((item) => (
                                    <tr key={item.barangay}>
                                      <td>{item.barangay}</td>
                                      <td>{item.workers}</td>
                                      <td>
                                        <div className="analytics-meter availability">
                                          <span
                                            style={{
                                              width: `${Math.max(8, (item.workers / Math.max(...barangayWorkerAnalytics.map((row) => row.workers), 1)) * 100)}%`,
                                            }}
                                          />
                                        </div>
                                      </td>
                                    </tr>
                                  ))
                                ) : (
                                  <tr>
                                    <td colSpan="3" className="text-center text-muted py-4">
                                      No barangay worker data yet.
                                    </td>
                                  </tr>
                                )}
                              </tbody>
                            </table>
                          </div>
                        </div>
                      </div>
                      </div>
                    </div>

                    <div className="row g-3 mt-1">
                      <div className="col-xl-4">
                        <div className="profile-card analytics-card h-100">
                          <div className="profile-card-head">Average Worker Rating</div>
                          <div className="analytics-rating-summary">
                            <p className="analytics-rating-value mb-1">{averageWorkerRating}</p>
                            <p className="small text-muted mb-0">{ratedWorkerCount} rated worker profile(s)</p>
                          </div>
                        </div>
                      </div>
                      <div className="col-xl-4">
                        <div className="profile-card analytics-card h-100">
                          <div className="profile-card-head">Rating Distribution</div>
                          <div className="analytics-chart-wrap compact">
                            <ResponsiveContainer width="100%" height={230}>
                              <BarChart
                                data={ratingDistribution}
                                margin={{
                                  top: 16,
                                  right: 18,
                                  left: 0,
                                  bottom: 4,
                                }}
                              >
                                <CartesianGrid strokeDasharray="3 3" stroke="#d9e2ff" />
                                <XAxis
                                  dataKey="stars"
                                  tick={{
                                    fill: "#5f6b7b",
                                    fontSize: 12,
                                  }}
                                />
                                <YAxis
                                  allowDecimals={false}
                                  tick={{
                                    fill: "#5f6b7b",
                                    fontSize: 12,
                                  }}
                                />
                                <Tooltip />
                                <Bar dataKey="count" fill="#ffc107" radius={[8, 8, 0, 0]} />
                              </BarChart>
                            </ResponsiveContainer>
                          </div>
                        </div>
                      </div>
                      <div className="col-xl-4">
                        <div className="profile-card analytics-card h-100">
                          <div className="profile-card-head">Average Rates by Category</div>
                          <div className="table-responsive">
                            <table className="table align-middle mb-0 analytics-table">
                              <thead>
                                <tr>
                                  <th>Category</th>
                                  <th>Posts</th>
                                  <th>Average Rate</th>
                                </tr>
                              </thead>
                              <tbody>
                                {jobCategories.length > 0 ? (
                                  jobCategories.map((item) => (
                                    <tr key={item.skill}>
                                      <td>{item.skill}</td>
                                      <td>{item.count}</td>
                                      <td>{formatCurrency(item.averageRate)}</td>
                                    </tr>
                                  ))
                                ) : (
                                  <tr>
                                    <td colSpan="3" className="text-center text-muted py-4">
                                      No rate data yet.
                                    </td>
                                  </tr>
                                )}
                              </tbody>
                            </table>
                          </div>
                        </div>
                      </div>
                    </div>

                    <div className="profile-card analytics-card analytics-pricing-card mt-3">
                      <div className="profile-card-head">Pricing Trends</div>
                      <div className="analytics-chart-wrap">
                        <ResponsiveContainer width="100%" height={260}>
                          <LineChart
                            data={pricingTrends}
                            margin={{
                              top: 16,
                              right: 18,
                              left: 0,
                              bottom: 4,
                            }}
                          >
                            <CartesianGrid strokeDasharray="3 3" stroke="#d9e2ff" />
                            <XAxis
                              dataKey="month"
                              tick={{
                                fill: "#5f6b7b",
                                fontSize: 12,
                              }}
                            />
                            <YAxis
                              tick={{
                                fill: "#5f6b7b",
                                fontSize: 12,
                              }}
                              tickFormatter={(value) => formatCurrency(value)}
                            />
                            <Tooltip
                              formatter={(value, name) => [
                                name === "averageRate" ? formatCurrency(value) : value,
                                name === "averageRate" ? "Average Rate" : "Postings",
                              ]}
                            />
                            <Line
                              type="monotone"
                              dataKey="averageRate"
                              stroke="#28a745"
                              strokeWidth={3}
                              dot={{
                                r: 4,
                              }}
                              activeDot={{
                                r: 6,
                              }}
                            />
                          </LineChart>
                        </ResponsiveContainer>
                      </div>
                    </div>
                  </div>
                </>
              )}

              {superAdminSection === "adminmgmt" && (
                <div className="profile-card mt-3">
                  <div className="profile-card-head d-flex justify-content-between align-items-center gap-3 flex-wrap">
                    <span>Registered Admins</span>
                    <button className="btn btn-primary btn-sm" type="button">
                      Add Admin
                    </button>
                  </div>
                  <div className="table-responsive">
                    <table className="table align-middle mb-0">
                      <thead>
                        <tr>
                          <th>Admin Name</th>
                          <th>Username</th>
                          <th>Role</th>
                          <th>Status</th>
                          <th>Action</th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr>
                          <td>
                            <strong>Super Admin</strong>
                          </td>
                          <td>superadmin</td>
                          <td>Full System Control</td>
                          <td>
                            <span className="badge text-bg-dark">Owner</span>
                          </td>
                          <td>
                            <button className="btn btn-outline-secondary btn-sm" type="button">
                              Manage
                            </button>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                </div>
              )}

              {superAdminSection === "audit" && (
                <div className="profile-card mt-3">
                  <div className="profile-card-head">Audit Logs</div>
                  <div className="table-responsive">
                    <table className="table align-middle mb-0">
                      <thead>
                        <tr>
                          <th>Timestamp</th>
                          <th>Admin</th>
                          <th>Action</th>
                          <th>Target</th>
                          <th>Status</th>
                        </tr>
                      </thead>
                      <tbody>
                        {recentAuditLogs.map((log) => (
                          <tr key={log.id}>
                            <td>{log.timestamp}</td>
                            <td>{log.admin}</td>
                            <td>{log.action}</td>
                            <td>{log.target}</td>
                            <td>{renderStatusBadge(log.status)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
