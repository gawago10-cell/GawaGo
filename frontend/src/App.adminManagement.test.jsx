import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";

import App from "./App";

const TOKEN_KEY = "gawago-auth-token";

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

const SUPERADMIN = {
  id: 1,
  user_id: 1,
  username: "Gawago",
  email: "owner@example.com",
  full_name: "Gawago Owner",
  role: "superadmin",
  user_type: "household",
  verification_status: "verified",
  is_staff: true,
  is_superuser: true,
};

function adminRow(overrides) {
  return {
    id: 2,
    username: "staffer",
    email: "staffer@example.com",
    full_name: "Staff Member",
    is_active: true,
    is_superuser: false,
    role_label: "Admin",
    last_login: null,
    date_joined: "2026-01-01T00:00:00Z",
    ...overrides,
  };
}

function mockBackend({ admins = [], onPost, onPatch } = {}) {
  const calls = [];
  let adminList = admins;
  vi.spyOn(globalThis, "fetch").mockImplementation(async (url, options) => {
    const path = String(url);
    const method = (options?.method || "GET").toUpperCase();
    calls.push({ path, method, body: options?.body });

    if (path.includes("/accounts/admin/admins/")) {
      if (method === "POST") {
        const created = onPost?.(JSON.parse(options.body));
        if (created?.error) {
          return jsonResponse({ detail: created.error }, 400);
        }
        adminList = [...adminList, adminRow(created)];
        return jsonResponse(adminRow(created), 201);
      }
      if (method === "PATCH") {
        const patched = onPatch?.(JSON.parse(options.body));
        adminList = adminList.map((row) =>
          path.includes(`/${row.username}/`) ? { ...row, ...patched } : row,
        );
        return jsonResponse(adminList.find((row) => path.includes(`/${row.username}/`)));
      }
      return jsonResponse(adminList);
    }
    if (path.includes("/accounts/me/")) {
      // The real /accounts/me/ shape: { role, user, profile }.
      return jsonResponse({
        role: "superadmin",
        user: { id: SUPERADMIN.user_id, username: SUPERADMIN.username, email: SUPERADMIN.email, first_name: "Gawago", last_name: "Owner" },
        profile: SUPERADMIN,
      });
    }
    if (path.includes("/accounts/profiles/")) {
      return jsonResponse([SUPERADMIN]);
    }
    return jsonResponse([]);
  });
  return calls;
}

async function openAdminManagement() {
  const nav = await waitFor(() => {
    const found = document.querySelector(".worker-nav");
    expect(found).toBeTruthy();
    return found;
  });
  fireEvent.click(within(nav).getByRole("button", { name: /Admin Management/i }));
}

