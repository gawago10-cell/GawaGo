import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/apiClient";

export default function WorkerPortfolioViewPublic({
  workerId,
  workerName,
  currentUser,
}) {
  const [portfolio, setPortfolio] = useState(null);
  const [loading, setLoading] = useState(true);
  const [showGallery, setShowGallery] = useState(false);
  const [selectedImage, setSelectedImage] = useState(null);

  useEffect(() => {
    fetchPortfolio();
  }, [workerId]);

  const fetchPortfolio = async () => {
    try {
      setLoading(true);
      const response = await apiRequest(`/accounts/profiles/${workerId}/portfolio/`, "GET");
      setPortfolio(response);
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

  if (!portfolio || (typeof portfolio === 'object' && Object.keys(portfolio).length === 0)) {
    return (
      <div style={{ padding: "2rem", textAlign: "center", color: "#999", background: "#fafafa", borderRadius: "8px", marginTop: "2rem" }}>
        No portfolio information yet
      </div>
    );
  }

  const skills = portfolio.skills || [];
  const certifications = portfolio.certifications || [];
  const portfolioItems = portfolio.portfolio_items || [];

  return (
    <div className="worker-portfolio-public" style={{ marginTop: "2rem" }}>
      <style>{`
        .worker-portfolio-public {
          background: white;
          border-radius: 12px;
          border: 1px solid var(--gg-border);
          overflow: hidden;
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
          background: var(--gg-bg);
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
          background: var(--gg-primary);
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
          color: #ffc107;
          font-size: 0.9rem;
        }

        .skill-rating-count {
          color: var(--gg-dark-3);
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

        .cert-item-public {
          background: var(--gg-bg);
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
          color: var(--gg-dark-3);
          margin-bottom: 0.25rem;
        }

        .cert-date {
          font-size: 0.85rem;
          color: #999;
          margin-bottom: 0.5rem;
        }

        .cert-badge {
          display: inline-block;
          background: var(--gg-accent-2);
          color: var(--gg-primary-strong);
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
      {portfolio.bio && (
        <div className="portfolio-section-public">
          <h3 className="section-title-public">Professional Summary</h3>
          <p style={{ color: "var(--gg-dark)", lineHeight: 1.6 }}>
            {portfolio.bio}
          </p>
          {portfolio.years_experience > 0 && (
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
                <div className="skill-level-badge">{skill.proficiency}</div>
                {skill.average_rating ? (
                  <div className="skill-rating-display">
                    <span>★</span>
                    <span>{skill.average_rating.toFixed(1)}</span>
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
            {portfolioItems.map((item) => (
              <div
                key={item.id}
                className="gallery-item"
                onClick={() => {
                  setSelectedImage(item.image_url);
                  setShowGallery(true);
                }}
              >
                <img src={item.image_url} alt={item.title} />
              </div>
            ))}
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
