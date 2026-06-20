-- Run this in Supabase SQL Editor (once).
-- Verifies student email/password server-side (SECURITY DEFINER) so the app does not need broad RLS on users.password.
-- Requires pgcrypto extension (usually schema `extensions` on Supabase) for bcrypt password verification.

-- Step 1: Supabase installs pgcrypto in the `extensions` schema (not public).
-- Without that schema on search_path, `crypt(...)` fails with "function crypt(text, text) does not exist".
create extension if not exists pgcrypto with schema extensions;

create or replace function public.student_login(p_email text, p_password text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  result json;
begin
  select to_json(t) into result
  from (
    select u.id, u.email, u.role, u.name, u.student_id
    from public.users u
    where lower(trim(u.email)) = lower(trim(p_email))
      and u.role = 'student'
      -- crypt() lives in pgcrypto (usually schema `extensions` on Supabase); search_path must include it.
      and u.password = crypt(p_password, u.password)
    limit 1
  ) t;

  return result;
end;
$$;

revoke all on function public.student_login(text, text) from public;
grant execute on function public.student_login(text, text) to anon;
grant execute on function public.student_login(text, text) to authenticated;
