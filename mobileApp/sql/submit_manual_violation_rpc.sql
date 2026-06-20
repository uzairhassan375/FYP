-- Run in Supabase SQL Editor after manual_violations table + bucket exist.
-- Inserts a manual violation row with SECURITY DEFINER so RLS on the table
-- cannot block the student app (anon / authenticated) after evidence is uploaded to Storage.

create or replace function public.submit_manual_violation(
  p_id uuid,
  p_reporter_user_id uuid,
  p_category text,
  p_description text,
  p_location text,
  p_subject_student_name text,
  p_subject_sap_id text,
  p_subject_department text,
  p_evidence_media_type text,
  p_video_storage_path text,
  p_image_storage_path text,
  p_video_duration_seconds integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_evidence_media_type is null or p_evidence_media_type not in ('video', 'image') then
    raise exception 'invalid evidence_media_type';
  end if;

  if not exists (
    select 1
    from public.users u
    where u.id = p_reporter_user_id
      and u.role = 'student'
  ) then
    raise exception 'invalid reporter';
  end if;

  insert into public.manual_violations (
    id,
    reporter_user_id,
    category,
    description,
    location,
    subject_student_name,
    subject_sap_id,
    subject_department,
    evidence_media_type,
    video_storage_path,
    image_storage_path,
    video_duration_seconds,
    status
  ) values (
    p_id,
    p_reporter_user_id,
    p_category,
    p_description,
    p_location,
    p_subject_student_name,
    p_subject_sap_id,
    p_subject_department,
    p_evidence_media_type,
    p_video_storage_path,
    p_image_storage_path,
    p_video_duration_seconds,
    'pending'
  );
end;
$$;

revoke all on function public.submit_manual_violation(
  uuid, uuid, text, text, text, text, text, text, text, text, text, integer
) from public;

grant execute on function public.submit_manual_violation(
  uuid, uuid, text, text, text, text, text, text, text, text, text, integer
) to anon;

grant execute on function public.submit_manual_violation(
  uuid, uuid, text, text, text, text, text, text, text, text, text, integer
) to authenticated;

-- Storage: upsert / replace can require UPDATE or DELETE on the same path.
drop policy if exists "anon_delete_manual_violation_media" on storage.objects;
create policy "anon_delete_manual_violation_media"
on storage.objects for delete
to anon
using (bucket_id = 'manual-violations');

drop policy if exists "authenticated_delete_manual_violation_media" on storage.objects;
create policy "authenticated_delete_manual_violation_media"
on storage.objects for delete
to authenticated
using (bucket_id = 'manual-violations');
