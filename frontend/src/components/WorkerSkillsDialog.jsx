import React, { useState } from "react";
import { MAX_WORKER_SKILLS, OTHER_SKILL, SKILLS } from "../constants/appConstants";
import { splitWorkerSkills } from "../utils/skillUtils";

const CATALOG = SKILLS.filter((skill) => skill !== OTHER_SKILL);

/**
 * Picks the worker's (at most 3) skills from the catalog, plus any typed
 * skill outside it, and saves them in one step. "Save skills" stores the
 * list; the dialog used to close on "Done" without saving anything, and its
 * "Other" box saved the word "Other" as a skill.
 */
export default function WorkerSkillsDialog({ savedSkills, onSave, onClose }) {
  const initial = splitWorkerSkills(savedSkills, SKILLS);
  const [skills, setSkills] = useState([...initial.selected, ...initial.custom]);
  const [typedSkill, setTypedSkill] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const has = (name) => skills.some((skill) => skill.toLowerCase() === name.toLowerCase());
  const full = skills.length >= MAX_WORKER_SKILLS;
  const customSkills = skills.filter((skill) => !CATALOG.some((name) => name.toLowerCase() === skill.toLowerCase()));

  const toggle = (name) => {
    setError("");
    if (has(name)) {
      setSkills((prev) => prev.filter((skill) => skill.toLowerCase() !== name.toLowerCase()));
      return;
    }
    if (full) {
      setError(`You can list up to ${MAX_WORKER_SKILLS} skills. Remove one first.`);
      return;
    }
    setSkills((prev) => [...prev, name]);
  };

  const addTypedSkill = () => {
    const name = typedSkill.replace(/\s+/g, " ").trim();
    if (!name) return;
    if (name.toLowerCase() === OTHER_SKILL.toLowerCase()) {
      setError("Type the skill's name instead of \"Other\".");
      return;
    }
    const catalogName = CATALOG.find((skill) => skill.toLowerCase() === name.toLowerCase());
    if (has(catalogName || name)) {
      setTypedSkill("");
      return;
    }
    if (full) {
      setError(`You can list up to ${MAX_WORKER_SKILLS} skills. Remove one first.`);
      return;
    }
    setSkills((prev) => [...prev, catalogName || name]);
    setTypedSkill("");
    setError("");
  };

  const save = async () => {
    if (skills.length === 0) {
      setError("Choose at least one skill so households can find you.");
      return;
    }
    setSaving(true);
    try {
      await onSave(skills);
      onClose();
    } catch (saveError) {
      setError(saveError.message || "Unable to save your skills.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="modal d-block" style={{ backgroundColor: "rgba(0,0,0,0.5)" }} onClick={onClose}>
      <div
        className="modal-dialog modal-dialog-centered"
        role="dialog"
        aria-modal="true"
        aria-labelledby="worker-skills-dialog-title"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="modal-content">
          <div className="modal-header bg-success">
            <h5 className="modal-title" id="worker-skills-dialog-title">Your Skills</h5>
            <button type="button" className="btn-close" aria-label="Close" onClick={onClose}></button>
          </div>
          <div className="modal-body">
            <p className="text-muted small mb-3">
              Choose up to {MAX_WORKER_SKILLS}. Matching uses these to find jobs for you.
            </p>
            <div className="skills-grid">
              {CATALOG.map((skill) => (
                <label key={skill} className="form-check">
                  <input
                    type="checkbox"
                    className="form-check-input"
                    checked={has(skill)}
                    onChange={() => toggle(skill)}
                  />
                  <span className="form-check-label">{skill}</span>
                </label>
              ))}
            </div>
            {customSkills.length > 0 && (
              <div className="d-flex flex-wrap gap-2 mt-3">
                {customSkills.map((skill) => (
                  <span key={skill} className="badge text-bg-primary d-inline-flex align-items-center gap-1">
                    {skill}
                    <button
                      type="button"
                      className="btn btn-sm btn-link p-0 text-reset"
                      aria-label={`Remove ${skill}`}
                      onClick={() => toggle(skill)}
                    >
                      ×
                    </button>
                  </span>
                ))}
              </div>
            )}
            <label className="form-label fw-semibold mt-3 mb-1" htmlFor="worker-skills-dialog-other">
              A skill not listed
            </label>
            <div className="input-group">
              <input
                id="worker-skills-dialog-other"
                type="text"
                className="form-control"
                maxLength={120}
                placeholder="e.g. Masonry"
                value={typedSkill}
                onChange={(event) => setTypedSkill(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") {
                    event.preventDefault();
                    addTypedSkill();
                  }
                }}
              />
              <button type="button" className="btn btn-outline-secondary" onClick={addTypedSkill} disabled={!typedSkill.trim()}>
                Add
              </button>
            </div>
            {error && <div className="invalid-feedback d-block mt-2" role="alert">{error}</div>}
          </div>
          <div className="modal-footer">
            <button type="button" className="btn btn-outline-secondary" onClick={onClose} disabled={saving}>
              Cancel
            </button>
            <button type="button" className="btn btn-success" onClick={save} disabled={saving}>
              {saving ? "Saving..." : "Save skills"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
