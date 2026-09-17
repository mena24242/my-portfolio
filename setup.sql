-- =====================================================================
--  Mena Medhat Portfolio — Supabase setup
--  Run this ONCE in:  Supabase Dashboard → SQL Editor → New query → Run
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- 1) Content table: one row (id = 'main') holding the whole portfolio JSON
create table if not exists public.portfolio (
  id         text primary key,
  content    jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- 2) Dashboard password (stored hashed — never readable from the API)
create table if not exists public.portfolio_auth (
  id            text primary key,
  password_hash text not null
);

insert into public.portfolio (id, content) values ('main', '{}'::jsonb)
on conflict (id) do nothing;

-- default password: mena2026  (change it from the dashboard → Settings)
insert into public.portfolio_auth (id, password_hash)
values ('main', extensions.crypt('mena2026', extensions.gen_salt('bf')))
on conflict (id) do nothing;

-- 3) Security: everyone can READ the content, nobody can write directly
alter table public.portfolio      enable row level security;
alter table public.portfolio_auth enable row level security;

drop policy if exists "portfolio public read" on public.portfolio;
create policy "portfolio public read" on public.portfolio
  for select using (true);
-- (no insert/update/delete policies → direct writes are blocked)
-- (no policies at all on portfolio_auth → completely hidden from the API)

-- 4) Functions (RPC) — the only way to write, protected by the password
create or replace function public.check_password(p_password text)
returns boolean
language sql security definer set search_path = public, extensions as $$
  select exists (
    select 1 from public.portfolio_auth
    where id = 'main' and password_hash = crypt(p_password, password_hash)
  );
$$;

create or replace function public.save_portfolio(p_password text, p_content jsonb)
returns timestamptz
language plpgsql security definer set search_path = public, extensions as $$
declare ts timestamptz;
begin
  if not public.check_password(p_password) then
    raise exception 'WRONG_PASSWORD';
  end if;
  insert into public.portfolio (id, content, updated_at)
  values ('main', p_content, now())
  on conflict (id) do update set content = excluded.content, updated_at = now()
  returning updated_at into ts;
  return ts;
end $$;

create or replace function public.change_password(p_old text, p_new text)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.check_password(p_old) then
    raise exception 'WRONG_PASSWORD';
  end if;
  if length(coalesce(p_new, '')) < 4 then
    raise exception 'PASSWORD_TOO_SHORT';
  end if;
  update public.portfolio_auth
     set password_hash = crypt(p_new, gen_salt('bf'))
   where id = 'main';
  return true;
end $$;

grant usage on schema public to anon, authenticated;
grant select on public.portfolio to anon, authenticated;
grant execute on function public.check_password(text)          to anon, authenticated;
grant execute on function public.save_portfolio(text, jsonb)   to anon, authenticated;
grant execute on function public.change_password(text, text)   to anon, authenticated;

-- Done ✓  Now open dashboard.html → login → "Import current site" → Save.
