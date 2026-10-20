import { afterEach, vi } from "vitest";
import { cleanup, configure } from "@testing-library/react";

// The app's screens are lazy-loaded; the first one a test file renders is
// compiled on demand, which can take several seconds on a busy machine.
configure({ asyncUtilTimeout: 10000 });

// jsdom lacks these; the app calls them on navigation and for notices.
window.scrollTo = vi.fn();
window.alert = vi.fn();
window.confirm = vi.fn(() => true);
// Desktop width: the app's mobile-sidebar handlers check this on every click.
window.matchMedia = (query) => ({
  matches: false,
  media: query,
  onchange: null,
  addListener: () => {},
  removeListener: () => {},
  addEventListener: () => {},
  removeEventListener: () => {},
  dispatchEvent: () => false,
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
  window.localStorage.clear();
});
