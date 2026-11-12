import { afterEach, describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";

import JobScheduleBox, { JobScheduleLines, workingDaysText } from "./JobScheduleBox";
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

  it("lists the schedule as lines for My Applications, or its wording without dates", () => {
    at("2026-10-31");
    const { rerender } = render(
      <JobScheduleLines startDate="2026-11-08" endDate="2026-11-10" workingDays={3} scheduleLabel="One-Time" />,
    );
    expect(screen.getByText("Sun, Nov 8, 2026")).toBeTruthy();
    expect(screen.getByText("Tue, Nov 10, 2026")).toBeTruthy();
    expect(screen.getByText("One-Time · 3 working days")).toBeTruthy();

    rerender(<JobScheduleLines startDate="" endDate="" scheduleLabel="Part-Time" />);
    expect(screen.getByText("Part-Time")).toBeTruthy();
    expect(screen.queryByText("Not set")).toBeNull();
  });

  it("says when the working days are fewer than the dates span", () => {
    at("2026-10-31");
    render(<JobScheduleBox startDate="2026-12-08" endDate="2026-12-09" workingDays={1} />);
    expect(screen.getByText("1 working day out of 2")).toBeTruthy();
    expect(workingDaysText("2026-12-08", "2026-12-10", 3)).toBe("3 working days");
    expect(workingDaysText("2026-12-08", "", 2)).toBe("2 working days");
    expect(workingDaysText("2026-12-08", "2026-12-09", null)).toBe("");
  });

  it("says Not set for a missing end on a longer job", () => {
    at("2026-10-31");
    render(<JobScheduleBox startDate="2026-11-03" endDate="" workingDays={4} />);
    expect(screen.getByText("Not set")).toBeTruthy();
  });
});
