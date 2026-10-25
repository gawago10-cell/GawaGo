import { TAYABAS_CITY_BOUNDARY } from "../data/tayabasCityBoundary";

// GawaGo serves Tayabas City only (AGENTS.md, Scope), so its maps stay on
// the city: they can't be panned or zoomed out to the rest of Quezon, the
// city boundary is outlined, and everything outside it is washed out. A
// rectangle alone couldn't do this -- the city is irregular, and any box
// around it takes in Lucena proper, Lucban, Sariaya and Pagbilao.

const MASK_PANE = "ggTayabasMask";
// Outer edge of the mask; the city is cut out of it as a hole.
const WORLD_RING = [[-85, -180], [-85, 180], [85, 180], [85, -180]];
// How far past the city edge the view may go, as a share of its size, so
// pins near the border aren't jammed against the frame.
const PAN_MARGIN = 0.12;

export function isInsideTayabasCity(latitude, longitude) {
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return false;
  }
  let inside = false;
  for (let i = 0, j = TAYABAS_CITY_BOUNDARY.length - 1; i < TAYABAS_CITY_BOUNDARY.length; j = i++) {
    const [latI, lngI] = TAYABAS_CITY_BOUNDARY[i];
    const [latJ, lngJ] = TAYABAS_CITY_BOUNDARY[j];
    if (latI > lat !== latJ > lat && lng < ((lngJ - lngI) * (lat - latI)) / (latJ - latI) + lngI) {
      inside = !inside;
    }
  }
  return inside;
}

/**
 * Locks a Leaflet map to Tayabas City and draws the boundary and mask.
 * Returns helpers for maps whose data can sit outside the city (an old
 * worker pin, a route): `includePoints` widens the frame just enough to show
 * them, and `showWholeCity` fits the view to the city.
 */
export function frameMapToTayabas(map, L) {
  const city = L.latLngBounds(TAYABAS_CITY_BOUNDARY);
  let limit = city.pad(PAN_MARGIN);
  let fitTarget = city;

  const applyLimits = () => {
    const size = map.getSize();
    if (!size.x || !size.y) {
      return;
    }
    // getBoundsZoom never answers below the current minZoom, so clear it
    // first or a frame widened by includePoints could never zoom out to fit.
    map.options.minZoom = 0;
    map.setMinZoom(map.getBoundsZoom(fitTarget));
    map.setMaxBounds(limit);
  };

  map.options.maxBoundsViscosity = 1;
  // Whole-number zooms left a phone-sized map either too tight for the city
  // or showing about twice its area; quarter steps let it fit snugly.
  map.options.zoomSnap = 0.25;
  if (!map.getPane(MASK_PANE)) {
    // Above the tiles (200), below routes and areas (400) and pins (600),
    // so nothing the app draws ends up under the wash.
    const pane = map.createPane(MASK_PANE);
    pane.style.zIndex = "350";
    pane.style.pointerEvents = "none";
  }
  L.polygon([WORLD_RING, TAYABAS_CITY_BOUNDARY], {
    pane: MASK_PANE,
    stroke: false,
    fillColor: "#e4d8b8",
    // Strong enough that neighbouring town names stop reading, light enough
    // that roads leading out of the city still show where they go.
    fillOpacity: 0.86,
    interactive: false,
  }).addTo(map);
  L.polygon(TAYABAS_CITY_BOUNDARY, {
    pane: MASK_PANE,
    fill: false,
    color: "#c2453a",
    weight: 2.5,
    opacity: 0.9,
    interactive: false,
  }).addTo(map);

  applyLimits();
  map.on("resize", applyLimits);

  return {
    cityBounds: city,
    includePoints(points) {
      const list = (points || []).filter(Boolean);
      if (!list.length) {
        return;
      }
      const data = L.latLngBounds(list);
      if (city.contains(data)) {
        return;
      }
      fitTarget = L.latLngBounds(city.getSouthWest(), city.getNorthEast()).extend(data);
      limit = fitTarget.pad(PAN_MARGIN);
      applyLimits();
    },
    showWholeCity() {
      map.fitBounds(city);
    },
  };
}
