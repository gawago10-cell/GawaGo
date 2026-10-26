import { MAX_WORKER_SKILLS, OTHER_SKILL } from "../constants/appConstants";

function cleanSkillName(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function isOtherChoice(value) {
  return cleanSkillName(value).toLowerCase() === OTHER_SKILL.toLowerCase();
}

/**
 * The skills a worker form saves: the ticked catalog skills, plus the typed
 * skill when "Other" is ticked. "Other" itself is never saved -- it used to
 * be, taking one of the three slots and lowering every match score.
 * Duplicates differing only in case or spacing count once.
 */
export function resolveWorkerSkills(selected, customSkill) {
  const names = [];
  const seen = new Set();
  const add = (value) => {
    const name = cleanSkillName(value);
    const key = name.toLowerCase();
    if (!name || isOtherChoice(name) || seen.has(key)) return;
    seen.add(key);
    names.push(name);
  };
  const chosen = Array.isArray(selected) ? selected : [];
  chosen.forEach(add);
  if (chosen.some(isOtherChoice)) add(customSkill);
  return names;
}

/** `{ skills?: message, customSkill?: message }` for a worker's skill choice. */
export function validateWorkerSkills(selected, customSkill) {
  const chosen = Array.isArray(selected) ? selected : [];
  if (chosen.some(isOtherChoice) && (!cleanSkillName(customSkill) || isOtherChoice(customSkill))) {
    return { customSkill: "Type the name of your other skill, or untick Other." };
  }
  const skills = resolveWorkerSkills(chosen, customSkill);
  if (skills.length === 0) {
    return { skills: "Choose at least one skill so households can find you." };
  }
  if (skills.length > MAX_WORKER_SKILLS) {
    return { skills: `You can list up to ${MAX_WORKER_SKILLS} skills, including a typed one.` };
  }
  return {};
}

/** Splits a saved skill list into catalog ticks and a typed "Other" skill,
 * so a form can show a custom skill in its text box. */
export function splitWorkerSkills(savedSkills, catalog) {
  const catalogByKey = new Map(catalog.filter((name) => !isOtherChoice(name)).map((name) => [name.toLowerCase(), name]));
  const selected = [];
  const custom = [];
  (Array.isArray(savedSkills) ? savedSkills : []).forEach((value) => {
    const name = cleanSkillName(value);
    if (!name || isOtherChoice(name)) return;
    const catalogName = catalogByKey.get(name.toLowerCase());
    if (catalogName) {
      selected.push(catalogName);
    } else {
      custom.push(name);
    }
  });
  return { selected, custom };
}
