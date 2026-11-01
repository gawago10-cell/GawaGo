import { describe, expect, it } from "vitest";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";

import { AppDialogHost, askReason, confirmDialog } from "./AppDialogs";
import { labelStackedTable } from "../utils/stackedTables";
import { normalizeBackendApplication, normalizeBackendJob } from "../utils/normalizers";

describe("app dialogs", () => {
  it("resolves a confirm with the button the user pressed", async () => {
    render(<AppDialogHost />);
    let answer;
    act(() => {
      confirmDialog({ title: "Cancel this job?", message: "This can't be undone.", confirmLabel: "Cancel job" }).then(
        (value) => {
          answer = value;
        },
      );
    });

    const dialog = await screen.findByRole("alertdialog");
    expect(dialog.textContent).toContain("Cancel this job?");
    fireEvent.click(screen.getByRole("button", { name: "Cancel job" }));

    await waitFor(() => expect(answer).toBe(true));
    expect(screen.queryByRole("alertdialog")).toBeNull();
  });

  it("treats Escape as going back", async () => {
    render(<AppDialogHost />);
    let answer;
    act(() => {
      confirmDialog({ title: "Delete this notification?" }).then((value) => {
        answer = value;
      });
    });
    await screen.findByRole("alertdialog");

    fireEvent.keyDown(window, { key: "Escape" });

    await waitFor(() => expect(answer).toBe(false));
  });

  it("won't take a blank reason, and hands back the trimmed one", async () => {
    render(<AppDialogHost />);
    let answer = "unset";
    act(() => {
      askReason({ title: "Back out of Garden Trim?", label: "Why?", confirmLabel: "Back out", requiredMessage: "Say why." }).then(
        (value) => {
          answer = value;
        },
      );
    });
    await screen.findByRole("dialog");

    fireEvent.click(screen.getByRole("button", { name: "Back out" }));
    expect((await screen.findByRole("alert")).textContent).toBe("Say why.");
    expect(answer).toBe("unset");

    fireEvent.change(screen.getByLabelText("Why?"), { target: { value: "  I got   sick.  " } });
    fireEvent.click(screen.getByRole("button", { name: "Back out" }));

    await waitFor(() => expect(answer).toBe("I got sick."));
  });

  it("returns null when the reason is dismissed", async () => {
    render(<AppDialogHost />);
    let answer = "unset";
    act(() => {
      askReason({ title: "Reject this?" }).then((value) => {
        answer = value;
      });
    });
    await screen.findByRole("dialog");

    fireEvent.click(screen.getByRole("button", { name: "Go back" }));

    await waitFor(() => expect(answer).toBeNull());
  });
});

describe("stacked tables", () => {
  it("labels each cell with its column and marks a spanning row", () => {
    document.body.innerHTML = `
      <table class="gg-stack-table">
        <thead><tr><th>User</th><th>Status</th><th></th></tr></thead>
        <tbody>
          <tr><td>Ana</td><td>Active</td><td><button>Suspend</button></td></tr>
          <tr><td colspan="3">No users yet.</td></tr>
          <tr><td>Ben</td><td data-label="State">Away</td><td></td></tr>
        </tbody>
      </table>`;

    labelStackedTable(document.querySelector("table"));

    const rows = document.querySelectorAll("tbody tr");
    expect([...rows[0].children].map((cell) => cell.getAttribute("data-label"))).toEqual(["User", "Status", ""]);
    expect(rows[1].children[0].classList.contains("gg-stack-full")).toBe(true);
    expect(rows[2].children[1].getAttribute("data-label")).toBe("State");
  });
});

describe("withdrawing and cancelling", () => {
  it("reads a withdrawn application and the worker's options", () => {
    const application = normalizeBackendApplication({
      id: 7,
      status: "withdrawn",
      status_label: "Withdrawn",
      can_withdraw: false,
      can_back_out: false,
    });
    expect(application.status).toBe("Withdrawn");
    expect(application.statusLabel).toBe("Withdrawn");

    const pending = normalizeBackendApplication({ id: 8, status: "pending", can_withdraw: true });
    const hired = normalizeBackendApplication({ id: 9, status: "hired", can_back_out: true });
    expect(pending.canWithdraw).toBe(true);
    expect(hired.canBackOut).toBe(true);
  });

  it("reads whether the household can cancel and owes a reason", () => {
    const job = normalizeBackendJob({ id: 3, status: "assigned", can_cancel: true, cancel_needs_reason: true });
    expect(job.canCancel).toBe(true);
    expect(job.cancelNeedsReason).toBe(true);

    expect(normalizeBackendJob({ id: 4, status: "open" }).canCancel).toBeNull();
  });
});
