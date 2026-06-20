-- Run in Supabase SQL Editor (idempotent-ish: drops policies / constraints before recreate).
-- Evidence: either a short video OR one photo (paths in Storage bucket `manual-violations`).

create table if not exists public.manual_violations (
  id uuid not null default gen_random_uuid (),
  reporter_user_id uuid not null references public.users (id) on delete cascade,
  category text not null,
  description text not null,
  location text null,
  subject_student_name text null,
  subject_sap_id text null,
  subject_department text null,
  evidence_media_type text not null default 'video',
  video_storage_path text null,
  image_storage_path text null,
  video_duration_seconds integer null,
  status text not null default 'pending',
  created_at timestamp with time zone not null default now(),
  constraint manual_violations_pkey primary key (id),
  constraint manual_violations_status_check check (
    status = any (array['pending'::text, 'approved'::text, 'rejected'::text])
  ),
  constraint manual_violations_evidence_media_type_check check (
    evidence_media_type = any (array['video'::text, 'image'::text])
  ),
  constraint manual_violations_evidence_chk check (
    (
      evidence_media_type = 'video'
      and video_storage_path is not null
      and image_storage_path is null
    )
    or (
      evidence_media_type = 'image'
      and image_storage_path is not null
      and video_storage_path is null
    )
  )
) tablespace pg_default;

create index if not exists idx_manual_violations_reporter on public.manual_violations using btree (reporter_user_id) tablespace pg_default;
create index if not exists idx_manual_violations_created_at on public.manual_violations using btree (created_at desc) tablespace pg_default;

alter table public.manual_violations enable row level security;

drop policy if exists "anon_insert_manual_violations" on public.manual_violations;
create policy "anon_insert_manual_violations"
on public.manual_violations for insert
to anon
with check (true);

insert into storage.buckets (id, name, public)
values ('manual-violations', 'manual-violations', false)
on conflict (id) do update set public = excluded.public;

drop policy if exists "anon_insert_manual_violation_videos" on storage.objects;
create policy "anon_insert_manual_violation_videos"
on storage.objects for insert
to anon
with check (bucket_id = 'manual-violations');

-- ---------------------------------------------------------------------------
-- Upgrade older `manual_violations` tables (safe to re-run on existing DBs).
-- ---------------------------------------------------------------------------

alter table public.manual_violations
  add column if not exists evidence_media_type text;

update public.manual_violations
set evidence_media_type = 'video'
where evidence_media_type is null;

alter table public.manual_violations
  alter column evidence_media_type set default 'video';

alter table public.manual_violations
  alter column evidence_media_type set not null;

alter table public.manual_violations
  add column if not exists image_storage_path text;

alter table public.manual_violations
  alter column video_storage_path drop not null;

alter table public.manual_violations
  drop constraint if exists manual_violations_evidence_media_type_check;

alter table public.manual_violations
  add constraint manual_violations_evidence_media_type_check check (
    evidence_media_type = any (array['video'::text, 'image'::text])
  );

alter table public.manual_violations
  drop constraint if exists manual_violations_evidence_chk;

alter table public.manual_violations
  add constraint manual_violations_evidence_chk check (
    (
      evidence_media_type = 'video'
      and video_storage_path is not null
      and image_storage_path is null
    )
    or (
      evidence_media_type = 'image'
      and image_storage_path is not null
      and video_storage_path is null
    )
  );
