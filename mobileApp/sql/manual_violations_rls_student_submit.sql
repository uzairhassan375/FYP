-- Run in Supabase SQL Editor after manual_violations_and_storage.sql
-- Fixes: "new row violates row-level security policy" when submitting a report
-- from the student app (storage upload + manual_violations insert).

-- -----------------------------------------------------------------------------
-- public.manual_violations: student app may use `authenticated` JWT, not only `anon`
-- (e.g. if a session exists). Custom RPC login still often uses `anon`; cover both.
-- -----------------------------------------------------------------------------
drop policy if exists "authenticated_insert_manual_violations" on public.manual_violations;
create policy "authenticated_insert_manual_violations"
on public.manual_violations for insert
to authenticated
with check (true);

-- -----------------------------------------------------------------------------
-- storage.objects: upsert: true on upload can UPDATE an existing object path
-- -----------------------------------------------------------------------------
drop policy if exists "anon_update_manual_violation_media" on storage.objects;
create policy "anon_update_manual_violation_media"
on storage.objects for update
to anon
using (bucket_id = 'manual-violations')
with check (bucket_id = 'manual-violations');

drop policy if exists "authenticated_insert_manual_violation_media" on storage.objects;
create policy "authenticated_insert_manual_violation_media"
on storage.objects for insert
to authenticated
with check (bucket_id = 'manual-violations');

drop policy if exists "authenticated_update_manual_violation_media" on storage.objects;
create policy "authenticated_update_manual_violation_media"
on storage.objects for update
to authenticated
using (bucket_id = 'manual-violations')
with check (bucket_id = 'manual-violations');
