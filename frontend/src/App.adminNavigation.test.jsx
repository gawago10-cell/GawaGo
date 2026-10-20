import { beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";

import App from "./App";

const LOGIN_RESPONSES = {
  admin: { role: "admin", is_staff: true, username: "staff", display_name: "Staff Admin" },
  worker: { role: "worker", is_staff: false, username: "juan", display_name: "Juan Worker" },
};

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function mockBackend(account) {
  const login = LOGIN_RESPONSES[account];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
    const path = String(url);
    if (path.includes("/accounts/login/")) {
      // The admin's profile role defaults to "worker" on the backend; the UI
      // must follow the account role instead.
      return jsonResponse({ ...login, access: "a.b.c", profile: { role: "worker", username: login.username } });
    }
    if (path.includes("/accounts/me/")) {
      return jsonResponse({
        role: login.role,
        user: { id: 1, username: login.username },
        profile: { role: "worker", username: login.username },
      });
    }
    if (path.includes("/analytics/")) {
      return jsonResponse({});
    }
    if (path.includes("/accounts/profiles/") && login.role === "worker") {
      // The app signs a worker out if their own profile is missing here.
      return jsonResponse([
        { id: 1, user_id: 1, username: login.username, role: "worker", user_type: "worker", verification_status: "verified" },
      ]);
    }
    return jsonResponse([]);
  });
}

async function logIn(username) {
  render(<App />);
  // The home view is lazy-loaded.
  const signIn = await waitFor(() => {
    const button = document.querySelector(".home-landing-signin");
    expect(button).toBeTruthy();
    return button;
  });
  fireEvent.click(signIn);
  await waitFor(() => expect(document.querySelector("#home-login-username")).toBeTruthy());
  fireEvent.change(document.querySelector("#home-login-username"), { target: { value: username } });
  fireEvent.change(document.querySelector("#home-login-password"), { target: { value: "password" } });
  fireEvent.click(document.querySelector(".home-login-submit"));
}

function sidebarLabels() {
  const nav = document.querySelector(".worker-nav");
  return nav ? within(nav).getAllByRole("button").map((button) => button.textContent.trim()) : [];
}

function activeLabels() {
  return [...document.querySelectorAll(".worker-nav .worker-nav-item.active")].map((item) => item.textContent.trim());
}

describe("staff admin navigation", () => {
  beforeEach(() => mockBackend("admin"));

  it("lands on the admin dashboard with only admin sidebar items", async () => {
    await logIn("staff");

    await waitFor(() => expect(screen.getByText("Admin Panel")).toBeTruthy());
    expect(sidebarLabels()).toEqual(["Verification Queue", "Workers History"]);
    expect(screen.queryByText("My Reports")).toBeNull();
    expect(screen.queryByText("Find Jobs")).toBeNull();
    expect(activeLabels()).toEqual(["Verification Queue"]);
  });

  it("Workers History renders the admin history page, not the worker profile form", async () => {
    await logIn("staff");
    await waitFor(() => expect(screen.getByText("Admin Panel")).toBeTruthy());

    fireEvent.click(within(document.querySelector(".worker-nav")).getByText("Workers History"));

    await waitFor(() => expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Workers History"));
    expect(screen.getByText("Admin Panel")).toBeTruthy();
    expect(activeLabels()).toEqual(["Workers History"]);
    expect(screen.queryByText("Edit Profile Information")).toBeNull();
    expect(screen.queryByText("My Applications")).toBeNull();
  });

  it("Back and the Verification Queue item always return to the admin dashboard", async () => {
    await logIn("staff");
    await waitFor(() => expect(screen.getByText("Admin Panel")).toBeTruthy());
    fireEvent.click(within(document.querySelector(".worker-nav")).getByText("Workers History"));

    fireEvent.click(screen.getByRole("button", { name: /Back/ }));
    await waitFor(() => expect(activeLabels()).toEqual(["Verification Queue"]));
    expect(screen.getByText("Admin Panel")).toBeTruthy();
    expect(sidebarLabels()).toEqual(["Verification Queue", "Workers History"]);
  });
});

describe("a newly created admin's first sign-in", () => {
  // An admin created from the Admin Management screen has no UserProfile row
  // until something calls /me/, so login returns profile: null. The account
  // role has to come from the login response, not the (missing) profile.
  beforeEach(() => {
    vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
      const path = String(url);
      if (path.includes("/accounts/login/")) {
        return jsonResponse({
          role: "admin",
          is_staff: true,
          username: "new-admin",
          display_name: "New Admin",
          access: "a.b.c",
          profile: null,
        });
      }
      if (path.includes("/analytics/")) {
        return jsonResponse({});
      }
      return jsonResponse([]);
    });
  });

  it("reaches the admin panel even with no profile on the login response", async () => {
    await logIn("new-admin");

    await waitFor(() => expect(screen.getByText("Admin Panel")).toBeTruthy());
    expect(sidebarLabels()).toEqual(["Verification Queue", "Workers History"]);
    expect(screen.queryByText("Find Jobs")).toBeNull();
  });
});

describe("worker navigation is unaffected", () => {
  beforeEach(() => mockBackend("worker"));

  it("a worker still lands on the worker dashboard with a single active item", async () => {
    await logIn("juan");
    // Wait for the sidebar itself: "Find Jobs" also appears in the home page copy.
    await waitFor(() => expect(sidebarLabels()).toContain("Find Jobs"));
    expect(screen.queryByText("Admin Panel")).toBeNull();
    expect(activeLabels()).toEqual(["Dashboard"]);
  });
});
