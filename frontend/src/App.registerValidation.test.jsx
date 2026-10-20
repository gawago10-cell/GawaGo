import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, waitFor } from "@testing-library/react";

import App from "./App";
import { validateRegistration } from "./utils/registrationValidation";

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

const FILLED = {
  firstName: "Ralph",
  lastName: "Amarillo",
  username: "Ralph",
  email: "ralph@gmail.com",
  phone: "9436534856",
  barangay: "Alitao",
  streetAddress: "45 Mabini St.",
  password: "password1",
  confirmPassword: "password1",
};

describe("validateRegistration", () => {
  it("flags only the fields that are actually empty", () => {
    const errors = validateRegistration({ ...FILLED, streetAddress: "" });

    expect(Object.keys(errors)).toEqual(["streetAddress"]);
    expect(errors.streetAddress).toMatch(/required/i);
  });

  it("treats whitespace-only as empty", () => {
    expect(validateRegistration({ ...FILLED, firstName: "   " }).firstName).toMatch(/required/i);
  });

  it("flags every empty field at once, not just the first", () => {
    const errors = validateRegistration({});

    expect(Object.keys(errors).sort()).toEqual(
      ["barangay", "confirmPassword", "email", "firstName", "lastName", "password", "phone", "streetAddress", "username"].sort(),
    );
  });

  it("explains a bad email, a short password and a mismatch on their own fields", () => {
    expect(validateRegistration({ ...FILLED, email: "ralph@yahoo.com" }).email).toMatch(/gmail/i);
    expect(validateRegistration({ ...FILLED, password: "short", confirmPassword: "short" }).password).toMatch(/8/);
    expect(validateRegistration({ ...FILLED, confirmPassword: "different1" }).confirmPassword).toMatch(/match/i);
  });

  it("passes a complete, valid form", () => {
    expect(validateRegistration(FILLED)).toEqual({});
  });
});

describe("household registration form", () => {
  beforeEach(() => {
    window.localStorage.clear();
    window.history.replaceState(null, "", "/");
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => jsonResponse([]));
    vi.spyOn(window, "alert").mockImplementation(() => {});
  });
  afterEach(() => {
    vi.restoreAllMocks();
    window.localStorage.clear();
  });

  async function openForm() {
    const rendered = render(<App />);
    window.history.replaceState(null, "", "/#/register-household");
    window.dispatchEvent(new PopStateEvent("popstate"));
    await waitFor(() => expect(document.querySelector('form [name="streetAddress"]')).toBeTruthy());
    return rendered;
  }

  function fill(name, value) {
    fireEvent.change(document.querySelector(`form [name="${name}"]`), { target: { name, value } });
  }

  function invalidNames() {
    return [...document.querySelectorAll("form .is-invalid")].map((el) => el.getAttribute("name"));
  }

  it("marks only the empty field, with a message beneath it and no alert", async () => {
    await openForm();
    for (const [name, value] of Object.entries(FILLED)) {
      if (name !== "streetAddress") fill(name, value);
    }

    fireEvent.submit(document.querySelector("form"));

    await waitFor(() => expect(invalidNames()).toEqual(["streetAddress"]));
    expect(document.querySelector("#register-error-streetAddress").textContent).toMatch(/street.*required/i);
    expect(document.querySelector('[name="streetAddress"]').getAttribute("aria-invalid")).toBe("true");
    expect(window.alert).not.toHaveBeenCalled();
  });

  it("puts an asterisk on every required label", async () => {
    await openForm();

    expect(document.querySelectorAll("form .required-mark").length).toBe(9);
  });

  it("marks every empty field when the form is submitted blank", async () => {
    await openForm();

    fireEvent.submit(document.querySelector("form"));

    await waitFor(() => expect(invalidNames()).toHaveLength(9));
  });

  it("clears a field's error as soon as the person types in it", async () => {
    await openForm();
    fireEvent.submit(document.querySelector("form"));
    await waitFor(() => expect(invalidNames()).toContain("firstName"));

    fill("firstName", "Ralph");

    await waitFor(() => expect(invalidNames()).not.toContain("firstName"));
    expect(invalidNames()).toContain("lastName");
  });
});

describe("worker registration form", () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => jsonResponse([]));
    vi.spyOn(window, "alert").mockImplementation(() => {});
  });
  afterEach(() => {
    vi.restoreAllMocks();
    window.localStorage.clear();
  });

  it("flags the empty required fields inline, same as the household form", async () => {
    render(<App />);
    window.history.replaceState(null, "", "/#/register-worker");
    window.dispatchEvent(new PopStateEvent("popstate"));
    await waitFor(() => expect(document.querySelector('form [name="streetAddress"]')).toBeTruthy());

    expect(document.querySelectorAll("form .required-mark").length).toBe(9);
    fireEvent.submit(document.querySelector("form"));

    await waitFor(() => expect(document.querySelectorAll("form .is-invalid").length).toBe(9));
    expect(window.alert).not.toHaveBeenCalled();
  });
});
