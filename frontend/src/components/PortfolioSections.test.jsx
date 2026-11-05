import React from "react";
import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";

import { EmploymentHistoryList, SkillCard, WorkSampleCard } from "./PortfolioSections";

describe("EmploymentHistoryList", () => {
  it("shows the household's own rating as the overall, with skill bars", () => {
    render(
      <EmploymentHistoryList
        jobs={[
          {
            id: 1,
            title: "asasd",
            household_name: "Elsalyn Barlan",
            location: "Anos",
            completed_at: "2026-11-02T08:00:00Z",
            skill_ratings: [{ skill_name: "Cooking", rating: 5 }, { skill_name: "Laundry", rating: 4 }],
            household_rating: { rating: 4.5, is_default: false, metrics: [] },
          },
        ]}
      />,
    );
    expect(screen.getByText("4.5")).toBeTruthy();
    expect(screen.getByText("Cooking")).toBeTruthy();
    expect(screen.getByText("Completed Nov 2, 2026")).toBeTruthy();
  });

  it("uses the metric ratings when the job has no skill ratings, and never says unrated when it was rated", () => {
    render(
      <EmploymentHistoryList
        jobs={[
          {
            id: 2,
            title: "Laundry and Ironing",
            skill_ratings: [],
            household_rating: { rating: 5, is_default: false, metrics: [{ label: "Punctuality", value: 5 }] },
          },
        ]}
      />,
    );
    expect(screen.getByText("5.0")).toBeTruthy();
    expect(screen.getByText("Punctuality")).toBeTruthy();
    expect(screen.queryByText(/Not rated yet/)).toBeNull();
  });

  it("says when the household has not rated yet", () => {
    render(<EmploymentHistoryList jobs={[{ id: 3, title: "Garden Cleanup", skill_ratings: [], household_rating: null }]} />);
    expect(screen.getByText("Not rated yet")).toBeTruthy();
    expect(screen.getByText("Waiting for the household's rating.")).toBeTruthy();
  });
});

describe("WorkSampleCard", () => {
  it("shows one photo, without Before/After tags, when the sample has one", () => {
    const { container } = render(<WorkSampleCard sample={{ title: "Living room", beforePreview: "data:image/png;base64,AA", afterPreview: "" }} />);
    expect(container.querySelectorAll("img")).toHaveLength(1);
    expect(screen.queryByText("After")).toBeNull();
  });

  it("shows a before/after pair when both exist", () => {
    const { container } = render(
      <WorkSampleCard sample={{ title: "Kitchen", beforePreview: "data:image/png;base64,AA", afterPreview: "data:image/png;base64,BB" }} />,
    );
    expect(container.querySelectorAll("img")).toHaveLength(2);
    expect(screen.getByText("After")).toBeTruthy();
  });
});

describe("SkillCard", () => {
  it("reads level and rating the same way on both profiles", () => {
    render(<SkillCard name="Cooking" proficiency="expert" averageRating="4.50" ratingCount={2} />);
    expect(screen.getByText("Expert")).toBeTruthy();
    expect(screen.getByText("★ 4.5 from 2 household ratings")).toBeTruthy();
  });
});
