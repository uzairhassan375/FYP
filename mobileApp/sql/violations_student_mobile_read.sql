-- Run in Supabase SQL Editor so the student app (anon key) can read `violations.clip_url`
-- for rows linked from `fines.violation_id` (camera evidence on fines).
-- Demo-wide read; tighten for production (e.g. RPC that checks student_id).

alter table if exists public.violations enable row level security;

drop policy if exists violations_anon_select_all on public.violations;
create policy violations_anon_select_all
on public.violations for select
to anon
using (true);

drop policy if exists violations_authenticated_select_all on public.violations;
create policy violations_authenticated_select_all
on public.violations for select
to authenticated
using (true);

grant select on table public.violations to anon, authenticated;

notify pgrst, 'reload schema';
