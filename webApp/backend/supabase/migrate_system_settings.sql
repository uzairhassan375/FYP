-- Admin-configurable system settings (violation cooldown, etc.)
CREATE TABLE IF NOT EXISTS system_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;

INSERT INTO system_settings (key, value)
VALUES ('violation_cooldown_minutes', '15')
ON CONFLICT (key) DO NOTHING;
