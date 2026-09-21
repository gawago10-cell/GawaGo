import React, { useMemo, useState } from "react";

import { setUserAccountBlocked } from "../services/backendDataService";
import { formatCurrency, getDisplayName } from "../utils/formatters";
import AdminUserHistorySection from "./AdminUserHistorySection";

const STATUS_FILTERS = [
  { value: "all", label: "All" },
  { value: "active", label: "Active" },
  { value: "suspended", label: "Suspended" },
  { value: "pending", label: "Pending" },
];

const STATUS_LABEL = {
  active: "Active",
  suspended: "Suspended",
  pending: "Pending",
};

function accountStatus(user) {
  if (user.isBlocked) return "suspended";
  if (user.verification === "Under Review") return "pending";
  return "active";
}

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function initials(name) {
  const parts = (name || "").trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

/**
 * Superadmin-wide directory of every household and worker account, with the
 * suspend/restore action already built for the complaint-review queue
 * (AdminComplaintsQueue.jsx) surfaced here as a general-purpose tool instead
 * of only being reachable from a specific report.
 */
export default function UserManagementView({
  currentUser,
  registeredHouseholds,
  registeredWorkers,
  postedJobs,
  refreshProfilesFromBackend,
}) {
  const [tab, setTab] = useState("households");
  const [statusFilter, setStatusFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [selectedUsername, setSelectedUsername] = useState(null);
  const [savingUsername, setSavingUsername] = useState(null);

  const jobsByHouseholdUsername = useMemo(() => {
    const map = new Map();
    (postedJobs || []).forEach((job) => {
      const key = job.householdUsername?.toLowerCase();
      if (!key) return;
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(job);
    });
    return map;
  }, [postedJobs]);

  const applicationsByWorkerUsername = useMemo(() => {
    const map = new Map();
    (postedJobs || []).forEach((job) => {
      (job.applications || []).forEach((application) => {
        const key = application.workerUsername?.toLowerCase();
        if (!key) return;
        if (!map.has(key)) map.set(key, []);
        map.get(key).push(application);
      });
    });
    return map;
  }, [postedJobs]);

  const householdRows = useMemo(
    () =>
      (registeredHouseholds || [])
        .filter((household) => !household.isStaff)
        .map((household) => {
          const jobs = jobsByHouseholdUsername.get(household.username?.toLowerCase()) || [];
          const completedJobs = jobs.filter((job) => job.status === "Completed");
          const totalSpent = completedJobs.reduce((sum, job) => sum + (Number(job.offeredRate) || 0), 0);
          return {
            ...household,
            jobsPosted: jobs.length,
            jobsCompleted: completedJobs.length,
            totalSpent,
            status: accountStatus(household),
          };
        }),
    [registeredHouseholds, jobsByHouseholdUsername],
  );

  const workerRows = useMemo(
    () =>
      (registeredWorkers || [])
        .filter((worker) => !worker.isStaff)
        .map((worker) => {
          const applications = applicationsByWorkerUsername.get(worker.username?.toLowerCase()) || [];
          const completedJobs = applications.filter((application) => application.status === "Completed");
          return {
            ...worker,
            jobsCompleted: completedJobs.length,
            status: accountStatus(worker),
          };
        }),
    [registeredWorkers, applicationsByWorkerUsername],
  );

  const stats = useMemo(() => {
    const everyone = [...householdRows, ...workerRows];
    return {
      totalHouseholds: householdRows.length,
      totalWorkers: workerRows.length,
      active: everyone.filter((user) => user.status === "active").length,
      suspended: everyone.filter((user) => user.status === "suspended").length,
    };
  }, [householdRows, workerRows]);

  const isHouseholds = tab === "households";
  const activeRows = isHouseholds ? householdRows : workerRows;

  const chipCounts = useMemo(
    () => ({
      all: activeRows.length,
      active: activeRows.filter((user) => user.status === "active").length,
      suspended: activeRows.filter((user) => user.status === "suspended").length,
      pending: activeRows.filter((user) => user.status === "pending").length,
    }),
    [activeRows],
  );

  const searchTerm = search.trim().toLowerCase();
  const visibleRows = activeRows.filter((user) => {
    if (statusFilter !== "all" && user.status !== statusFilter) {
      return false;
    }
    if (!searchTerm) {
      return true;
    }
    const name = getDisplayName(user.firstName, user.lastName, user.username).toLowerCase();
    return (
      name.includes(searchTerm) ||
      (user.username || "").toLowerCase().includes(searchTerm) ||
      (user.email || "").toLowerCase().includes(searchTerm)
    );
  });

  const selectedHousehold = householdRows.find((user) => user.username === selectedUsername) || null;
  const selectedWorker = workerRows.find((user) => user.username === selectedUsername) || null;
  const selectedUser = selectedHousehold || selectedWorker;
  const selectedUserRole = selectedHousehold ? "household" : "worker";

  async function suspend(user, durationDays) {
    const durationLabel = durationDays ? `for ${durationDays} days` : "permanently";
    const confirmed = window.confirm(
      `Suspend ${user.username} ${durationLabel}? They will be signed out immediately and cannot log back in until restored.`,
    );
    if (!confirmed) return;
    const reason = window.prompt("Reason for suspending (shown to the user):", "");
    if (reason === null) return;

    setSavingUsername(user.username);
    try {
      await setUserAccountBlocked(user.username, { blocked: true, reason: reason || "", durationDays });
      await refreshProfilesFromBackend();
    } catch (error) {
      window.alert(error.message || "Unable to update this account.");
    } finally {
      setSavingUsername(null);
    }
  }

  async function restore(user) {
    setSavingUsername(user.username);
    try {
      await setUserAccountBlocked(user.username, { blocked: false });
      await refreshProfilesFromBackend();
    } catch (error) {
      window.alert(error.message || "Unable to update this account.");
    } finally {
      setSavingUsername(null);
    }
  }

  return (
    <div className="admin-users-page">
      <div className="admin-reports-header">
        <div>
          <h2>User Management</h2>
          <p>View and manage all registered households and workers on the platform.</p>
        </div>
      </div>

      <div className="admin-users-stats">
        <div className="admin-users-stat blue">
          <div className="admin-users-stat-head">
            <span>Total Households</span>
            <span aria-hidden="true">🏠</span>
          </div>
          <strong>{stats.totalHouseholds}</strong>
        </div>
        <div className="admin-users-stat green">
          <div className="admin-users-stat-head">
            <span>Total Workers</span>
            <span aria-hidden="true">🧰</span>
          </div>
          <strong>{stats.totalWorkers}</strong>
        </div>
        <div className="admin-users-stat mint">
          <div className="admin-users-stat-head">
            <span>Active Users</span>
            <span aria-hidden="true">✓</span>
          </div>
          <strong>{stats.active}</strong>
        </div>
        <div className="admin-users-stat red">
          <div className="admin-users-stat-head">
            <span>Suspended</span>
            <span aria-hidden="true">⊘</span>
          </div>
          <strong>{stats.suspended}</strong>
        </div>
      </div>

      <div className="admin-credentials-toolbar">
        <div className="household-history-tabs mb-0">
          <button
            type="button"
            className={`household-history-tab ${isHouseholds ? "active" : ""}`}
            onClick={() => setTab("households")}
          >
            Households <span className="household-history-tab-count">{householdRows.length}</span>
          </button>
          <button
            type="button"
            className={`household-history-tab ${isHouseholds ? "" : "active"}`}
            onClick={() => setTab("workers")}
          >
            Workers <span className="household-history-tab-count">{workerRows.length}</span>
          </button>
        </div>
        <input
          type="search"
          className="admin-credentials-search"
          placeholder="Search by name or email…"
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

      {visibleRows.length === 0 ? (
        <div className="admin-reports-empty">No {isHouseholds ? "households" : "workers"} match this filter.</div>
      ) : (
        <div className="admin-reports-table-card">
          <div className="table-responsive">
            <table className="admin-reports-table">
              <thead>
                <tr>
                  <th>User</th>
                  <th>Location</th>
                  <th>Stats</th>
                  <th>Joined</th>
                  <th>Status</th>
                  <th aria-hidden="true"></th>
                </tr>
              </thead>
              <tbody>
                {visibleRows.map((user) => (
                  <tr key={user.username} onClick={() => setSelectedUsername(user.username)}>
                    <td>
                      <div className="admin-report-party-cell">
                        <span className="admin-report-party-avatar">
                          {initials(getDisplayName(user.firstName, user.lastName, user.username))}
                        </span>
                        <div>
                          <div className="fw-semibold">{user.username}</div>
                          <div className="small text-muted">{user.email || "No email on file"}</div>
                        </div>
                      </div>
                    </td>
                    <td className="text-muted">
                      {[user.barangay, user.streetAddress].filter(Boolean).join(", ") || "—"}
                    </td>
                    <td className="text-muted">
                      {isHouseholds ? (
                        <>
                          {user.jobsCompleted} jobs completed
                          <br />
                          {formatCurrency(user.totalSpent)} spent
                        </>
                      ) : (
                        <>
                          {user.jobsCompleted} jobs completed
                          <br />
                          {user.rating}
                        </>
                      )}
                    </td>
                    <td className="text-muted">{formatDate(user.memberSince)}</td>
                    <td>
                      <span className={`admin-user-status-badge ${user.status}`}>{STATUS_LABEL[user.status]}</span>
                    </td>
                    <td className="admin-users-row-chevron text-muted" aria-hidden="true">
                      ›
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {selectedUser && (
        <div className="gg-modal-backdrop" role="presentation" onClick={() => setSelectedUsername(null)}>
          <div
            className="gg-modal-panel admin-user-modal"
            role="dialog"
            aria-modal="true"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="gg-modal-head admin-report-modal-head">
              <div className="d-flex align-items-center gap-3">
                <span className="admin-report-party-avatar admin-user-modal-avatar">
                  {initials(getDisplayName(selectedUser.firstName, selectedUser.lastName, selectedUser.username))}
                </span>
                <div>
                  <p className="gg-modal-kicker">
                    {selectedUserRole === "household" ? "Household" : "Worker"} Profile
                  </p>
                  <h2>{getDisplayName(selectedUser.firstName, selectedUser.lastName, selectedUser.username)}</h2>
                </div>
              </div>
              <div className="d-flex align-items-center gap-3">
                <span className={`admin-user-status-badge ${selectedUser.status}`}>
                  {STATUS_LABEL[selectedUser.status]}
                </span>
                <button
                  type="button"
                  className="gg-modal-close"
                  onClick={() => setSelectedUsername(null)}
                  aria-label="Close"
                >
                  ×
                </button>
              </div>
            </div>

            <div className="gg-modal-body admin-report-modal-body">
              <div className="admin-report-info-card">
                <p className="admin-report-info-kicker">Contact</p>
                <p className="mb-1">✉️ {selectedUser.email || "Not provided"}</p>
                <p className="mb-1">📞 {selectedUser.phone || "Not provided"}</p>
                <p className="mb-1">
                  📍 {[selectedUser.barangay, selectedUser.streetAddress].filter(Boolean).join(", ") || "Not set"}
                </p>
                <p className="mb-0">🗓️ Joined {formatDate(selectedUser.memberSince)}</p>
              </div>

              <div className="admin-report-info-card">
                <p className="admin-report-info-kicker">Activity</p>
                <div className="admin-users-activity-grid">
                  {selectedUserRole === "household" ? (
                    <>
                      <div>
                        <span>Jobs Posted</span>
                        <strong>{selectedUser.jobsPosted}</strong>
                      </div>
                      <div>
                        <span>Jobs Completed</span>
                        <strong>{selectedUser.jobsCompleted}</strong>
                      </div>
                      <div className="wide">
                        <span>Total Spent</span>
                        <strong>{formatCurrency(selectedUser.totalSpent)}</strong>
                      </div>
                    </>
                  ) : (
                    <>
                      <div>
                        <span>Jobs Completed</span>
                        <strong>{selectedUser.jobsCompleted}</strong>
                      </div>
                      <div>
                        <span>Rating</span>
                        <strong>{selectedUser.rating}</strong>
                      </div>
                      <div className="wide">
                        <span>Skills</span>
                        <strong>{(selectedUser.skills || []).join(", ") || "None listed"}</strong>
                      </div>
                    </>
                  )}
                </div>
              </div>

              <AdminUserHistorySection
                role={selectedUserRole}
                fullRecord={selectedUser}
                postedJobs={postedJobs}
                currentUser={currentUser}
              />

              <div className="admin-report-info-card">
                <p className="admin-report-info-kicker">Admin Actions</p>
                <div className="d-flex align-items-center gap-2 flex-wrap">
                  {selectedUser.isBlocked ? (
                    <>
                      <button
                        type="button"
                        className="btn btn-sm btn-outline-success"
                        disabled={savingUsername === selectedUser.username}
                        onClick={() => restore(selectedUser)}
                      >
                        Restore Account
                      </button>
                      <span className="badge text-bg-danger">
                        {selectedUser.blockedUntil
                          ? `Suspended until ${formatDate(selectedUser.blockedUntil)}`
                          : "Account blocked (permanent)"}
                      </span>
                    </>
                  ) : (
                    <>
                      <button
                        type="button"
                        className="btn btn-sm btn-outline-warning"
                        disabled={savingUsername === selectedUser.username}
                        onClick={() => suspend(selectedUser, 3)}
                      >
                        Suspend 3 Days
                      </button>
                      <button
                        type="button"
                        className="btn btn-sm btn-outline-warning"
                        disabled={savingUsername === selectedUser.username}
                        onClick={() => suspend(selectedUser, 7)}
                      >
                        Suspend 7 Days
                      </button>
                      <button
                        type="button"
                        className="btn btn-sm btn-outline-danger"
                        disabled={savingUsername === selectedUser.username}
                        onClick={() => suspend(selectedUser, null)}
                      >
                        Block Permanently
                      </button>
                    </>
                  )}
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
