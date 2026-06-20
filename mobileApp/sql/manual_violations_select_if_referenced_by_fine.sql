-- Optional: if `manual_violations` has RLS enabled and SELECT is denied to the mobile client,
-- this policy lets anon/authenticated read a report row when a fine references it (so the fined
-- student can load attachment evidence on the Fines screen).
--
-- Security note: any client using the anon key can then SELECT those rows if they know the UUID.
-- Prefer tightening later (e.g. Supabase Auth + claim matching `fines.student_id`, or a SECURITY DEFINER RPC).

alter table if exists public.manual_violations enable row level security;

drop policy if exists manual_violations_select_if_referenced_by_fine on public.manual_violations;
create policy manual_violations_select_if_referenced_by_fine
on public.manual_violations for select
to anon, authenticated
using (
  exists (
    select 1
    from public.fines f
    where f.manual_violation_id = manual_violations.id
  )
);

grant select on table public.manual_violations to anon, authenticated;

notify pgrst, 'reload schema';
