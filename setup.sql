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
values ('main', extensions.crypt('242006', extensions.gen_salt('bf')))
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

-- 5) Analytics events (views, CV downloads, project views, clicks, form submits)
create table if not exists public.portfolio_events (
  id          bigserial primary key,
  event       text not null,
  visitor_id  text,
  meta        jsonb default '{}'::jsonb,
  path        text,
  created_at  timestamptz not null default now()
);

-- 6) Contact form messages (stored alongside Web3Forms delivery)
create table if not exists public.portfolio_messages (
  id          bigserial primary key,
  name        text not null,
  email       text not null,
  message     text not null,
  visitor_id  text,
  created_at  timestamptz not null default now()
);

-- Security: public (anon) can insert events & messages
alter table public.portfolio_events   enable row level security;
alter table public.portfolio_messages enable row level security;

drop policy if exists "portfolio_events insert public" on public.portfolio_events;
create policy "portfolio_events insert public" on public.portfolio_events
  for insert with check (true);

drop policy if exists "portfolio_events select public" on public.portfolio_events;
create policy "portfolio_events select public" on public.portfolio_events
  for select using (true);

drop policy if exists "portfolio_messages insert public" on public.portfolio_messages;
create policy "portfolio_messages insert public" on public.portfolio_messages
  for insert with check (true);

drop policy if exists "portfolio_messages select public" on public.portfolio_messages;
create policy "portfolio_messages select public" on public.portfolio_messages
  for select using (true);

grant select, insert on public.portfolio_events   to anon, authenticated;
grant select, insert on public.portfolio_messages to anon, authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;

-- =====================================================================
--  ADDITION (v2) — Analytics + Messages
--  مطلوبة لتبويبَي Analytics و Messages في dashboard.html
--  (آمن إنك تشغّلها أكتر من مرة)
-- =====================================================================

-- 1) حالة الرسالة (new / read / replied)
alter table public.portfolio_messages add column if not exists status text not null default 'new';
create index if not exists portfolio_messages_created_idx on public.portfolio_messages (created_at desc);
create index if not exists portfolio_events_created_idx   on public.portfolio_events   (created_at desc);

-- 2) RPC الإحصائيات اللي الداشبورد بيقراها
create or replace function public.get_analytics(p_days int default 30)
returns jsonb
language sql
security definer
set search_path = public
as $$
  with bounds as (
    select date_trunc('day', now() - (coalesce(p_days, 30) || ' days')::interval) as since
  ),
  ev as (
    select e.* from public.portfolio_events e, bounds b where e.created_at >= b.since
  ),
  totals as (
    select jsonb_build_object(
      'view',           count(*) filter (where event = 'view'),
      'project_view',   count(*) filter (where event = 'project_view'),
      'cv_download',    count(*) filter (where event in ('cv_download', 'download_cv')),
      'github_click',   count(*) filter (where event = 'github_click'),
      'linkedin_click', count(*) filter (where event = 'linkedin_click'),
      'contact_submit', count(*) filter (where event in ('contact_submit', 'generate_lead'))
    ) as j
    from ev
  ),
  daily as (
    select coalesce(
      (select jsonb_agg(x order by x.date) from (
         select to_char(d.day, 'YYYY-MM-DD')  as date,
                count(distinct e.visitor_id)  as visitors,
                count(e.id)                   as events
         from generate_series((select since from bounds), date_trunc('day', now()), interval '1 day') d(day)
         left join ev e on date_trunc('day', e.created_at) = d.day
         group by d.day
       ) x), '[]'::jsonb) as j
  ),
  top as (
    select coalesce(
      (select jsonb_build_object('id', coalesce(meta->>'project', meta->>'title', 'unknown'), 'views', count(*))
         from ev where event = 'project_view'
        group by 1 order by count(*) desc limit 1),
      'null'::jsonb) as j
  )
  select jsonb_build_object(
    'days',        coalesce(p_days, 30),
    'totals',      (select j from totals),
    'daily',       (select j from daily),
    'top_project', (select j from top)
  );
$$;

-- 3) تعليم الرسالة (جديدة / مقروءة / تم الرد) — محمية بالباسورد
create or replace function public.update_message(p_password text, p_id bigint, p_status text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare ok boolean;
begin
  if not public.check_password(p_password) then
    raise exception 'WRONG_PASSWORD';
  end if;
  if p_status not in ('new', 'read', 'replied') then
    raise exception 'BAD_STATUS';
  end if;
  update public.portfolio_messages set status = p_status where id = p_id returning true into ok;
  return coalesce(ok, false);
end $$;

grant execute on function public.get_analytics(int)                 to anon, authenticated;
grant execute on function public.update_message(text, bigint, text) to anon, authenticated;

-- Done ✓  Now open dashboard.html → login → "Import current site" → Save.
