import React, { useEffect, useMemo, useRef, useState } from "react";
import { applyTwoFingerPan } from "../utils/mapGestures";
import { frameMapToTayabas } from "../utils/tayabasMapFrame";

function getHeatMapColor(value, maxValue) {
  if (!value) {
    return "#c8d3e8";
  }
  const intensity = maxValue ? value / maxValue : 0;
  if (intensity >= 0.75) {
    return "#dc3545";
  }
  if (intensity >= 0.5) {
    return "#fd7e14";
  }
  if (intensity >= 0.25) {
    return "#ffc107";
  }
  return "#20c997";
}

export default function SuperAdminHeatMap({ data, metricLabel, mapCenter, loadLeafletAssets }) {
  const mapNodeRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const initialCenter = mapCenter || { latitude: 12.8797, longitude: 121.774 };
  const mapViewRef = useRef({ center: [initialCenter.latitude, initialCenter.longitude], zoom: 6, touched: false });
  const [mapStatus, setMapStatus] = useState("loading");
  const heatMapData = Array.isArray(data) ? data : [];
  const maxValue = Math.max(...heatMapData.map((item) => item.value), 1);
  const rankedData = useMemo(
    () =>
      [...heatMapData]
        .filter((item) => item.value > 0)
        .sort((a, b) => b.value - a.value)
        .slice(0, 5),
    [heatMapData],
  );

  useEffect(() => {
    let cancelled = false;
    async function renderMap() {
      if (!mapNodeRef.current) {
        return;
      }
      if (typeof loadLeafletAssets !== "function") {
        setMapStatus("fallback");
        return;
      }
      setMapStatus("loading");
      try {
        const L = await loadLeafletAssets();
        if (cancelled || !L) {
          return;
        }
        if (mapInstanceRef.current) {
          mapInstanceRef.current.remove();
          mapInstanceRef.current = null;
        }
        const map = L.map(mapNodeRef.current, {
          zoomControl: true,
          scrollWheelZoom: true,
          dragging: true,
          touchZoom: true,
          tap: false,
        }).setView(mapViewRef.current.center, mapViewRef.current.zoom);
        mapInstanceRef.current = map;
        map.dragging.enable();
        map.touchZoom.enable();
        applyTwoFingerPan(map);
        const frame = frameMapToTayabas(map, L);
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          attribution: "&copy; OpenStreetMap contributors",
        }).addTo(map);
        const heatPoints = [];
        heatMapData.forEach((item) => {
          const color = getHeatMapColor(item.value, maxValue);
          const radius = item.value > 0 ? 350 + (item.value / maxValue) * 1400 : 180;
          const point = [item.latitude, item.longitude];
          if (item.value > 0) {
            heatPoints.push(point);
          }
          L.circle(point, {
            radius,
            color,
            fillColor: color,
            fillOpacity: item.value > 0 ? 0.42 : 0.12,
            weight: item.value > 0 ? 2 : 1,
          }).addTo(map).bindPopup(`
            <strong>${item.barangay}</strong><br />
            ${metricLabel}: ${item.value}<br />
            Jobs: ${item.jobs}<br />
            Workers: ${item.workers}<br />
            Pending verifications: ${item.pendingVerifications}
          `);
        });
        if (!mapViewRef.current.touched && heatPoints.length > 0) {
          map.fitBounds(L.latLngBounds(heatPoints).pad(0.28));
        } else if (!mapViewRef.current.touched) {
          frame.showWholeCity();
        }
        map.on("moveend zoomend", () => {
          const center = map.getCenter();
          mapViewRef.current = { center: [center.lat, center.lng], zoom: map.getZoom(), touched: true };
        });
        setMapStatus("ready");
      } catch (error) {
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
  }, [heatMapData, maxValue, metricLabel, loadLeafletAssets]);

  return (
    <div className="analytics-heatmap-layout">
      <div className="analytics-heatmap-map" ref={mapNodeRef}>
        {mapStatus !== "ready" && (
          <div className="analytics-heatmap-fallback">
            {mapStatus === "fallback"
              ? "Map tiles unavailable. Showing barangay ranking beside the map."
              : "Loading heat map..."}
          </div>
        )}
      </div>
      <div className="analytics-heatmap-side">
        <div className="analytics-heatmap-legend">
          <span>
            <i className="heat-low" /> Low
          </span>
          <span>
            <i className="heat-mid" /> Medium
          </span>
          <span>
            <i className="heat-high" /> High
          </span>
        </div>
        <div className="analytics-heatmap-ranking">
          {rankedData.length > 0 ? (
            rankedData.map((item) => (
              <div className="analytics-heatmap-rank" key={item.barangay}>
                <span>{item.barangay}</span>
                <strong>{item.value}</strong>
              </div>
            ))
          ) : (
            <p className="small text-muted mb-0">No barangay data yet.</p>
          )}
        </div>
      </div>
    </div>
  );
}
