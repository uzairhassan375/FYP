/**
 * Canonical violation type keys — must stay in sync with AI output in video_pipeline.py
 * and matching logic in webApp/backend/server.js.
 */
export const AI_VIOLATION_PRESETS = [
  {
    key: "gun",
    title: "Gun Detected",
    severity: "HIGH",
    aliases: "gun, pistol, rifle, firearm",
  },
  {
    key: "knife",
    title: "Knife Detected",
    severity: "HIGH",
    aliases: "knife, blade, knives",
  },
  {
    key: "weapon",
    title: "Weapon (Generic)",
    severity: "HIGH",
    aliases: "weapon (when type is unclear)",
  },
  {
    key: "fight",
    title: "Fighting",
    severity: "HIGH",
    aliases: "fight, fighting, violence",
  },
  {
    key: "above_the_knee",
    title: "Improper Uniform / Dress Code",
    severity: "LOW",
    aliases: "above_the_knee, dresscode, uniform",
  },
  {
    key: "smoking",
    title: "Smoking",
    severity: "MED",
    aliases: "smoking (manual reports)",
  },
];

const ALIAS_GROUPS = [
  ["gun", "pistol", "rifle", "firearm", "guns"],
  ["knife", "blade", "knives"],
  ["weapon"],
  ["fight", "fighting", "violence"],
  ["dresscode", "dress_code", "dress code"],
  [
    "above_the_knee",
    "above knee",
    "shorts",
    "skirt",
    "uniform",
    "improper_uniform",
    "improper uniform",
    "improper_dress",
    "improper dress",
  ],
  ["smoking"],
];

const CANONICAL_OVERRIDES = {
  gun: "gun",
  pistol: "gun",
  rifle: "gun",
  firearm: "gun",
  guns: "gun",
  knife: "knife",
  blade: "knife",
  knives: "knife",
  weapon: "weapon",
  fight: "fight",
  fighting: "fight",
  violence: "fight",
  dresscode: "above_the_knee",
  dress_code: "above_the_knee",
  "dress code": "above_the_knee",
  above_the_knee: "above_the_knee",
  "above knee": "above_the_knee",
  shorts: "above_the_knee",
  skirt: "above_the_knee",
  uniform: "above_the_knee",
  improper_uniform: "above_the_knee",
  "improper uniform": "above_the_knee",
  improper_dress: "above_the_knee",
  "improper dress": "above_the_knee",
  smoking: "smoking",
};

export function canonicalViolationType(violationType) {
  if (violationType == null || String(violationType).trim() === "") return null;
  const key = String(violationType).toLowerCase().trim();
  if (CANONICAL_OVERRIDES[key]) return CANONICAL_OVERRIDES[key];
  for (const group of ALIAS_GROUPS) {
    if (group.includes(key)) return group[0] === "dresscode" ? "above_the_knee" : group[0];
  }
  return key;
}

/** Pick the policy rule that best matches an AI / violation type string. */
export function findMatchingPolicyRule(rules, violationType) {
  if (!rules?.length) return null;
  const canon = canonicalViolationType(violationType);
  if (!canon) {
    return rules.find((r) => !r.violation_type) || null;
  }

  let rule = rules.find(
    (r) => r.violation_type && r.violation_type.toLowerCase() === canon,
  );
  if (rule) return rule;

  rule = rules.find(
    (r) =>
      r.violation_type &&
      canonicalViolationType(r.violation_type) === canon,
  );
  if (rule) return rule;

  rule = rules.find((r) => {
    if (!r.violation_type) return false;
    const rt = r.violation_type.toLowerCase();
    return rt.includes(canon) || canon.includes(rt);
  });
  if (rule) return rule;

  return rules.find((r) => !r.violation_type) || null;
}

export function presetForViolationKey(key) {
  return AI_VIOLATION_PRESETS.find((p) => p.key === key) || null;
}
