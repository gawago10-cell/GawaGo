import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";

vi.mock("../services/backendDataService", () => ({
  changePassword: vi.fn(),
}));

import { changePassword } from "../services/backendDataService";
import ChangePasswordCard from "./ChangePasswordCard";

function fill(current, next, confirm) {
  fireEvent.change(screen.getByLabelText("Current password"), { target: { value: current } });
  fireEvent.change(screen.getByLabelText("New password"), { target: { value: next } });
  fireEvent.change(screen.getByLabelText("Confirm new password"), { target: { value: confirm } });
  fireEvent.click(screen.getByRole("button", { name: "Update Password" }));
}

describe("ChangePasswordCard", () => {

  it("checks the new password on the page before sending it", () => {
    render(<ChangePasswordCard />);
    fill("OldPass#2026", "short", "short");
    expect(screen.getByRole("alert").textContent).toBe("Use at least 8 characters for the new password.");
    fill("OldPass#2026", "NewPass#2027", "NewPass#2028");
    expect(screen.getByRole("alert").textContent).toBe("The new passwords don't match.");
    expect(changePassword).not.toHaveBeenCalled();
  });

  it("sends the change and clears the form", async () => {
    changePassword.mockResolvedValue({ detail: "Your password was updated." });
    render(<ChangePasswordCard />);
    fill("OldPass#2026", "NewPass#2027", "NewPass#2027");
    expect(await screen.findByText("Your password was updated.")).toBeTruthy();
    expect(changePassword).toHaveBeenCalledWith("OldPass#2026", "NewPass#2027");
    expect(screen.getByLabelText("Current password").value).toBe("");
  });

  it("shows the backend's reason when the current password is wrong", async () => {
    changePassword.mockImplementation(async () => {
      throw new Error("That isn't your current password.");
    });
    render(<ChangePasswordCard />);
    fill("nope", "NewPass#2027", "NewPass#2027");
    expect(await screen.findByText("That isn't your current password.")).toBeTruthy();
  });
});
