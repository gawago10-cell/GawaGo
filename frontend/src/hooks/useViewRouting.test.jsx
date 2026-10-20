import React from "react";
import { act, render } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import useViewRouting, { readViewFromHash } from "./useViewRouting";

function Harness({ initialView = "home", sessionRestoring = false, onView }) {
  const [view, setView] = React.useState(initialView);
  useViewRouting({ view, setView, sessionRestoring, fallbackView: "home" });
  onView?.(view, setView);
  return <div data-testid="view">{view}</div>;
}

describe("readViewFromHash", () => {
  it("reads a view name out of the hash", () => {
    expect(readViewFromHash("#/worker-dashboard")).toBe("worker-dashboard");
    expect(readViewFromHash("#worker-dashboard")).toBe("worker-dashboard");
  });

  it("rejects anything that isn't a plain view name", () => {
    expect(readViewFromHash("")).toBeNull();
    expect(readViewFromHash("#/")).toBeNull();
    expect(readViewFromHash("#/Worker_Dashboard")).toBeNull();
    expect(readViewFromHash("#/<script>")).toBeNull();
  });
});

describe("useViewRouting", () => {
  beforeEach(() => {
    window.history.replaceState(null, "", "/");
  });

  it("writes the current view into the hash without stacking a history entry", () => {
    const pushState = vi.spyOn(window.history, "pushState");

    render(<Harness initialView="home" />);

    expect(window.location.hash).toBe("#/home");
    expect(pushState).not.toHaveBeenCalled();
    pushState.mockRestore();
  });

  it("pushes a new history entry on each later navigation", () => {
    let setView;
    render(<Harness initialView="home" onView={(_, setter) => { setView = setter; }} />);

    act(() => setView("worker-dashboard"));

    expect(window.location.hash).toBe("#/worker-dashboard");
  });

  it("adopts the view named in the hash on load", () => {
    window.history.replaceState(null, "", "/#/worker-find-jobs");

    const { getByTestId } = render(<Harness initialView="home" />);

    expect(getByTestId("view").textContent).toBe("worker-find-jobs");
  });

  it("honouring a deep link leaves nothing extra for Back to stop at", () => {
    window.history.replaceState(null, "", "/#/worker-find-jobs");
    const pushState = vi.spyOn(window.history, "pushState");

    const { getByTestId } = render(<Harness initialView="home" />);

    expect(getByTestId("view").textContent).toBe("worker-find-jobs");
    expect(window.location.hash).toBe("#/worker-find-jobs");
    // The initial view must never be written over the deep link on the way.
    expect(pushState).not.toHaveBeenCalled();
    pushState.mockRestore();
  });

  it("holds a deep link until the session has been restored", () => {
    window.history.replaceState(null, "", "/#/worker-find-jobs");

    // While restoring, the requested view must not be applied -- the role
    // guard would read the still-null user as signed out and bounce it.
    const { getByTestId, rerender } = render(<Harness initialView="home" sessionRestoring />);
    expect(getByTestId("view").textContent).toBe("home");
    expect(window.location.hash).toBe("#/worker-find-jobs");

    rerender(<Harness initialView="home" sessionRestoring={false} />);
    expect(getByTestId("view").textContent).toBe("worker-find-jobs");
  });

  it("follows the back button instead of leaving the app", () => {
    let setView;
    const { getByTestId } = render(
      <Harness initialView="home" onView={(_, setter) => { setView = setter; }} />,
    );

    act(() => setView("worker-dashboard"));
    expect(getByTestId("view").textContent).toBe("worker-dashboard");

    act(() => {
      window.history.replaceState(null, "", "#/home");
      window.dispatchEvent(new PopStateEvent("popstate"));
    });

    expect(getByTestId("view").textContent).toBe("home");
  });

  it("falls back when the hash is popped to something unusable", () => {
    let setView;
    const { getByTestId } = render(
      <Harness initialView="worker-dashboard" onView={(_, setter) => { setView = setter; }} />,
    );

    act(() => {
      window.history.replaceState(null, "", "#/");
      window.dispatchEvent(new PopStateEvent("popstate"));
    });

    expect(getByTestId("view").textContent).toBe("home");
    expect(setView).toBeTypeOf("function");
  });
});
