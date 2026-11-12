import { BARANGAYS, BARANGAY_CENTERS, TAYABAS_CITY_CENTER } from "../constants/appConstants";

export function normalizeBarangayName(value) {
  const normalized = String(value || "").trim().replace(/^barangay\s+/i, "");
  if (!normalized) {
    return "";
  }
  return BARANGAYS.find((barangay) => barangay.toLowerCase() === normalized.toLowerCase()) || normalized;
}

export function findTayabasBarangayFromText(value) {
  const normalized = String(value || "").toLowerCase();
  if (!normalized) {
    return "";
  }
  return BARANGAYS.find((barangay) => {
    const escapedBarangay = barangay.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`(?:^|[^a-z])(?:barangay\\s+)?${escapedBarangay}(?:$|[^a-z])`, "i").test(normalized);
  }) || "";
}

/** The Tayabas barangay named in `value`, or "" when it names none. This
 * used to answer "Poblacion", which is not one of the city's barangays, so
 * an unmatched place was filed under a name no form offers and sat on the
 * town-centre coordinates. */
export function getFallbackBarangay(value = "") {
  const matchedBarangay = findTayabasBarangayFromText(value) || BARANGAYS.find((barangay) => barangay.toLowerCase() === String(value || "").trim().replace(/^barangay\s+/i, "").toLowerCase());
  return matchedBarangay || "";
}

export function getBarangayCenter(barangay) {
  const resolvedBarangay = getFallbackBarangay(barangay);
  return {
    barangay: resolvedBarangay,
    ...(BARANGAY_CENTERS[resolvedBarangay] || TAYABAS_CITY_CENTER),
  };
}

export function getNearestBarangay(latitude, longitude) {
  const numericLatitude = Number(latitude);
  const numericLongitude = Number(longitude);
  if (!Number.isFinite(numericLatitude) || !Number.isFinite(numericLongitude)) {
    return "";
  }
  let nearestBarangay = "";
  let nearestDistance = Number.POSITIVE_INFINITY;
  Object.entries(BARANGAY_CENTERS).forEach(([barangay, center]) => {
    const latitudeDifference = numericLatitude - Number(center.latitude);
    const longitudeDifference = numericLongitude - Number(center.longitude);
    const distance = latitudeDifference ** 2 + longitudeDifference ** 2;
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestBarangay = barangay;
    }
  });
  return nearestBarangay;
}

export function parseLocationLabel(locationLabel) {
  const parts = String(locationLabel || "").split(",").map((part) => part.trim()).filter(Boolean);
  const barangayIndex = parts.findIndex((part) => BARANGAYS.some((barangay) => barangay.toLowerCase() === part.replace(/^barangay\s+/i, "").trim().toLowerCase()));
  if (barangayIndex >= 0) {
    const barangay = normalizeBarangayName(parts[barangayIndex]);
    const streetParts = parts.filter((_, index) => index !== barangayIndex).filter((part) => !/^(tayabas|tayabas city|quezon|philippines)$/i.test(part));
    return {
      barangay,
      streetAddress: streetParts.join(", "),
    };
  }
  return {
    barangay: normalizeBarangayName(parts[0] || ""),
    streetAddress: parts.slice(1).join(", "),
  };
}

// Parts of a saved location label that name no street: the city, province
// and country, and "Poblacion", which older versions filed unmatched places
// under although no Tayabas barangay has that name.
const NOT_A_STREET = /^(tayabas|tayabas city|quezon|qz|philippines|poblacion)$/i;

/** The Tayabas barangay `value` names, spelled as the list spells it, or "". */
export function knownBarangay(value) {
  const normalized = String(value || "").trim().replace(/^barangay\s+/i, "").toLowerCase();
  return BARANGAYS.find((barangay) => barangay.toLowerCase() === normalized) || "";
}

/**
 * A profile's barangay and street from its saved location label. Unlike
 * parseLocationLabel, a first part that names no barangay is not taken as
 * one: "Poblacion, QZ, Philippines" showed "Poblacion" as the barangay, which
 * the profile's barangay list can't select, and "QZ, Philippines" as the
 * street. Such a profile reads as having no barangay until one is picked.
 */
export function parseProfileLocation(locationLabel) {
  const parsed = parseLocationLabel(locationLabel);
  const barangay = knownBarangay(parsed.barangay);
  if (barangay) {
    return { barangay, streetAddress: parsed.streetAddress };
  }
  const streetParts = String(locationLabel || "")
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part && !NOT_A_STREET.test(part));
  return { barangay: "", streetAddress: streetParts.join(", ") };
}
