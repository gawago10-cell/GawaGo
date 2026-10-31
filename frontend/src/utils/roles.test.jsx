import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";

import { DashboardSidebar } from "../components/DashboardLayout";
import { useGawaGoNavigation } from "../hooks/useGawaGoNavigation";
import {
  buildAdminNavItems,
  canRoleAccessView,
  dashboardViewForRole,
  getUserRole,
  resolveGuardedView,
} from "./roles";

const STAFF_ADMIN = { username: "staff", role: "admin", is_staff: true, isSuperAdmin: false };
const SUPERADMIN = { username: "root", role: "superadmin", is_staff: true, isSuperAdmin: true };
const HOUSEHOLD = { username: "maria", role: "household", is_staff: false };
const WORKER = { username: "juan", role: "worker", is_staff: false };

describe("getUserRole", () => {
  it("maps each account type to exactly one role", () => {
    expect(getUserRole(STAFF_ADMIN)).toBe("admin");
    expect(getUserRole(SUPERADMIN)).toBe("superadmin");
    expect(getUserRole(HOUSEHOLD)).toBe("household");
    expect(getUserRole(WORKER)).toBe("worker");
  });

  it("never lets a staff account read as a worker", () => {
    // Admin profiles default to role "worker" on the backend.
    expect(getUserRole({ role: "worker", is_staff: true })).toBe("admin");
    expect(getUserRole({ is_staff: true })).toBe("admin");
    expect(getUserRole({ role: "admin", is_superuser: true })).toBe("superadmin");
  });

  it("returns null, not worker, when the role is unknown", () => {
    expect(getUserRole(null)).toBeNull();
    expect(getUserRole({})).toBeNull();
    expect(getUserRole({ role: "moderator" })).toBeNull();
  });
});

describe("view guard", () => {
  const WORKER_VIEWS = ["worker-dashboard", "worker-profile", "worker-find-jobs", "worker-job-detail"];
  const HOUSEHOLD_VIEWS = ["household-dashboard", "household-post-job", "household-worker-profile"];

  it("sends a staff admin on any worker, household or shared-user view back to the admin dashboard", () => {
    for (const view of [...WORKER_VIEWS, ...HOUSEHOLD_VIEWS, "my-reports", "superadmin-dashboard"]) {
      expect(resolveGuardedView(STAFF_ADMIN, view)).toBe("admin-dashboard");
    }
    expect(resolveGuardedView(STAFF_ADMIN, "admin-dashboard")).toBeNull();
  });

  it("sends workers and households on admin views to their own dashboard", () => {
    for (const view of ["admin-dashboard", "superadmin-dashboard"]) {
      expect(resolveGuardedView(WORKER, view)).toBe("worker-dashboard");
      expect(resolveGuardedView(HOUSEHOLD, view)).toBe("household-dashboard");
    }
    expect(resolveGuardedView(WORKER, "household-post-job")).toBe("worker-dashboard");
    expect(resolveGuardedView(HOUSEHOLD, "worker-find-jobs")).toBe("household-dashboard");
  });

  it("lets each role see its own views and the shared My Complaints", () => {
    WORKER_VIEWS.forEach((view) => expect(canRoleAccessView("worker", view)).toBe(true));
    HOUSEHOLD_VIEWS.forEach((view) => expect(canRoleAccessView("household", view)).toBe(true));
    expect(canRoleAccessView("worker", "my-reports")).toBe(true);
    expect(canRoleAccessView("household", "my-reports")).toBe(true);
    expect(canRoleAccessView("superadmin", "superadmin-dashboard")).toBe(true);
  });

  it("sends signed-out users and unknown roles to login, never a worker screen", () => {
    expect(resolveGuardedView(null, "worker-dashboard")).toBe("login");
    expect(resolveGuardedView(null, "home")).toBeNull();
    expect(resolveGuardedView({ role: "moderator" }, "worker-dashboard")).toBe("login");
    expect(dashboardViewForRole(null)).toBe("login");
  });

  it("closes unknown views by default", () => {
    expect(canRoleAccessView("worker", "some-new-view")).toBe(false);
    expect(resolveGuardedView(WORKER, "some-new-view")).toBe("worker-dashboard");
  });
});

describe("admin sidebar", () => {
  function renderAdminSidebar(adminSection, handlers = {}) {
    const openAdminDashboard = handlers.openAdminDashboard || vi.fn();
    const openAdminWorkersHistory = handlers.openAdminWorkersHistory || vi.fn();
    render(
      <DashboardSidebar
        brand="Admin Panel"
        items={buildAdminNavItems({ adminSection, openAdminDashboard, openAdminWorkersHistory })}
      />,
    );
    return { openAdminDashboard, openAdminWorkersHistory };
  }

  it("lists only admin pages -- no My Complaints", () => {
    renderAdminSidebar("verification");
    const labels = screen.getAllByRole("button").map((button) => button.textContent.trim());
    expect(labels).toEqual(["Verification Queue", "Workers History"]);
    expect(screen.queryByText("My Complaints")).toBeNull();
  });

  it.each([
    ["verification", "Verification Queue"],
    ["history", "Workers History"],
  ])("highlights exactly one item in the %s section", (section, activeLabel) => {
    renderAdminSidebar(section);
    const active = screen.getAllByRole("button").filter((button) => button.getAttribute("aria-current") === "page");
    expect(active).toHaveLength(1);
    expect(active[0].textContent.trim()).toBe(activeLabel);
  });

  it("Workers History opens the admin history section", () => {
    const { openAdminWorkersHistory, openAdminDashboard } = renderAdminSidebar("verification");
    fireEvent.click(screen.getByText("Workers History"));
    expect(openAdminWorkersHistory).toHaveBeenCalledTimes(1);
    expect(openAdminDashboard).not.toHaveBeenCalled();
  });
});

describe("goBack / Dashboard on shared views", () => {
  it.each([
    [STAFF_ADMIN, "admin-dashboard"],
    [SUPERADMIN, "superadmin-dashboard"],
    [HOUSEHOLD, "household-dashboard"],
    [WORKER, "worker-dashboard"],
    [null, "home"],
    [{ role: "moderator" }, "login"],
  ])("returns %o to %s", (currentUser, expectedView) => {
    const setView = vi.fn();
    const setAdminSection = vi.fn();
    const { goBack } = useGawaGoNavigation({ currentUser, setView, setAdminSection });
    goBack();
    expect(setView).toHaveBeenCalledWith(expectedView);
    if (expectedView === "admin-dashboard") {
      expect(setAdminSection).toHaveBeenCalledWith("verification");
    } else {
      expect(setAdminSection).not.toHaveBeenCalled();
    }
  });
});
