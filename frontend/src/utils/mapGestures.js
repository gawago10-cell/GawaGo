// On a phone a map that pans with one finger traps the page: a visitor who
// swipes to scroll down, with their finger on the map, drags the map off to
// somewhere else instead (one ended up looking at the sea off General Nakar).
// Like an embedded Google Map, phones get one finger to scroll the page and
// two fingers to move or zoom the map, with a hint when one finger is used.
// Mouse and trackpad users keep normal dragging.

const HINT_VISIBLE_MS = 1400;

export function isTouchFirstDevice() {
  return (
    typeof window !== "undefined" &&
    typeof window.matchMedia === "function" &&
    window.matchMedia("(pointer: coarse)").matches
  );
}

export function applyTwoFingerPan(map) {
  if (!map || !isTouchFirstDevice()) {
    return;
  }
  // Two-finger moves are handled by Leaflet's pinch handler, which also pans
  // with the midpoint of the fingers, so only one-finger dragging goes.
  map.dragging.disable();
  map.touchZoom.enable();

  const container = map.getContainer();
  container.classList.add("gg-map-two-finger");
  const hint = document.createElement("div");
  hint.className = "gg-map-gesture-hint";
  hint.setAttribute("aria-hidden", "true");
  hint.textContent = "Use two fingers to move the map";
  container.appendChild(hint);

  let hideTimer = null;
  const hideHint = () => {
    window.clearTimeout(hideTimer);
    hint.classList.remove("visible");
  };
  const handleTouchMove = (event) => {
    // Dragging a pin is a one-finger gesture that should stay quiet.
    if (event.touches.length !== 1 || event.target?.closest?.(".leaflet-marker-draggable")) {
      hideHint();
      return;
    }
    hint.classList.add("visible");
    window.clearTimeout(hideTimer);
    hideTimer = window.setTimeout(hideHint, HINT_VISIBLE_MS);
  };
  const handleTouchStart = (event) => {
    if (event.touches.length > 1) {
      hideHint();
    }
  };
  container.addEventListener("touchmove", handleTouchMove, { passive: true });
  container.addEventListener("touchstart", handleTouchStart, { passive: true });

  map.on("unload", () => {
    window.clearTimeout(hideTimer);
    container.removeEventListener("touchmove", handleTouchMove);
    container.removeEventListener("touchstart", handleTouchStart);
    hint.remove();
  });
}
