-- AI review metadata for mobile student reports.
-- Run in Supabase SQL Editor after manual_violations exists.

alter table if exists public.manual_violations
  add column if not exists ai_status text;

alter table if exists public.manual_violations
  add column if not exists ai_analysis jsonb;

alter table if exists public.manual_violations
  add column if not exists ai_violation_id uuid references public.violations (id) on delete set null;

comment on column public.manual_violations.ai_status is
  'pending AI: processing | auto_fined | detected_no_fine | pending_review | no_detection | failed';
