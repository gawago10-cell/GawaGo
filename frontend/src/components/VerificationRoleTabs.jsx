import React from "react";

export const VERIFICATION_ROLE_TABS = [
  { value: "all", label: "All" },
  { value: "household", label: "Households" },
  { value: "worker", label: "Workers" },
];

// Both clients hold every page of the verification list (fetchAllRecords),
// so filtering here sees the whole queue, not just the first 20.
export function filterVerificationRequestsByRole(requests, role) {
  if (!role || role === "all") {
    return requests;
  }
  return requests.filter((request) => request.accountRole === role);
}

/** All / Households / Workers tabs above an admin verification queue. */
export default function VerificationRoleTabs({ requests, value, onChange }) {
  return (
    <div className="household-history-tabs verification-role-tabs" role="tablist" aria-label="Filter by account type">
      {VERIFICATION_ROLE_TABS.map((tab) => (
        <button
          key={tab.value}
          type="button"
          role="tab"
          aria-selected={value === tab.value}
          className={`household-history-tab ${value === tab.value ? "active" : ""}`}
          onClick={() => onChange(tab.value)}
        >
          {tab.label}{" "}
          <span className="household-history-tab-count">
            {filterVerificationRequestsByRole(requests, tab.value).length}
          </span>
        </button>
      ))}
    </div>
  );
}
