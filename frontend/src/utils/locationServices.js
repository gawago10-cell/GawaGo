import {
  BARANGAYS,
  EMAIL_ADDRESS_PATTERN,
  OPENROUTESERVICE_API_KEY,
  OPENROUTESERVICE_REVERSE_URL,
  OPENROUTESERVICE_SEARCH_URL,
  PHILIPPINES_MAP_BOUNDS,
  TAYABAS_CITY_CENTER,
  TAYABAS_MAP_BOUNDS,
} from "../constants/appConstants";
import { formatLocation } from "./formatters";
import { getBarangayFromBoundary } from "./geofenceUtils";
import { findTayabasBarangayFromText, getBarangayCenter, getFallbackBarangay, normalizeBarangayName, parseLocationLabel } from "./locationUtils";
import { isInsideTayabasCity } from "./tayabasMapFrame";

let tayabasBarangayCentersPromise = null;

// A street-level geocode further than this from the chosen barangay's centre
// is taken to be a same-named street elsewhere in the city, not this one.
const MAX_GEOCODE_DISTANCE_FROM_BARANGAY_KM = 2;
// Pelias layers precise enough to stand for a home or job site. "locality"
// (the "Tayabas, QZ" town point) and "county" answers used to be accepted,
// which put people up to 13 km from home.
const PRECISE_GEOCODE_LAYERS = new Set(["address", "street", "venue"]);
// Above this, a device fix is used but the person is told to check the pin.
const LOW_GPS_ACCURACY_METERS = 150;

export function isValidEmailAddress(email) {
  return EMAIL_ADDRESS_PATTERN.test(String(email || "").trim());
}

export function buildTayabasLocationQuery(barangay, streetAddress) {
  return [streetAddress, barangay, "Tayabas City", "Quezon", "Philippines"].filter(Boolean).join(", ");
}

export function formatCoordinateAddress(latitude, longitude) {
  const lat = Number(Number(latitude).toFixed(5));
  const lon = Number(Number(longitude).toFixed(5));
  return `Tayabas City coordinates ${lat}, ${lon}`;
}

/** Text the app wrote into a street field itself (or a bare place name such
 * as "Tayabas City" from the street lookup), which a pin may replace;
 * anything else was typed by the person and is kept. */
export function isAutoFilledStreetAddress(streetAddress) {
  const text = String(streetAddress || "").trim();
  return (
    !text ||
    isGenericAddressPart(text) ||
    /^barangay\s+.+,\s*tayabas city$/i.test(text) ||
    /^tayabas city coordinates\s/i.test(text)
  );
}

export function isGenericAddressPart(part) {
  return /^(barangay\s+)?(tayabas|tayabas city|quezon|qz|philippines|poblacion)$/i.test(String(part || "").trim());
}

export function getSavedHouseholdLocation(currentHousehold, currentUser) {
  const profileLocation = parseLocationLabel(currentUser?.profile?.location_label || currentUser?.profile?.locationLabel || "");
  return {
    barangay: normalizeBarangayName(currentHousehold?.barangay || currentUser?.barangay || profileLocation.barangay || ""),
    streetAddress: currentHousehold?.streetAddress || currentUser?.streetAddress || profileLocation.streetAddress || "",
  };
}

export function haversineDistanceKm(lat1, lon1, lat2, lon2) {
  const firstLatitude = Number(lat1);
  const firstLongitude = Number(lon1);
  const secondLatitude = Number(lat2);
  const secondLongitude = Number(lon2);
  if (![firstLatitude, firstLongitude, secondLatitude, secondLongitude].every(Number.isFinite)) {
    return null;
  }
  const earthRadiusKm = 6371;
  const toRadians = (value) => value * Math.PI / 180;
  const deltaLatitude = toRadians(secondLatitude - firstLatitude);
  const deltaLongitude = toRadians(secondLongitude - firstLongitude);
  const a = Math.sin(deltaLatitude / 2) ** 2 + Math.cos(toRadians(firstLatitude)) * Math.cos(toRadians(secondLatitude)) * Math.sin(deltaLongitude / 2) ** 2;
  return 2 * earthRadiusKm * Math.asin(Math.sqrt(a));
}

