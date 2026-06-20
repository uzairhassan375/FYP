-- Run in Supabase SQL Editor (idempotent).
-- 1) Review metadata on manual_violations for approve/reject workflow
-- 2) Let student mobile (anon) read own rewards rows for the Rewards screen
-- 3) Optional: Realtime (ignore errors if tables already in publication)

alter table if exists public.manual_violations
  add column if not exists review_note text;

alter table if exists public.manual_violations
  add column if not exists reviewed_at timestamptz;

alter table if exists public.manual_violations
  add column if not exists reviewed_by_name text;

-- Student app reads rewards with anon key — allow SELECT (insert still only via backend / staff).
drop policy if exists rewards_anon_select_all on public.rewards;
create policy rewards_anon_select_all
on public.rewards for select
to anon
using (true);

drop policy if exists rewards_authenticated_select_all on public.rewards;
create policy rewards_authenticated_select_all
on public.rewards for select
to authenticated
using (true);

grant select on table public.rewards to anon, authenticated;

-- Realtime (Supabase): so mobile can subscribe to changes (optional).
do $$
begin
  alter publication supabase_realtime add table public.manual_violations;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.rewards;
exception
  when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';
