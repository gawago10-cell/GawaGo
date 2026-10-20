import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";

import ForgotPasswordView from "./ForgotPasswordView";

function renderView(step, overrides = {}) {
  return render(
    <ForgotPasswordView
      form={{ email: "worker@example.com", token: "", newPassword: "", confirmPassword: "" }}
      step={step}
      notice=""
      error=""
      loading={false}
      onChange={vi.fn()}
      onEmailSubmit={vi.fn()}
      onVerifyToken={vi.fn()}
      onResetPassword={vi.fn()}
      onOpenLogin={vi.fn()}
      onOpenForgotPassword={vi.fn()}
      {...overrides}
    />,
  );
}

describe("ForgotPasswordView", () => {
  it("reuses the same landing hero shell as the login screen, not a separate card", () => {
    renderView("email");
    // .home-login-card is HomeView's own login panel class -- sharing it
    // (rather than a bespoke password-reset-card) is what keeps this screen
    // visually identical to login/signup instead of a different page.
    expect(document.querySelector(".home-login-card")).toBeTruthy();
    expect(document.querySelector(".hero-section.hero-dark")).toBeTruthy();
    expect(document.querySelector(".home-landing-header")).toBeTruthy();
    expect(document.querySelector(".password-reset-card")).toBeNull();
  });

  it("shows the boxed OTP input on the verify step, sized to the code length", () => {
    renderView("verify");
    expect(screen.getAllByRole("textbox")).toHaveLength(6);
  });

  it("shows new-password fields on the reset step", () => {
    renderView("reset");
    expect(screen.getByLabelText("New Password")).toBeTruthy();
    expect(screen.getByLabelText("Confirm Password")).toBeTruthy();
  });
});
