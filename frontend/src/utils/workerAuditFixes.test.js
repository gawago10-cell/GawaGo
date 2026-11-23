// Mobile worker audit (2026-11-23): the shared web pieces behind the fixes.
import { describe, expect, it } from "vitest";

import { formatRate, rateUnit } from "./formatters";
import { serverProfileFieldErrors, workerProfileFieldErrors } from "./profileValidation";
import { serverRegistrationErrors } from "./registrationValidation";
import { averageRating } from "./reviewUtils";

describe("one rate wording", () => {
  it("reads PHP 650.00 / day, / hour or / job", () => {
    expect(formatRate(650, "Per Day")).toBe("PHP 650.00 / day");
    expect(formatRate(120, "Per Hour")).toBe("PHP 120.00 / hour");
    expect(formatRate(1500, "Fixed Rate")).toBe("PHP 1500.00 / job");
    expect(rateUnit("per_hour")).toBe("hour");
    expect(rateUnit("")).toBe("day");
  });
});

describe("averageRating", () => {
  it("rounds halves up like the backend", () => {
    // 4.35 is 4.3499... as a float; the backend's Decimal gives 4.4.
    expect(averageRating([4.3, 4.4])).toBe(4.4);
    expect(averageRating([4.3, 4.5])).toBe(4.4);
    expect(averageRating([3])).toBe(3);
    expect(averageRating([])).toBeNull();
  });
});

describe("worker rates follow the server limits", () => {
  const base = { email: "dan@example.com", phone: "9171234567", dailyRate: "650" };

  it("refuses out-of-range rates under the field", () => {
    expect(workerProfileFieldErrors({ ...base, hourlyRate: "0.5" }).hourlyRate).toBe(
      "Enter at least PHP 1, or leave it blank.",
    );
    expect(workerProfileFieldErrors({ ...base, hourlyRate: "20000" }).hourlyRate).toBe("Enter PHP 10,000 or less.");
    expect(workerProfileFieldErrors({ ...base, dailyRate: "100001" }).dailyRate).toBe("Enter PHP 100,000 or less.");
    expect(workerProfileFieldErrors({ ...base, hourlyRate: "-5" }).hourlyRate).toBe("A rate can't be negative.");
  });

  it("still takes 0 or blank as not given", () => {
    expect(workerProfileFieldErrors({ ...base, hourlyRate: "0" })).toEqual({});
    expect(workerProfileFieldErrors({ ...base, hourlyRate: "" })).toEqual({});
  });

  it("puts the server's rate and experience errors under their fields", () => {
    const data = { daily_rate: ["Enter PHP 100,000 or less."], years_experience: ["Enter 60 years or fewer."] };
    expect(serverRegistrationErrors(data)).toEqual({
      dailyRate: "Enter PHP 100,000 or less.",
      yearsExperience: "Enter 60 years or fewer.",
    });
    expect(serverProfileFieldErrors({ hourly_rate: ["Enter the rate as a number."] })).toEqual({
      hourlyRate: "Enter the rate as a number.",
    });
  });
});
