import { useEffect, useRef } from "react";

// The app navigates by setting a `view` string, with no router. That left the
// browser Back button pointing at whatever page preceded the app (so Back
// exited GawaGo entirely) and made every screen unlinkable.
//
// This mirrors `view` into the URL hash rather than the path on purpose: a
// path-based route needs the host to rewrite unknown paths to index.html, and
// getting that wrong in one environment serves a 404 for every deep link. A
// hash travels with the document and needs no server config, so it behaves
// the same under Vite, a static host and the /admin entry point.

const VIEW_PATTERN = /^[a-z0-9-]+$/;

export function readViewFromHash(hash) {
  const value = String(hash || "").replace(/^#\/?/, "");
  return VIEW_PATTERN.test(value) ? value : null;
}

export default function useViewRouting({ view, setView, sessionRestoring, fallbackView }) {
  // Captured at mount, before anything can overwrite it, and applied only
  // once we know who (if anyone) is signed in -- applying a deep link to a
  // private screen while the session is still being restored would let the
  // role guard bounce it to login before the user was known.
  const pendingViewRef = useRef(readViewFromHash(window.location.hash));
  const hasWrittenRef = useRef(false);

  useEffect(() => {
    if (sessionRestoring) {
      return;
    }
    const requested = pendingViewRef.current;
    if (!requested) {
      return;
    }
    // Held until `view` has actually caught up, so the sync below doesn't
    // write the pre-navigation view over the deep link we're about to honour
    // and leave an extra entry for Back to stop at.
    if (requested === view) {
      pendingViewRef.current = null;
      return;
    }
    setView(requested);
  }, [sessionRestoring, view, setView]);

  useEffect(() => {
    if (sessionRestoring || pendingViewRef.current) {
      return;
    }
    const target = `#/${view}`;
    if (window.location.hash === target) {
      hasWrittenRef.current = true;
      return;
    }
    // The first write replaces the entry the page loaded with, so a reload
    // doesn't leave a duplicate the user has to press Back through twice.
    if (hasWrittenRef.current) {
      window.history.pushState(null, "", target);
    } else {
      window.history.replaceState(null, "", target);
      hasWrittenRef.current = true;
    }
  }, [view, sessionRestoring]);

  useEffect(() => {
    function handlePopState() {
      setView(readViewFromHash(window.location.hash) || fallbackView);
    }
    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, [setView, fallbackView]);
}
