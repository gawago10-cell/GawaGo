const RAW_API_BASE_URL = import.meta.env.VITE_API_URL || import.meta.env.REACT_APP_API_URL || "http://localhost:8000/api";
const API_BASE_URL = RAW_API_BASE_URL.replace(/\/$/, "");
const AUTH_TOKEN_KEY = "gawago-auth-token";

let unauthorizedHandler = null;

function getAuthHeaders() {
  const token = getAuthToken();
  if (!token) {
    return {};
  }
  return { Authorization: `Bearer ${token}` };
}

function buildUrl(path) {
  const cleanedPath = String(path || "").replace(/^\/+/, "");
  return `${API_BASE_URL}/${cleanedPath}`;
}

export function getApiBaseUrl() {
  return API_BASE_URL;
}

export function getAuthToken() {
  if (typeof window === "undefined") {
    return null;
  }
  return window.localStorage.getItem(AUTH_TOKEN_KEY);
}

export function setAuthToken(token) {
  if (typeof window === "undefined") {
    return;
  }
  if (!token) {
    window.localStorage.removeItem(AUTH_TOKEN_KEY);
    return;
  }
  window.localStorage.setItem(AUTH_TOKEN_KEY, token);
}

export function clearAuthToken() {
  setAuthToken("");
}

export function setUnauthorizedHandler(handler) {
  unauthorizedHandler = typeof handler === "function" ? handler : null;
}

// A stuck request (dead connection, server hung) used to leave the UI on
// "Posting..." forever with no feedback and no way to retry, and background
// polls piled up behind it. File uploads get longer: a multipart body with
// several photos legitimately takes longer than a plain JSON call.
const DEFAULT_TIMEOUT_MS = 30000;
const UPLOAD_TIMEOUT_MS = 90000;

export async function apiRequest(path, options = {}) {
  const {
    method = "GET",
    body,
    headers = {},
    auth = true,
    suppressUnauthorized = false,
    credentials = "omit",
    timeoutMs,
    ...rest
  } = options;

  const requestHeaders = { ...headers };
  const sentToken = auth ? getAuthToken() : null;
  if (auth) {
    Object.assign(requestHeaders, getAuthHeaders());
  }
  if (body != null && !(body instanceof FormData) && !(body instanceof Blob) && typeof body !== "string") {
    requestHeaders["Content-Type"] = requestHeaders["Content-Type"] || "application/json";
  }

  const effectiveTimeoutMs =
    timeoutMs ?? (body instanceof FormData ? UPLOAD_TIMEOUT_MS : DEFAULT_TIMEOUT_MS);

  let response;
  try {
    response = await fetch(buildUrl(path), {
      method,
      headers: requestHeaders,
      credentials,
      mode: "cors",
      body:
        body == null || method.toUpperCase() === "GET"
          ? undefined
          : requestHeaders["Content-Type"] === "application/json" && typeof body !== "string"
            ? JSON.stringify(body)
            : body,
      // rest.signal (if a caller ever passes one) wins; most calls don't,
      // so this is what actually bounds the request.
      signal: rest.signal || AbortSignal.timeout(effectiveTimeoutMs),
      ...rest,
    });
  } catch (error) {
    if (error?.name === "TimeoutError" || error?.name === "AbortError") {
      throw new Error("That took too long to respond. Please try again.");
    }
    throw new Error("Can't connect to GawaGo right now. Check your internet connection and try again.");
  }

  if (response.status === 401 && unauthorizedHandler) {
    if (!suppressUnauthorized) {
      unauthorizedHandler(response.clone());
    } else if (sentToken && sentToken === getAuthToken()) {
      // Background refreshes suppress 401s, but a 401 on the token still in
      // use means the session itself ended (suspended, expired, revoked), so
      // sign out instead of leaving a dashboard whose every request fails.
      // Clearing first makes the other in-flight refreshes skip this branch.
      clearAuthToken();
      unauthorizedHandler(response.clone());
    }
  }

  return response;
}
