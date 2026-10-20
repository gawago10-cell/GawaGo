import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor, within } from "@testing-library/react";

import App from "./App";

const TOKEN_KEY = "gawago-auth-token";

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// The real /accounts/me/ shape: { role, user, profile }. This used to be a
// flat object, which is exactly the shape the restore code wrongly assumed --
// so the test passed while every real reload lost the user's name, skills,
// rating and verification.
function profileRecord(overrides) {
  return {
    id: 7,
    user_id: 7,
    username: "juan",
    full_name: "Juan Worker",
    role: "worker",
    user_type: "worker",
    verification_status: "verified",
    skills: ["House Cleaning"],
    ...overrides,
  };
}

function meProfile({ role = "worker", user = {}, profile = {} } = {}) {
  return {
    role,
    user: { id: 7, username: "juan", email: "juan@example.com", first_name: "Juan", last_name: "Worker", ...user },
    profile: profileRecord(profile),
  };
}

function mockBackend({ meStatus = 200, me = meProfile() } = {}) {
  const calls = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (url, options) => {
    const path = String(url);
    calls.push({ path, headers: options?.headers || {} });
    if (path.includes("/accounts/me/")) {
      return meStatus === 200 ? jsonResponse(me) : jsonResponse({ detail: "Invalid token." }, meStatus);
    }
    if (path.includes("/accounts/profiles/")) {
      return jsonResponse([me.profile]);
    }
    if (path.includes("/analytics/")) {
      return jsonResponse({});
    }
    return jsonResponse([]);
  });
  return calls;
}

function sidebarLabels() {
  const nav = document.querySelector(".worker-nav");
  return nav ? within(nav).getAllByRole("button").map((button) => button.textContent.trim()) : [];
}

describe("a stored token restores the session on page load", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });
  afterEach(() => {
    vi.restoreAllMocks();
    window.localStorage.clear();
  });

  it("a worker comes back signed in instead of on the logged-out home page", async () => {
    window.localStorage.setItem(TOKEN_KEY, "a.b.c");
    mockBackend();

    render(<App />);

    await waitFor(() => expect(sidebarLabels()).toContain("Find Jobs"));
    expect(window.localStorage.getItem(TOKEN_KEY)).toBe("a.b.c");
  });

  it("a reloaded worker keeps their name and verified status", async () => {
    window.localStorage.setItem(TOKEN_KEY, "a.b.c");
    mockBackend();

    render(<App />);

    // After a reload these fell back to "Welcome, Worker" and "Not Yet
    // Verified", because the account was read from the wrong level.
    await waitFor(() => expect(document.body.textContent).toContain("Welcome, Juan Worker"));
    expect(document.body.textContent).not.toContain("Not Yet Verified");
  });

  it("a reloaded household still sees its own jobs", async () => {
    window.localStorage.setItem(TOKEN_KEY, "a.b.c");
    const me = meProfile({
      role: "household",
      user: { id: 9, username: "ana", first_name: "Ana", last_name: "Reyes" },
      profile: { id: 9, user_id: 9, username: "ana", full_name: "Ana Reyes", role: "household", user_type: "household", skills: [] },
    });
    const job = {
      id: 31, title: "Linis ng buong bahay", job_type: "House Cleaning", required_skill: "House Cleaning",
      status: "open", status_stage: "open", household_username: "ana", household_name: "Ana Reyes",
      location_label: "Isabang, Tayabas City", service_rate: "600.00", worker_slots: 1, applications: [],
    };
    vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
      const path = String(url);
      if (path.includes("/accounts/me/")) return jsonResponse(me);
      if (path.includes("/accounts/profiles/")) return jsonResponse([me.profile]);
      if (path.includes("/jobs/")) return jsonResponse([job]);
      if (path.includes("/analytics/")) return jsonResponse({});
      return jsonResponse([]);
    });

    render(<App />);

    // The household dashboard showed "IN PROCESS · 0" after every reload:
    // jobs are matched to the household by username, which was empty.
    await waitFor(() => expect(document.body.textContent).toContain("Welcome, Ana Reyes"));
    await waitFor(() => expect(document.body.textContent).toContain("Linis ng buong bahay"));
  });

  it("a superadmin comes back as a superadmin, not a staff admin", async () => {
    window.localStorage.setItem(TOKEN_KEY, "a.b.c");
    mockBackend({
      me: meProfile({ role: "superadmin", user: { username: "Gawago", first_name: "Gawago", last_name: "Admin" } }),
    });

    render(<App />);

    // The staff-admin panel has only the verification queue; the superadmin
    // panel is a different screen entirely.
    await waitFor(() => expect(document.querySelector(".worker-nav")).toBeTruthy());
    await waitFor(() => expect(sidebarLabels().length).toBeGreaterThan(2));
    expect(sidebarLabels()).not.toEqual(["Verification Queue", "Workers History"]);
  });

  it("a token the backend rejects is cleared instead of being used in the background", async () => {
    window.localStorage.setItem(TOKEN_KEY, "expired.token");
    mockBackend({ meStatus: 401 });

    render(<App />);

    await waitFor(() => expect(window.localStorage.getItem(TOKEN_KEY)).toBeNull());
    expect(document.querySelector(".worker-nav")).toBeNull();
  });

  it("with no stored token the app does not call the account endpoint", async () => {
    const calls = mockBackend();

    render(<App />);

    await waitFor(() => expect(document.querySelector(".home-landing-signin")).toBeTruthy());
    expect(calls.filter((call) => call.path.includes("/accounts/me/"))).toHaveLength(0);
  });
});
