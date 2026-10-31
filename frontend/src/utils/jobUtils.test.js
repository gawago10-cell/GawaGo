import { describe, expect, it } from "vitest";

import { getWorkerJobMatches } from "./jobUtils";

describe("getWorkerJobMatches", () => {
  const worker = { skills: ["House Cleaning"] };

  it("keeps open jobs a full-time worker can't apply to yet, and drops applied ones", () => {
    const jobs = [
      { id: 1, serviceType: "House Cleaning", canApply: true, createdAt: "2026-10-30" },
      { id: 2, serviceType: "Cooking", canApply: false, applyBlockedReason: "You're on a full-time job.", createdAt: "2026-10-29" },
      { id: 3, serviceType: "Cooking", canApply: false, applyBlockedReason: "", createdAt: "2026-10-28" },
    ];
    expect(getWorkerJobMatches(worker, jobs).map((job) => job.id)).toEqual([1, 2]);
  });
});