describe("the superadmin Admin Management tab", () => {
  beforeEach(() => {
    window.localStorage.clear();
    window.localStorage.setItem(TOKEN_KEY, "a.b.c");
    window.history.replaceState(null, "", "/");
  });
  afterEach(() => {
    vi.restoreAllMocks();
    window.localStorage.clear();
  });

  it("lists the real admin accounts instead of a hardcoded row", async () => {
    mockBackend({
      admins: [
        adminRow({ id: 1, username: "Gawago", full_name: "Gawago Owner", is_superuser: true, role_label: "Full System Control" }),
        adminRow(),
      ],
    });

    render(<App />);
    await openAdminManagement();

    await waitFor(() => expect(screen.getByText("Staff Member")).toBeTruthy());
    expect(screen.getByText("staffer")).toBeTruthy();
    // The placeholder row this screen used to render unconditionally.
    expect(screen.queryByText("Super Admin")).toBeNull();
  });

  it("creates an admin through the Add Admin form and reloads the list", async () => {
    const posted = [];
    const calls = mockBackend({
      admins: [adminRow({ id: 1, username: "Gawago", is_superuser: true })],
      onPost: (body) => {
        posted.push(body);
        return { id: 9, username: body.username, email: body.email, full_name: "Brand New" };
      },
    });

    render(<App />);
    await openAdminManagement();

    fireEvent.click(screen.getByRole("button", { name: "Add Admin" }));
    fireEvent.change(screen.getByLabelText("Username"), { target: { value: "new-admin" } });
    fireEvent.change(screen.getByLabelText("Email"), { target: { value: "new@example.com" } });
    fireEvent.change(screen.getByLabelText("Temporary password"), { target: { value: "br4nd-new-pass" } });
    fireEvent.click(screen.getByRole("button", { name: "Create admin" }));

    await waitFor(() => expect(posted).toHaveLength(1));
    expect(posted[0]).toMatchObject({ username: "new-admin", email: "new@example.com" });
    await waitFor(() => expect(screen.getByText(/created/i)).toBeTruthy());
    // The list is re-read so the new row appears without a manual refresh.
    expect(
      calls.filter((call) => call.path.includes("/accounts/admin/admins/") && call.method === "GET").length,
    ).toBeGreaterThan(1);
  });

  it("surfaces a rejected password instead of failing silently", async () => {
    mockBackend({
      admins: [adminRow({ id: 1, username: "Gawago", is_superuser: true })],
      onPost: () => ({ error: "This password is too common." }),
    });

    render(<App />);
    await openAdminManagement();

    fireEvent.click(screen.getByRole("button", { name: "Add Admin" }));
    fireEvent.change(screen.getByLabelText("Username"), { target: { value: "weak-admin" } });
    fireEvent.change(screen.getByLabelText("Email"), { target: { value: "weak@example.com" } });
    fireEvent.change(screen.getByLabelText("Temporary password"), { target: { value: "password" } });
    fireEvent.click(screen.getByRole("button", { name: "Create admin" }));

    await waitFor(() => expect(screen.getByText("This password is too common.")).toBeTruthy());
  });

  it("deactivates an admin after confirming", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(true);
    const patched = [];
    mockBackend({
      admins: [
        adminRow({ id: 1, username: "Gawago", is_superuser: true, role_label: "Full System Control" }),
        adminRow(),
      ],
      onPatch: (body) => {
        patched.push(body);
        return { is_active: body.is_active };
      },
    });

    render(<App />);
    await openAdminManagement();

    await waitFor(() => expect(screen.getByRole("button", { name: "Deactivate" })).toBeTruthy());
    fireEvent.click(screen.getByRole("button", { name: "Deactivate" }));

    await waitFor(() => expect(patched).toEqual([{ is_active: false }]));
    await waitFor(() => expect(screen.getByText("Deactivated")).toBeTruthy());
  });

  it("does not deactivate when the confirmation is dismissed", async () => {
    vi.spyOn(window, "confirm").mockReturnValue(false);
    const patched = [];
    mockBackend({
      admins: [adminRow({ id: 1, username: "Gawago", is_superuser: true }), adminRow()],
      onPatch: (body) => {
        patched.push(body);
        return { is_active: body.is_active };
      },
    });

    render(<App />);
    await openAdminManagement();

    await waitFor(() => expect(screen.getByRole("button", { name: "Deactivate" })).toBeTruthy());
    fireEvent.click(screen.getByRole("button", { name: "Deactivate" }));

    expect(patched).toEqual([]);
  });

  it("offers no action against the owner account or the signed-in superadmin", async () => {
    mockBackend({
      admins: [
        adminRow({ id: 1, username: "Gawago", full_name: "Gawago Owner", is_superuser: true, role_label: "Full System Control" }),
      ],
    });

    render(<App />);
    await openAdminManagement();

    await waitFor(() => expect(screen.getByText("Gawago Owner")).toBeTruthy());
    expect(screen.queryByRole("button", { name: "Deactivate" })).toBeNull();
    expect(screen.getByText("This is you")).toBeTruthy();
  });
});
