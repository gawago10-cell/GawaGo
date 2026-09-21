import React from "react";

export function SidebarIcon({ name, size = 18 }) {
  const commonProps = {
    className: "sidebar-mobile-icon",
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 2,
    strokeLinecap: "round",
    strokeLinejoin: "round",
    "aria-hidden": "true",
  };

  switch (name) {
    case "search":
    case "find-jobs":
      return (
        <svg {...commonProps}>
          <circle cx="11" cy="11" r="8" />
          <line x1="21" y1="21" x2="16.65" y2="16.65" />
        </svg>
      );
    case "profile":
      return (
        <svg {...commonProps}>
          <circle cx="12" cy="8" r="4" />
          <path d="M4 20c0-4 3.6-7 8-7s8 3 8 7" />
        </svg>
      );
    case "applications":
    case "jobs":
    case "post-job":
    case "history":
      return (
        <svg {...commonProps}>
          <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" />
          <polyline points="14 2 14 8 20 8" />
        </svg>
      );
    case "verified":
    case "verification":
      return (
        <svg {...commonProps}>
          <path d="M22 11.08V12a10 10 0 11-5.93-9.14" />
          <polyline points="22 4 12 14.01 9 11.01" />
        </svg>
      );
    case "notifications":
      return (
        <svg {...commonProps}>
          <path d="M18 8A6 6 0 006 8c0 7-3 9-3 9h18s-3-2-3-9" />
          <path d="M13.73 21a2 2 0 01-3.46 0" />
        </svg>
      );
    case "flag":
      return (
        <svg {...commonProps}>
          <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z" />
          <line x1="4" y1="22" x2="4" y2="15" />
        </svg>
      );
    case "logout":
      return (
        <svg {...commonProps} width={size - 2} height={size - 2}>
          <path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4" />
          <polyline points="16 17 21 12 16 7" />
          <line x1="21" y1="12" x2="9" y2="12" />
        </svg>
      );
    case "dashboard":
    default:
      return (
        <svg {...commonProps}>
          <rect x="3" y="3" width="7" height="7" />
          <rect x="14" y="3" width="7" height="7" />
          <rect x="14" y="14" width="7" height="7" />
          <rect x="3" y="14" width="7" height="7" />
        </svg>
      );
  }
}

export function DashboardSidebar({ brand = "GawaGo Community Platform", items = [], footerAction = null }) {
  return (
    <aside className="worker-sidebar">
      <div className="worker-sidebar-head">
        <div className="worker-logo">GG</div>
        <p className="worker-brand mb-0">{brand}</p>
      </div>
      <nav className="worker-nav">
        {items.map((item) => (
          <React.Fragment key={item.id || item.label}>
            {item.section ? <span className="worker-nav-section">{item.section}</span> : null}
            <button
              type="button"
              className={`worker-nav-item ${item.active ? "active" : ""}`}
              onClick={item.onClick}
            >
              <SidebarIcon name={item.icon || item.id} />
              <span>{item.label}</span>
              {item.count > 0 && <span className="nav-count-badge">{item.count}</span>}
            </button>
          </React.Fragment>
        ))}
      </nav>
      {footerAction && (
        <div className="worker-sidebar-footer">
          <button className="worker-sidebar-logout" type="button" onClick={footerAction.onClick}>
            <SidebarIcon name={footerAction.icon || "logout"} size={16} />
            <span>{footerAction.label}</span>
          </button>
        </div>
      )}
    </aside>
  );
}

export function DashboardTopbar({ title, subtitle = "", children }) {
  return (
    <div className="worker-topbar">
      <div>
        <h1 className={`h4 ${subtitle ? "mb-1" : "mb-0"}`}>{title}</h1>
        {subtitle ? <p className="small text-muted mb-0">{subtitle}</p> : null}
      </div>
      {children ? <div className="worker-user-meta d-flex align-items-center gap-2">{children}</div> : null}
    </div>
  );
}

export function MetricCard({ label, value, note = "", className = "" }) {
  return (
    <div className={`metric-card ${className}`.trim()}>
      <p className="metric-label mb-1">{label}</p>
      <p className="metric-value mb-0">{value}</p>
      {note ? <p className="small text-muted mb-0">{note}</p> : null}
    </div>
  );
}
