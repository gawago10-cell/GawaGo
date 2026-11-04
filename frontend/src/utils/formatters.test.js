import { describe, expect, it } from "vitest";

import { describeJobSpan, formatDistance, formatJobDate, isSameWorker } from "./formatters";

describe("formatDistance", () => {
  it("uses the backend's wording, never '1 meters away'", () => {
    expect(formatDistance(0)).toBe("Within 1 km");
    expect(formatDistance(0.48)).toBe("Within 1 km");
    expect(formatDistance(2.345)).toBe("2.3 km away");
    expect(formatDistance(null, "Road distance unavailable")).toBe("Road distance unavailable");
  });
});

describe("formatJobDate", () => {
  it("writes a complaint's filing date like the rest of the app", () => {
    expect(formatJobDate("2026-10-29")).toBe("Oct 29, 2026");
  });
});

describe("describeJobSpan", () => {
  it("counts the days between the dates now that they aren't typed in", () => {
    expect(describeJobSpan("2026-11-10", "2026-11-14")).toBe("5 days, Nov 10, 2026 to Nov 14, 2026.");
  });

  it("treats a job with no end date, or one before its start, as one day", () => {
    expect(describeJobSpan("2026-11-10", "")).toBe("One-day job on Nov 10, 2026. Set an end date if it runs longer.");
    expect(describeJobSpan("2026-11-10", "2026-11-10")).toBe(
      "One-day job on Nov 10, 2026. Set an end date if it runs longer.",
    );
    expect(describeJobSpan("", "")).toBe("Pick the dates the job starts and ends.");
  });
});

describe("isSameWorker", () => {
  const juan = { username: "juan1", firstName: "Juan", lastName: "Dela Paz", id: 7 };
  const namesake = { username: "juan2", firstName: "Juan", lastName: "Dela Paz", id: 9 };

  it("goes by username when the record has one, so a namesake never matches", () => {
    const application = { workerUsername: "juan2", workerName: "Juan Dela Paz", workerId: 7 };
    expect(isSameWorker(juan, application)).toBe(false);
    expect(isSameWorker(namesake, application)).toBe(true);
  });

  it("falls back to the name or id only when there is no username", () => {
    expect(isSameWorker(juan, { workerName: "Juan Dela Paz" })).toBe(true);
    expect(isSameWorker(juan, { workerId: 7 })).toBe(true);
    expect(isSameWorker(juan, { workerName: "Someone Else" })).toBe(false);
  });
});
