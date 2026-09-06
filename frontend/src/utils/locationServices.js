import {
  BARANGAYS,
  GMAIL_ADDRESS_PATTERN,
  OPENROUTESERVICE_API_KEY,
  OPENROUTESERVICE_REVERSE_URL,
  OPENROUTESERVICE_SEARCH_URL,
  PHILIPPINES_MAP_BOUNDS,
  PHILIPPINES_MAP_CENTER,
  TAYABAS_CITY_CENTER,
  TAYABAS_MAP_BOUNDS,
} from "../constants/appConstants";
import { formatLocation } from "./formatters";
import { getBarangayFromBoundary } from "./geofenceUtils";
import { findTayabasBarangayFromText, getBarangayCenter, getFallbackBarangay, normalizeBarangayName, parseLocationLabel } from "./locationUtils";

let tayabasBarangayCentersPromise = null;

export function isValidGmailAddress(email) {
  return GMAIL_ADDRESS_PATTERN.test(String(email || "").trim());
}

export function buildTayabasLocationQuery(barangay, streetAddress) {
  return [streetAddress, barangay, "Tayabas City", "Quezon", "Philippines"].filter(Boolean).join(", ");
}

export function formatCoordinateAddress(latitude, longitude) {
  const lat = Number(Number(latitude).toFixed(5));
  const lon = Number(Number(longitude).toFixed(5));
  return `Tayabas City coordinates ${lat}, ${lon}`;
}

