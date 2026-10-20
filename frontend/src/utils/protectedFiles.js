import { apiRequest, getApiBaseUrl } from "../api/apiClient";

// A blob: URL runs with this app's origin, so only types that can't carry
// script may be opened as a page (SVG and HTML can).
const PREVIEWABLE_TYPES = /^(image\/(png|jpe?g|webp|gif|hei[cf])|application\/pdf)$/;

/**
 * Open a document in a new tab. Permission-checked API routes (IDs,
 * complaint evidence) can't be linked directly because a plain link can't
 * send the bearer token, so they are fetched and shown from a blob: URL.
 */
export async function openProtectedFile(fileUrl) {
  if (!fileUrl) return;
  const normalizedUrl = String(fileUrl);
  const apiBaseUrl = getApiBaseUrl();
  const apiIndex = normalizedUrl.indexOf("/api/");
  const isProtectedApiDocument = normalizedUrl.startsWith("/api/") || normalizedUrl.startsWith(apiBaseUrl);
  if (!isProtectedApiDocument && apiIndex === -1) {
    window.open(normalizedUrl, "_blank", "noopener,noreferrer");
    return;
  }
  const apiPath = normalizedUrl.startsWith(apiBaseUrl)
    ? normalizedUrl.slice(apiBaseUrl.length).replace(/^\/+/, "")
    : normalizedUrl.slice(apiIndex + "/api/".length);
  try {
    const response = await apiRequest(apiPath, { auth: true });
    if (!response.ok) {
      window.alert("You are not allowed to view this document, or it is no longer available.");
      return;
    }
    const blob = await response.blob();
    if (!PREVIEWABLE_TYPES.test(blob.type)) {
      window.alert("This document can't be previewed.");
      return;
    }
    const objectUrl = window.URL.createObjectURL(blob);
    window.open(objectUrl, "_blank", "noopener,noreferrer");
    window.setTimeout(() => window.URL.revokeObjectURL(objectUrl), 60_000);
  } catch (error) {
    window.alert("Unable to open this document right now.");
  }
}
