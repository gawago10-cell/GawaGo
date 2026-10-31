import { describe, expect, it } from "vitest";

import { formatDistance, formatJobDate } from "./formatters";

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
