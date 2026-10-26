import {
  describeGpsAccuracy,
  isAutoFilledStreetAddress,
  OUTSIDE_TAYABAS_GPS_MESSAGE,
  requestCurrentCoordinates,
} from "../utils/locationServices";
import { isInsideTayabasCity } from "../utils/tayabasMapFrame";

// A job's location is a pin the household confirmed: a device fix or a spot
// they chose on the map. Choosing a barangay only suggests a pin at its
// centre ("barangay" source), which posting does not accept on its own: a
// barangay centre can be kilometres from the job site, and matching uses a
// 1 km default radius.
export const CONFIRMED_JOB_PIN_SOURCES = new Set(["device", "manual"]);

export function isConfirmedJobPin(location) {
  return (
    location?.latitude != null &&
    location?.longitude != null &&
    CONFIRMED_JOB_PIN_SOURCES.has(location?.source)
  );
}

export function useHouseholdJobLocation({
  buildCoordinateLocation,
  buildMapPreviewUrl,
  formatCoordinateAddress,
  formatLocation,
  getBarangayCenter,
  getFallbackBarangay,
  getNearestBarangayFromCoordinates,
  householdJobBarangaySyncRef,
  householdJobForm,
  householdJobMapViewRef,
  reverseGeocodeCoordinates,
  setHouseholdJobCoordinates,
  setHouseholdJobForm,
  setHouseholdJobLocationPreview,
  setHouseholdJobMapMode,
}) {
  async function captureHouseholdJobLocation() {
    const { coordinates, message } = await requestCurrentCoordinates();
    if (!coordinates) {
      window.alert(message);
      return null;
    }
    if (!isInsideTayabasCity(coordinates.latitude, coordinates.longitude)) {
      window.alert(OUTSIDE_TAYABAS_GPS_MESSAGE);
      return null;
    }
    const resolvedLocation = await placeHouseholdJobPin(
      coordinates.latitude,
      coordinates.longitude,
      "device",
      false,
      coordinates.accuracy,
    );
    window.alert(resolvedLocation.warning || "Current location pinned. Check the pin, then post the job.");
    return resolvedLocation;
  }
  async function placeHouseholdJobPin(latitude, longitude, source = "manual", showSuccessMessage = false, accuracy = null) {
    let reverseResult = null;
    try {
      reverseResult = await reverseGeocodeCoordinates(
        latitude,
        longitude,
        householdJobForm.barangay,
        householdJobForm.streetAddress,
      );
    } catch {
      reverseResult = null;
    }
    // The chosen point is kept exactly; the lookup only names it.
    const pointLatitude = Number(Number(latitude).toFixed(7));
    const pointLongitude = Number(Number(longitude).toFixed(7));
    const pinBarangay =
      getFallbackBarangay(reverseResult?.barangay) ||
      getFallbackBarangay(await getNearestBarangayFromCoordinates(pointLatitude, pointLongitude)) ||
      getFallbackBarangay(householdJobForm.barangay);
    // A street the household typed stays; only the form's own filler is
    // replaced by the street at the pin.
    const keepTypedStreet = !isAutoFilledStreetAddress(householdJobForm.streetAddress);
    const resolvedStreetAddress = keepTypedStreet
      ? householdJobForm.streetAddress.trim()
      : reverseResult?.streetAddress || formatCoordinateAddress(pointLatitude, pointLongitude);
    const previousBarangay = getFallbackBarangay(householdJobForm.barangay);
    const warnings = [];
    if (previousBarangay && pinBarangay && previousBarangay !== pinBarangay) {
      warnings.push(`The pin is in ${pinBarangay}, so the barangay was changed from ${previousBarangay}.`);
    }
    if (source === "device") {
      const accuracyWarning = describeGpsAccuracy(accuracy);
      if (accuracyWarning) warnings.push(accuracyWarning);
    }
    const resolvedLocation = {
      latitude: pointLatitude,
      longitude: pointLongitude,
      barangay: pinBarangay,
      streetAddress: resolvedStreetAddress,
      locationLabel: formatLocation(pinBarangay, resolvedStreetAddress),
      mapUrl: buildMapPreviewUrl(pointLatitude, pointLongitude),
      source,
      accuracy: source === "device" ? accuracy : null,
      warning: warnings.join(" "),
    };
    setHouseholdJobCoordinates({
      latitude: resolvedLocation.latitude,
      longitude: resolvedLocation.longitude,
    });
    setHouseholdJobLocationPreview(resolvedLocation);
    setHouseholdJobForm((prev) => ({
      ...prev,
      barangay: pinBarangay || prev.barangay,
      streetAddress: resolvedStreetAddress,
    }));
    if (source !== "manual") {
      setHouseholdJobMapMode("preview");
    }
    if (showSuccessMessage) {
      window.alert(
        resolvedLocation.warning ||
          (source === "manual" ? "Job site pinned. Drag the pin to adjust it." : "Location updated."),
      );
    }
    return resolvedLocation;
  }
  /**
   * Moves the map to a barangay and suggests a pin at its centre. Used when
   * the household picks a barangay and when Post a Job opens with their
   * saved one, so the map starts where the job is rather than on the whole
   * city. `keepStreetAddress` keeps a saved street instead of the filler.
   */
  function syncHouseholdJobBarangayLocation(barangay, { keepStreetAddress = false } = {}) {
    const selectedBarangay = getFallbackBarangay(barangay);
    if (!selectedBarangay) {
      return null;
    }
    const syncId = householdJobBarangaySyncRef.current + 1;
    householdJobBarangaySyncRef.current = syncId;
    const barangayCenter = getBarangayCenter(selectedBarangay);
    const keptStreetAddress = keepStreetAddress ? String(householdJobForm.streetAddress || "").trim() : "";
    const suggestedLocation = buildCoordinateLocation(
      barangayCenter.latitude,
      barangayCenter.longitude,
      selectedBarangay,
      keptStreetAddress || `Barangay ${selectedBarangay}, Tayabas City`,
      "barangay",
      `The pin is at the centre of ${selectedBarangay}. Drag it to the job site, pin it on the map, or use your current location before posting.`,
    );
    setHouseholdJobCoordinates(null);
    setHouseholdJobLocationPreview(suggestedLocation);
    setHouseholdJobMapMode("preview");
    householdJobMapViewRef.current = {
      center: [suggestedLocation.latitude, suggestedLocation.longitude],
      zoom: 15,
      touched: false,
    };
    setHouseholdJobForm((prev) => ({
      ...prev,
      barangay: selectedBarangay,
      streetAddress: suggestedLocation.streetAddress,
    }));
    return suggestedLocation;
  }
  return {
    captureHouseholdJobLocation,
    placeHouseholdJobPin,
    syncHouseholdJobBarangayLocation,
  };
}
