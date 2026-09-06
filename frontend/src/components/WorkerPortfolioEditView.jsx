import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/apiClient";

export default function WorkerPortfolioEditView({
  currentUser,
  currentWorker,
  onSave,
  onCancel,
  formatCurrency,
}) {
  const [portfolio, setPortfolio] = useState(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [portfolioData, setPortfolioData] = useState({
    bio: "",
    years_experience: 0,
  });
  const [skills, setSkills] = useState([]);
  const [newSkill, setNewSkill] = useState({ skill_name: "", proficiency: "beginner" });
  const [certifications, setCertifications] = useState([]);
  const [portfolioItems, setPortfolioItems] = useState([]);

  useEffect(() => {
    fetchPortfolio();
  }, [currentUser.id]);

  const fetchPortfolio = async () => {
    try {
      setLoading(true);
      const response = await apiRequest(`/accounts/me/portfolio/`, "GET");
      setPortfolio(response);
      setPortfolioData({
        bio: response.bio || "",
        years_experience: response.years_experience || 0,
      });
      setSkills(response.skills || []);
      setCertifications(response.certifications || []);
      setPortfolioItems(response.portfolio_items || []);
    } catch (error) {
      console.error("Failed to fetch portfolio:", error);
    } finally {
      setLoading(false);
    }
  };

  const handlePortfolioChange = (e) => {
    const { name, value } = e.target;
    setPortfolioData((prev) => ({
      ...prev,
      [name]: name === "years_experience" ? parseInt(value) || 0 : value,
    }));
  };

  const handleAddSkill = async () => {
    if (!newSkill.skill_name.trim()) {
      alert("Please enter a skill name");
      return;
    }
    try {
      const response = await apiRequest(`/accounts/me/portfolio/skills/`, "POST", newSkill);
      setSkills((prev) => [...prev, response]);
      setNewSkill({ skill_name: "", proficiency: "beginner" });
    } catch (error) {
      console.error("Failed to add skill:", error);
      alert("Failed to add skill");
    }
  };

  const handleRemoveSkill = async (skillId) => {
    if (!window.confirm("Remove this skill?")) return;
    try {
      await apiRequest(`/accounts/me/portfolio/skills/${skillId}/`, "DELETE");
      setSkills((prev) => prev.filter((s) => s.id !== skillId));
    } catch (error) {
      console.error("Failed to remove skill:", error);
      alert("Failed to remove skill");
    }
  };

  const handleAddCertification = async () => {
    // This would open a modal/form for adding certification
    // For now, just show a basic alert
    alert("Certification upload feature coming soon");
  };

  const handleRemoveCertification = async (certId) => {
    if (!window.confirm("Remove this certification?")) return;
    try {
      await apiRequest(`/accounts/me/portfolio/certifications/${certId}/`, "DELETE");
      setCertifications((prev) => prev.filter((c) => c.id !== certId));
    } catch (error) {
      console.error("Failed to remove certification:", error);
      alert("Failed to remove certification");
    }
  };

  const handleAddPortfolioItem = async (file) => {
    if (!file) return;
    try {
      const formData = new FormData();
      formData.append("image", file);
      formData.append("title", file.name.split(".")[0]);
      const response = await apiRequest(`/accounts/me/portfolio/items/`, "POST", formData, {
        headers: { "Content-Type": "multipart/form-data" },
      });
      setPortfolioItems((prev) => [...prev, response]);
    } catch (error) {
      console.error("Failed to add portfolio item:", error);
      alert("Failed to upload image");
    }
  };

  const handleRemovePortfolioItem = async (itemId) => {
    if (!window.confirm("Remove this work sample?")) return;
    try {
      await apiRequest(`/accounts/me/portfolio/items/${itemId}/`, "DELETE");
      setPortfolioItems((prev) => prev.filter((i) => i.id !== itemId));
    } catch (error) {
      console.error("Failed to remove item:", error);
      alert("Failed to remove item");
    }
  };

  const handleSavePortfolio = async () => {
    try {
      setSaving(true);
      await apiRequest(`/accounts/me/portfolio/`, "PATCH", portfolioData);
      alert("Portfolio saved successfully!");
      if (onSave) onSave();
    } catch (error) {
      console.error("Failed to save portfolio:", error);
      alert("Failed to save portfolio");
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return <div className="text-center py-5">Loading portfolio...</div>;
  }

  return (
    <div className="worker-portfolio-container">
      <style>{`
        .worker-portfolio-container {
          max-width: 1200px;
          margin: 0 auto;
          padding: 2rem;
          background: var(--gg-bg);
        }

        .portfolio-header {
          background: white;
          border-radius: 12px;
          padding: 2rem;
          margin-bottom: 2rem;
          border: 1px solid var(--gg-border);
        }

        .portfolio-section {
          background: white;
          border-radius: 12px;
          padding: 2rem;
          margin-bottom: 2rem;
          border: 1px solid var(--gg-border);
        }

        .section-title {
          font-size: 1.2rem;
          font-weight: 600;
          color: var(--gg-dark);
          margin-bottom: 1.5rem;
          display: flex;
          justify-content: space-between;
          align-items: center;
        }

        .btn-add {
          background: var(--gg-primary);
          color: white;
          border: none;
          padding: 0.5rem 1rem;
          border-radius: 6px;
          cursor: pointer;
          font-weight: 500;
          font-size: 0.9rem;
        }

        .btn-add:hover {
          background: var(--gg-primary-strong);
        }

        .form-group {
          margin-bottom: 1.5rem;
        }

        .form-group label {
          font-weight: 600;
          color: var(--gg-dark);
          margin-bottom: 0.5rem;
          display: block;
        }

        .form-group input,
        .form-group textarea,
        .form-group select {
          width: 100%;
          padding: 0.75rem;
          border: 1px solid var(--gg-border);
          border-radius: 6px;
          font-size: 0.95rem;
          font-family: inherit;
        }

        .form-group input:focus,
        .form-group textarea:focus,
        .form-group select:focus {
          outline: none;
          border-color: var(--gg-primary);
          background: var(--gg-soft);
          box-shadow: 0 0 0 3px rgba(76, 175, 116, 0.1);
        }

        .skill-input-group {
          display: grid;
          grid-template-columns: 2fr 1fr auto;
          gap: 1rem;
          align-items: flex-end;
        }

        .skill-card {
          background: var(--gg-bg);
          padding: 1rem;
          border-radius: 8px;
          border: 1px solid var(--gg-border);
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 0.5rem;
        }

        .skill-name {
          font-weight: 600;
          color: var(--gg-dark);
        }

        .skill-level {
          background: var(--gg-primary);
          color: white;
          padding: 0.25rem 0.75rem;
          border-radius: 4px;
          font-size: 0.75rem;
          font-weight: 600;
        }

        .btn-remove {
          background: none;
          border: none;
          color: #dc3545;
          cursor: pointer;
          font-size: 1.2rem;
        }

        .portfolio-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
          gap: 1rem;
        }

        .portfolio-item {
          border-radius: 8px;
          overflow: hidden;
          background: var(--gg-bg);
          border: 1px solid var(--gg-border);
          aspect-ratio: 1;
          position: relative;
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .portfolio-item img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }

        .action-buttons {
          display: flex;
          gap: 1rem;
          margin-top: 2rem;
        }

        .btn-save {
          background: var(--gg-primary);
          color: white;
          border: none;
          padding: 0.75rem 2rem;
          border-radius: 6px;
          cursor: pointer;
          font-weight: 600;
        }

        .btn-save:hover {
          background: var(--gg-primary-strong);
        }

        .btn-cancel {
          background: var(--gg-bg);
          color: var(--gg-dark);
          border: 1px solid var(--gg-border);
          padding: 0.75rem 2rem;
          border-radius: 6px;
          cursor: pointer;
          font-weight: 600;
        }
      `}</style>

      {/* Portfolio Header */}
      <div className="portfolio-header">
        <h2 style={{ margin: 0, color: "var(--gg-dark)" }}>My Portfolio</h2>
        <p style={{ color: "var(--gg-dark-3)", marginTop: "0.5rem" }}>
          Build your professional profile with skills, work samples, and certifications.
        </p>
      </div>

      {/* Bio & Experience */}
      <div className="portfolio-section">
        <h3 style={{ color: "var(--gg-dark)", marginTop: 0 }}>Professional Summary</h3>
        <div className="form-group">
          <label>Professional Bio</label>
          <textarea
            name="bio"
            value={portfolioData.bio}
            onChange={handlePortfolioChange}
            placeholder="Tell households about your experience and skills..."
            rows="4"
          />
        </div>
        <div className="form-group">
          <label>Years of Experience</label>
          <input
            type="number"
            name="years_experience"
            value={portfolioData.years_experience}
            onChange={handlePortfolioChange}
            min="0"
          />
        </div>
      </div>

      {/* Skills */}
      <div className="portfolio-section">
        <div className="section-title">
          <h3 style={{ margin: 0 }}>Skills</h3>
          <button className="btn-add" onClick={() => {}}>+ Add Skill</button>
        </div>

        <div className="skill-input-group" style={{ marginBottom: "1.5rem" }}>
          <input
            type="text"
            placeholder="Skill name (e.g., House Cleaning)"
            value={newSkill.skill_name}
            onChange={(e) => setNewSkill((prev) => ({ ...prev, skill_name: e.target.value }))}
          />
          <select
            value={newSkill.proficiency}
            onChange={(e) => setNewSkill((prev) => ({ ...prev, proficiency: e.target.value }))}
          >
            <option value="beginner">Beginner</option>
            <option value="intermediate">Intermediate</option>
            <option value="expert">Expert</option>
          </select>
          <button className="btn-add" onClick={handleAddSkill}>Add</button>
        </div>

        <div>
          {skills.map((skill) => (
            <div key={skill.id} className="skill-card">
              <div>
                <div className="skill-name">{skill.skill_name}</div>
              </div>
              <div style={{ display: "flex", gap: "1rem", alignItems: "center" }}>
                <span className="skill-level">{skill.proficiency}</span>
                {skill.average_rating && (
                  <span style={{ color: "var(--gg-dark-3)", fontSize: "0.9rem" }}>
                    ★ {skill.average_rating.toFixed(1)} ({skill.rating_count})
                  </span>
                )}
                <button className="btn-remove" onClick={() => handleRemoveSkill(skill.id)}>×</button>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Work Samples */}
      <div className="portfolio-section">
        <div className="section-title">
          <h3 style={{ margin: 0 }}>Work Samples</h3>
          <label className="btn-add" style={{ margin: 0, display: "block", cursor: "pointer" }}>
            + Upload Sample
            <input
              type="file"
              onChange={(e) => handleAddPortfolioItem(e.target.files?.[0])}
              style={{ display: "none" }}
              accept="image/*"
            />
          </label>
        </div>

        {portfolioItems.length > 0 ? (
          <div className="portfolio-grid">
            {portfolioItems.map((item) => (
              <div key={item.id} className="portfolio-item" style={{ position: "relative" }}>
                <img src={item.image_url} alt={item.title} />
                <button
                  className="btn-remove"
                  onClick={() => handleRemovePortfolioItem(item.id)}
                  style={{ position: "absolute", top: "0.5rem", right: "0.5rem" }}
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        ) : (
          <p style={{ color: "var(--gg-dark-3)" }}>No work samples yet. Upload photos of your completed work.</p>
        )}
      </div>

      {/* Certifications */}
      <div className="portfolio-section">
        <div className="section-title">
          <h3 style={{ margin: 0 }}>Certifications</h3>
          <button className="btn-add" onClick={handleAddCertification}>+ Add Certificate</button>
        </div>

        {certifications.length > 0 ? (
          <div>
            {certifications.map((cert) => (
              <div key={cert.id} style={{
                background: "var(--gg-bg)",
                padding: "1rem",
                borderRadius: "8px",
                borderLeft: "4px solid var(--gg-primary)",
                marginBottom: "1rem",
                display: "flex",
                justifyContent: "space-between",
              }}>
                <div>
                  <div style={{ fontWeight: 600, color: "var(--gg-dark)" }}>{cert.certificate_name}</div>
                  <div style={{ fontSize: "0.9rem", color: "var(--gg-dark-3)" }}>{cert.issuer}</div>
                  <div style={{ fontSize: "0.85rem", color: "#999" }}>{cert.issue_date}</div>
                  {cert.is_verified && (
                    <span style={{
                      display: "inline-block",
                      background: "var(--gg-accent-2)",
                      color: "var(--gg-primary-strong)",
                      padding: "0.25rem 0.75rem",
                      borderRadius: "4px",
                      fontSize: "0.7rem",
                      fontWeight: 600,
                      marginTop: "0.5rem",
                    }}>
                      ✓ Verified
                    </span>
                  )}
                </div>
                <button className="btn-remove" onClick={() => handleRemoveCertification(cert.id)}>×</button>
              </div>
            ))}
          </div>
        ) : (
          <p style={{ color: "var(--gg-dark-3)" }}>No certifications yet. Add TESDA or other credentials.</p>
        )}
      </div>

      {/* Employment History - Auto-populated, read-only */}
      <div className="portfolio-section">
        <h3 style={{ color: "var(--gg-dark)", marginTop: 0 }}>Employment History</h3>
        <p style={{ color: "var(--gg-dark-3)", fontSize: "0.9rem", marginBottom: "1.5rem" }}>
          Auto-populated from completed jobs. Shows skill ratings from households.
        </p>
        {/* Will be populated from job completion data */}
        <p style={{ color: "var(--gg-dark-3)" }}>No completed jobs yet.</p>
      </div>

      {/* Action Buttons */}
      <div className="action-buttons">
        <button className="btn-save" onClick={handleSavePortfolio} disabled={saving}>
          {saving ? "Saving..." : "Save Changes"}
        </button>
        <button className="btn-cancel" onClick={onCancel}>Cancel</button>
      </div>
    </div>
  );
}
