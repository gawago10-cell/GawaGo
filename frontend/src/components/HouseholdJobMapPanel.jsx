import React, { useEffect, useRef, useState } from "react";

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
  const heading =
    householdJobLocationPreview?.source === "device"
      ? "Current Location Preview"
      : householdJobLocationPreview?.source === "address"
        ? "Address-based Preview"
        : householdJobLocationPreview?.source === "manual"
          ? "Manual Pin Preview"
          : "Philippines Map Preview";
  const title = householdJobLocationPreview?.mapUrl
    ? "Check the saved job pin before posting"
    : householdJobMapMode === "manual"
      ? "Manual pin mode is active"
      : "The map opens on the Philippines, then drops a pin after location capture";
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
          marker.on("dragend", async () => {
            const draggedPoint = marker.getLatLng();
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
          await syncMarker(householdJobLocationPreview.latitude, householdJobLocationPreview.longitude);
        } else {
          mapInstance.setView(householdJobMapViewRef.current.center, householdJobMapViewRef.current.zoom);
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
            "Use your current location or complete the address fields to place the job on the map."}
        </p>
        <p className="small mb-2 household-job-map-coords">
          {householdJobLocationPreview?.latitude != null && householdJobLocationPreview?.longitude != null
            ? `Latitude: ${householdJobLocationPreview.latitude}, Longitude: ${householdJobLocationPreview.longitude}`
            : "No confirmed map pin yet."}
        </p>
        <p className="small mb-3 household-job-map-accuracy">
          {householdJobLocationPreview?.accuracy
            ? `Reported device accuracy: about ${Math.round(householdJobLocationPreview.accuracy)} meters`
            : householdJobMapMode === "manual"
              ? "Click or drag anywhere in the Philippines map to set the exact job location, then review the auto-filled address fields."
              : "Map opens at the Philippines by default and adds a pin after you confirm location."}
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
              ? "Manual pin mode is active. Click on the map to place the exact job location and auto-fill the address."
              : hasCoordinates
                ? `Current coordinates saved for this job: ${householdJobCoordinates.latitude}, ${householdJobCoordinates.longitude}`
                : "Capture your current browser location or pin the exact job location on the map."}
          </p>
        </div>
        {warning && <p className="small mb-2 household-job-map-warning">{warning}</p>}
        <p className="small text-muted mt-2 mb-0">
          Geocoding uses OpenRouteService, while the visual map preview is rendered with OpenStreetMap.
        </p>
      </div>
    </div>
  );
}
