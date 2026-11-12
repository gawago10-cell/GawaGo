import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const apiRequest = vi.fn();
vi.mock("../api/apiClient", () => ({
  apiRequest: (...args) => apiRequest(...args),
  getApiBaseUrl: () => "http://api.test/api",
}));

import { openProtectedFile } from "./protectedFiles";

const FILE_URL = "http://api.test/api/common/verification-requests/7/documents/primary/";

function fakeTab() {
  return {
    closed: false,
    opener: "page",
    location: { href: "" },
    document: { title: "", body: { textContent: "" } },
    close: vi.fn(function close() {
      this.closed = true;
    }),
  };
}

describe("openProtectedFile", () => {
  beforeEach(() => {
    window.URL.createObjectURL = vi.fn(() => "blob:http://localhost/doc");
    window.URL.revokeObjectURL = vi.fn();
    vi.spyOn(window, "alert").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
    apiRequest.mockReset();
  });

  it("opens the tab at the click and fills it once the file arrives", async () => {
    const tab = fakeTab();
    const open = vi.spyOn(window, "open").mockReturnValue(tab);
    let finishDownload;
    apiRequest.mockReturnValue(new Promise((resolve) => (finishDownload = resolve)));

    const opening = openProtectedFile(FILE_URL);
    // Before the download finishes: the tab already exists, cut off from the page.
    expect(open).toHaveBeenCalledWith("", "_blank");
    expect(tab.opener).toBeNull();
    expect(tab.document.body.textContent).toBe("Opening document...");

    finishDownload({ ok: true, blob: async () => new Blob(["%PDF"], { type: "application/pdf" }) });
    await opening;

    expect(apiRequest).toHaveBeenCalledWith("common/verification-requests/7/documents/primary/", { auth: true });
    expect(tab.location.href).toBe("blob:http://localhost/doc");
    expect(open).toHaveBeenCalledTimes(1);
  });

  it("closes the tab and says why when the file is gone", async () => {
    const tab = fakeTab();
    vi.spyOn(window, "open").mockReturnValue(tab);
    apiRequest.mockResolvedValue({
      ok: false,
      json: async () => ({ detail: "This document is no longer stored on the server, so it can't be opened." }),
    });

    await openProtectedFile(FILE_URL);

    expect(tab.close).toHaveBeenCalled();
    expect(window.alert).toHaveBeenCalledWith("This document is no longer stored on the server, so it can't be opened.");
  });

  it("still opens the file when the waiting tab was blocked", async () => {
    const open = vi.spyOn(window, "open").mockReturnValueOnce(null).mockReturnValueOnce(null);
    apiRequest.mockResolvedValue({ ok: true, blob: async () => new Blob(["x"], { type: "image/png" }) });

    await openProtectedFile(FILE_URL);

    expect(open).toHaveBeenLastCalledWith("blob:http://localhost/doc", "_blank", "noopener,noreferrer");
  });
});
