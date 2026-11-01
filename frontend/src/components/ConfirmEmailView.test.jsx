import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";

vi.mock("../services/backendDataService", () => ({
  verifySignupCode: vi.fn(async () => ({ detail: "ok" })),
  resendSignupCode: vi.fn(async () => ({ detail: "sent" })),
}));

import { resendSignupCode, verifySignupCode } from "../services/backendDataService";
import ConfirmEmailView from "./ConfirmEmailView";

describe("ConfirmEmailView", () => {
  it("sends the 6-digit code and moves on once it's accepted", async () => {
    const onConfirmed = vi.fn();
    const { container } = render(<ConfirmEmailView email="new@example.com" onConfirmed={onConfirmed} onOpenLogin={() => {}} />);
    expect(screen.getByText("We sent it to new@example.com.")).toBeTruthy();
    const submit = screen.getByRole("button", { name: "Confirm Email" });
    expect(submit.disabled).toBe(true);

    const boxes = container.querySelectorAll("input");
    fireEvent.paste(boxes[0], { clipboardData: { getData: () => "123456" } });
    await waitFor(() => expect(submit.disabled).toBe(false));
    fireEvent.click(submit);
    await waitFor(() => expect(onConfirmed).toHaveBeenCalled());
    expect(verifySignupCode).toHaveBeenCalledWith("new@example.com", "123456");
  });

  it("asks for the address when a refresh lost it", async () => {
    const { container } = render(<ConfirmEmailView email="" onConfirmed={() => {}} onOpenLogin={() => {}} />);
    const submit = screen.getByRole("button", { name: "Confirm Email" });
    fireEvent.paste(container.querySelector("input[inputmode=numeric]"), { clipboardData: { getData: () => "654321" } });
    expect(submit.disabled).toBe(true);
    fireEvent.change(screen.getByLabelText("Email address"), { target: { value: "new@example.com" } });
    await waitFor(() => expect(submit.disabled).toBe(false));
    fireEvent.click(submit);
    await waitFor(() => expect(verifySignupCode).toHaveBeenCalledWith("new@example.com", "654321"));
  });

  it("can ask for another code", async () => {
    render(<ConfirmEmailView email="new@example.com" onConfirmed={() => {}} onOpenLogin={() => {}} />);
    fireEvent.click(screen.getByRole("button", { name: "Didn't get a code? Send another" }));
    expect(await screen.findByText("A new code is on its way to new@example.com.")).toBeTruthy();
    expect(resendSignupCode).toHaveBeenCalledWith("new@example.com");
  });
});
