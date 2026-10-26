import React, { useEffect, useMemo, useRef, useState } from "react";

import { formatWorkerRate, getDisplayName, getHouseholdInitials } from "../utils/formatters";
import { loadLeafletAssets } from "../utils/mapAssets";
import { applyTwoFingerPan } from "../utils/mapGestures";
import { frameMapToTayabas } from "../utils/tayabasMapFrame";

const TAYABAS_CENTER = [14.0269, 121.5926];
const DEFAULT_ZOOM = 13;

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => `&#${character.charCodeAt(0)};`);
}

function toPoint(latitude, longitude) {
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (latitude == null || longitude == null || !Number.isFinite(lat) || !Number.isFinite(lng)) {
    return null;
  }
  return [lat, lng];
}

function workerName(worker) {
  return getDisplayName(worker.firstName, worker.lastName, worker.username);
}

// Workers arrive snapped to a ~1 km grid, so several often share one spot --
// especially on a 1 km job radius, where every candidate lands in the same
// cell. One pin per spot, listing everyone there, keeps them all reachable.
function groupWorkersByArea(workers) {
  const groups = new Map();
  const unmapped = [];
  workers.forEach((worker) => {
    const point = toPoint(worker.approximateLatitude, worker.approximateLongitude);
    if (!point) {
      unmapped.push(worker);
      return;
    }
    const key = point.join(",");
    if (!groups.has(key)) {
      groups.set(key, { key, point, workers: [] });
    }
    groups.get(key).workers.push(worker);
  });
  return { groups: [...groups.values()], unmapped };
}

function pinLabel(group) {
  return group.workers.length === 1 ? getHouseholdInitials(workerName(group.workers[0])) : String(group.workers.length);
}

function workerPinIcon(L, group) {
  const matches = group.workers.some((worker) => worker.matchesSkill);
  const classes = ["worker-jobs-map-pin", matches ? "is-match" : "is-other"].join(" ");
  return L.divIcon({
    className: "worker-jobs-map-pin-wrap",
    html: `<div class="${classes}"><span>${escapeHtml(pinLabel(group))}</span></div>`,
    iconSize: [44, 44],
    iconAnchor: [22, 44],
  });
}

function jobPinIcon(L) {
  return L.divIcon({
    className: "worker-jobs-map-pin-wrap",
    html: '<div class="worker-jobs-map-you">Job</div>',
    iconSize: [46, 24],
    iconAnchor: [23, 12],
  });
}

