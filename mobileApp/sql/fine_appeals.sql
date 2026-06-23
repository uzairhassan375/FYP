-- Fine appeals: students request review; incharge approves (waive) or rejects.
-- Run in Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS fine_appeals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  fine_id UUID NOT NULL REFERENCES fines(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE SET NULL,
  student_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  student_name TEXT,
  message TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  review_note TEXT,
  reviewed_by_name TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fine_appeals_fine_id ON fine_appeals(fine_id);
CREATE INDEX IF NOT EXISTS idx_fine_appeals_status ON fine_appeals(status);
CREATE INDEX IF NOT EXISTS idx_fine_appeals_created_at ON fine_appeals(created_at DESC);

-- Only one open appeal per fine
CREATE UNIQUE INDEX IF NOT EXISTS idx_fine_appeals_one_pending
  ON fine_appeals(fine_id)
  WHERE status = 'pending';

ALTER TABLE fine_appeals ENABLE ROW LEVEL SECURITY;

-- Mobile reads own appeals via backend; optional direct read for anon/authenticated
DROP POLICY IF EXISTS fine_appeals_select_all ON fine_appeals;
CREATE POLICY fine_appeals_select_all ON fine_appeals FOR SELECT TO anon, authenticated USING (true);

GRANT SELECT, INSERT ON fine_appeals TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
