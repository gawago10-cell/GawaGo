import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/apiClient";
import { readResponseData } from "../utils/apiUtils";
import { fetchWorkerEmploymentHistory } from "../services/backendDataService";

export default function WorkerPortfolioViewPublic({
  workerId,
  workerName,
  currentUser,
}) {
  const [portfolio, setPortfolio] = useState(null);
  const [loading, setLoading] = useState(true);
  const [showGallery, setShowGallery] = useState(false);
  const [selectedImage, setSelectedImage] = useState(null);
  // A household reviewing an applicant could see this worker's completed
  // jobs only from the worker's own account (App.jsx) -- the public
  // portfolio view hiring decisions actually happen from never loaded it.
  const [employmentHistory, setEmploymentHistory] = useState([]);

  useEffect(() => {
    fetchPortfolio();
    (async () => {
      try {
        const history = await fetchWorkerEmploymentHistory(workerId);
        setEmploymentHistory(history || []);
      } catch (error) {
        console.error("Failed to fetch employment history:", error);
      }
    })();
  }, [workerId]);

  const fetchPortfolio = async () => {
    try {
      setLoading(true);
      const response = await apiRequest(`accounts/profiles/${workerId}/portfolio/`, { auth: true });
      if (!response.ok) {
        setPortfolio({});
        return;
      }
      setPortfolio(await readResponseData(response));
    } catch (error) {
      console.error("Failed to fetch portfolio:", error);
      setPortfolio({});
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return <div className="text-center py-5">Loading portfolio...</div>;
  }

  const skills = portfolio?.skills || [];
  const certifications = portfolio?.certifications || [];
  const portfolioItems = portfolio?.portfolio_items || [];

  // The endpoint get_or_creates the portfolio row, so a worker who has filled
  // nothing in still returns a full object -- emptiness has to be judged on
  // the content itself, not on whether the response has keys.
  const hasContent =
    Boolean(portfolio?.bio) ||
    Number(portfolio?.years_experience) > 0 ||
    skills.length > 0 ||
    certifications.length > 0 ||
    portfolioItems.length > 0 ||
    employmentHistory.length > 0;

  if (!hasContent) {
    return (
      <div style={{ padding: "2rem", textAlign: "center", color: "#999", background: "#fafafa", borderRadius: "8px", marginTop: "2rem" }}>
        No portfolio information yet
      </div>
    );
  }

  return (
    <div className="worker-portfolio-public" style={{ marginTop: "2rem" }}>
      <style>{`
        .worker-portfolio-public {
          background: white;
          border-radius: 12px;
          border: 1px solid var(--gg-border);
          overflow: hidden;
          /* overflow:hidden gives a flex item an automatic minimum size of 0,
             so inside a flex-column modal body this gets crushed to a sliver
             instead of the body scrolling. */
          flex-shrink: 0;
        }

        .portfolio-section-public {
          padding: 2rem;
          border-bottom: 1px solid var(--gg-border);
        }

        .portfolio-section-public:last-child {
          border-bottom: none;
        }

        .section-title-public {
          font-size: 1.1rem;
          font-weight: 600;
          color: var(--gg-dark);
          margin-bottom: 1.5rem;
        }

        .skill-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
          gap: 1rem;
        }

        .skill-card-public {
          background: var(--gg-card-muted);
          padding: 1rem;
          border-radius: 8px;
          border: 1px solid var(--gg-border);
          text-align: center;
        }

        .skill-name-public {
          font-weight: 600;
          color: var(--gg-dark);
          margin-bottom: 0.5rem;
        }

        .skill-level-badge {
          display: inline-block;
          background: var(--gg-leaf-deep);
          color: white;
          padding: 0.25rem 0.75rem;
          border-radius: 4px;
          font-size: 0.75rem;
          font-weight: 600;
          margin-bottom: 0.5rem;
        }

        .skill-rating-display {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.25rem;
          color: #8a5a00;
          font-size: 0.9rem;
        }

        .skill-rating-count {
          color: var(--gg-ink-muted);
          font-size: 0.8rem;
          display: block;
          margin-top: 0.25rem;
        }

        .gallery-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
          gap: 1rem;
        }

        .gallery-item {
          border-radius: 8px;
          overflow: hidden;
          background: var(--gg-bg);
          border: 1px solid var(--gg-border);
          aspect-ratio: 1;
          position: relative;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          transition: transform 0.2s;
        }

        .gallery-item:hover {
          transform: scale(1.02);
        }

        .gallery-item img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }

        /* A whole row, capped, rather than "span 2": spanning two tracks of an
           auto-fill grid that only has room for one creates an implicit
           column and overflows, and that depends on the container's width,
           not the viewport's. */
        .gallery-pair {
          grid-column: 1 / -1;
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 0.5rem;
          max-width: 420px;
        }

        .gallery-tag {
          position: absolute;
          left: 0.4rem;
          bottom: 0.4rem;
          padding: 0.1rem 0.5rem;
          border-radius: 4px;
          font-size: 0.75rem;
          font-weight: 600;
          color: #fff;
          background: rgba(0, 0, 0, 0.65);
        }

        .gallery-tag.after {
          background: var(--gg-leaf-deep);
        }

        .cert-item-public {
          background: var(--gg-card-muted);
          padding: 1rem;
          border-radius: 8px;
          border-left: 4px solid var(--gg-primary);
          margin-bottom: 1rem;
        }

        .cert-item-public:last-child {
          margin-bottom: 0;
        }

        .cert-name {
          font-weight: 600;
          color: var(--gg-dark);
          margin-bottom: 0.25rem;
        }

        .cert-issuer {
          font-size: 0.9rem;
          color: var(--gg-ink-muted);
          margin-bottom: 0.25rem;
        }

        .cert-date {
          font-size: 0.85rem;
          color: var(--gg-ink-muted);
          margin-bottom: 0.5rem;
        }

        .cert-badge {
          display: inline-block;
          background: var(--gg-accent-2);
          color: var(--gg-leaf-text);
          padding: 0.25rem 0.75rem;
          border-radius: 4px;
          font-size: 0.7rem;
          font-weight: 600;
        }

        .empty-state {
          color: var(--gg-dark-3);
          padding: 1rem;
          text-align: center;
        }

        .modal-overlay {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background: rgba(0, 0, 0, 0.7);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 1000;
          padding: 1rem;
        }

        .modal-content {
          background: white;
          border-radius: 12px;
          max-width: 90%;
          max-height: 90vh;
          overflow: auto;
          position: relative;
        }

        .modal-close {
          position: absolute;
          top: 1rem;
          right: 1rem;
          background: rgba(255, 255, 255, 0.9);
          border: none;
          width: 40px;
          height: 40px;
          border-radius: 50%;
          cursor: pointer;
          font-size: 1.5rem;
          color: var(--gg-dark);
        }

        .modal-image {
          width: 100%;
          max-height: 90vh;
          object-fit: contain;
        }
      `}</style>

      {/* Professional Summary */}
      {(portfolio.bio || Number(portfolio.years_experience) > 0) && (
        <div className="portfolio-section-public">
          <h3 className="section-title-public">Professional Summary</h3>
          {portfolio.bio && (
            <p style={{ color: "var(--gg-dark)", lineHeight: 1.6 }}>
              {portfolio.bio}
            </p>
          )}
          {Number(portfolio.years_experience) > 0 && (
            <p style={{ color: "var(--gg-dark-3)", fontSize: "0.9rem" }}>
              <strong>{portfolio.years_experience}</strong> years of experience
            </p>
          )}
        </div>
      )}

      {/* Skills */}
      {skills.length > 0 && (
        <div className="portfolio-section-public">
          <h3 className="section-title-public">Skills</h3>
          <div className="skill-grid">
            {skills.map((skill) => (
              <div key={skill.id} className="skill-card-public">
                <div className="skill-name-public">{skill.skill_name}</div>
                {skill.proficiency && <div className="skill-level-badge">{skill.proficiency}</div>}
                {skill.average_rating ? (
                  <div className="skill-rating-display">
                    <span>★</span>
                    {/* DRF serializes DecimalField as a string, e.g. "5.00" */}
                    <span>{Number(skill.average_rating).toFixed(1)}</span>
                    <span className="skill-rating-count">({skill.rating_count})</span>
                  </div>
                ) : (
                  <div className="skill-rating-count">Not yet rated</div>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Work Samples */}
      {portfolioItems.length > 0 && (
        <div className="portfolio-section-public">
          <h3 className="section-title-public">Work Samples</h3>
          <div className="gallery-grid">
            {portfolioItems.map((item) => {
              const openImage = (url) => {
                setSelectedImage(url);
                setShowGallery(true);
              };
              if (item.before_image_url && item.after_image_url) {
                return (
                  <div key={item.id} className="gallery-pair">
                    <div className="gallery-item" onClick={() => openImage(item.before_image_url)}>
                      <img src={item.before_image_url} alt={`${item.title || "Work sample"} (before)`} />
                      <span className="gallery-tag">Before</span>
                    </div>
                    <div className="gallery-item" onClick={() => openImage(item.after_image_url)}>
                      <img src={item.after_image_url} alt={`${item.title || "Work sample"} (after)`} />
                      <span className="gallery-tag after">After</span>
                    </div>
                  </div>
                );
              }
              const imageUrl = item.image_url || item.after_image_url || item.before_image_url;
              if (!imageUrl) return null;
              return (
                <div key={item.id} className="gallery-item" onClick={() => openImage(imageUrl)}>
                  <img src={imageUrl} alt={item.title} />
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Certifications */}
      {certifications.length > 0 && (
        <div className="portfolio-section-public">
          <h3 className="section-title-public">Certifications</h3>
          <div>
            {certifications.map((cert) => (
              <div key={cert.id} className="cert-item-public">
                <div className="cert-name">{cert.certificate_name}</div>
                <div className="cert-issuer">{cert.issuer}</div>
                <div className="cert-date">Issued {cert.issue_date}</div>
                {cert.is_verified && (
                  <div className="cert-badge">✓ Verified</div>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Employment History */}
      {employmentHistory.length > 0 && (
        <div className="portfolio-section-public">
          <h3 className="section-title-public">Employment History</h3>
          <div>
            {employmentHistory.map((job) => {
              const skillRatings = job.skill_ratings || [];
              return (
                <div key={job.id} className="cert-item-public">
                  <div className="cert-name">{job.title}</div>
                  <div className="cert-issuer">{job.household_name || "Household"}</div>
                  <div className="cert-date">
                    {job.location || ""}
                    {job.completed_at ? ` • Completed ${new Date(job.completed_at).toLocaleDateString()}` : ""}
                  </div>
                  {skillRatings.length > 0 && (
                    <div style={{ marginTop: "0.5rem" }}>
                      {skillRatings.map((sr, idx) => (
                        <div key={idx} className="d-flex justify-content-between mb-1">
                          <small className="text-muted">{sr.skill_name || sr.skill}:</small>
                          <small className="fw-bold">
                            <span className="badge bg-success">{sr.rating} ★</span>
                          </small>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Image Modal */}
      {showGallery && selectedImage && (
        <div className="modal-overlay" onClick={() => setShowGallery(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <button
              className="modal-close"
              onClick={() => setShowGallery(false)}
            >
              ×
            </button>
            <img src={selectedImage} alt="Full view" className="modal-image" />
          </div>
        </div>
      )}
    </div>
  );
}
