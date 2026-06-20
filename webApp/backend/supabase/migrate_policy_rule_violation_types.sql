-- Normalize policy_rules.violation_type to AI-canonical keys.
-- Run once in Supabase SQL editor if existing rules use old labels.

UPDATE policy_rules
SET violation_type = 'fight'
WHERE LOWER(COALESCE(violation_type, '')) IN ('fighting', 'violence');

UPDATE policy_rules
SET violation_type = 'above_the_knee'
WHERE LOWER(COALESCE(violation_type, '')) IN (
  'uniform',
  'improper uniform',
  'improper_uniform',
  'improper_dress',
  'improper dress',
  'dresscode',
  'dress_code',
  'dress code',
  'incomplete uniform'
);

UPDATE policy_rules
SET violation_type = 'gun'
WHERE LOWER(COALESCE(violation_type, '')) IN ('gun detected', 'guns', 'pistol', 'rifle', 'firearm');

UPDATE policy_rules
SET violation_type = 'knife'
WHERE LOWER(COALESCE(violation_type, '')) IN ('knife detected', 'knives', 'blade');

-- Optional: align titles when violation_type was missing but title is descriptive
UPDATE policy_rules SET title = 'Gun Detected', violation_type = 'gun'
WHERE violation_type IS NULL AND LOWER(title) LIKE '%gun%';

UPDATE policy_rules SET title = 'Knife Detected', violation_type = 'knife'
WHERE violation_type IS NULL AND LOWER(title) LIKE '%knife%';

UPDATE policy_rules SET title = 'Fighting', violation_type = 'fight'
WHERE violation_type IS NULL AND LOWER(title) LIKE '%fight%';

UPDATE policy_rules SET title = 'Improper Uniform / Dress Code', violation_type = 'above_the_knee'
WHERE violation_type IS NULL
  AND (LOWER(title) LIKE '%uniform%' OR LOWER(title) LIKE '%dress%');
