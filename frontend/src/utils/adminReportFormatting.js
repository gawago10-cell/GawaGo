// Shared formatting/status-tone helpers between the admin Reports page
// (Posted Jobs / Worker Applications) and the Complaints queue's
// per-user profile & history panel, so IDs and status colors stay
// consistent wherever a job or application shows up in the admin UI.

export const JOB_STATUS_TONE = {
  Open: "review",
  "Already found a worker": "submitted",
  "Waiting for Household Confirmation": "submitted",
  Completed: "resolved",
  Cancelled: "closed",
};

export const APPLICATION_STATUS_TONE = {
  Pending: "submitted",
  "Hire Request": "submitted",
  Hired: "resolved",
  Completed: "resolved",
  Rejected: "closed",
  Closed: "closed",
};

export function jobCode(id) {
  return `JOB-${String(id).padStart(3, "0")}`;
}

export function appCode(id) {
  return `APP-${String(id).padStart(3, "0")}`;
}

export function formatMoney(amount) {
  const value = Number(amount) || 0;
  return `₱${value.toLocaleString("en-PH", { minimumFractionDigits: 0 })}`;
}
