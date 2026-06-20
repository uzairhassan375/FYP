-- Run in Supabase SQL Editor so the student mobile app (anon key) can list fines for their student_id.
-- The app filters by student_id in Dart; tighten RLS later for production (e.g. RPC with student_login).

alter table if exists public.fines enable row level security;

drop policy if exists fines_anon_select_all on public.fines;
create policy fines_anon_select_all
on public.fines for select
to anon
using (true);

drop policy if exists fines_authenticated_select_all on public.fines;
create policy fines_authenticated_select_all
on public.fines for select
to authenticated
using (true);

grant select on table public.fines to anon, authenticated;

notify pgrst, 'reload schema';
