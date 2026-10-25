import React, { useEffect, useRef, useState } from "react";
import { TAYABAS_CITY_CENTER } from "../constants/appConstants";
import { buildCoordinateLocation, getCurrentCoordinates, reverseGeocodeCoordinates } from "../utils/locationServices";
import { getBarangayCenter } from "../utils/locationUtils";
import { applyTwoFingerPan } from "../utils/mapGestures";
import { frameMapToTayabas, isInsideTayabasCity } from "../utils/tayabasMapFrame";

const OUTSIDE_TAYABAS_MESSAGE = "GawaGo serves Tayabas City only. Please pin a spot inside the red boundary.";

export default function WorkerLocationPicker({ form, setForm, loadLeafletAssets, compact = false }) {
  const mapNodeRef = useRef(null);
  const mapRef = useRef(null);
  const markerRef = useRef(null);
  const [manualMode, setManualMode] = useState(false);
  const [warning, setWarning] = useState("");
  const hasCoordinates = form?.latitude != null && form?.longitude != null;

  const updateFormFromLocation = (location, source = "manual") => {
    if (!location?.latitude || !location?.longitude) {
      return;
    }
    setForm((prev) => ({
      ...prev,
      barangay: location.barangay || prev.barangay,
      streetAddress: location.streetAddress || prev.streetAddress,
      latitude: location.latitude,
      longitude: location.longitude,
      locationLabel: location.locationLabel || "",
      locationSource: source,
      locationWarning: location.warning || "",
      locationAccuracy: location.accuracy || "",
    }));
  };

  const resolvePoint = async (latitude, longitude, source = "manual") => {
    let location = null;
    try {
      location = await reverseGeocodeCoordinates(latitude, longitude, form.barangay, form.streetAddress);
    } catch {
      location = null;
    }
    updateFormFromLocation(
      location || buildCoordinateLocation(latitude, longitude, form.barangay, form.streetAddress, source),
      source,
    );
  };

  const useCurrentLocation = async () => {
    const coordinates = await getCurrentCoordinates();
    if (!coordinates) {
      setWarning("Browser location is unavailable. Pin your location manually on the map.");
      return;
    }
    await resolvePoint(coordinates.latitude, coordinates.longitude, "device");
    setWarning("");
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
      }).setView(center, hasCoordinates ? 15 : 12);
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

  return (
    <div className={`worker-location-picker ${compact ? "compact" : ""}`}>
      <div className="worker-location-picker-head">
        <strong>Exact Worker Location</strong>
        <span>{hasCoordinates ? "Location ready" : "Pin required for accurate distance"}</span>
      </div>
      <div className="worker-location-picker-map" ref={mapNodeRef} />
      <div className="worker-location-picker-actions">
        <button className="btn btn-primary btn-sm" type="button" onClick={useCurrentLocation}>
          Use My Current Location
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
          ? `Saved coordinates: ${form.latitude}, ${form.longitude}`
          : "Use browser location or click the map so households see accurate distance and routes."}
      </p>
      {(warning || form?.locationWarning) && (
        <p className="worker-location-picker-warning">{warning || form.locationWarning}</p>
      )}
    </div>
  );
}
