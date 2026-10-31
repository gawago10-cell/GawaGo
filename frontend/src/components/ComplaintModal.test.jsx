import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";

vi.mock("../services/backendDataService", () => ({
  createComplaint: vi.fn(),
  fetchMyComplaints: vi.fn(async () => [
    { id: 5, jobId: 22, status: "under_review", respondentUsername: "home", createdAt: "2026-11-01T09:00:00" },
    { id: 3, jobId: 22, status: "closed", respondentUsername: "home", createdAt: "2026-10-20T09:00:00" },
  ]),
}));

import ComplaintModal from "./ComplaintModal";

describe("ComplaintModal", () => {
  it("says a complaint about this job is already open and holds Submit", async () => {
    render(<ComplaintModal isOpen onClose={() => {}} job={{ id: 22, jobTitle: "Deep Cleaning" }} role="worker" />);

    expect(await screen.findByText("You already filed a complaint about this job.")).toBeTruthy();
    expect(screen.getByText(/CMP-005 was sent on Nov 1, 2026/)).toBeTruthy();
    expect(screen.getByRole("button", { name: "Submit Complaint" }).disabled).toBe(true);
  });

  it("lets a complaint through when the earlier one is settled", async () => {
    render(<ComplaintModal isOpen onClose={() => {}} job={{ id: 9, jobTitle: "Gardening" }} role="worker" />);

    await screen.findByText("File a Complaint");
    expect(screen.queryByText("You already filed a complaint about this job.")).toBeNull();
    expect(screen.getByRole("button", { name: "Submit Complaint" }).disabled).toBe(false);
  });
});
