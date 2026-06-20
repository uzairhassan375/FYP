-- Run in Supabase SQL Editor if PostgREST says it cannot find
-- `evidence_media_type` (or related columns) on `manual_violations`.
-- Adds any missing columns from an older table, then tells the API to reload its schema cache.

alter table if exists public.manual_violations
  add column if not exists evidence_media_type text;

update public.manual_violations
set evidence_media_type = 'video'
where evidence_media_type is null;

alter table public.manual_violations
  alter column evidence_media_type set default 'video';

do $$
begin
  if not exists (
    select 1 from public.manual_violations where evidence_media_type is null
  ) then
    alter table public.manual_violations
      alter column evidence_media_type set not null;
  end if;
end $$;

alter table if exists public.manual_violations
  add column if not exists image_storage_path text;

alter table if exists public.manual_violations
  add column if not exists video_storage_path text;

alter table if exists public.manual_violations
  add column if not exists video_duration_seconds integer;

-- Allow null video path when only images are used (matches app + full schema).
alter table public.manual_violations
  alter column video_storage_path drop not null;

-- PostgREST / Supabase: refresh schema cache so `evidence_media_type` is visible immediately.
notify pgrst, 'reload schema';
