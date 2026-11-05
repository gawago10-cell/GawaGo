import React from "react";
import { CertificateStatusBadge, CertificateThumb } from "./CertificatePreview";

/*
 * The pieces of a worker's portfolio, shared by the worker's own Skills &
 * Portfolio tab and the profile households open before hiring, so both sides
 * read the same skill levels, certificate details, work samples and job
 * ratings (2026-11-05). Each piece takes an optional `children`/`actions`
 * slot for the worker's own edit controls.
 */

const formatDate = (value) => {
  if (!value) return "";
  const parsed = new Date(String(value).length === 10 ? `${value}T00:00:00` : value);
  return Number.isNaN(parsed.getTime())
    ? String(value)
    : parsed.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
};

const titleCase = (value) => String(value || "").replace(/\b\w/g, (letter) => letter.toUpperCase());

export function SkillCard({ name, proficiency, averageRating, ratingCount, children }) {
  const rated = Number(ratingCount) > 0 && averageRating != null;
  return (
    <div className="pf-skill">
      <div className="pf-skill-name">{name}</div>
      {proficiency ? (
        <span className="pf-chip">{titleCase(proficiency)}</span>
      ) : (
        <span className="pf-muted">Level not set</span>
      )}
      <span className="pf-muted">
        {rated
          ? `★ ${Number(averageRating).toFixed(1)} from ${ratingCount} household rating${Number(ratingCount) === 1 ? "" : "s"}`
          : "Not yet rated"}
      </span>
      {children}
    </div>
  );
}

export function CertificateCard({ cert, actions }) {
  const meta = [
    cert.issuer,
    cert.issueDate ? `Issued ${formatDate(cert.issueDate)}` : "",
    cert.expiryDate ? `Expires ${formatDate(cert.expiryDate)}` : "",
  ].filter(Boolean);
  return (
    <div className="pf-cert">
      <div className="pf-cert-thumb">
        <CertificateThumb cert={cert} height="88px" />
      </div>
      <div className="pf-cert-body">
        <div className="pf-cert-name">{cert.name || "Certificate"}</div>
        {meta.length > 0 && <div className="pf-muted">{meta.join(" · ")}</div>}
        <div>
          <CertificateStatusBadge cert={cert} />
        </div>
        {cert.verificationStatus === "rejected" && cert.verificationNotes && (
          <div className="pf-cert-reason">Reason: {cert.verificationNotes}</div>
        )}
        {actions && <div className="pf-actions">{actions}</div>}
      </div>
    </div>
  );
}

/** A before/after pair when both photos exist, otherwise the one photo. */
export function WorkSampleCard({ sample, onOpen, actions }) {
  const before = sample.beforePreview || "";
  const after = sample.afterPreview || "";
  const pair = Boolean(before && after);
  const single = before || after;
  const open = (url) => onOpen && onOpen(url);
  return (
    <div className="pf-sample">
      <div className="pf-sample-title">{sample.title || "Work sample"}</div>
      {pair ? (
        <div className="pf-sample-pair">
          <button type="button" className="pf-sample-img" onClick={() => open(before)}>
            <img src={before} alt={`${sample.title || "Work sample"} (before)`} />
            <span className="pf-sample-tag">Before</span>
          </button>
          <button type="button" className="pf-sample-img" onClick={() => open(after)}>
            <img src={after} alt={`${sample.title || "Work sample"} (after)`} />
            <span className="pf-sample-tag after">After</span>
          </button>
        </div>
      ) : single ? (
        <button type="button" className="pf-sample-img pf-sample-single" onClick={() => open(single)}>
          <img src={single} alt={sample.title || "Work sample"} />
        </button>
      ) : (
        <div className="pf-muted">No photo</div>
      )}
      {actions && <div className="pf-actions">{actions}</div>}
    </div>
  );
}

/**
 * Completed jobs with the household's own rating as the overall (the review
 * that counts toward the worker's reputation), and the per-skill ratings, or
 * the household's metric ratings, as bars.
 */
export function EmploymentHistoryList({ jobs }) {
  return (
    <div className="pf-history">
      {jobs.map((job, index) => {
        const review = job.household_rating || null;
        const skillBars = (job.skill_ratings || []).map((item) => ({
          label: item.skill_name || item.skill,
          value: Number(item.rating),
        }));
        const bars = skillBars.length > 0 ? skillBars : (review?.metrics || []).map((item) => ({ label: item.label, value: Number(item.value) }));
        const where = [job.household_name || "Household", job.location].filter(Boolean).join(" · ");
        return (
          <article className="pf-job" key={job.id || index}>
            <div>
              <div className="pf-job-title">{job.title}</div>
              <div className="pf-muted">{where}</div>
              {job.completed_at && <div className="pf-muted">Completed {formatDate(job.completed_at)}</div>}
            </div>
            <div className="pf-job-rating">
              <div className={`pf-overall${review ? "" : " empty"}`}>
                {review ? (
                  <>
                    <span className="pf-overall-value">{Number(review.rating).toFixed(1)}</span>
                    <span className="pf-overall-label">overall ★</span>
                  </>
                ) : (
                  <span className="pf-overall-label">Not rated yet</span>
                )}
              </div>
              <div className="pf-bars">
                {bars.length > 0 ? (
                  bars.map((bar) => (
                    <div className="pf-bar" key={bar.label}>
                      <span className="pf-bar-label" title={bar.label}>{bar.label}</span>
                      <span className="pf-bar-track" aria-hidden="true">
                        <span className="pf-bar-fill" style={{ width: `${Math.max(0, Math.min(5, bar.value)) * 20}%` }} />
                      </span>
                      <b className="pf-bar-value">{Number.isInteger(bar.value) ? bar.value : bar.value.toFixed(1)}</b>
                    </div>
                  ))
                ) : (
                  <span className="pf-muted">
                    {review
                      ? review.is_default
                        ? "Automatic 3.5 rating: the household didn't rate this job in time."
                        : "The household gave an overall rating only."
                      : "Waiting for the household's rating."}
                  </span>
                )}
              </div>
            </div>
          </article>
        );
      })}
    </div>
  );
}