export function isGenericAddressPart(part) {
  return /^(barangay\s+)?(tayabas|tayabas city|quezon|philippines|poblacion)$/i.test(String(part || "").trim());
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
  const numericLatitude = Number(latitude);
  const numericLongitude = Number(longitude);
  const resolvedLatitude = Number((Number.isFinite(numericLatitude) ? numericLatitude : PHILIPPINES_MAP_CENTER.latitude).toFixed(7));
  const resolvedLongitude = Number((Number.isFinite(numericLongitude) ? numericLongitude : PHILIPPINES_MAP_CENTER.longitude).toFixed(7));
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

export function buildTayabasOnlyLocation(latitude, longitude, fallbackBarangay = "", fallbackStreetAddress = "", source = "address", warning = "") {
  const selectedBarangay = getFallbackBarangay(fallbackBarangay);
  const boundedPoint = isWithinTayabasBounds(latitude, longitude)
    ? { latitude: Number(latitude), longitude: Number(longitude) }
    : getBarangayCenter(selectedBarangay || "Poblacion");
  return buildCoordinateLocation(
    boundedPoint.latitude,
    boundedPoint.longitude,
    selectedBarangay || getFallbackBarangay("Poblacion"),
    fallbackStreetAddress || `Barangay ${selectedBarangay || "Poblacion"}, Tayabas City`,
    source,
    warning || "Location is limited to Tayabas City for GawaGo job matching.",
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

export function getCurrentCoordinates() {
  if (typeof window === "undefined" || !window.navigator?.geolocation) {
    return Promise.resolve(null);
  }
  return new Promise((resolve) => {
    window.navigator.geolocation.getCurrentPosition(
      (position) => resolve({
        latitude: Number(position.coords.latitude.toFixed(7)),
        longitude: Number(position.coords.longitude.toFixed(7)),
        accuracy: Number(position.coords.accuracy || 0),
      }),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  });
}

export async function reverseGeocodeCoordinates(latitude, longitude, fallbackBarangay = "", fallbackStreetAddress = "") {
  const coordinateStreetAddress = formatCoordinateAddress(latitude, longitude);
  if (!OPENROUTESERVICE_API_KEY) {
    return buildCoordinateLocation(latitude, longitude, await getNearestBarangayFromCoordinates(latitude, longitude), coordinateStreetAddress, "device", "Reverse geocoding is unavailable right now, so the form used the map coordinates as the job address.");
  }
  let data = null;
  try {
    const response = await fetch(
      `${OPENROUTESERVICE_REVERSE_URL}?point.lon=${encodeURIComponent(longitude)}&point.lat=${encodeURIComponent(latitude)}&size=1&layers=address,street,locality,neighbourhood`,
      { method: "GET", headers: getOpenRouteServiceHeaders() },
    );
    if (!response.ok) {
      return buildCoordinateLocation(latitude, longitude, await getNearestBarangayFromCoordinates(latitude, longitude), coordinateStreetAddress, "device", "Reverse geocoding could not find a precise address, so the form used the map coordinates.");
    }
    data = await response.json();
  } catch (error) {
    return buildCoordinateLocation(latitude, longitude, await getNearestBarangayFromCoordinates(latitude, longitude), coordinateStreetAddress, "device", "Reverse geocoding could not be reached, so the form used the map coordinates.");
  }
  const feature = Array.isArray(data?.features) ? data.features[0] : null;
  if (!feature) {
    return buildCoordinateLocation(latitude, longitude, await getNearestBarangayFromCoordinates(latitude, longitude), coordinateStreetAddress, "device", "Reverse geocoding could not find a precise address, so the form used the map coordinates.");
  }
  const coordinates = Array.isArray(feature?.geometry?.coordinates) ? feature.geometry.coordinates : [];
  const properties = feature?.properties || {};
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
  }, "", coordinateStreetAddress);
  const resolvedLatitude = Number(Number(coordinates[1] ?? latitude).toFixed(7));
  const resolvedLongitude = Number(Number(coordinates[0] ?? longitude).toFixed(7));
  const textBarangay = findTayabasBarangayFromText(normalized.barangay || properties.label || "");
  const nearestBarangay = textBarangay ? "" : await getNearestBarangayFromCoordinates(resolvedLatitude, resolvedLongitude);
  const barangay = getFallbackBarangay(textBarangay || nearestBarangay || normalized.barangay || properties.label);
  const streetAddress = normalized.streetAddress || formatCoordinateAddress(resolvedLatitude, resolvedLongitude);
  return {
    latitude: resolvedLatitude,
    longitude: resolvedLongitude,
    barangay,
    streetAddress,
    locationLabel: properties.label || formatLocation(barangay, streetAddress),
    mapUrl: buildMapPreviewUrl(resolvedLatitude, resolvedLongitude),
    source: "device",
  };
}

export async function geocodeAddressLocation(barangay, streetAddress) {
  const requestedBarangay = String(barangay || "").trim();
  const selectedBarangay = requestedBarangay ? getFallbackBarangay(requestedBarangay) : "";
  const selectedStreetAddress = String(streetAddress || "").trim();
  if (selectedBarangay && !selectedStreetAddress) {
    const barangayCenter = getBarangayCenter(selectedBarangay);
    return buildCoordinateLocation(
      barangayCenter.latitude,
      barangayCenter.longitude,
      selectedBarangay,
      `Barangay ${selectedBarangay}, Tayabas City`,
      "barangay",
    );
  }
  if (!OPENROUTESERVICE_API_KEY) {
    if (!selectedBarangay) {
      return null;
    }
    const barangayCenter = getBarangayCenter(selectedBarangay);
    return buildCoordinateLocation(
      barangayCenter.latitude,
      barangayCenter.longitude,
      selectedBarangay,
      selectedStreetAddress || `Barangay ${selectedBarangay}, Tayabas City`,
      "barangay",
      "Address geocoding is unavailable right now, so the barangay center was used.",
    );
  }
  const query = buildTayabasLocationQuery(barangay, streetAddress);
  if (!query) {
    return null;
  }
  const response = await fetch(
    `${OPENROUTESERVICE_SEARCH_URL}?text=${encodeURIComponent(query)}&boundary.country=PH&focus.point.lon=${encodeURIComponent(TAYABAS_CITY_CENTER.longitude)}&focus.point.lat=${encodeURIComponent(TAYABAS_CITY_CENTER.latitude)}&size=1&layers=address,street,locality,neighbourhood`,
    { method: "GET", headers: getOpenRouteServiceHeaders() },
  );
  if (!response.ok) {
    return null;
  }
  const data = await response.json();
  const feature = Array.isArray(data?.features) ? data.features[0] : null;
  if (!feature) {
    return null;
  }
  const coordinates = Array.isArray(feature.geometry?.coordinates) ? feature.geometry.coordinates : [];
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
  }, barangay, streetAddress);
  const resolvedLatitude = Number(Number(coordinates[1]).toFixed(7));
  const resolvedLongitude = Number(Number(coordinates[0]).toFixed(7));
  if (!Number.isFinite(resolvedLatitude) || !Number.isFinite(resolvedLongitude)) {
    return null;
  }
  const resultLabel = String(properties.label || "");
  if (!isWithinTayabasBounds(resolvedLatitude, resolvedLongitude) || !/\btayabas\b/i.test(resultLabel)) {
    const barangayCenter = getBarangayCenter(selectedBarangay || "Poblacion");
    return buildCoordinateLocation(
      barangayCenter.latitude,
      barangayCenter.longitude,
      selectedBarangay || "Poblacion",
      selectedStreetAddress || `Barangay ${selectedBarangay || "Poblacion"}, Tayabas City`,
      "barangay",
      "The address search returned a location outside Tayabas City, so the selected barangay center was used.",
    );
  }
  return {
    latitude: resolvedLatitude,
    longitude: resolvedLongitude,
    barangay: getFallbackBarangay(normalized.barangay || properties.label || barangay),
    streetAddress: normalized.streetAddress || streetAddress,
    locationLabel: properties.label || normalized.locationLabel || query,
    mapUrl: buildMapPreviewUrl(resolvedLatitude, resolvedLongitude),
    source: "address",
  };
}

