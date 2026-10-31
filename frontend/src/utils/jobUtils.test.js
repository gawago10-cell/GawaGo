import { describe, expect, it } from "vitest";

import { getWorkerJobMatches } from "./jobUtils";

describe("getWorkerJobMatches", () => {
  const worker = { skills: ["House Cleaning"] };

  it("keeps jobs still in the market: open, held from, or applied to and pending", () => {
    const jobs = [
      { id: 1, serviceType: "House Cleaning", canApply: true, createdAt: "2026-10-30" },
      { id: 2, serviceType: "Cooking", canApply: false, applyBlockedReason: "You're on a full-time job.", createdAt: "2026-10-29" },
      { id: 3, serviceType: "Cooking", canApply: false, acceptingApplications: true, applicationStatus: "Pending", createdAt: "2026-10-28" },
      // Full, finished, or no longer theirs to wait on: gone from Find Jobs.
      { id: 4, serviceType: "Cooking", canApply: false, acceptingApplications: false, applicationStatus: "Pending", createdAt: "2026-10-27" },
      { id: 5, serviceType: "Cooking", canApply: false, acceptingApplications: true, applicationStatus: "Rejected", createdAt: "2026-10-26" },
      { id: 6, serviceType: "Cooking", canApply: false, applyBlockedReason: "", createdAt: "2026-10-25" },
    ];
    expect(getWorkerJobMatches(worker, jobs).map((job) => job.id)).toEqual([1, 2, 3]);
  });
});
