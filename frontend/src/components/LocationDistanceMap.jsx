import React, { useEffect, useMemo, useRef, useState } from "react";
import { applyTwoFingerPan } from "../utils/mapGestures";

let leafletAssetsPromise = null;

function localFormatDistance(distanceKm) {
  const numericDistance = Number(distanceKm);
  if (!Number.isFinite(numericDistance) || numericDistance < 0) {
    return "Distance not available";
  }
  if (numericDistance < 1) {
    return `${Math.max(1, Math.round(numericDistance * 1000))} meters away`;
  }
  return `${numericDistance.toFixed(1)} km away`;
}

async function loadLeafletAssets() {
  if (typeof window === "undefined") {
    return null;
  }
  if (window.L) {
    return window.L;
  }
  if (!leafletAssetsPromise) {
    leafletAssetsPromise = new Promise((resolve, reject) => {
      if (!document.querySelector('link[data-leaflet-runtime="true"]')) {
        const stylesheet = document.createElement("link");
        stylesheet.rel = "stylesheet";
        stylesheet.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
        stylesheet.dataset.leafletRuntime = "true";
        document.head.appendChild(stylesheet);
      }
      const existingScript = document.querySelector('script[data-leaflet-runtime="true"]');
      if (existingScript) {
        existingScript.addEventListener("load", () => resolve(window.L), { once: true });
        existingScript.addEventListener("error", () => reject(new Error("Unable to load Leaflet map assets.")), {
          once: true,
        });
        return;
      }
      const script = document.createElement("script");
      script.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
      script.async = true;
      script.dataset.leafletRuntime = "true";
      script.onload = () => resolve(window.L);
      script.onerror = () => reject(new Error("Unable to load Leaflet map assets."));
      document.body.appendChild(script);
    });
  }
  return leafletAssetsPromise;
}

function createPinIcon(L, label, color, markerType) {
  return L.divIcon({
    className: `location-distance-pin location-distance-pin-${markerType}`,
    html: `
      <svg width="36" height="44" viewBox="0 0 36 44" role="img" aria-label="${label} location marker" xmlns="http://www.w3.org/2000/svg">
        <path d="M18 2C10.268 2 4 8.268 4 16c0 10 14 26 14 26S32 26 32 16C32 8.268 25.732 2 18 2z" fill="${color}"/>
        <circle cx="18" cy="16" r="8.5" fill="#fff"/>
        <text x="18" y="19.5" text-anchor="middle" font-size="11" font-weight="800" fill="${color}" font-family="Arial, Helvetica, sans-serif">${label}</text>
      </svg>
    `,
    iconSize: [36, 44],
    iconAnchor: [18, 44],
    popupAnchor: [0, -44],
  });
}

function buildCoordinatePoint(latitude, longitude) {
  const resolvedLatitude = Number(latitude);
  const resolvedLongitude = Number(longitude);
  const insideTayabas =
    resolvedLatitude >= 13.9 &&
    resolvedLatitude <= 14.11 &&
    resolvedLongitude >= 121.5 &&
    resolvedLongitude <= 121.73;
  if (!Number.isFinite(resolvedLatitude) || !Number.isFinite(resolvedLongitude) || !insideTayabas) {
    return null;
  }
  return { latitude: resolvedLatitude, longitude: resolvedLongitude };
}

function normalizeRoutePoints(routePoints) {
  return (Array.isArray(routePoints) ? routePoints : [])
    .map((point) => [Number(point?.[0]), Number(point?.[1])])
    .filter(
      ([latitude, longitude]) =>
        Number.isFinite(latitude) &&
        Number.isFinite(longitude) &&
        latitude >= 13.9 &&
        latitude <= 14.11 &&
        longitude >= 121.5 &&
        longitude <= 121.73,
    );
}

function createPopupContent(title, location, point) {
  const wrapper = document.createElement("div");
  const heading = document.createElement("strong");
  const address = document.createElement("div");
  const coordinates = document.createElement("small");
  heading.textContent = title;
  address.textContent = location || "Registered coordinates";
  coordinates.textContent = `${point[0].toFixed(6)}, ${point[1].toFixed(6)}`;
  wrapper.append(heading, address, coordinates);
  return wrapper;
}

function getMarkerConfig(markerType) {
  return markerType === "worker"
    ? { label: "W", color: "#E85D04", type: "worker" }
    : { label: "H", color: "#1565C0", type: "household" };
}

