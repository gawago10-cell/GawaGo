import React from "react";

import AuthImage from "./AuthImage";
import { openProtectedFile } from "../utils/protectedFiles";

const STATUS_LABELS = {
  approved: "✓ Verified",
  pending: "Pending review",
  rejected: "Rejected",
};

/**
 * A worker's certificate thumbnail. Saved files sit behind a
 * permission-checked API route, so a plain <img src> can't load them; a file
 * the worker just picked is still a local data: URL and can.
 */
export function CertificateThumb({ cert, height }) {
  const src = cert.certificatePreview || "";
  const style = { height, width: "100%" };
  if (src.startsWith("data:") || src.startsWith("blob:")) {
    return <img src={src} alt={cert.name} className="gg-cert-thumb-img rounded" style={style} />;
  }
  if (src && cert.fileType === "image") {
    return (
      <div className="gg-cert-thumb rounded" style={style}>
        <AuthImage src={src} alt={cert.name} className="gg-cert-thumb-img" />
      </div>
    );
  }
  return (
    <button
      type="button"
      className="gg-cert-thumb gg-cert-thumb-file rounded"
      style={style}
      onClick={() => src && openProtectedFile(src)}
      disabled={!src}
    >
      {src ? (cert.fileType === "pdf" ? "PDF · Open" : "File · Open") : "No file"}
    </button>
  );
}

export function CertificateStatusBadge({ cert }) {
  const status = cert.isVerified ? "approved" : cert.verificationStatus || "pending";
  return <span className={`gg-cert-status ${status}`}>{STATUS_LABELS[status] || status}</span>;
}
