// One source of truth for "who is this user and which screens are theirs".
// Every layout, sidebar, guard and redirect should go through these helpers
// instead of comparing role strings inline -- scattered checks are how staff
// admins used to fall through to the worker layout.

export const ROLES = Object.freeze({
  SUPERADMIN: "superadmin",
  ADMIN: "admin",
  HOUSEHOLD: "household",
  WORKER: "worker",
});

const DASHBOARD_VIEW = {
  [ROLES.SUPERADMIN]: "superadmin-dashboard",
  [ROLES.ADMIN]: "admin-dashboard",
  [ROLES.HOUSEHOLD]: "household-dashboard",
  [ROLES.WORKER]: "worker-dashboard",
};

// Reachable with or without an account.
const PUBLIC_VIEWS = new Set(["home", "login", "forgot-password", "register-worker", "register-household"]);

// Views not covered by a role prefix below.
const SHARED_VIEW_ROLES = {
  "my-reports": [ROLES.HOUSEHOLD, ROLES.WORKER],
  "admin-dashboard": [ROLES.ADMIN],
  "superadmin-dashboard": [ROLES.SUPERADMIN],
};

/**
 * "superadmin" | "admin" | "household" | "worker", or null when the role
 * can't be determined. Staff always map to an admin role -- never to a
 * worker, whatever their (defaulted) profile role says.
 */
export function getUserRole(user) {
  if (!user) {
    return null;
  }
  const role = String(user.role || "").trim().toLowerCase();
  const isStaff = Boolean(user.is_staff ?? user.isStaff);
  if (role === ROLES.SUPERADMIN || user.isSuperAdmin === true || user.is_superuser === true) {
    return ROLES.SUPERADMIN;
  }
  if (role === ROLES.ADMIN || isStaff) {
    return ROLES.ADMIN;
  }
  if (role === ROLES.HOUSEHOLD || role === ROLES.WORKER) {
    return role;
  }
  return null;
}

export function isAdminRole(role) {
  return role === ROLES.ADMIN || role === ROLES.SUPERADMIN;
}

/** Each role's home screen; "login" when the role is unknown. */
export function dashboardViewForRole(role) {
  return DASHBOARD_VIEW[role] || "login";
}

/** Which roles may render a view. null means anyone (public view). */
export function rolesForView(view) {
  if (PUBLIC_VIEWS.has(view)) {
    return null;
  }
  if (SHARED_VIEW_ROLES[view]) {
    return SHARED_VIEW_ROLES[view];
  }
  if (view.startsWith("worker-")) {
    return [ROLES.WORKER];
  }
  if (view.startsWith("household-")) {
    return [ROLES.HOUSEHOLD];
  }
  // Unknown views are closed by default rather than open.
  return [];
}

export function canRoleAccessView(role, view) {
  const allowed = rolesForView(view);
  return allowed === null || allowed.includes(role);
}

/**
 * Where to send someone who is on a view they may not see: their own
 * dashboard, "login" if signed out, or null if the view is fine.
 */
export function resolveGuardedView(user, view) {
  if (!user) {
    return rolesForView(view) === null ? null : "login";
  }
  const role = getUserRole(user);
  if (!role) {
    return "login";
  }
  return canRoleAccessView(role, view) ? null : dashboardViewForRole(role);
}

/** The staff-admin sidebar. Exactly one item is active per section. */
export function buildAdminNavItems({ adminSection, openAdminDashboard, openAdminWorkersHistory }) {
  return [
    {
      id: "verification",
      label: "Verification Queue",
      active: adminSection !== "history",
      onClick: openAdminDashboard,
    },
    {
      id: "history",
      label: "Workers History",
      active: adminSection === "history",
      onClick: openAdminWorkersHistory,
    },
  ];
}
