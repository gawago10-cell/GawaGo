import { beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, waitFor } from "@testing-library/react";

import App from "./App";

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function mockRejectedLogin() {
  vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
    if (String(url).includes("/accounts/login/")) {
      return jsonResponse({ detail: "Invalid username or password." }, 400);
    }
    return jsonResponse([]);
  });
}

async function openLoginPanel() {
  render(<App />);
  const signIn = await waitFor(() => {
    const button = document.querySelector(".home-landing-signin");
    expect(button).toBeTruthy();
    return button;
  });
  fireEvent.click(signIn);
  await waitFor(() => expect(document.querySelector("#home-login-username")).toBeTruthy());
}

function submitLogin(username, password) {
  fireEvent.change(document.querySelector("#home-login-username"), { target: { value: username } });
  fireEvent.change(document.querySelector("#home-login-password"), { target: { value: password } });
  fireEvent.click(document.querySelector(".home-login-submit"));
}

describe("login errors stay inside the login form", () => {
  beforeEach(() => mockRejectedLogin());

  it("shows the rejection in the form, not in a toast", async () => {
    await openLoginPanel();
    submitLogin("household1", "wrongpassword");

    const error = await waitFor(() => {
      const node = document.querySelector(".home-login-error");
      expect(node).toBeTruthy();
      return node;
    });
    expect(error.textContent).toContain("Invalid username or password.");
    // The global window.alert -> toast bridge must not also fire for a login.
    expect(document.querySelector(".gawago-toast")).toBeNull();
    expect(document.querySelector("#home-login-username").className).toContain("is-invalid");
    expect(document.querySelector("#home-login-password").className).toContain("is-invalid");
  });

  it("clears the error once the credentials are edited again", async () => {
    await openLoginPanel();
    submitLogin("household1", "wrongpassword");
    await waitFor(() => expect(document.querySelector(".home-login-error")).toBeTruthy());

    fireEvent.change(document.querySelector("#home-login-password"), { target: { value: "another-try" } });

    expect(document.querySelector(".home-login-error")).toBeNull();
    expect(document.querySelector("#home-login-password").className).not.toContain("is-invalid");
  });

  it("reports missing credentials in the form instead of a toast", async () => {
    await openLoginPanel();
    fireEvent.click(document.querySelector(".home-login-submit"));

    const error = await waitFor(() => {
      const node = document.querySelector(".home-login-error");
      expect(node).toBeTruthy();
      return node;
    });
    expect(error.textContent).toContain("Please enter your username and password.");
    expect(document.querySelector(".gawago-toast")).toBeNull();
  });

  it("no longer offers a Back button in the login form", async () => {
    await openLoginPanel();

    const head = document.querySelector(".home-login-form-head");
    expect(head).toBeTruthy();
    expect(head.querySelector("button")).toBeNull();
  });
});
