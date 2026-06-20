-- Links a fine to the student-submitted manual report whose evidence should show in the mobile app.
-- Run in Supabase SQL Editor after manual_violations exists.

alter table if exists public.fines
  add column if not exists manual_violation_id uuid references public.manual_violations (id) on delete set null;

create index if not exists idx_fines_manual_violation_id on public.fines (manual_violation_id);

notify pgrst, 'reload schema';
