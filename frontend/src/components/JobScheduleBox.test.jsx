import { afterEach, describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";

import JobScheduleBox from "./JobScheduleBox";
import { formatJobDay } from "../utils/formatters";

describe("formatJobDay", () => {
  it("adds the day of the week to a job date", () => {
    expect(formatJobDay("2026-10-30")).toBe("Fri, Oct 30, 2026");
    expect(formatJobDay("")).toBe("");
  });
});

describe("JobScheduleBox", () => {
  afterEach(() => vi.useRealTimers());

  function at(today) {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(`${today}T09:00:00`));
  }

  it("shows nothing without dates", () => {
    const { container } = render(<JobScheduleBox startDate="" endDate="" />);
    expect(container.innerHTML).toBe("");
  });

  it("words a job that hasn't started yet", () => {
    at("2026-10-31");
    render(<JobScheduleBox startDate="2026-11-03" endDate="2026-11-05" workingDays={3} />);
    expect(screen.getByText("Starts")).toBeTruthy();
    expect(screen.getByText("Tue, Nov 3, 2026")).toBeTruthy();
    expect(screen.getByText("Ends")).toBeTruthy();
    expect(screen.getByText("Thu, Nov 5, 2026")).toBeTruthy();
    expect(screen.getByText("3 working days")).toBeTruthy();
  });

  it("words a job that is under way, and one that is finished", () => {
    at("2026-10-31");
    const { rerender } = render(<JobScheduleBox startDate="2026-10-30" endDate="2026-11-01" />);
    expect(screen.getByText("Started")).toBeTruthy();
    expect(screen.getByText("Ends")).toBeTruthy();

    rerender(<JobScheduleBox startDate="2026-10-30" endDate="2026-11-01" finished />);
    expect(screen.getByText("Ended")).toBeTruthy();
  });

  it("ends a one-day job on its start day when no end date was set", () => {
    at("2026-10-31");
    render(<JobScheduleBox startDate="2026-10-22" endDate="" workingDays={1} />);
    expect(screen.getAllByText("Thu, Oct 22, 2026")).toHaveLength(2);
    expect(screen.getByText("1 working day")).toBeTruthy();
  });

  it("says Not set for a missing end on a longer job", () => {
    at("2026-10-31");
    render(<JobScheduleBox startDate="2026-11-03" endDate="" workingDays={4} />);
    expect(screen.getByText("Not set")).toBeTruthy();
  });
});
