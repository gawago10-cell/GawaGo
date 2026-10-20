import React, { useEffect, useState } from "react";
import ComplaintModal from "./ComplaintModal";
import { DashboardSidebar, DashboardTopbar } from "./DashboardLayout";
import JobImageGallery from "./JobImageGallery";
import LocationDistanceMap from "./LocationDistanceMap";
import {
  formatDateTime,
  formatDistance,
  formatLocation,
  formatRate,
  getDisplayName,
  getHouseholdPhoto,
} from "../utils/formatters";
import { getVerificationNavLabel } from "../utils/normalizers";
import {
  getApplicationStatusLabel,
  getHiringProgressLabel,
  getJobStatusBadgeClass,
  getJobStatusText,
} from "../utils/jobUtils";

export default function WorkerJobDetailView({
  currentWorker,
  currentWorkerJobDetail,
  currentWorkerJobHousehold,
  handleApplyToJob,
  handleLogout,
  handleWorkerHireDecision,
  handleWorkerRequestCompletion,
  openWorkerApplications,
  openWorkerDashboard,
  openWorkerFindJobs,
  openWorkerGetVerified,
  openWorkerMyJobs,
  openMyComplaints,
  openWorkerNotifications,
  openWorkerProfile,
  workerApplicationUnreadCount,
  addToast,
}) {
  const job = currentWorkerJobDetail;
  const household = currentWorkerJobHousehold;
  const householdName = getDisplayName(
    household?.firstName,
    household?.lastName,
    job?.householdName || job?.householdUsername || "Household",
  );
  const householdPhoto = getHouseholdPhoto(household);
  const currentWorkerApplication = job?.currentWorkerApplication || null;
  const alreadyApplied = Boolean(currentWorkerApplication);
  const jobLatitude = job?.latitude ?? household?.latitude ?? null;
  const jobLongitude = job?.longitude ?? household?.longitude ?? null;
  const workerLatitude = currentWorker?.latitude ?? null;
  const workerLongitude = currentWorker?.longitude ?? null;
  const jobDistanceKm = job?.routeDistanceKm ?? null;
  const [routeDistanceKm, setRouteDistanceKm] = useState(null);
  const [completionNote, setCompletionNote] = useState("I have completed the service today.");
  // Prefer the backend's own wording, but only while showing the job's own
  // distance -- once a fresher live route comes back (routeDistanceKm),
  // format that value instead rather than showing a label computed from a
  // now-stale number.
  const distanceLabel =
    routeDistanceKm === null && job?.distanceLabel
      ? job.distanceLabel
      : formatDistance(routeDistanceKm ?? jobDistanceKm);
  const currentWorkerApplicationStatus = job?.applicationStatus || currentWorkerApplication?.status || "";
  const currentWorkerApplicationId = job?.applicationId || currentWorkerApplication?.id || null;
  const hasRejectedHireRequest = currentWorkerApplicationStatus === "Rejected";
  const isAssignedWorker = ["Hired", "Completed"].includes(currentWorkerApplicationStatus);
  const verificationNavLabel = getVerificationNavLabel(currentWorker);
  const isCompletionRequested = job?.status === "Waiting for Household Confirmation";
  const isCompletedJob = job?.status === "Completed";
  const canApply = Boolean(job?.canApply);
  const canAcceptHireRequest = Boolean(job?.canAcceptHireRequest);
  const canRequestCompletion = Boolean(job?.canRequestCompletion);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [showComplaintModal, setShowComplaintModal] = useState(false);
  useEffect(() => {
    setRouteDistanceKm(null);
  }, [job?.id, currentWorker?.id, currentWorker?.username]);
  useEffect(() => {
    document.body.classList.toggle("gawago-mobile-menu-open", mobileMenuOpen);
    return () => document.body.classList.remove("gawago-mobile-menu-open");
  }, [mobileMenuOpen]);
  useEffect(() => {
    if (!mobileMenuOpen) return undefined;
    const closeOnNavigate = (event) => {
      if (event.target.closest(".worker-nav-item, .worker-sidebar-logout")) {
        setMobileMenuOpen(false);
      }
    };
    document.addEventListener("click", closeOnNavigate);
    return () => document.removeEventListener("click", closeOnNavigate);
  }, [mobileMenuOpen]);
  return (
    <div className="app-shell">
      <div className="mobile-sidebar-overlay" onClick={() => setMobileMenuOpen(false)} />
      <header className="mobile-dashboard-topbar">
        <button
          type="button"
          className={`mobile-burger-button ${mobileMenuOpen ? "open" : ""}`}
          aria-label="Toggle navigation"
          aria-expanded={mobileMenuOpen}
          onClick={() => setMobileMenuOpen((open) => !open)}
        >
          <span />
          <span />
          <span />
        </button>
        <span className="mobile-dashboard-title">GawaGo</span>
      </header>
      <main>
        <section className="worker-dashboard worker-job-detail-page">
          <div className="worker-layout">
            <DashboardSidebar
              items={[
                {
                  id: "dashboard",
                  label: "Dashboard",
                  onClick: openWorkerDashboard,
                },
                {
                  id: "find-jobs",
                  label: "Find Jobs",
                  active: true,
                  onClick: openWorkerFindJobs,
                },
                {
                  id: "profile",
                  label: "My Profile",
                  onClick: openWorkerProfile,
                },
                {
                  id: "applications",
                  label: "My Applications",
                  count: workerApplicationUnreadCount,
                  onClick: openWorkerApplications,
                },
                {
                  id: "jobs",
                  label: "My Jobs",
                  onClick: openWorkerMyJobs,
                },
                {
                  id: "flag",
                  label: "My Reports",
                  onClick: openMyComplaints,
                },
                {
                  id: "verified",
                  label: verificationNavLabel,
                  section: "Account",
                  onClick: openWorkerGetVerified,
                },
                {
                  id: "notifications",
                  label: "Notifications",
                  onClick: openWorkerNotifications,
                },
              ]}
              footerAction={{
                label: "Log Out",
                onClick: handleLogout,
              }}
            />
            <div className="worker-content">
              <DashboardTopbar title="Job Details" />
              {!job ? (
                <div className="profile-card mt-3">
                  <div className="profile-card-head">Job not found</div>
                  <div className="p-3">
                    <p className="mb-3 text-muted">This job is no longer available or could not be loaded.</p>
                    <button className="btn btn-primary" type="button" onClick={openWorkerFindJobs}>
                      Back to Find Jobs
                    </button>
                  </div>
                </div>
              ) : (
                <div className="worker-job-detail-shell">
                  <div className="worker-job-detail-main">
                    <div className="profile-card worker-job-household-card" data-household-profile-preview="true">
                      <div className="profile-card-head">Household Profile</div>
                      <div className="worker-job-household-body">
                        {householdPhoto ? (
                          <img src={householdPhoto} alt={`${householdName} profile`} className="household-profile-photo" />
                        ) : (
                          <div className="household-profile-fallback">
                            {(householdName || "H").slice(0, 1).toUpperCase()}
                          </div>
                        )}
                        <div>
                          <p className="mb-1 fw-semibold">{householdName}</p>
                          <p className="mb-1 small text-muted">
                            {formatLocation(household?.barangay || job.barangay, household?.streetAddress || job.streetAddress)}
                          </p>
                          <p className="mb-0 small text-muted">
                            {isAssignedWorker
                              ? [job?.householdPhone ? `+63${job.householdPhone}` : "", job?.householdEmail || ""]
                                  .filter(Boolean)
                                  .join(" | ") || "Contact details not provided"
                              : "Contact details become available after you are hired."}
                          </p>
                        </div>
                      </div>
                    </div>

                    <div className="profile-card worker-job-info-card">
                      <div className="profile-card-head d-flex justify-content-between align-items-center gap-3">
                        <span>{job.jobTitle || job.serviceType}</span>
                        <span className={`badge ${getJobStatusBadgeClass(job.status)}`}>{getJobStatusText(job)}</span>
                      </div>
                      <div className="worker-job-info-body">
                        <dl className="worker-job-detail-list">
                          <div>
                            <dt>Service</dt>
                            <dd>{job.serviceType || "Not set"}</dd>
                          </div>
                          <div>
                            <dt>Schedule</dt>
                            <dd>{job.scheduleType || "Not set"}</dd>
                          </div>
                          {(job.jobStartDate || job.jobEndDate) && (
                            <div>
                              <dt>Job Period</dt>
                              <dd>
                                {job.jobStartDate || "Not set"}
                                {job.jobEndDate ? ` to ${job.jobEndDate}` : ""}
                              </dd>
                            </div>
                          )}
                          {job.estimatedWorkingDays ? (
                            <div>
                              <dt>Working Days</dt>
                              <dd>
                                {job.estimatedWorkingDays} day
                                {Number(job.estimatedWorkingDays) === 1 ? "" : "s"}
                              </dd>
                            </div>
                          ) : null}
                          <div>
                            <dt>Needed</dt>
                            <dd>{getHiringProgressLabel(job)} hired</dd>
                          </div>
                          <div>
                            <dt>Rate</dt>
                            <dd>{formatRate(job.offeredRate, job.rateType)}</dd>
                          </div>
                          <div>
                            <dt>Location</dt>
                            <dd>{formatLocation(household?.barangay || job.barangay, household?.streetAddress || job.streetAddress)}</dd>
                          </div>
                        </dl>
                        <div className="worker-job-description">
                          <p className="small text-muted fw-semibold mb-1">Description</p>
                          <p className="mb-0">{job.description || "No description provided."}</p>
                        </div>
                        {isAssignedWorker && (
                          <div className="worker-completion-request-card">
                            <div>
                              <p className="small text-muted fw-semibold mb-1">Completion Request</p>
                              <p className="mb-0">
                                {isCompletionRequested
                                  ? "Completion request sent. The household has been notified to confirm the service."
                                  : isCompletedJob
                                    ? "This job is already completed."
                                    : "When the service is done, notify the household so they can confirm completion."}
                              </p>
                            </div>
                            {!isCompletionRequested && !isCompletedJob && (
                              <>
                                <label className="form-label fw-semibold" htmlFor="worker-completion-note">
                                  Completion note
                                </label>
                                <textarea
                                  className="form-control"
                                  id="worker-completion-note"
                                  rows="3"
                                  value={completionNote}
                                  onChange={(event) => setCompletionNote(event.target.value)}
                                />
                              </>
                            )}
                            <button
                              className="btn btn-success btn-sm"
                              type="button"
                              disabled={!canRequestCompletion}
                              onClick={() => handleWorkerRequestCompletion(job.id, completionNote)}
                            >
                              {isCompletionRequested
                                ? "Waiting for Household Confirmation"
                                : isCompletedJob
                                  ? "Job Completed"
                                  : "Request Completion"}
                            </button>
                          </div>
                        )}
                        <div className="worker-job-actions">
                          <button
                            className="btn btn-outline-secondary btn-sm"
                            type="button"
                            onClick={canAcceptHireRequest ? openWorkerNotifications : openWorkerFindJobs}
                          >
                            {canAcceptHireRequest ? "Back to Notifications" : "Back to Find Jobs"}
                          </button>
                          {canAcceptHireRequest ? (
                            <>
                              <button
                                className="btn btn-success btn-sm"
                                type="button"
                                disabled={!currentWorkerApplicationId}
                                onClick={() => handleWorkerHireDecision(currentWorkerApplicationId, "accept")}
                              >
                                Accept Request
                              </button>
                              <button
                                className="btn btn-outline-danger btn-sm"
                                type="button"
                                disabled={!currentWorkerApplicationId}
                                onClick={() => {
                                  if (window.confirm("Reject this hire request? This can't be undone.")) {
                                    handleWorkerHireDecision(currentWorkerApplicationId, "reject");
                                  }
                                }}
                              >
                                Reject Request
                              </button>
                            </>
                          ) : (
                            <button
                              className="btn btn-primary btn-sm"
                              type="button"
                              disabled={!canApply}
                              onClick={() => handleApplyToJob(job.id)}
                            >
                              {alreadyApplied
                                ? hasRejectedHireRequest
                                  ? "Request Rejected"
                                  : "Already Applied"
                                : "Apply Now"}
                            </button>
                          )}
                        </div>
                        {canAcceptHireRequest && (
                          <div className="alert alert-info mt-3 mb-0 py-2">
                            This household sent you a hire request. Review the job details before accepting or rejecting.
                          </div>
                        )}
                        {!canApply && !alreadyApplied && !canAcceptHireRequest && (
                          <div className="alert alert-warning mt-3 mb-0 py-2">
                            Applications are unavailable for this job right now.
                          </div>
                        )}
                        {alreadyApplied && (
                          <div style={{ marginTop: "1rem", paddingTop: "1rem", borderTop: "1px solid #e0e0e0" }}>
                            <button
                              type="button"
                              className="btn btn-outline-danger btn-sm"
                              onClick={() => setShowComplaintModal(true)}
                            >
                              🚩 Report an Issue
                            </button>
                          </div>
                        )}
                      </div>
                    </div>
                  </div>

                  <div className="profile-card worker-job-map-card" data-worker-job-distance-map="true">
                    <div className="profile-card-head d-flex justify-content-between align-items-center gap-3">
                      <span>Distance & Locations</span>
                      <span className="badge text-bg-light">{distanceLabel}</span>
                    </div>
                    <div className="worker-job-map-body">
                      <LocationDistanceMap
                        userLatitude={workerLatitude}
                        userLongitude={workerLongitude}
                        targetLatitude={jobLatitude}
                        targetLongitude={jobLongitude}
                        userLocation={formatLocation(currentWorker?.barangay, currentWorker?.streetAddress)}
                        targetLocation={formatLocation(
                          household?.barangay || job.barangay,
                          household?.streetAddress || job.streetAddress,
                        )}
                        userMarkerType="worker"
                        targetMarkerType="household"
                        distanceKm={jobDistanceKm}
                        routePoints={job.routePoints || []}
                        formatDistanceFn={formatDistance}
                        onRouteDistanceChange={setRouteDistanceKm}
                      />
                    </div>
                  </div>

                  <div className="profile-card worker-job-photos-card">
                    <div className="profile-card-head">Photos of Work Area</div>
                    <div className="worker-job-photos-body">
                      <p className="small text-muted mb-3">These photos help workers see the area before applying.</p>
                      <JobImageGallery images={job.images || []} />
                    </div>
                  </div>
                </div>
              )}
              {job && showComplaintModal && (
                <ComplaintModal
                  isOpen={showComplaintModal}
                  onClose={() => setShowComplaintModal(false)}
                  onSubmitted={() => addToast?.("Report submitted. Our admin team will review it.", "success")}
                  job={job}
                  role="worker"
                />
              )}
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}