export function buildMapPreviewUrl(latitude, longitude) {
  const numericLatitude = Number(latitude);
  const numericLongitude = Number(longitude);
  if (!Number.isFinite(numericLatitude) || !Number.isFinite(numericLongitude)) {
    return "";
  }
  const latOffset = 0.008;
  const lonOffset = 0.008;
  const left = encodeURIComponent((numericLongitude - lonOffset).toFixed(6));
  const bottom = encodeURIComponent((numericLatitude - latOffset).toFixed(6));
  const right = encodeURIComponent((numericLongitude + lonOffset).toFixed(6));
  const top = encodeURIComponent((numericLatitude + latOffset).toFixed(6));
  const marker = `${encodeURIComponent(numericLatitude.toFixed(6))}%2C${encodeURIComponent(numericLongitude.toFixed(6))}`;
  return `https://www.openstreetmap.org/export/embed.html?bbox=${left}%2C${bottom}%2C${right}%2C${top}&layer=mapnik&marker=${marker}`;
}

export function buildTayabasMapPreviewUrl() {
  const left = encodeURIComponent(TAYABAS_MAP_BOUNDS.west.toFixed(6));
  const bottom = encodeURIComponent(TAYABAS_MAP_BOUNDS.south.toFixed(6));
  const right = encodeURIComponent(TAYABAS_MAP_BOUNDS.east.toFixed(6));
  const top = encodeURIComponent(TAYABAS_MAP_BOUNDS.north.toFixed(6));
  return `https://www.openstreetmap.org/export/embed.html?bbox=${left}%2C${bottom}%2C${right}%2C${top}&layer=mapnik`;
}

export function buildPhilippinesMapPreviewUrl() {
  const left = encodeURIComponent(PHILIPPINES_MAP_BOUNDS.west.toFixed(6));
  const bottom = encodeURIComponent(PHILIPPINES_MAP_BOUNDS.south.toFixed(6));
  const right = encodeURIComponent(PHILIPPINES_MAP_BOUNDS.east.toFixed(6));
  const top = encodeURIComponent(PHILIPPINES_MAP_BOUNDS.north.toFixed(6));
  return `https://www.openstreetmap.org/export/embed.html?bbox=${left}%2C${bottom}%2C${right}%2C${top}&layer=mapnik`;
}

export function getOpenRouteServiceHeaders() {
  return OPENROUTESERVICE_API_KEY ? {
    Authorization: OPENROUTESERVICE_API_KEY,
    Accept: "application/json, application/geo+json",
  } : {
    Accept: "application/json, application/geo+json",
  };
}

export function normalizeGeocodedAddress(address = {}, fallbackBarangay = "", fallbackStreetAddress = "") {
  const labelParts = String(address.label || "").split(",").map((part) => part.trim()).filter(Boolean);
  const addressParts = [
    address.neighbourhood,
    address.borough,
    address.suburb,
    address.quarter,
    address.locality,
    address.county,
    ...labelParts,
    fallbackBarangay,
  ];
  const barangay = normalizeBarangayName(addressParts.map(findTayabasBarangayFromText).find(Boolean) || fallbackBarangay || "");
  const streetFromFields = [address.house_number, address.street || address.name || address.road].filter(Boolean).join(" ").trim();
  const streetFromLabel = labelParts.find((part) => part !== barangay && !findTayabasBarangayFromText(part) && !isGenericAddressPart(part));
  const streetAddress = streetFromFields || streetFromLabel || fallbackStreetAddress || "";
  return {
    barangay,
    streetAddress,
    locationLabel: formatLocation(barangay, streetAddress),
  };
}

export function buildCoordinateLocation(latitude, longitude, fallbackBarangay = "", fallbackStreetAddress = "", source = "device", warning = "") {
  const resolvedLatitude = Number(Number(latitude).toFixed(7));
  const resolvedLongitude = Number(Number(longitude).toFixed(7));
  const barangay = getFallbackBarangay(fallbackBarangay);
  const streetAddress = fallbackStreetAddress || formatCoordinateAddress(resolvedLatitude, resolvedLongitude);
  return {
    latitude: resolvedLatitude,
    longitude: resolvedLongitude,
    barangay,
    streetAddress,
    locationLabel: formatLocation(barangay, streetAddress),
    mapUrl: buildMapPreviewUrl(resolvedLatitude, resolvedLongitude),
    source,
    warning,
  };
}

