import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, waitFor } from "@testing-library/react";

import App from "./App";
import { validateRegistration, validateWorkerRegistration } from "./utils/registrationValidation";
import { resolveWorkerSkills } from "./utils/skillUtils";

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

  it("accepts any email provider, as the backend and mobile app do", () => {
    expect(validateRegistration({ ...FILLED, email: "ralph@yahoo.com" })).toEqual({});
    expect(validateRegistration({ ...FILLED, email: "ralph@school.edu.ph" })).toEqual({});
  });

  it("explains a bad email, a short password and a mismatch on their own fields", () => {
    expect(validateRegistration({ ...FILLED, email: "ralph@yahoo" }).email).toMatch(/complete email/i);
    expect(validateRegistration({ ...FILLED, email: "ralph yahoo.com" }).email).toMatch(/complete email/i);
    expect(validateRegistration({ ...FILLED, password: "short", confirmPassword: "short" }).password).toMatch(/8/);
    expect(validateRegistration({ ...FILLED, confirmPassword: "different1" }).confirmPassword).toMatch(/match/i);
  });

  it("passes a complete, valid form", () => {
    expect(validateRegistration(FILLED)).toEqual({});
  });
});

describe("validateWorkerRegistration", () => {
  const WORKER = { ...FILLED, latitude: 14.05, longitude: 121.53, skills: ["Plumbing"], customSkill: "" };

  it("passes a complete worker form", () => {
    expect(validateWorkerRegistration(WORKER)).toEqual({});
  });

  it("requires a map pin, since matching measures distance from it", () => {
    expect(validateWorkerRegistration({ ...WORKER, latitude: null, longitude: null }).location).toMatch(/pin/i);
  });

  it("requires a skill, and a typed name when Other is ticked", () => {
    expect(validateWorkerRegistration({ ...WORKER, skills: [] }).skills).toMatch(/at least one/i);
    expect(validateWorkerRegistration({ ...WORKER, skills: ["Other"] }).customSkill).toMatch(/type/i);
    expect(validateWorkerRegistration({ ...WORKER, skills: ["Other"], customSkill: "other" }).customSkill).toMatch(/type/i);
    expect(validateWorkerRegistration({ ...WORKER, skills: ["Other"], customSkill: "Masonry" })).toEqual({});
  });

  it("counts a typed skill toward the limit of three", () => {
    const skills = ["Plumbing", "Carpentry", "Welding", "Other"];
    expect(validateWorkerRegistration({ ...WORKER, skills, customSkill: "Masonry" }).skills).toMatch(/up to 3/);
  });
});

describe("resolveWorkerSkills", () => {
  it("never saves the word Other, and saves the typed skill in its place", () => {
    expect(resolveWorkerSkills(["Electrical Work", "Other"], "  Solar   Panel Install ")).toEqual([
      "Electrical Work",
      "Solar Panel Install",
    ]);
  });

  it("ignores a typed skill when Other is not ticked, and merges case duplicates", () => {
    expect(resolveWorkerSkills(["Plumbing"], "Masonry")).toEqual(["Plumbing"]);
    expect(resolveWorkerSkills(["Plumbing", "Other"], "plumbing")).toEqual(["Plumbing"]);
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

  it("drops a field's asterisk once it is answered, and brings it back if cleared", async () => {
    await openForm();
    const firstNameLabel = () => document.querySelector('form [name="firstName"]').closest("div").querySelector("label");
    expect(firstNameLabel().querySelector(".required-mark")).toBeTruthy();

    fill("firstName", "Ralph");
    await waitFor(() => expect(firstNameLabel().querySelector(".required-mark")).toBeNull());
    expect(document.querySelectorAll("form .required-mark").length).toBe(8);

    fill("firstName", "   ");
    await waitFor(() => expect(firstNameLabel().querySelector(".required-mark")).toBeTruthy());
  });

  it("keeps the red box on a filled but wrong field", async () => {
    await openForm();
    for (const [name, value] of Object.entries(FILLED)) fill(name, value);
    fill("email", "ralph@yahoo");

    fireEvent.submit(document.querySelector("form"));

    await waitFor(() => expect(invalidNames()).toEqual(["email"]));
    // Answered, so no asterisk -- the red box and message say what's wrong.
    expect(document.querySelectorAll("form .required-mark").length).toBe(0);
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

    // The nine shared fields, plus the map pin and the skills.
    expect(document.querySelectorAll("form .required-mark").length).toBe(11);
    fireEvent.submit(document.querySelector("form"));

    await waitFor(() => expect(document.querySelectorAll("form .is-invalid").length).toBe(11));
    expect(document.querySelector("#register-error-location").textContent).toMatch(/pin/i);
    expect(document.querySelector("#register-error-skills").textContent).toMatch(/at least one skill/i);
    expect(window.alert).not.toHaveBeenCalled();
  });
});