export default function LocationDistanceMap({
  userLatitude,
  userLongitude,
  targetLatitude,
  targetLongitude,
  userLocation = "User location",
  targetLocation = "Target location",
  userMarkerType = "household",
  targetMarkerType = "worker",
  distanceKm,
  routePoints = [],
  formatDistanceFn,
  onRouteDistanceChange,
}) {
  const mapNodeRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const [resolvedPoints, setResolvedPoints] = useState({
    user: buildCoordinatePoint(userLatitude, userLongitude),
    target: buildCoordinatePoint(targetLatitude, targetLongitude),
  });
  const [status, setStatus] = useState("loading");
  const [mapStatus, setMapStatus] = useState("idle");
  const routePointsKey = useMemo(() => JSON.stringify(Array.isArray(routePoints) ? routePoints : []), [routePoints]);
  const normalizedRoutePoints = useMemo(() => normalizeRoutePoints(routePoints), [routePointsKey]);

  useEffect(() => {
    let cancelled = false;
    async function resolvePoints() {
      const nextUser = buildCoordinatePoint(userLatitude, userLongitude);
      const nextTarget = buildCoordinatePoint(targetLatitude, targetLongitude);
      if (cancelled) {
        return;
      }
      setResolvedPoints({ user: nextUser, target: nextTarget });
      setStatus(nextUser && nextTarget ? "ready" : "missing");
    }
    resolvePoints();
    return () => {
      cancelled = true;
    };
  }, [userLatitude, userLongitude, targetLatitude, targetLongitude]);

  useEffect(() => {
    onRouteDistanceChange?.(distanceKm ?? null);
  }, [distanceKm, onRouteDistanceChange]);

  const resolvedDistanceKm = useMemo(() => {
    if (distanceKm !== null && distanceKm !== undefined && distanceKm !== "") {
      return Number(distanceKm);
    }
    return null;
  }, [distanceKm]);
  const hasRoadRoute = normalizedRoutePoints.length > 1 && distanceKm !== null && distanceKm !== undefined && distanceKm !== "";
  const distanceLabel = hasRoadRoute
    ? (formatDistanceFn || localFormatDistance)(resolvedDistanceKm)
    : "Driving route unavailable";

  useEffect(() => {
    let cancelled = false;
    async function renderMap() {
      const userPointReady =
        resolvedPoints.user &&
        Number.isFinite(Number(resolvedPoints.user.latitude)) &&
        Number.isFinite(Number(resolvedPoints.user.longitude));
      const targetPointReady =
        resolvedPoints.target &&
        Number.isFinite(Number(resolvedPoints.target.latitude)) &&
        Number.isFinite(Number(resolvedPoints.target.longitude));
      if (!mapNodeRef.current || !userPointReady || !targetPointReady) {
        return;
      }
      setMapStatus("loading");
      let mapRendered = false;
      const fallbackTimer = window.setTimeout(() => {
        if (!cancelled && !mapRendered) {
          setMapStatus("fallback");
        }
      }, 1800);
      try {
        const L = await loadLeafletAssets();
        if (cancelled || !L) {
          return;
        }
        if (mapInstanceRef.current) {
          mapInstanceRef.current.remove();
          mapInstanceRef.current = null;
        }
        const map = L.map(mapNodeRef.current, { zoomControl: true, scrollWheelZoom: true });
        mapInstanceRef.current = map;
        applyTwoFingerPan(map);
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          attribution: "&copy; OpenStreetMap contributors",
        }).addTo(map);
        const userPoint = [resolvedPoints.user.latitude, resolvedPoints.user.longitude];
        const targetPoint = [resolvedPoints.target.latitude, resolvedPoints.target.longitude];
        const boundsPoints = normalizedRoutePoints.length > 1 ? normalizedRoutePoints : [userPoint, targetPoint];
        const userMarker = getMarkerConfig(userMarkerType);
        const targetMarker = getMarkerConfig(targetMarkerType);
        const userIcon = createPinIcon(L, userMarker.label, userMarker.color, userMarker.type);
        const targetIcon = createPinIcon(L, targetMarker.label, targetMarker.color, targetMarker.type);
        L.marker(userPoint, { icon: userIcon })
          .addTo(map)
          .bindPopup(
            createPopupContent(
              userMarker.type === "household" ? "Job site" : "Worker location",
              userLocation,
              userPoint,
            ),
          );
        L.marker(targetPoint, { icon: targetIcon })
          .addTo(map)
          .bindPopup(
            createPopupContent(
              targetMarker.type === "worker" ? "Worker registered location" : "Household location",
              targetLocation,
              targetPoint,
            ),
          );
        if (normalizedRoutePoints.length > 1) {
          L.polyline(normalizedRoutePoints, {
            color: "#0d6efd",
            weight: 5,
            opacity: 0.95,
          }).addTo(map);
        }
        map.fitBounds(L.latLngBounds(boundsPoints).pad(0.28));
        window.setTimeout(() => {
          if (!cancelled && mapInstanceRef.current === map) {
            map.invalidateSize({ pan: false });
          }
        }, 0);
        mapRendered = true;
        window.clearTimeout(fallbackTimer);
        setMapStatus("ready");
      } catch (error) {
        window.clearTimeout(fallbackTimer);
        if (!cancelled) {
          setMapStatus("fallback");
        }
      }
    }
    renderMap();
    return () => {
      cancelled = true;
      if (mapInstanceRef.current) {
        mapInstanceRef.current.remove();
        mapInstanceRef.current = null;
      }
    };
  }, [
    resolvedPoints.user?.latitude,
    resolvedPoints.user?.longitude,
    resolvedPoints.target?.latitude,
    resolvedPoints.target?.longitude,
    routePointsKey,
    userLocation,
    targetLocation,
    userMarkerType,
    targetMarkerType,
  ]);

  return (
    <div className="location-distance-map">
      <div className="location-distance-map-canvas" ref={mapNodeRef}>
        {status === "loading" && <div className="location-distance-map-placeholder">Loading map...</div>}
        {status === "missing" && (
          <div className="location-distance-map-placeholder">Location coordinates unavailable.</div>
        )}
        {status === "ready" && mapStatus !== "ready" && (
          <div className="location-distance-fallback">
            <div className="location-distance-fallback-route">
              <span className="location-distance-fallback-pin user-pin">
                {getMarkerConfig(userMarkerType).label}
              </span>
              <span className="location-distance-fallback-line" />
              <span className="location-distance-fallback-pin target-pin">
                {getMarkerConfig(targetMarkerType).label}
              </span>
            </div>
            <div className="location-distance-fallback-label">
              <strong>{distanceLabel}</strong>
              <small>
                {mapStatus === "fallback"
                  ? "Map tiles unavailable. Driving route may be unavailable."
                  : "Preparing map view..."}
              </small>
            </div>
          </div>
        )}
      </div>
      <div className="location-distance-summary">
        <span>{distanceLabel}</span>
        <small>
          {hasRoadRoute ? "Driving route" : "No road route available"}:{" "}
          {userLocation || "Job site"} to {targetLocation || "worker location"}
        </small>
      </div>
    </div>
  );
}
