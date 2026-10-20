import React, { useEffect, useState } from "react";
import { apiRequest, getApiBaseUrl } from "../api/apiClient";

function toApiPath(url) {
  const value = String(url || "");
  const base = getApiBaseUrl();
  if (value.startsWith(base)) return value.slice(base.length).replace(/^\/+/, "");
  const apiIndex = value.indexOf("/api/");
  return apiIndex === -1 ? value : value.slice(apiIndex + "/api/".length);
}

/**
 * An image served by a permission-checked API route (e.g. complaint
 * evidence). A plain <img src> can't send the bearer token, so the bytes are
 * fetched with it and shown from a blob: URL. Clicking opens the full image.
 */
export default function AuthImage({ src, alt, className = "" }) {
  const [objectUrl, setObjectUrl] = useState("");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    let created = "";
    setObjectUrl("");
    setFailed(false);
    (async () => {
      const response = await apiRequest(toApiPath(src), { auth: true, suppressUnauthorized: true });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      created = URL.createObjectURL(await response.blob());
      if (cancelled) {
        URL.revokeObjectURL(created);
      } else {
        setObjectUrl(created);
      }
    })().catch(() => {
      if (!cancelled) setFailed(true);
    });
    return () => {
      cancelled = true;
      if (created) URL.revokeObjectURL(created);
    };
  }, [src]);

  if (failed) {
    return <span className={`auth-image-placeholder ${className}`.trim()} title="Image unavailable">!</span>;
  }
  if (!objectUrl) {
    return <span className={`auth-image-placeholder ${className}`.trim()} aria-label="Loading image" />;
  }
  return (
    <a href={objectUrl} target="_blank" rel="noreferrer">
      <img className={className} src={objectUrl} alt={alt} />
    </a>
  );
}
