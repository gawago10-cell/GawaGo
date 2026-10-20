import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";

vi.mock("../api/apiClient", () => ({
  apiRequest: vi.fn(async () => ({ ok: true })),
}));
vi.mock("../utils/apiUtils", () => ({
  readResponseData: vi.fn(async () => ({
    bio: "Ten years of home cleaning.",
    skills: [],
    certifications: [],
    portfolio_items: [
      {
        id: 1,
        title: "Kitchen deep clean",
        image_url: "http://testserver/media/single.png",
        before_image_url: "http://testserver/media/before.png",
        after_image_url: "http://testserver/media/after.png",
      },
      {
        id: 2,
        title: "Laundry",
        image_url: "http://testserver/media/laundry.png",
        before_image_url: null,
        after_image_url: null,
      },
    ],
  })),
}));
vi.mock("../services/backendDataService", () => ({
  fetchWorkerEmploymentHistory: vi.fn(async () => [
    {
      id: 9,
      title: "Weekly cleaning",
      household_name: "Santos Household",
      location: "Isabang",
      completed_at: null,
      skill_ratings: [{ skill_name: "House Cleaning", rating: 4.5 }],
    },
  ]),
}));

import WorkerPortfolioViewPublic from "./WorkerPortfolioViewPublic";

describe("WorkerPortfolioViewPublic", () => {
  it("shows both halves of a before/after work sample, not just one photo", async () => {
    render(<WorkerPortfolioViewPublic workerId={3} workerName="Ana" />);

    const before = await screen.findByAltText("Kitchen deep clean (before)");
    const after = screen.getByAltText("Kitchen deep clean (after)");
    expect(before.getAttribute("src")).toBe("http://testserver/media/before.png");
    expect(after.getAttribute("src")).toBe("http://testserver/media/after.png");
    expect(screen.getByAltText("Laundry").getAttribute("src")).toBe("http://testserver/media/laundry.png");
  });

  it("lists the skill ratings received on each completed job", async () => {
    render(<WorkerPortfolioViewPublic workerId={3} workerName="Ana" />);

    expect(await screen.findByText("House Cleaning:")).toBeTruthy();
    expect(screen.getByText("4.5 ★")).toBeTruthy();
  });
});