export default function HouseholdWorkersMap({ workers, job, onViewProfile, onHire }) {
  const mapNodeRef = useRef(null);
  const mapRef = useRef(null);
  const layerRef = useRef(null);
  const frameRef = useRef(null);
  const markersRef = useRef(new Map());
  const [mapReady, setMapReady] = useState(false);
  const [mapError, setMapError] = useState("");
  const [selectedKey, setSelectedKey] = useState(null);

  const { groups, unmapped } = useMemo(() => groupWorkersByArea(workers), [workers]);
  // The household owns this job, so its site is their own address -- pinned
  // exactly, unlike the candidates around it.
  const jobPoint = toPoint(job?.latitude, job?.longitude);
  const selectedGroup = groups.find((group) => group.key === selectedKey) || null;

  useEffect(() => {
    let cancelled = false;
    loadLeafletAssets()
      .then((L) => {
        if (cancelled || !L || !mapNodeRef.current || mapRef.current) {
          return;
        }
        // Leaflet focuses the map on mousedown and then restores only the
        // window's scroll; here .worker-content is the scroller, so the page
        // jumped mid-click and the click missed the pin. Keep arrow-key
        // panning but focus without scrolling.
        const container = mapNodeRef.current;
        container.focus = (options) => HTMLElement.prototype.focus.call(container, { ...options, preventScroll: true });
        const map = L.map(container, { zoomControl: true, scrollWheelZoom: true });
        applyTwoFingerPan(map);
        frameRef.current = frameMapToTayabas(map, L);
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          maxZoom: 18,
          attribution: "&copy; OpenStreetMap contributors",
        }).addTo(map);
        map.setView(jobPoint || TAYABAS_CENTER, DEFAULT_ZOOM);
        map.on("click", (event) => {
          if (event.originalEvent?.target?.closest?.(".worker-jobs-map-pin-wrap")) {
            return;
          }
          setSelectedKey(null);
        });
        mapRef.current = map;
        layerRef.current = L.layerGroup().addTo(map);
        setMapReady(true);
      })
      .catch(() => setMapError("The map could not be loaded. Check your connection and try again."));
    return () => {
      cancelled = true;
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
        layerRef.current = null;
      }
    };
    // The map is built once; markers are redrawn by the effect below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const L = window.L;
    const layer = layerRef.current;
    if (!mapReady || !L || !layer) {
      return;
    }
    layer.clearLayers();
    markersRef.current = new Map();
    if (jobPoint) {
      L.marker(jobPoint, { icon: jobPinIcon(L), interactive: false, keyboard: false }).addTo(layer);
    }
    groups.forEach((group) => {
      const baseZIndex = group.workers.some((worker) => worker.matchesSkill) ? 500 : 0;
      const marker = L.marker(group.point, {
        icon: workerPinIcon(L, group),
        zIndexOffset: baseZIndex,
        baseZIndex,
        title: group.workers.map((worker) => workerName(worker)).join("\n"),
      });
      marker.on("click", () => {
        setSelectedKey((current) => (current === group.key ? null : group.key));
      });
      marker.addTo(layer);
      // A mouse press would focus the (keyboard-reachable) pin, and focusing
      // scrolls the page, sliding the pin out from under the cursor before
      // mouseup -- so the click landed on the map and closed the panel.
      marker.getElement()?.addEventListener("mousedown", (event) => event.preventDefault());
      markersRef.current.set(group.key, marker);
    });
    // Markers are rebuilt only when the workers change; selection just
    // restyles them (below), so a click never removes the pin it landed on.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [groups, mapReady, jobPoint?.[0], jobPoint?.[1]]);

  useEffect(() => {
    markersRef.current.forEach((marker, key) => {
      const selected = key === selectedKey;
      marker.getElement()?.querySelector(".worker-jobs-map-pin")?.classList.toggle("is-selected", selected);
      marker.setZIndexOffset(selected ? 1000 : marker.options.baseZIndex);
    });
  }, [selectedKey, groups, mapReady]);

  useEffect(() => {
    if (selectedKey && !groups.some((group) => group.key === selectedKey)) {
      setSelectedKey(null);
    }
  }, [groups, selectedKey]);

  const showAllWorkers = () => {
    const L = window.L;
    const map = mapRef.current;
    if (!L || !map) {
      return;
    }
    const points = groups.map((group) => group.point);
    if (jobPoint) {
      points.push(jobPoint);
    }
    if (points.length === 0) {
      return;
    }
    frameRef.current?.includePoints(points);
    map.fitBounds(L.latLngBounds(points), { padding: [48, 48], maxZoom: 15 });
  };

  const recenter = () => {
    mapRef.current?.setView(jobPoint || TAYABAS_CENTER, DEFAULT_ZOOM);
  };

  return (
    <div className="worker-jobs-map">
      <div className="worker-jobs-map-frame">
        <div ref={mapNodeRef} className="worker-jobs-map-canvas" role="region" aria-label="Map of matched workers" />
        {mapError && <div className="worker-jobs-map-error">{mapError}</div>}
        <div className="worker-jobs-map-controls">
          <button type="button" className="worker-jobs-map-control" onClick={showAllWorkers} disabled={!mapReady}>
            Show all workers
          </button>
          <button type="button" className="worker-jobs-map-control" onClick={recenter} disabled={!mapReady}>
            {jobPoint ? "My job site" : "Tayabas City"}
          </button>
        </div>
        {selectedGroup && (
          <div className="worker-jobs-map-panel" role="dialog" aria-label="Workers available in this area">
            <div className="worker-jobs-map-panel-head">
              <span>
                {selectedGroup.workers.length === 1
                  ? "1 worker in this area"
                  : `${selectedGroup.workers.length} workers in this area`}
              </span>
              <button
                type="button"
                className="worker-jobs-map-panel-close"
                aria-label="Close"
                onClick={() => setSelectedKey(null)}
              >
                ×
              </button>
            </div>
            <div className="worker-jobs-map-panel-list">
              {selectedGroup.workers.map((worker) => (
                <article className="worker-jobs-map-job" key={worker.username || worker.id}>
                  <div className="worker-jobs-map-job-who">
                    <div className="worker-jobs-map-avatar">{getHouseholdInitials(workerName(worker))}</div>
                    <div className="worker-jobs-map-job-ident">
                      <strong>{workerName(worker)}</strong>
                      <span>{worker.verification === "Verified" ? "✓ Verified worker" : "Unverified worker"}</span>
                    </div>
                    <span className={`worker-jobs-map-tag ${worker.matchesSkill ? "is-match" : ""}`}>
                      {worker.matchesSkill ? "Matches Skills" : "Other Worker"}
                    </span>
                  </div>
                  <div className="worker-jobs-map-job-title-row">
                    <h3>{(worker.skills || []).slice(0, 2).join(", ") || "No skills listed"}</h3>
                    <p>
                      <strong>{formatWorkerRate(worker.dailyRate)}</strong>
                      <span>/day</span>
                    </p>
                  </div>
                  <p className="worker-jobs-map-job-meta">
                    {[worker.rating, worker.barangay, worker.distanceLabel].filter(Boolean).join(" · ")}
                  </p>
                  <div className="worker-jobs-map-job-actions">
                    <button type="button" className="worker-jobcard-btn is-ghost" onClick={() => onViewProfile(worker)}>
                      View Profile
                    </button>
                    <button type="button" className="worker-jobcard-btn is-primary" onClick={() => onHire(worker)}>
                      Send Request
                    </button>
                  </div>
                </article>
              ))}
            </div>
          </div>
        )}
      </div>
      <div className="worker-jobs-map-legend">
        <span>
          <i className="worker-jobs-map-dot is-match" /> Matches the job&apos;s skill
        </span>
        <span>
          <i className="worker-jobs-map-dot is-other" /> Other matched workers
        </span>
        {jobPoint && (
          <span>
            <i className="worker-jobs-map-dot is-you" /> Your job site
          </span>
        )}
        <span className="worker-jobs-map-note">
          Pins mark the general area (about 1 km) to keep the map readable. Once a worker applies, their applicant
          card shows their exact location and route.
        </span>
        {unmapped.length > 0 && (
          <span className="worker-jobs-map-note">
            {unmapped.length === 1
              ? "1 worker has no map location yet and appears only in List View."
              : `${unmapped.length} workers have no map location yet and appear only in List View.`}
          </span>
        )}
      </div>
    </div>
  );
}
