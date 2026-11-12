import { afterEach, describe, expect, it, vi } from "vitest";
import { act, fireEvent, render, screen } from "@testing-library/react";

import UpdateAvailableBanner, { isNewerVersionLive } from "./UpdateAvailableBanner";

const page = (entry) =>
  `<!doctype html><html><head><script type="module" crossorigin src="${entry}"></script></head><body></body></html>`;

function running(entry) {
  const script = document.createElement("script");
  script.type = "module";
  script.setAttribute("src", entry);
  document.head.appendChild(script);
  return script;
}

describe("isNewerVersionLive", () => {
  let script;
  afterEach(() => script?.remove());

  it("is true when the site serves a different build", async () => {
    script = running("/assets/index-OLD111.js");
    const fetchImpl = vi.fn(async () => ({ ok: true, text: async () => page("/assets/index-NEW222.js") }));

    expect(await isNewerVersionLive({ fetchImpl })).toBe(true);
    expect(fetchImpl).toHaveBeenCalledWith("/", { cache: "no-store" });
  });

  it("is false for the same build, an error page, or the dev server", async () => {
    script = running("/assets/index-SAME.js");
    expect(
      await isNewerVersionLive({ fetchImpl: async () => ({ ok: true, text: async () => page("/assets/index-SAME.js") }) }),
    ).toBe(false);
    expect(await isNewerVersionLive({ fetchImpl: async () => ({ ok: false, text: async () => "" }) })).toBe(false);
    script.remove();
    script = null;
    // Under the dev server there is no built entry script to compare.
    expect(await isNewerVersionLive({ fetchImpl: vi.fn() })).toBe(false);
  });
});

describe("UpdateAvailableBanner", () => {
  let script;
  afterEach(() => {
    script?.remove();
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("offers a refresh once a newer build is live, and can be put off", async () => {
    vi.useFakeTimers();
    script = running("/assets/index-OLD111.js");
    vi.spyOn(window, "fetch").mockResolvedValue({ ok: true, text: async () => page("/assets/index-NEW222.js") });

    render(<UpdateAvailableBanner enabled />);
    expect(screen.queryByText("A new version of GawaGo is available.")).toBeNull();

    await act(async () => {
      await vi.advanceTimersByTimeAsync(5 * 60 * 1000);
    });
    expect(screen.getByText("A new version of GawaGo is available.")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Refresh" })).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Later" }));
    expect(screen.queryByText("A new version of GawaGo is available.")).toBeNull();
  });

  it("does nothing outside a built site", async () => {
    vi.useFakeTimers();
    const fetchSpy = vi.spyOn(window, "fetch");
    render(<UpdateAvailableBanner enabled={false} />);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(10 * 60 * 1000);
    });
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});
