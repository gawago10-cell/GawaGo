import { apiRequest, getApiBaseUrl } from "../api/apiClient";

// A blob: URL runs with this app's origin, so only types that can't carry
// script may be opened as a page (SVG and HTML can).
const PREVIEWABLE_TYPES = /^(image\/(png|jpe?g|webp|gif|hei[cf])|application\/pdf)$/;

// A blank tab saying the document is on its way, cut off from this page
// (opener cleared). Null when the browser blocked it anyway.
function openWaitingTab() {
  const tab = window.open("", "_blank");
  if (!tab) return null;
  try {
    tab.opener = null;
    tab.document.title = "Opening document...";
    tab.document.body.textContent = "Opening document...";
  } catch {
    // A tab we can't write to still works as the place the file opens.
  }
  return tab;
}

function closeTab(tab) {
  try {
    if (tab && !tab.closed) tab.close();
  } catch {
    // Already gone.
  }
}

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
  // The tab opens now, while the click still counts as the person's own:
  // opened only after the download, a slow server (Render's wakes in 30s+)
  // made the browser block it as a pop-up, with no message.
  const tab = openWaitingTab();
  const fail = (message) => {
    closeTab(tab);
    window.alert(message);
  };
  try {
    const response = await apiRequest(apiPath, { auth: true });
    if (!response.ok) {
      const body = await response.json().catch(() => null);
      fail(
        (typeof body?.detail === "string" && body.detail) ||
          "You are not allowed to view this document, or it is no longer available.",
      );
      return;
    }
    const blob = await response.blob();
    if (!PREVIEWABLE_TYPES.test(blob.type)) {
      fail("This document can't be previewed.");
      return;
    }
    const objectUrl = window.URL.createObjectURL(blob);
    if (tab && !tab.closed) {
      tab.location.href = objectUrl;
    } else {
      window.open(objectUrl, "_blank", "noopener,noreferrer");
    }
    window.setTimeout(() => window.URL.revokeObjectURL(objectUrl), 60_000);
  } catch (error) {
    fail("Unable to open this document right now.");
  }
}
