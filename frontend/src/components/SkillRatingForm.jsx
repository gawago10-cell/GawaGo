import React, { useEffect, useState } from "react";
import { apiRequest } from "../api/apiClient";

export default function SkillRatingForm({
  jobId,
  workerId,
  workerName,
  jobTitle,
  onSubmitSuccess,
  onCancel,
}) {
  const [skills, setSkills] = useState([]);
  const [skillRatings, setSkillRatings] = useState({});
  const [feedback, setFeedback] = useState("");
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    fetchWorkerSkills();
  }, [workerId]);

  const fetchWorkerSkills = async () => {
    try {
      setLoading(true);
      const response = await apiRequest(`/accounts/profiles/${workerId}/portfolio/`, "GET");
      setSkills(response.skills || []);
      const initialRatings = {};
      (response.skills || []).forEach((skill) => {
        initialRatings[skill.id] = 5;
      });
      setSkillRatings(initialRatings);
    } catch (error) {
      console.error("Failed to fetch worker skills:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleRatingChange = (skillId, rating) => {
    setSkillRatings((prev) => ({
      ...prev,
      [skillId]: parseInt(rating),
    }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (Object.values(skillRatings).filter(r => r).length === 0) {
      alert("Please rate at least one skill");
      return;
    }

    try {
      setSubmitting(true);
      for (const [skillId, rating] of Object.entries(skillRatings)) {
        if (rating) {
          await apiRequest(`/accounts/jobs/${jobId}/skill-ratings/`, "POST", {
            job: jobId,
            skill: skillId,
            rating: rating,
            feedback: feedback,
          });
        }
      }
      alert("Skills rated successfully!");
      if (onSubmitSuccess) onSubmitSuccess();
    } catch (error) {
      console.error("Failed to submit ratings:", error);
      alert("Failed to submit ratings");
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) {
    return <div className="text-center py-5">Loading worker skills...</div>;
  }

  if (skills.length === 0) {
    return (
      <div className="alert alert-info">
        {workerName} hasn't added any skills to their portfolio yet.
      </div>
    );
  }

  return (
    <div className="skill-rating-form" style={{ maxWidth: "600px" }}>
      <style>{`
        .skill-rating-form {
          background: white;
          border-radius: 12px;
          padding: 2rem;
          border: 1px solid var(--gg-border);
        }

        .form-title {
          font-size: 1.2rem;
          font-weight: 600;
          color: var(--gg-dark);
          margin-bottom: 0.5rem;
        }

        .form-subtitle {
          font-size: 0.9rem;
          color: var(--gg-dark-3);
          margin-bottom: 1.5rem;
        }

        .skill-rating-item {
          margin-bottom: 1.5rem;
          padding-bottom: 1.5rem;
          border-bottom: 1px solid var(--gg-border);
        }

        .skill-rating-item:last-of-type {
          border-bottom: none;
        }

        .skill-rating-label {
          font-weight: 600;
          color: var(--gg-dark);
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 0.75rem;
        }

        .skill-level-badge {
          background: var(--gg-accent-2);
          color: var(--gg-primary-strong);
          padding: 0.25rem 0.75rem;
          border-radius: 4px;
          font-size: 0.75rem;
          font-weight: 600;
        }

        .rating-stars {
          display: flex;
          gap: 0.5rem;
          font-size: 1.5rem;
        }

        .star {
          cursor: pointer;
          color: #ddd;
          transition: color 0.2s;
        }

        .star.active {
          color: #ffc107;
        }

        .star:hover {
          color: #ffc107;
        }

        .rating-value {
          color: var(--gg-dark-3);
          font-size: 0.9rem;
          margin-top: 0.5rem;
        }

        .form-group {
          margin-bottom: 1.5rem;
        }

        .form-group label {
          font-weight: 600;
          color: var(--gg-dark);
          display: block;
          margin-bottom: 0.5rem;
        }

        .form-group textarea {
          width: 100%;
          padding: 0.75rem;
          border: 1px solid var(--gg-border);
          border-radius: 6px;
          font-size: 0.95rem;
          font-family: inherit;
          resize: vertical;
        }

        .form-group textarea:focus {
          outline: none;
          border-color: var(--gg-primary);
          box-shadow: 0 0 0 3px rgba(76, 175, 116, 0.1);
        }

        .action-buttons {
          display: flex;
          gap: 1rem;
          margin-top: 2rem;
        }

        .btn-submit {
          background: var(--gg-primary);
          color: white;
          border: none;
          padding: 0.75rem 2rem;
          border-radius: 6px;
          cursor: pointer;
          font-weight: 600;
          flex: 1;
        }

        .btn-submit:hover {
          background: var(--gg-primary-strong);
        }

        .btn-submit:disabled {
          opacity: 0.6;
          cursor: not-allowed;
        }

        .btn-cancel {
          background: var(--gg-bg);
          color: var(--gg-dark);
          border: 1px solid var(--gg-border);
          padding: 0.75rem 2rem;
          border-radius: 6px;
          cursor: pointer;
          font-weight: 600;
          flex: 1;
        }
      `}</style>

      <div className="form-title">Rate {workerName}'s Skills</div>
      <div className="form-subtitle">
        You worked together on: <strong>{jobTitle}</strong>
      </div>

      <form onSubmit={handleSubmit}>
        {skills.map((skill) => (
          <div key={skill.id} className="skill-rating-item">
            <div className="skill-rating-label">
              <div>
                {skill.skill_name}
                <span className="skill-level-badge" style={{ marginLeft: "0.5rem" }}>
                  {skill.proficiency}
                </span>
              </div>
            </div>

            <div className="rating-stars">
              {[1, 2, 3, 4, 5].map((star) => (
                <span
                  key={star}
                  className={`star ${skillRatings[skill.id] >= star ? "active" : ""}`}
                  onClick={() => handleRatingChange(skill.id, star)}
                >
                  ★
                </span>
              ))}
            </div>
            <div className="rating-value">
              {skillRatings[skill.id]
                ? `${skillRatings[skill.id]}/5 stars`
                : "Not rated"}
            </div>
          </div>
        ))}

        <div className="form-group">
          <label htmlFor="feedback">Optional Feedback</label>
          <textarea
            id="feedback"
            value={feedback}
            onChange={(e) => setFeedback(e.target.value)}
            placeholder="Share details about the worker's performance..."
            rows="3"
          />
        </div>

        <div className="action-buttons">
          <button
            type="submit"
            className="btn-submit"
            disabled={submitting}
          >
            {submitting ? "Submitting..." : "Submit Ratings"}
          </button>
          <button
            type="button"
            className="btn-cancel"
            onClick={onCancel}
            disabled={submitting}
          >
            Cancel
          </button>
        </div>
      </form>
    </div>
  );
}
