import { describe, expect, it } from "vitest";

import { householdJobFormErrors } from "./jobFormValidation";

const complete = {
  serviceType: "Gardening",
  customServiceType: "",
  workersNeeded: "1",
  offeredRate: "600",
  jobStartDate: "2026-11-20",
  jobEndDate: "2026-11-21",
};
const ready = { pinConfirmed: true, today: "2026-11-13" };

describe("householdJobFormErrors", () => {
  it("has nothing to say about a complete form", () => {
    expect(householdJobFormErrors(complete, ready)).toEqual({});
  });

  it("names each missing field on its own", () => {
    const errors = householdJobFormErrors(
      { serviceType: "", workersNeeded: "", offeredRate: "", jobStartDate: "", jobEndDate: "" },
      { today: "2026-11-13" },
    );
    expect(errors).toEqual({
      serviceType: "Choose a service type.",
      workersNeeded: "Enter how many workers you need, from 1 to 50.",
      offeredRate: "Enter the rate you'll pay.",
      jobStartDate: "Choose the day the job starts.",
      pin: "Pin the job site: use your current location, drag the pin on the map, or pin it manually.",
    });
  });

  it("checks the values the server would refuse", () => {
    expect(householdJobFormErrors({ ...complete, offeredRate: "0.11" }, ready).offeredRate).toBe(
      "Enter a rate of at least PHP 1.00.",
    );
    expect(householdJobFormErrors({ ...complete, workersNeeded: "51" }, ready).workersNeeded).toBeTruthy();
    expect(householdJobFormErrors({ ...complete, workersNeeded: "1.5" }, ready).workersNeeded).toBeTruthy();
    expect(householdJobFormErrors({ ...complete, jobStartDate: "2026-11-12" }, ready).jobStartDate).toBe(
      "Choose today or a later date.",
    );
    expect(householdJobFormErrors({ ...complete, jobEndDate: "2026-11-19" }, ready).jobEndDate).toBe(
      "The end date can't be before the start date.",
    );
    // A one-day job may end the day it starts.
    expect(householdJobFormErrors({ ...complete, jobEndDate: "2026-11-20" }, ready)).toEqual({});
    expect(householdJobFormErrors({ ...complete, serviceType: "Other" }, ready).customServiceType).toBe(
      "Name the service.",
    );
  });
});
