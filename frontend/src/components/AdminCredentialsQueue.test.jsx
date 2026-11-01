import { describe, expect, it, vi, afterEach } from "vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";

vi.mock("../services/backendDataService", () => ({
  fetchAdminCertificates: vi.fn(async () => [
    {
      id: 1,
      workerName: "Mery Cruz",
      workerUsername: "mery",
      certificateName: "Old certificate",
      certificateTypeLabel: "TESDA",
      createdAt: "2026-10-01T09:00:00",
      fileUrl: "",
      fileType: "",
      verificationStatus: "pending",
    },
  ]),
  reviewCertificate: vi.fn(),
}));

import { reviewCertificate } from "../services/backendDataService";
import AdminCredentialsQueue from "./AdminCredentialsQueue";

describe("AdminCredentialsQueue", () => {
  afterEach(() => vi.restoreAllMocks());

  it("won't approve a certificate with no document", async () => {
    render(<AdminCredentialsQueue />);
    expect(await screen.findByText("No document attached")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Approve" }).disabled).toBe(true);
  });

  it("asks again for a reason instead of rejecting without one", async () => {
    vi.spyOn(window, "prompt").mockReturnValue("   ");
    const alert = vi.spyOn(window, "alert").mockImplementation(() => {});
    render(<AdminCredentialsQueue />);
    fireEvent.click(await screen.findByRole("button", { name: "Reject" }));
    await waitFor(() => expect(alert).toHaveBeenCalledWith("Please give a reason so the worker knows what to fix."));
    expect(reviewCertificate).not.toHaveBeenCalled();
  });
});
