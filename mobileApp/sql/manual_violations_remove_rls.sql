-- Run once in Supabase SQL Editor.
-- Removes RLS on manual_violations and replaces storage policies with simple
-- allow rules for bucket `manual-violations` so the student app can upload + insert.

-- -----------------------------------------------------------------------------
-- 1) Drop every RLS policy on public.manual_violations, then turn RLS off
-- -----------------------------------------------------------------------------
do $$
declare
  pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'manual_violations'
  loop
    execute format('drop policy if exists %I on public.manual_violations', pol.policyname);
  end loop;
end $$;

alter table if exists public.manual_violations disable row level security;

grant select, insert, update, delete on table public.manual_violations to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2) Storage: drop known policies for this bucket, then one permissive policy per role
-- -----------------------------------------------------------------------------
drop policy if exists "anon_insert_manual_violation_videos" on storage.objects;
drop policy if exists "anon_update_manual_violation_media" on storage.objects;
drop policy if exists "anon_delete_manual_violation_media" on storage.objects;
drop policy if exists "authenticated_insert_manual_violation_media" on storage.objects;
drop policy if exists "authenticated_update_manual_violation_media" on storage.objects;
drop policy if exists "authenticated_delete_manual_violation_media" on storage.objects;

-- Optional older / alternate names
drop policy if exists "anon_insert_manual_violations_storage" on storage.objects;
drop policy if exists "authenticated_insert_manual_violations_storage" on storage.objects;

drop policy if exists "manual_violations_bucket_anon_all" on storage.objects;
create policy "manual_violations_bucket_anon_all"
on storage.objects
for all
to anon
using (bucket_id = 'manual-violations')
with check (bucket_id = 'manual-violations');

drop policy if exists "manual_violations_bucket_authenticated_all" on storage.objects;
create policy "manual_violations_bucket_authenticated_all"
on storage.objects
for all
to authenticated
using (bucket_id = 'manual-violations')
with check (bucket_id = 'manual-violations');
