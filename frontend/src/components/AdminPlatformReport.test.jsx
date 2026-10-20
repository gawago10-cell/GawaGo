import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";

const fetchPlatformReport = vi.fn();
const downloadPlatformReportCsv = vi.fn();
vi.mock("../services/backendDataService", () => ({
  fetchPlatformReport: (...args) => fetchPlatformReport(...args),
  downloadPlatformReportCsv: (...args) => downloadPlatformReportCsv(...args),
}));

import AdminPlatformReport from "./AdminPlatformReport";

const REPORT = {
  scope: "platform",
  title: "Platform activity report",
  period: { start: "2026-04-20", end: "2026-10-17" },
  summary: {
    totalAccounts: 12,
    jobsPosted: 8,
    hiringSuccessRate: 37.5,
    averageWorkerRating: null,
    completedJobValue: 800.5,
  },
  sections: [
    {
      title: "Jobs by barangay",
      description: "Geographic distribution of job demand.",
      columns: ["Barangay", "Jobs posted"],
      rows: [["Isabang", 5]],
    },
  ],
};

describe("AdminPlatformReport", () => {
  it("shows the backend's period report, money as the value of completed jobs", async () => {
    fetchPlatformReport.mockResolvedValue(REPORT);

    render(<AdminPlatformReport />);

    expect(await screen.findByText("Value of completed jobs")).toBeTruthy();
    expect(screen.getByText("₱800.5")).toBeTruthy();
    expect(screen.getByText("37.5%")).toBeTruthy();
    expect(screen.getByText("No ratings yet")).toBeTruthy();
    expect(screen.getByText("Isabang")).toBeTruthy();
    const [period] = fetchPlatformReport.mock.calls[0];
    expect(period.start).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(period.end).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("exports the same period as CSV", async () => {
    fetchPlatformReport.mockResolvedValue(REPORT);
    downloadPlatformReportCsv.mockResolvedValue(true);

    render(<AdminPlatformReport />);
    await screen.findByText("Value of completed jobs");
    fireEvent.click(screen.getByRole("button", { name: "Export CSV" }));

    await waitFor(() => expect(downloadPlatformReportCsv).toHaveBeenCalledTimes(1));
    expect(downloadPlatformReportCsv.mock.calls[0][0]).toEqual(fetchPlatformReport.mock.calls.at(-1)[0]);
  });

  it("says so when the report can't be loaded", async () => {
    fetchPlatformReport.mockResolvedValue(null);

    render(<AdminPlatformReport />);

    expect(await screen.findByText(/Unable to load the report/)).toBeTruthy();
  });
});
