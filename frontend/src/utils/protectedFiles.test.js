import { afterEach, describe, expect, it, vi } from "vitest";

const apiRequest = vi.fn();
vi.mock("../api/apiClient", () => ({
  apiRequest: (...args) => apiRequest(...args),
  getApiBaseUrl: () => "http://api.test/api/",
}));

const { openProtectedFile } = await import("./protectedFiles");

describe("openProtectedFile", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    apiRequest.mockReset();
  });

  it("tells the admin why a document won't open", async () => {
    const alert = vi.spyOn(window, "alert").mockImplementation(() => {});
    apiRequest.mockResolvedValue(
      new Response(JSON.stringify({ detail: "This document is no longer stored on the server, so it can't be opened." }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      }),
    );

    await openProtectedFile("http://api.test/api/common/verification-requests/10/documents/primary/");

    expect(apiRequest).toHaveBeenCalledWith("common/verification-requests/10/documents/primary/", { auth: true });
    expect(alert).toHaveBeenCalledWith("This document is no longer stored on the server, so it can't be opened.");
  });

  it("falls back to the general message when the error has no reason", async () => {
    const alert = vi.spyOn(window, "alert").mockImplementation(() => {});
    apiRequest.mockResolvedValue(new Response("<html>bad gateway</html>", { status: 502 }));

    await openProtectedFile("/api/common/verification-requests/10/documents/primary/");

    expect(alert).toHaveBeenCalledWith("You are not allowed to view this document, or it is no longer available.");
  });
});