export async function resolveLocationCoordinates(barangay, streetAddress, preferCurrentLocation = false) {
  const addressResult = await geocodeAddressLocation(barangay, streetAddress);
  if (preferCurrentLocation) {
    const browserCoordinates = await getCurrentCoordinates();
    if (browserCoordinates && isWithinTayabasBounds(browserCoordinates.latitude, browserCoordinates.longitude)) {
      const reverseResult = await reverseGeocodeCoordinates(browserCoordinates.latitude, browserCoordinates.longitude, barangay, streetAddress);
      if (reverseResult && addressResult) {
        const deviationKm = haversineDistanceKm(reverseResult.latitude, reverseResult.longitude, addressResult.latitude, addressResult.longitude);
        if (deviationKm != null && deviationKm > 1.2 && browserCoordinates.accuracy > 60) {
          return {
            ...reverseResult,
            source: "device",
            warning: `Device location differed from the entered address by ${deviationKm.toFixed(1)} km, so the shared location was used and the address fields were auto-filled from that pin.`,
            accuracy: browserCoordinates.accuracy,
          };
        }
      }
      if (reverseResult) {
        return {
          ...reverseResult,
          accuracy: browserCoordinates.accuracy,
        };
      }
      if (addressResult) {
        return {
          ...addressResult,
          source: "address",
          warning: "Browser geolocation was not precise enough, so the address-based map point was used instead.",
          accuracy: browserCoordinates.accuracy,
        };
      }
      return {
        ...buildCoordinateLocation(browserCoordinates.latitude, browserCoordinates.longitude, "", streetAddress, "device", "We captured your current location and used the coordinates as the approximate address."),
        accuracy: browserCoordinates.accuracy,
      };
    }
    if (browserCoordinates && addressResult) {
      return {
        ...addressResult,
        warning: "Your device location was outside Tayabas City, so the entered Tayabas address was used.",
        accuracy: browserCoordinates.accuracy,
      };
    }
  }
  return addressResult;
}

export function buildTayabasLatLngBounds(L) {
  return L.latLngBounds(
    [TAYABAS_MAP_BOUNDS.south, TAYABAS_MAP_BOUNDS.west],
    [TAYABAS_MAP_BOUNDS.north, TAYABAS_MAP_BOUNDS.east],
  );
}

export function isWithinTayabasBounds(latitude, longitude) {
  const numericLatitude = Number(latitude);
  const numericLongitude = Number(longitude);
  return Number.isFinite(numericLatitude)
    && Number.isFinite(numericLongitude)
    && numericLatitude >= TAYABAS_MAP_BOUNDS.south
    && numericLatitude <= TAYABAS_MAP_BOUNDS.north
    && numericLongitude >= TAYABAS_MAP_BOUNDS.west
    && numericLongitude <= TAYABAS_MAP_BOUNDS.east;
}

export function clampToTayabasBounds(latitude, longitude) {
  const numericLatitude = Number(latitude);
  const numericLongitude = Number(longitude);
  return {
    latitude: Math.min(Math.max(Number.isFinite(numericLatitude) ? numericLatitude : TAYABAS_CITY_CENTER.latitude, TAYABAS_MAP_BOUNDS.south), TAYABAS_MAP_BOUNDS.north),
    longitude: Math.min(Math.max(Number.isFinite(numericLongitude) ? numericLongitude : TAYABAS_CITY_CENTER.longitude, TAYABAS_MAP_BOUNDS.west), TAYABAS_MAP_BOUNDS.east),
  };
}
