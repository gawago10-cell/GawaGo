import React, { useEffect, useRef, useState } from "react";
import { applyTwoFingerPan } from "../utils/mapGestures";
import { frameMapToTayabas, isInsideTayabasCity } from "../utils/tayabasMapFrame";
import { isConfirmedJobPin } from "../hooks/useHouseholdJobLocation";

const OUTSIDE_TAYABAS_MESSAGE = "GawaGo serves Tayabas City only. Please pin a spot inside the red boundary.";

export default function HouseholdJobMapPanel({
  captureHouseholdJobLocation,
  householdJobCoordinates,
  householdJobLocationPreview,
  householdJobMapMode,
  householdJobMapRef,
  householdJobMapViewRef,
  loadLeafletAssets,
  placeHouseholdJobPin,
  setHouseholdJobMapMode,
}) {
  const mapContainerRef = useRef(null);
  const placeHouseholdJobPinRef = useRef(placeHouseholdJobPin);
  const [mapWarning, setMapWarning] = useState("");
  const pinConfirmed = isConfirmedJobPin(householdJobLocationPreview);
  const heading =
    householdJobLocationPreview?.source === "device"
      ? "Current Location"
      : householdJobLocationPreview?.source === "manual"
        ? "Pinned Job Site"
        : householdJobLocationPreview?.source === "barangay"
          ? "Barangay Centre (not the job site yet)"
          : "Tayabas City Map";
  const title = pinConfirmed
    ? "Check the job pin before posting"
    : householdJobMapMode === "manual"
      ? "Click the map where the job is"
      : householdJobLocationPreview
        ? "Move the pin to the job site"
        : "Pin the job site on the map";
  const hasCoordinates = householdJobCoordinates?.latitude != null && householdJobCoordinates?.longitude != null;
  const warning = mapWarning || householdJobLocationPreview?.warning || "";

  useEffect(() => {
    placeHouseholdJobPinRef.current = placeHouseholdJobPin;
  });

  useEffect(() => {
    let cancelled = false;
    const mapNode = mapContainerRef.current;

    async function renderMap() {
      if (!mapNode) {
        return;
      }
      try {
        setMapWarning("");
        const L = await loadLeafletAssets();
        if (cancelled || !L) {
          return;
        }
        if (householdJobMapRef.current) {
          householdJobMapRef.current.remove();
          householdJobMapRef.current = null;
        }
        const mapInstance = L.map(mapNode, {
          zoomControl: false,
          scrollWheelZoom: true,
          dragging: true,
          touchZoom: true,
          tap: false,
        });
        householdJobMapRef.current = mapInstance;
        mapInstance.dragging.enable();
        mapInstance.touchZoom.enable();
        applyTwoFingerPan(mapInstance);
        const frame = frameMapToTayabas(mapInstance, L);
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          attribution: "&copy; OpenStreetMap contributors",
        }).addTo(mapInstance);

        let marker = null;
        const syncMarker = async (latitude, longitude) => {
          if (marker) {
            marker.remove();
          }
          marker = L.marker([latitude, longitude], { draggable: true }).addTo(mapInstance);
          marker.dragging?.enable();
          let dragStartPoint = null;
          marker.on("dragstart", () => {
            dragStartPoint = marker.getLatLng();
          });
          marker.on("dragend", async () => {
            const draggedPoint = marker.getLatLng();
            if (!isInsideTayabasCity(draggedPoint.lat, draggedPoint.lng)) {
              if (dragStartPoint) {
                marker.setLatLng(dragStartPoint);
              }
              window.alert(OUTSIDE_TAYABAS_MESSAGE);
              return;
            }
            try {
              const nextLocation = await placeHouseholdJobPinRef.current(draggedPoint.lat, draggedPoint.lng, "manual", false);
              if (nextLocation?.latitude != null && nextLocation?.longitude != null) {
                marker.setLatLng([nextLocation.latitude, nextLocation.longitude]);
              }
            } catch (error) {
              window.alert("We could not update the dragged pin yet. Please try again.");
            }
          });
        };

        if (householdJobLocationPreview?.latitude != null && householdJobLocationPreview?.longitude != null) {
          if (householdJobMapViewRef.current.touched) {
            mapInstance.setView(householdJobMapViewRef.current.center, householdJobMapViewRef.current.zoom);
          } else {
            mapInstance.setView([householdJobLocationPreview.latitude, householdJobLocationPreview.longitude], 15);
          }
          frame.includePoints([[householdJobLocationPreview.latitude, householdJobLocationPreview.longitude]]);
          await syncMarker(householdJobLocationPreview.latitude, householdJobLocationPreview.longitude);
        } else if (householdJobMapViewRef.current.touched) {
          mapInstance.setView(householdJobMapViewRef.current.center, householdJobMapViewRef.current.zoom);
        } else {
          frame.showWholeCity();
        }

        mapInstance.on("moveend zoomend", () => {
          const center = mapInstance.getCenter();
          householdJobMapViewRef.current = {
            center: [center.lat, center.lng],
            zoom: mapInstance.getZoom(),
            touched: true,
          };
        });
        mapInstance.on("click", async (event) => {
          if (householdJobMapMode !== "manual") {
            return;
          }
          if (!isInsideTayabasCity(event.latlng.lat, event.latlng.lng)) {
            window.alert(OUTSIDE_TAYABAS_MESSAGE);
            return;
          }
          try {
            const nextLocation = await placeHouseholdJobPinRef.current(event.latlng.lat, event.latlng.lng, "manual", true);
            await syncMarker(nextLocation.latitude, nextLocation.longitude);
          } catch (error) {
            window.alert("We could not use that pin yet. Please try another nearby spot.");
          }
        });
      } catch (error) {
        if (!cancelled) {
          setMapWarning(
            "Interactive map could not be loaded right now. You can still use current location or typed address.",
          );
        }
      }
    }

    renderMap();

    return () => {
      cancelled = true;
      if (householdJobMapRef.current) {
        householdJobMapRef.current.remove();
        householdJobMapRef.current = null;
      }
    };
  }, [
    householdJobLocationPreview?.latitude,
    householdJobLocationPreview?.longitude,
    householdJobMapMode,
    loadLeafletAssets,
  ]);

  return (
    <div className="col-12 household-job-map-panel">
      <div className="household-job-map-card">
        <p className="household-job-map-eyebrow mb-2">{heading}</p>
        <h3 className="household-job-map-title mb-2">{title}</h3>
        <p className="small text-muted mb-2">
          {householdJobLocationPreview?.locationLabel ||
            "Choose the barangay, then pin the job site on the map or use your current location."}
        </p>
        <p className="small mb-2 household-job-map-coords">
          {pinConfirmed
            ? `Latitude: ${householdJobLocationPreview.latitude}, Longitude: ${householdJobLocationPreview.longitude}`
            : "No confirmed map pin yet."}
        </p>
        <p className="small mb-3 household-job-map-accuracy">
          {householdJobLocationPreview?.accuracy
            ? `Reported device accuracy: about ${Math.round(householdJobLocationPreview.accuracy)} meters`
            : householdJobMapMode === "manual"
              ? "Click or drag anywhere inside the red Tayabas City boundary to set the exact job location, then review the auto-filled address fields."
              : "Drag the pin, or turn on manual pinning and click the map, to set the exact job site."}
        </p>
        <div className="household-job-map-frame">
          <div
            className={`household-job-map-canvas ${householdJobMapMode === "manual" ? "manual-pin-active" : ""}`}
            ref={mapContainerRef}
          />
        </div>
        <div className="household-location-actions-panel">
          <div className="d-flex gap-2 flex-wrap">
            <button className="btn btn-primary btn-sm household-location-trigger" type="button" onClick={captureHouseholdJobLocation}>
              {hasCoordinates ? "Location Ready" : "Use My Current Location"}
            </button>
            <button
              className={`btn btn-outline-secondary btn-sm ${householdJobMapMode === "manual" ? "active" : ""}`}
              type="button"
              onClick={() => setHouseholdJobMapMode((prev) => (prev === "manual" ? "preview" : "manual"))}
            >
              {householdJobMapMode === "manual" ? "Click the Map to Pin" : "Pin on Map Manually"}
            </button>
          </div>
          <p className="form-text mb-0 household-location-helper">
            {householdJobMapMode === "manual"
              ? "Manual pin mode is active. Click on the map to place the exact job location."
              : hasCoordinates
                ? `Current coordinates saved for this job: ${householdJobCoordinates.latitude}, ${householdJobCoordinates.longitude}`
                : "A job needs a confirmed pin: use your current location, drag the pin, or pin it on the map."}
          </p>
        </div>
        {warning && <p className="small mb-2 household-job-map-warning">{warning}</p>}
        <p className="small text-muted mt-2 mb-0">
          Street names come from OpenRouteService; the map is OpenStreetMap.
        </p>
      </div>
    </div>
  );
}
