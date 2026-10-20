import React, { useEffect, useMemo, useRef, useState } from "react";

import { formatCurrency, getHouseholdInitials } from "../utils/formatters";
import { loadLeafletAssets } from "../utils/mapAssets";

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

// Jobs arrive snapped to a ~1 km grid, so several often share one spot.
// One pin per spot, listing every job there, keeps them all reachable.
function groupJobsByArea(jobs) {
  const groups = new Map();
  const unmapped = [];
  jobs.forEach((job) => {
    const point = toPoint(job.approximateLatitude, job.approximateLongitude);
    if (!point) {
      unmapped.push(job);
      return;
    }
    const key = point.join(",");
    if (!groups.has(key)) {
      groups.set(key, { key, point, jobs: [] });
    }
    groups.get(key).jobs.push(job);
  });
  return { groups: [...groups.values()], unmapped };
}

function pinLabel(group) {
  const households = new Set(group.jobs.map((job) => job.householdUsername || job.householdName));
  return households.size === 1 && group.jobs.length === 1
    ? getHouseholdInitials(group.jobs[0].householdName)
    : String(group.jobs.length);
}

function jobPinIcon(L, group) {
  const matches = group.jobs.some((job) => job.matchesSkill);
  const classes = ["worker-jobs-map-pin", matches ? "is-match" : "is-other"].join(" ");
  return L.divIcon({
    className: "worker-jobs-map-pin-wrap",
    html: `<div class="${classes}"><span>${escapeHtml(pinLabel(group))}</span></div>`,
    iconSize: [44, 44],
    iconAnchor: [22, 44],
  });
}

function workerPinIcon(L) {
  return L.divIcon({
    className: "worker-jobs-map-pin-wrap",
    html: '<div class="worker-jobs-map-you">You</div>',
    iconSize: [46, 24],
    iconAnchor: [23, 12],
  });
}