/** The selected barangay's centre, labelled as such. The fallback whenever a
 * typed address can't be placed: it is never the town centre, and the label
 * keeps the barangay and the street the person typed. */
export function buildBarangayCenterLocation(barangay, streetAddress = "", warning = "") {
  const selectedBarangay = getFallbackBarangay(barangay);
  if (!selectedBarangay) {
    return null;
  }
  const center = getBarangayCenter(selectedBarangay);
  return buildCoordinateLocation(
    center.latitude,
    center.longitude,
    selectedBarangay,
    String(streetAddress || "").trim() || `Barangay ${selectedBarangay}, Tayabas City`,
    "barangay",
    warning,
  );
}

export async function fetchBarangayCenter(barangay) {
  if (!OPENROUTESERVICE_API_KEY) {
    return null;
  }
  try {
    const query = buildTayabasLocationQuery(barangay, "");
    const response = await fetch(
      `${OPENROUTESERVICE_SEARCH_URL}?text=${encodeURIComponent(query)}&boundary.country=PH&focus.point.lon=${encodeURIComponent(TAYABAS_CITY_CENTER.longitude)}&focus.point.lat=${encodeURIComponent(TAYABAS_CITY_CENTER.latitude)}&size=1&layers=locality,neighbourhood,address`,
      { method: "GET", headers: getOpenRouteServiceHeaders() },
    );
    if (!response.ok) {
      return null;
    }
    const data = await response.json();
    const feature = Array.isArray(data?.features) ? data.features[0] : null;
    const coordinates = Array.isArray(feature?.geometry?.coordinates) ? feature.geometry.coordinates : [];
    const latitude = Number(Number(coordinates[1]).toFixed(7));
    const longitude = Number(Number(coordinates[0]).toFixed(7));
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      return null;
    }
    return { barangay, latitude, longitude };
  } catch (error) {
    return null;
  }
}

export async function getTayabasBarangayCenters() {
  if (!tayabasBarangayCentersPromise) {
    tayabasBarangayCentersPromise = Promise.resolve(BARANGAYS.map(getBarangayCenter));
  }
  return tayabasBarangayCentersPromise;
}

export async function getNearestBarangayFromCoordinates(latitude, longitude) {
  const boundaryBarangay = getBarangayFromBoundary(latitude, longitude);
  if (boundaryBarangay) {
    return boundaryBarangay;
  }
  const centers = await getTayabasBarangayCenters();
  let nearest = null;
  centers.forEach((center) => {
    const distanceKm = haversineDistanceKm(latitude, longitude, center.latitude, center.longitude);
    if (distanceKm == null) {
      return;
    }
    if (!nearest || distanceKm < nearest.distanceKm) {
      nearest = { barangay: center.barangay, distanceKm };
    }
  });
  return nearest?.barangay || "";
}

const GEOLOCATION_FAILURE_MESSAGES = {
  unsupported: "This browser can't share your location. Pin the spot on the map instead.",
  1: "Location access is blocked for this site. Allow it in your browser or phone settings, or pin the spot on the map instead.",
  2: "Your device couldn't work out where it is. Pin the spot on the map instead.",
  3: "Finding your location took too long. Try again, or pin the spot on the map instead.",
};

export const OUTSIDE_TAYABAS_GPS_MESSAGE =
  "Your device places you outside Tayabas City, so its location wasn't used. GawaGo serves Tayabas City only: pin the spot on the map instead.";

/**
 * Asks the browser for the device's position. Resolves to
 * `{ coordinates, message }`: coordinates (with accuracy in metres) when a
 * fix was given, otherwise null and a message saying why -- blocked access,
 * no fix, or a timeout each need a different next step, and a silent
 * failure used to look like the button did nothing.
 */
