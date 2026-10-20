import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, waitFor } from "@testing-library/react";

import App from "./App";

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

describe("double-clicking login does not send a second request while the first is in flight", () => {
  let resolveLogin;
  let loginCallCount;

  beforeEach(() => {
    loginCallCount = 0;
    vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
      if (String(url).includes("/accounts/login/")) {
        loginCallCount += 1;
        // Stays pending until the test resolves it, so a second click while
        // this is in flight is the scenario under test.
        return new Promise((resolve) => {
          resolveLogin = () => resolve(jsonResponse({ detail: "Invalid username or password." }, 400));
        });
      }
      return jsonResponse([]);
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("ignores a second click until the first login request settles", async () => {
    render(<App />);
    const signIn = await waitFor(() => {
      const button = document.querySelector(".home-landing-signin");
      expect(button).toBeTruthy();
      return button;
    });
    fireEvent.click(signIn);
    await waitFor(() => expect(document.querySelector("#home-login-username")).toBeTruthy());

    fireEvent.change(document.querySelector("#home-login-username"), { target: { value: "household1" } });
    fireEvent.change(document.querySelector("#home-login-password"), { target: { value: "whatever" } });

    const submit = document.querySelector(".home-login-submit");
    fireEvent.click(submit);
    fireEvent.click(submit);
    fireEvent.click(submit);

    await waitFor(() => expect(loginCallCount).toBe(1));

    resolveLogin();
    await waitFor(() => expect(document.querySelector(".home-login-error")).toBeTruthy());

    // Now that the first request has settled, a fresh click is allowed
    // through again -- the guard blocks concurrent submits, not all retries.
    fireEvent.click(submit);
    await waitFor(() => expect(loginCallCount).toBe(2));
  });
});