export default function WorkerJobsMap({ jobs, worker, getDistanceLabel, onViewDetails, onApply }) {
  const mapNodeRef = useRef(null);
  const mapRef = useRef(null);
  const layerRef = useRef(null);
  const markersRef = useRef(new Map());
  const [mapReady, setMapReady] = useState(false);
  const [mapError, setMapError] = useState("");
  const [selectedKey, setSelectedKey] = useState(null);

  // The parent recomputes the job list on every render, so keying on the
  // array itself rebuilt every pin (and dropped keyboard focus on one) each
  // background poll. Rebuild only when what the map shows actually changed.
  const jobsSignature = jobs
    .map((job) =>
      [
        job.id,
        job.approximateLatitude,
        job.approximateLongitude,
        job.jobTitle,
        job.serviceType,
        job.barangay,
        job.householdName,
        job.canApply,
        job.matchesSkill,
        job.applicationStatus,
        job.distanceLabel,
        job.routeDistanceKm ?? job.distanceKm,
      ].join("~"),
    )
    .join("|");
  const jobsRef = useRef(jobs);
  jobsRef.current = jobs;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const { groups, unmapped } = useMemo(() => groupJobsByArea(jobsRef.current), [jobsSignature]);
  const workerPoint = toPoint(worker?.latitude, worker?.longitude);
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
        L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
          maxZoom: 18,
          attribution: "&copy; OpenStreetMap contributors",
        }).addTo(map);
        map.setView(workerPoint || TAYABAS_CENTER, DEFAULT_ZOOM);
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
    if (workerPoint) {
      L.marker(workerPoint, { icon: workerPinIcon(L), interactive: false, keyboard: false }).addTo(layer);
    }
    groups.forEach((group) => {
      const baseZIndex = group.jobs.some((job) => job.matchesSkill) ? 500 : 0;
      const marker = L.marker(group.point, {
        icon: jobPinIcon(L, group),
        zIndexOffset: baseZIndex,
        baseZIndex,
        title: group.jobs.map((job) => `${job.householdName}: ${job.jobTitle || job.serviceType}`).join("\n"),
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
    // Markers are rebuilt only when the jobs change; selection just restyles
    // them (below), so a click never removes the pin it landed on.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [groups, mapReady, workerPoint?.[0], workerPoint?.[1]]);

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

  const showAllJobs = () => {
    const L = window.L;
    const map = mapRef.current;
    if (!L || !map) {
      return;
    }
    const points = groups.map((group) => group.point);
    if (workerPoint) {
      points.push(workerPoint);
    }
    if (points.length === 0) {
      return;
    }
    map.fitBounds(L.latLngBounds(points), { padding: [48, 48], maxZoom: 15 });
  };

  const recenter = () => {
    mapRef.current?.setView(workerPoint || TAYABAS_CENTER, DEFAULT_ZOOM);
  };

  return (
    <div className="worker-jobs-map">
      <div className="worker-jobs-map-frame">
        <div ref={mapNodeRef} className="worker-jobs-map-canvas" role="region" aria-label="Map of open jobs" />
        {mapError && <div className="worker-jobs-map-error">{mapError}</div>}
        <div className="worker-jobs-map-controls">
          <button type="button" className="worker-jobs-map-control" onClick={showAllJobs} disabled={!mapReady}>
            Show all jobs
          </button>
          <button type="button" className="worker-jobs-map-control" onClick={recenter} disabled={!mapReady}>
            {workerPoint ? "Near me" : "Tayabas City"}
          </button>
        </div>
        {selectedGroup && (
          <div className="worker-jobs-map-panel" role="dialog" aria-label="Jobs posted in this area">
            <div className="worker-jobs-map-panel-head">
              <span>
                {selectedGroup.jobs.length === 1
                  ? "1 job in this area"
                  : `${selectedGroup.jobs.length} jobs in this area`}
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
              {selectedGroup.jobs.map((job) => (
                <article className="worker-jobs-map-job" key={job.id}>
                  <div className="worker-jobs-map-job-who">
                    <div className="worker-jobs-map-avatar">{getHouseholdInitials(job.householdName)}</div>
                    <div className="worker-jobs-map-job-ident">
                      <strong>{job.householdName}</strong>
                      <span>
                        {job.householdVerificationStatus === "verified" ? "✓ Verified household" : "Unverified household"}
                      </span>
                    </div>
                    <span className={`worker-jobs-map-tag ${job.matchesSkill ? "is-match" : ""}`}>
                      {job.matchesSkill ? "Matches Skills" : "Other Job"}
                    </span>
                  </div>
                  <div className="worker-jobs-map-job-title-row">
                    <h3>{job.jobTitle || job.serviceType}</h3>
                    <p>
                      <strong>{formatCurrency(job.offeredRate)}</strong>
                      <span>/{(job.rateType || "Per Day").toLowerCase()}</span>
                    </p>
                  </div>
                  <p className="worker-jobs-map-job-meta">
                    {[job.serviceType, job.barangay, getDistanceLabel(job)].filter(Boolean).join(" · ")}
                  </p>
                  <div className="worker-jobs-map-job-actions">
                    <button type="button" className="worker-jobcard-btn is-ghost" onClick={() => onViewDetails(job.id)}>
                      View Details
                    </button>
                    <button
                      type="button"
                      className="worker-jobcard-btn is-primary"
                      disabled={!job.canApply}
                      onClick={() => onApply(job.id)}
                    >
                      {job.canApply ? "Apply Now" : job.applicationStatus ? "Applied" : "Unavailable"}
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
          <i className="worker-jobs-map-dot is-match" /> Matches your skills
        </span>
        <span>
          <i className="worker-jobs-map-dot is-other" /> Other jobs
        </span>
        {workerPoint && (
          <span>
            <i className="worker-jobs-map-dot is-you" /> Your location
          </span>
        )}
        <span className="worker-jobs-map-note">
          Pins mark the general area (about 1 km) to keep the map readable. Open a job to see its exact location and
          the route from your place.
        </span>
        {unmapped.length > 0 && (
          <span className="worker-jobs-map-note">
            {unmapped.length === 1
              ? "1 job has no map location yet and appears only in List View."
              : `${unmapped.length} jobs have no map location yet and appear only in List View.`}
          </span>
        )}
      </div>
    </div>
  );
}