export function requestCurrentCoordinates() {
  if (typeof window === "undefined" || !window.navigator?.geolocation) {
    return Promise.resolve({ coordinates: null, message: GEOLOCATION_FAILURE_MESSAGES.unsupported });
  }
  return new Promise((resolve) => {
    window.navigator.geolocation.getCurrentPosition(
      (position) => resolve({
        coordinates: {
          latitude: Number(position.coords.latitude.toFixed(7)),
          longitude: Number(position.coords.longitude.toFixed(7)),
          accuracy: Number(position.coords.accuracy || 0),
        },
        message: "",
      }),
      (error) => resolve({
        coordinates: null,
        message: GEOLOCATION_FAILURE_MESSAGES[error?.code] || GEOLOCATION_FAILURE_MESSAGES[2],
      }),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  });
}

export async function getCurrentCoordinates() {
  const { coordinates } = await requestCurrentCoordinates();
  return coordinates;
}

/** A warning for a device fix too coarse to trust without a look, or "". */
export function describeGpsAccuracy(accuracy) {
  const meters = Number(accuracy);
  if (!Number.isFinite(meters) || meters <= LOW_GPS_ACCURACY_METERS) {
    return "";
  }
  return `Your device's location is only accurate to about ${Math.round(meters)} m. Check the pin and drag it to the exact spot if it's off.`;
}

/**
 * Describes a point the person chose (a pin or a device fix). The point
 * itself is kept exactly: the geocoder only supplies a street name, and its
 * snapped coordinate used to replace the pin, moving it up to 1 km to the
 * nearest mapped street. The label always names the barangay.
 */
export async function reverseGeocodeCoordinates(latitude, longitude, fallbackBarangay = "", fallbackStreetAddress = "") {
  const pointLatitude = Number(Number(latitude).toFixed(7));
  const pointLongitude = Number(Number(longitude).toFixed(7));
  const pointBarangay = await getNearestBarangayFromCoordinates(pointLatitude, pointLongitude);
  // "Barangay Lita, Tayabas City" is the form's own filler, and is wrong
  // once the pin is in another barangay.
  const typedStreetAddress = isAutoFilledStreetAddress(fallbackStreetAddress) ? "" : String(fallbackStreetAddress).trim();
  const fromCoordinates = (warning) =>
    buildCoordinateLocation(
      pointLatitude,
      pointLongitude,
      pointBarangay || fallbackBarangay,
      typedStreetAddress || formatCoordinateAddress(pointLatitude, pointLongitude),
      "device",
      warning,
    );
  if (!OPENROUTESERVICE_API_KEY) {
    return fromCoordinates("");
  }
  let data = null;
  try {
    const response = await fetch(
      `${OPENROUTESERVICE_REVERSE_URL}?point.lon=${encodeURIComponent(pointLongitude)}&point.lat=${encodeURIComponent(pointLatitude)}&size=1&layers=address,street,venue`,
      { method: "GET", headers: getOpenRouteServiceHeaders() },
    );
    if (!response.ok) {
      return fromCoordinates("");
    }
    data = await response.json();
  } catch (error) {
    return fromCoordinates("");
  }
  const feature = Array.isArray(data?.features) ? data.features[0] : null;
  if (!feature) {
    return fromCoordinates("");
  }
  const properties = feature.properties || {};
  const normalized = normalizeGeocodedAddress({
    label: properties.label,
    neighbourhood: properties.neighbourhood,
    borough: properties.borough,
    suburb: properties.suburb,
    quarter: properties.quarter,
    locality: properties.locality,
    county: properties.county,
    house_number: properties.housenumber,
    street: properties.street,
    name: properties.name,
  }, "", "");
  // The barangay comes from where the point is; the geocoder's text only
  // names one when it sits in the label, and often names none.
  const barangay = getFallbackBarangay(
    pointBarangay || findTayabasBarangayFromText(properties.label || "") || fallbackBarangay,
  );
  const streetAddress = normalized.streetAddress || typedStreetAddress || formatCoordinateAddress(pointLatitude, pointLongitude);
  return {
    latitude: pointLatitude,
    longitude: pointLongitude,
    barangay,
    streetAddress,
    locationLabel: formatLocation(barangay, streetAddress),
    mapUrl: buildMapPreviewUrl(pointLatitude, pointLongitude),
    source: "device",
  };
}

/**
 * Places a typed address. Only a street-level answer inside the city and
 * near the chosen barangay is used; anything vaguer falls back to that
 * barangay's centre, with a warning saying so. The label is always the
 * barangay and the street as typed -- the geocoder's own label is often just
 * "Tayabas, QZ, Philippines". Returns null only when no barangay was chosen
 * and the address could not be placed.
 */
export async function geocodeAddressLocation(barangay, streetAddress) {
  const selectedBarangay = String(barangay || "").trim() ? getFallbackBarangay(barangay) : "";
  const selectedStreetAddress = String(streetAddress || "").trim();
  const barangayFallback = (warning) => buildBarangayCenterLocation(selectedBarangay, selectedStreetAddress, warning);
  const notPlacedWarning = selectedBarangay
    ? `We couldn't find that street on the map, so the centre of ${selectedBarangay} is used. Pin your exact spot for accurate distances.`
    : "";
  if (!selectedStreetAddress || isAutoFilledStreetAddress(selectedStreetAddress)) {
    return barangayFallback("");
  }
  if (!OPENROUTESERVICE_API_KEY) {
    return barangayFallback(notPlacedWarning);
  }
  let data = null;
  try {
    const query = buildTayabasLocationQuery(selectedBarangay, selectedStreetAddress);
    const response = await fetch(
      `${OPENROUTESERVICE_SEARCH_URL}?text=${encodeURIComponent(query)}&boundary.country=PH&focus.point.lon=${encodeURIComponent(TAYABAS_CITY_CENTER.longitude)}&focus.point.lat=${encodeURIComponent(TAYABAS_CITY_CENTER.latitude)}&size=1&layers=address,street,venue`,
      { method: "GET", headers: getOpenRouteServiceHeaders() },
    );
    if (!response.ok) {
      return barangayFallback(notPlacedWarning);
    }
    data = await response.json();
  } catch (error) {
    return barangayFallback(notPlacedWarning);
  }
  const feature = Array.isArray(data?.features) ? data.features[0] : null;
  const coordinates = Array.isArray(feature?.geometry?.coordinates) ? feature.geometry.coordinates : [];
  const resolvedLatitude = Number(Number(coordinates[1]).toFixed(7));
  const resolvedLongitude = Number(Number(coordinates[0]).toFixed(7));
  const layer = String(feature?.properties?.layer || "");
  if (
    !feature ||
    !PRECISE_GEOCODE_LAYERS.has(layer) ||
    !Number.isFinite(resolvedLatitude) ||
    !Number.isFinite(resolvedLongitude) ||
    !isInsideTayabasCity(resolvedLatitude, resolvedLongitude)
  ) {
    return barangayFallback(notPlacedWarning);
  }
  const resolvedBarangay = selectedBarangay || (await getNearestBarangayFromCoordinates(resolvedLatitude, resolvedLongitude));
  if (selectedBarangay) {
    const center = getBarangayCenter(selectedBarangay);
    const offsetKm = haversineDistanceKm(resolvedLatitude, resolvedLongitude, center.latitude, center.longitude);
    if (offsetKm == null || offsetKm > MAX_GEOCODE_DISTANCE_FROM_BARANGAY_KM) {
      return barangayFallback(notPlacedWarning);
    }
  }
  return {
    latitude: resolvedLatitude,
    longitude: resolvedLongitude,
    barangay: resolvedBarangay,
    streetAddress: selectedStreetAddress,
    locationLabel: formatLocation(resolvedBarangay, selectedStreetAddress),
    mapUrl: buildMapPreviewUrl(resolvedLatitude, resolvedLongitude),
    source: "address",
    warning: "",
  };
}

/** Where a typed address is, for forms without a pin (household sign-up). */
export async function resolveLocationCoordinates(barangay, streetAddress) {
  return geocodeAddressLocation(barangay, streetAddress);
}

/** The one "inside Tayabas" check: the city boundary, not a bounding box
 * (any box around the city also takes in Lucena, Lucban and Sariaya). */
export function isWithinTayabasBounds(latitude, longitude) {
  return isInsideTayabasCity(latitude, longitude);
}
