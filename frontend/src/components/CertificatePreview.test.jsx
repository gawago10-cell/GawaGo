import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";

const openProtectedFile = vi.fn();
vi.mock("../utils/protectedFiles", () => ({ openProtectedFile: (...args) => openProtectedFile(...args) }));
vi.mock("./AuthImage", () => ({
  default: ({ src, alt }) => <span data-testid="auth-image" data-src={src}>{alt}</span>,
}));

import { CertificateStatusBadge, CertificateThumb } from "./CertificatePreview";

const FILE_URL = "http://localhost:8000/api/accounts/portfolio/certifications/4/file/";

describe("CertificateThumb", () => {
  it("loads a saved image through the token-carrying AuthImage", () => {
    render(<CertificateThumb cert={{ name: "NC II", certificatePreview: FILE_URL, fileType: "image" }} height="100px" />);

    expect(screen.getByTestId("auth-image").getAttribute("data-src")).toBe(FILE_URL);
  });

  it("shows a just-picked file directly", () => {
    render(<CertificateThumb cert={{ name: "New", certificatePreview: "data:image/png;base64,AAAA" }} height="100px" />);

    expect(screen.getByAltText("New").getAttribute("src")).toBe("data:image/png;base64,AAAA");
  });

  it("opens a PDF through the protected-file helper", () => {
    render(<CertificateThumb cert={{ name: "Licence", certificatePreview: FILE_URL, fileType: "pdf" }} height="100px" />);

    fireEvent.click(screen.getByRole("button", { name: "PDF · Open" }));

    expect(openProtectedFile).toHaveBeenCalledWith(FILE_URL);
  });
});

describe("CertificateStatusBadge", () => {
  it("names every review state, not just Verified", () => {
    const { rerender } = render(<CertificateStatusBadge cert={{ isVerified: true }} />);
    expect(screen.getByText("✓ Verified")).toBeTruthy();

    rerender(<CertificateStatusBadge cert={{ isVerified: false, verificationStatus: "pending" }} />);
    expect(screen.getByText("Pending review")).toBeTruthy();

    rerender(<CertificateStatusBadge cert={{ isVerified: false, verificationStatus: "rejected" }} />);
    expect(screen.getByText("Rejected")).toBeTruthy();
  });
});
