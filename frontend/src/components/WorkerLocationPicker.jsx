import React, { useEffect, useRef, useState } from "react";
import { TAYABAS_CITY_CENTER } from "../constants/appConstants";
import {
  describeGpsAccuracy,
  isAutoFilledStreetAddress,
  OUTSIDE_TAYABAS_GPS_MESSAGE,
  requestCurrentCoordinates,
  reverseGeocodeCoordinates,
} from "../utils/locationServices";
import { getBarangayCenter } from "../utils/locationUtils";
import { applyTwoFingerPan } from "../utils/mapGestures";
import { frameMapToTayabas, isInsideTayabasCity } from "../utils/tayabasMapFrame";

const OUTSIDE_TAYABAS_MESSAGE = "GawaGo serves Tayabas City only. Please pin a spot inside the red boundary.";

export default function WorkerLocationPicker({ form, setForm, loadLeafletAssets, compact = false, error = "" }) {
  const mapNodeRef = useRef(null);
  const mapRef = useRef(null);
  const markerRef = useRef(null);
  const [manualMode, setManualMode] = useState(false);
  const [warning, setWarning] = useState("");
  const [locating, setLocating] = useState(false);
  const hasCoordinates = form?.latitude != null && form?.longitude != null;

  // The point the worker chose is kept exactly; the lookup only names it. A
  // street the worker typed stays, and the barangay follows the pin, with a
  // note when that changes what they had picked.
  const resolvePoint = async (latitude, longitude, source = "manual", accuracy = null) => {
    let location = null;
    try {
      location = await reverseGeocodeCoordinates(latitude, longitude, form.barangay, form.streetAddress);
    } catch {
      location = null;
    }
    const notes = [];
    if (location?.barangay && form.barangay && location.barangay !== form.barangay) {
      notes.push(`The pin is in ${location.barangay}, so your barangay was changed from ${form.barangay}.`);
    }
    if (source === "device") {
      const accuracyNote = describeGpsAccuracy(accuracy);
      if (accuracyNote) notes.push(accuracyNote);
    }
    setForm((prev) => {
      const keepTypedStreet = !isAutoFilledStreetAddress(prev.streetAddress);
      const barangay = location?.barangay || prev.barangay;
      const streetAddress = keepTypedStreet ? prev.streetAddress : location?.streetAddress || prev.streetAddress;
      return {
        ...prev,
        barangay,
        streetAddress,
        latitude: Number(Number(latitude).toFixed(7)),
        longitude: Number(Number(longitude).toFixed(7)),
        locationLabel: [barangay, String(streetAddress || "").trim()].filter(Boolean).join(", "),
        locationSource: source,
        locationWarning: notes.join(" "),
        locationAccuracy: source === "device" && accuracy ? accuracy : "",
      };
    });
  };

  const useCurrentLocation = async () => {
    setLocating(true);
    try {
      const { coordinates, message } = await requestCurrentCoordinates();
      if (!coordinates) {
        setWarning(message);
        return;
      }
      if (!isInsideTayabasCity(coordinates.latitude, coordinates.longitude)) {
        setWarning(OUTSIDE_TAYABAS_GPS_MESSAGE);
        return;
      }
      setWarning("");
      await resolvePoint(coordinates.latitude, coordinates.longitude, "device", coordinates.accuracy);
    } finally {
      setLocating(false);
    }
  };

  useEffect(() => {
    let cancelled = false;
    async function renderMap() {
      if (!mapNodeRef.current || typeof loadLeafletAssets !== "function") {
        return;
      }
      const L = await loadLeafletAssets();
      if (cancelled || !L) {
        return;
      }
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
      }
      const center = hasCoordinates
        ? [Number(form.latitude), Number(form.longitude)]
        : form?.barangay
          ? [getBarangayCenter(form.barangay).latitude, getBarangayCenter(form.barangay).longitude]
          : [TAYABAS_CITY_CENTER.latitude, TAYABAS_CITY_CENTER.longitude];
      const map = L.map(mapNodeRef.current, {
        zoomControl: false,
        scrollWheelZoom: true,
        dragging: true,
        touchZoom: true,
        tap: false,
      }).setView(center, hasCoordinates ? 15 : form?.barangay ? 14 : 12);
      mapRef.current = map;
      applyTwoFingerPan(map);
      const frame = frameMapToTayabas(map, L);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: "&copy; OpenStreetMap contributors",
      }).addTo(map);
      // A pin dragged out of the city goes back to where the drag started.
      const placeDraggableMarker = (point) => {
        const marker = L.marker(point, { draggable: true }).addTo(map);
        let dragStartPoint = null;
        marker.on("dragstart", () => {
          dragStartPoint = marker.getLatLng();
        });
        marker.on("dragend", async () => {
          const dropped = marker.getLatLng();
          if (!isInsideTayabasCity(dropped.lat, dropped.lng)) {
            if (dragStartPoint) {
              marker.setLatLng(dragStartPoint);
            }
            setWarning(OUTSIDE_TAYABAS_MESSAGE);
            return;
          }
          setWarning("");
          await resolvePoint(dropped.lat, dropped.lng, "manual");
        });
        return marker;
      };
      if (hasCoordinates) {
        // An older saved pin may sit outside the city; keep it in view.
        frame.includePoints([center]);
        markerRef.current = placeDraggableMarker(center);
      }
      map.on("click", async (event) => {
        if (!manualMode) {
          return;
        }
        if (!isInsideTayabasCity(event.latlng.lat, event.latlng.lng)) {
          setWarning(OUTSIDE_TAYABAS_MESSAGE);
          return;
        }
        setWarning("");
        if (markerRef.current) {
          markerRef.current.remove();
        }
        markerRef.current = placeDraggableMarker([event.latlng.lat, event.latlng.lng]);
        await resolvePoint(event.latlng.lat, event.latlng.lng, "manual");
      });
    }
    renderMap();
    return () => {
      cancelled = true;
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
      }
    };
  }, [form?.barangay, form?.latitude, form?.longitude, hasCoordinates, loadLeafletAssets, manualMode]);

  const note = warning || form?.locationWarning;
  return (
    <div
      className={`worker-location-picker ${compact ? "compact" : ""}${error ? " is-invalid" : ""}`}
      data-field="location"
      tabIndex={-1}
      aria-invalid={error ? "true" : undefined}
      aria-describedby={error ? "register-error-location" : undefined}
    >
      <div className="worker-location-picker-head">
        <strong>Exact Worker Location <span className="required-mark" aria-hidden="true">*</span></strong>
        <span>{hasCoordinates ? "Location pinned" : "Pin required"}</span>
      </div>
      <div className="worker-location-picker-map" ref={mapNodeRef} />
      <div className="worker-location-picker-actions">
        <button className="btn btn-primary btn-sm" type="button" onClick={useCurrentLocation} disabled={locating}>
          {locating ? "Finding your location..." : "Use My Current Location"}
        </button>
        <button
          className={`btn btn-outline-secondary btn-sm ${manualMode ? "active" : ""}`}
          type="button"
          onClick={() => setManualMode((prev) => !prev)}
        >
          {manualMode ? "Click the Map to Pin" : "Pin on Map Manually"}
        </button>
      </div>
      <p className="worker-location-picker-note">
        {hasCoordinates
          ? `Pinned at ${form.latitude}, ${form.longitude}. Drag the pin to adjust it.`
          : "Use your current location or pin the map. Households see your distance from this point."}
      </p>
      {error && (
        <div className="invalid-feedback d-block" id="register-error-location">{error}</div>
      )}
      {note && <p className="worker-location-picker-warning">{note}</p>}
    </div>
  );
}
