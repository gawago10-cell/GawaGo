import React from "react";
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";

import SuspendAccountDialog from "./SuspendAccountDialog";
import VerificationBanFlag from "./VerificationBanFlag";

describe("SuspendAccountDialog ban list", () => {
  const credentials = {
    email: "w6.sample@gmail.com",
    phone: "0917 555 0106",
    idNumber: "N01-23-456789",
    idTypeLabel: "Driver's License",
  };

  it("lists what a permanent block bars from a new account", () => {
    render(<SuspendAccountDialog username="Worker6" banCredentials={credentials} onConfirm={vi.fn()} onCancel={vi.fn()} />);
    const box = document.getElementById("suspend-ban-credentials");
    expect(box).not.toBeNull();
    expect(box.textContent).toContain("w6.sample@gmail.com");
    expect(box.textContent).toContain("0917 555 0106");
    expect(box.textContent).toContain("Driver's License · N01-23-456789");
  });

  it("shows no ban list for a timed suspension", () => {
    render(
      <SuspendAccountDialog
        username="Worker6"
        durationDays={3}
        banCredentials={credentials}
        onConfirm={vi.fn()}
        onCancel={vi.fn()}
      />,
    );
    expect(document.getElementById("suspend-ban-credentials")).toBeNull();
  });
});

describe("VerificationBanFlag", () => {
  it("says the ID number matched a banned account", () => {
    render(<VerificationBanFlag request={{ banCheck: { idNumberMatch: "Worker6", nameMatch: "" } }} />);
    expect(screen.getByRole("note").textContent).toContain("ID number matches banned account @Worker6.");
  });

  it("warns about a shared name", () => {
    render(<VerificationBanFlag request={{ banCheck: { idNumberMatch: "", nameMatch: "Worker6" } }} />);
    expect(screen.getByRole("note").textContent).toContain("Same full name as banned account @Worker6.");
  });

  it("renders nothing for a clean request or the applicant's own copy", () => {
    const { container } = render(<VerificationBanFlag request={{ banCheck: null }} />);
    expect(container.textContent).toBe("");
  });
});
