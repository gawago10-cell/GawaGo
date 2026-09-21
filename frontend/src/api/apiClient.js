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

export async function apiRequest(path, options = {}) {
  const {
    method = "GET",
    body,
    headers = {},
    auth = true,
    suppressUnauthorized = false,
    credentials = "omit",
    ...rest
  } = options;

  const requestHeaders = { ...headers };
  if (auth) {
    Object.assign(requestHeaders, getAuthHeaders());
  }
  if (body != null && !(body instanceof FormData) && !(body instanceof Blob) && typeof body !== "string") {
    requestHeaders["Content-Type"] = requestHeaders["Content-Type"] || "application/json";
  }

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
      ...rest,
    });
  } catch (error) {
    const targetUrl = buildUrl(path);
    throw new Error(`Unable to reach backend at ${targetUrl}. Make sure Django is running on port 8000.`);
  }

  if (response.status === 401 && !suppressUnauthorized && unauthorizedHandler) {
    unauthorizedHandler(response.clone());
  }

  return response;
}
