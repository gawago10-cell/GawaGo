import React, { useEffect, useState } from "react";

const CHECK_EVERY_MS = 5 * 60 * 1000;

// The built page loads one entry script whose name changes with every deploy
// ("/assets/index-Dpbzkpg2.js").
const ENTRY_SCRIPT = /<script[^>]+type="module"[^>]+src="([^"]*\/assets\/[^"]+\.js)"/;

export function currentEntryScript(doc = document) {
  return doc.querySelector('script[type="module"][src*="/assets/"]')?.getAttribute("src") || "";
}

/**
 * True when the site now serves a different build from the one this tab is
 * running. A tab left open across a deploy kept the old code for hours: a
 * household saw "PHP 0.11 / Per Day" and none of the newer fixes (household
 * dashboard audit, 2026-11-13).
 */
export async function isNewerVersionLive({ fetchImpl = fetch, doc = document } = {}) {
  const running = currentEntryScript(doc);
  if (!running) {
    return false;
  }
  const response = await fetchImpl("/", { cache: "no-store" });
  if (!response.ok) {
    return false;
  }
  const live = (await response.text()).match(ENTRY_SCRIPT)?.[1] || "";
  return Boolean(live) && live !== running;
}

/** "A new version of GawaGo is available." with a Refresh button. */
export default function UpdateAvailableBanner({ enabled = import.meta.env.PROD }) {
  const [available, setAvailable] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    if (!enabled || available) {
      return undefined;
    }
    let cancelled = false;
    const check = async () => {
      if (document.hidden) {
        return;
      }
      try {
        if ((await isNewerVersionLive()) && !cancelled) {
          setAvailable(true);
        }
      } catch {
        // Offline or the server is waking up: try again next time.
      }
    };
    const intervalId = window.setInterval(check, CHECK_EVERY_MS);
    document.addEventListener("visibilitychange", check);
    return () => {
      cancelled = true;
      window.clearInterval(intervalId);
      document.removeEventListener("visibilitychange", check);
    };
  }, [enabled, available]);

  if (!available || dismissed) {
    return null;
  }
  return (
    <div className="gawago-update-banner" role="status">
      <span>A new version of GawaGo is available.</span>
      <button type="button" className="gawago-update-refresh" onClick={() => window.location.reload()}>
        Refresh
      </button>
      <button type="button" className="gawago-update-later" onClick={() => setDismissed(true)}>
        Later
      </button>
    </div>
  );
}
