-- =====================================================================
--  Mena Medhat Portfolio - Supabase setup (v3: ORGANIZED DATA)
--  Run in:  Supabase Dashboard -> SQL Editor -> New query -> Run
--
--  Safe to run at any time (fresh or existing project). Re-running it
--  detects previous runs and migrates old data automatically with zero
--  data loss (built-in verification, auto-rollback on any mismatch).
--
--  What this version does:
--  Instead of storing the whole portfolio as ONE huge JSON cell, the
--  content now lives in clear, human-readable tables you can browse and
--  edit directly from Supabase -> Table Editor:
--
--    site_content         text sections (brand, hero, about, contact, ...)
--    site_projects        one row per project
--    site_experience      one row per experience
--    site_education       one row per education item
--    site_services        one row per service
--    site_skills          one row per skill group (chips[])
--    site_certifications  one row per certificate
--    site_testimonials    one row per recommendation
--    site_meta            last-save time + existing sections
--    portfolio_auth       dashboard password (hashed, never readable)
--    portfolio_events     visitor analytics (one row per event)
--    portfolio_messages   contact-form messages (one row per message)
--
--  `portfolio` is now a VIEW that rebuilds the exact same JSON shape as
--  before, so index.html and dashboard.html keep working unchanged.
--  Full documentation (Arabic): see SUPABASE.md
--  NOTE: this file is intentionally pure ASCII (English comments only)
--  so it can always be copy-pasted into the SQL Editor safely.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.portfolio_auth (
  id            text primary key,
  password_hash text not null
);

insert into public.portfolio_auth (id, password_hash)
values ('main', extensions.crypt('242006', extensions.gen_salt('bf')))
on conflict (id) do nothing;

create or replace function public.check_password(p_password text)
returns boolean
language sql security definer set search_path = public, extensions as $$
  select exists (
    select 1 from public.portfolio_auth
    where id = 'main' and password_hash = crypt(p_password, password_hash)
  );
$$;

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

create table if not exists public.site_content (
  key        text primary key,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.site_meta (
  id         text primary key,
  updated_at timestamptz not null default now(),
  sections   jsonb not null default '[]'::jsonb
);
alter table public.site_meta add column if not exists sections jsonb not null default '[]'::jsonb;

create table if not exists public.site_projects (
  sort    int primary key,
  title   text not null default '',
  year    text not null default '',
  tag     text not null default '',
  role    text not null default '',
  visual  text not null default '',
  github  text not null default '',
  demo    text not null default '',
  code    text not null default '',
  bullets text[] not null default '{}',
  fields  jsonb not null default '[]'::jsonb,
  extra   jsonb not null default '{}'::jsonb
);

create table if not exists public.site_experience (
  sort    int primary key,
  title   text not null default '',
  role    text not null default '',
  "when"  text not null default '',
  grade   text not null default '',
  bullets text[] not null default '{}',
  extra   jsonb not null default '{}'::jsonb
);

create table if not exists public.site_education (
  sort    int primary key,
  title   text not null default '',
  role    text not null default '',
  "when"  text not null default '',
  grade   text not null default '',
  bullets text[] not null default '{}',
  extra   jsonb not null default '{}'::jsonb
);

create table if not exists public.site_services (
  sort  int primary key,
  icon  text not null default '',
  title text not null default '',
  body  text not null default '',
  extra jsonb not null default '{}'::jsonb
);

create table if not exists public.site_skills (
  sort  int primary key,
  icon  text not null default '',
  title text not null default '',
  chips text[] not null default '{}',
  extra jsonb not null default '{}'::jsonb
);

create table if not exists public.site_certifications (
  sort   int primary key,
  code   text not null default '',
  issuer text not null default '',
  "desc" text not null default '',
  link   text not null default '',
  extra  jsonb not null default '{}'::jsonb
);

create table if not exists public.site_testimonials (
  sort  int primary key,
  name  text not null default '',
  role  text not null default '',
  "text" text not null default '',
  extra jsonb not null default '{}'::jsonb
);

comment on table public.site_content        is 'Portfolio text sections (brand, hero, about, contact, footer, settings, design, custom) - one clear row per section';
comment on table public.site_meta           is 'Last time the portfolio content was saved';
comment on table public.site_projects       is 'Projects - one row per project, ordered by sort';
comment on table public.site_experience     is 'Experience - one row per item, ordered by sort';
comment on table public.site_education      is 'Education - one row per item, ordered by sort';
comment on table public.site_services       is 'Services - one row per service, ordered by sort';
comment on table public.site_skills         is 'Skill groups - one row per group (chips = array of skills)';
comment on table public.site_certifications is 'Certifications - one row per certificate';
comment on table public.site_testimonials   is 'Testimonials - one row per recommendation';

create or replace function public.pb_minus(p jsonb, k text)
returns jsonb language sql immutable as $$
  select case when jsonb_typeof(p) = 'object' then p - k else p end;
$$;

create or replace function public.pb_list(sec jsonb, k text)
returns jsonb language sql immutable as $$
  select case when jsonb_typeof(sec -> k) = 'array' then sec -> k else '[]'::jsonb end;
$$;

create or replace function public.pb_str_array(j jsonb)
returns text[] language sql immutable as $$
  select coalesce(array_agg(v order by ord), '{}')
    from jsonb_array_elements_text(case when jsonb_typeof(j) = 'array' then j else '[]'::jsonb end)
             with ordinality as t(v, ord);
$$;

create or replace function public.pb_extra(item jsonb, known text[])
returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
    from jsonb_each(case when jsonb_typeof(item) = 'object' then item else '{}'::jsonb end) e
   where not (e.key = any(known));
$$;

create or replace function public.write_portfolio_content(p_content jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  c       jsonb := coalesce(p_content, '{}'::jsonb);
  v_known text[] := array['brand','hero','about','contact','footer','settings','design','custom',
                          'projects','experience','education','services','skills','certifications',
                          'testimonials'];
  v_extra jsonb;
begin
  delete from public.site_content
   where site_content.key in ('brand','hero','about','contact','footer','settings','design','custom',
                              'projects','experience','education','services','skills','certifications',
                              'testimonials','__extra');
  insert into public.site_content (key, data)
  select sec.key, c -> sec.key
    from unnest(array['brand','hero','about','contact','footer','settings','design','custom']) as sec(key)
   where c ? sec.key;

  select public.pb_extra(c, v_known) into v_extra;
  if v_extra <> '{}'::jsonb then
    insert into public.site_content (key, data) values ('__extra', v_extra);
  end if;

  if c ? 'projects'       then insert into public.site_content (key, data) values ('projects',       public.pb_minus(c -> 'projects', 'items'));       end if;
  if c ? 'experience'     then insert into public.site_content (key, data) values ('experience',     public.pb_minus(c -> 'experience', 'items'));     end if;
  if c ? 'education'      then insert into public.site_content (key, data) values ('education',      public.pb_minus(c -> 'education', 'items'));      end if;
  if c ? 'services'       then insert into public.site_content (key, data) values ('services',       public.pb_minus(c -> 'services', 'items'));       end if;
  if c ? 'skills'         then insert into public.site_content (key, data) values ('skills',         public.pb_minus(c -> 'skills', 'groups'));        end if;
  if c ? 'certifications' then insert into public.site_content (key, data) values ('certifications', public.pb_minus(c -> 'certifications', 'certs')); end if;
  if c ? 'testimonials'   then insert into public.site_content (key, data) values ('testimonials',   public.pb_minus(c -> 'testimonials', 'items'));   end if;

  delete from public.site_projects;
  insert into public.site_projects (sort, title, year, tag, role, visual, github, demo, code, bullets, fields, extra)
  select x.ord,
         coalesce(x.item ->> 'title',''),  coalesce(x.item ->> 'year',''),
         coalesce(x.item ->> 'tag',''),    coalesce(x.item ->> 'role',''),
         coalesce(x.item ->> 'visual',''), coalesce(x.item ->> 'github',''),
         coalesce(x.item ->> 'demo',''),   coalesce(x.item ->> 'code',''),
         public.pb_str_array(x.item -> 'bullets'),
         case when jsonb_typeof(x.item -> 'fields') = 'array' then x.item -> 'fields' else '[]'::jsonb end,
         public.pb_extra(x.item, array['title','year','tag','role','visual','bullets','github','demo','code','fields'])
    from jsonb_array_elements(public.pb_list(c -> 'projects', 'items')) with ordinality as r(item, ord),
         lateral (select case when jsonb_typeof(r.item) = 'object' then r.item else '{}'::jsonb end as item,
                         r.ord as ord) x;

  delete from public.site_experience;
  insert into public.site_experience (sort, title, role, "when", grade, bullets, extra)
  select x.ord,
         coalesce(x.item ->> 'title',''), coalesce(x.item ->> 'role',''),
         coalesce(x.item ->> 'when',''),  coalesce(x.item ->> 'grade',''),
         public.pb_str_array(x.item -> 'bullets'),
         public.pb_extra(x.item, array['title','role','when','grade','bullets'])
    from jsonb_array_elements(public.pb_list(c -> 'experience', 'items')) with ordinality as r(item, ord),
         lateral (select case when jsonb_typeof(r.item) = 'object' then r.item else '{}'::jsonb end as item,
                         r.ord as ord) x;

  delete from public.site_education;
  insert into public.site_education (sort, title, role, "when", grade, bullets, extra)
  select x.ord,
         coalesce(x.item ->> 'title',''), coalesce(x.item ->> 'role',''),
         coalesce(x.item ->> 'when',''),  coalesce(x.item ->> 'grade',''),
         public.pb_str_array(x.item -> 'bullets'),
         public.pb_extra(x.item, array['title','role','when','grade','bullets'])
    from jsonb_array_elements(public.pb_list(c -> 'education', 'items')) with ordinality as r(item, ord),
         lateral (select case when jsonb_typeof(r.item) = 'object' then r.item else '{}'::jsonb end as item,
                         r.ord as ord) x;

  delete from public.site_services;
  insert into public.site_services (sort, icon, title, body, extra)
  select x.ord,
         coalesce(x.item ->> 'icon',''),
         coalesce(x.item ->> 'title',''),
         coalesce(x.item ->> 'body',''),
         public.pb_extra(x.item, array['icon','title','body'])
    from jsonb_array_elements(public.pb_list(c -> 'services', 'items')) with ordinality as r(item, ord),
         lateral (select case when jsonb_typeof(r.item) = 'object' then r.item else '{}'::jsonb end as item,
                         r.ord as ord) x;

  delete from public.site_skills;
  insert into public.site_skills (sort, icon, title, chips, extra)
  select x.ord,
         coalesce(x.item ->> 'icon',''),
         coalesce(x.item ->> 'title',''),
         public.pb_str_array(x.item -> 'chips'),
         public.pb_extra(x.item, array['icon','title','chips'])
    from jsonb_array_elements(public.pb_list(c -> 'skills', 'groups')) with ordinality as r(item, ord),
         lateral (select case when jsonb_typeof(r.item) = 'object' then r.item else '{}'::jsonb end as item,
                         r.ord as ord) x;

  delete from public.site_certifications;
  insert into public.site_certifications (sort, code, issuer, "desc", link, extra)
  select x.ord,
         coalesce(x.item ->> 'code',''),
         coalesce(x.item ->> 'issuer',''),
         coalesce(x.item ->> 'desc',''),
         coalesce(x.item ->> 'link',''),
         public.pb_extra(x.item, array['code','issuer','desc','link'])
    from jsonb_array_elements(public.pb_list(c -> 'certifications', 'certs')) with ordinality as r(item, ord),
         lateral (select case when jsonb_typeof(r.item) = 'object' then r.item else '{}'::jsonb end as item,
                         r.ord as ord) x;

  delete from public.site_testimonials;
  insert into public.site_testimonials (sort, name, role, "text", extra)
  select x.ord,
         coalesce(x.item ->> 'name',''),
         coalesce(x.item ->> 'role',''),
         coalesce(x.item ->> 'text',''),
         public.pb_extra(x.item, array['name','role','text'])
    from jsonb_array_elements(public.pb_list(c -> 'testimonials', 'items')) with ordinality as r(item, ord),
         lateral (select case when jsonb_typeof(r.item) = 'object' then r.item else '{}'::jsonb end as item,
                         r.ord as ord) x;

  insert into public.site_meta (id, updated_at, sections)
  values ('main', now(),
          (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from (select jsonb_object_keys(c) as k) ks))
  on conflict (id) do update set updated_at = excluded.updated_at, sections = excluded.sections;
end $$;

create or replace function public.build_portfolio_content()
returns jsonb
language sql stable security definer set search_path = public as $$
  select
    coalesce((select s.data from public.site_content s where s.key = '__extra'), '{}'::jsonb)
    || coalesce((select jsonb_build_object('brand',        s.data) from public.site_content s where s.key = 'brand'),        '{}'::jsonb)
    || coalesce((select jsonb_build_object('hero',         s.data) from public.site_content s where s.key = 'hero'),         '{}'::jsonb)
    || coalesce((select jsonb_build_object('about',        s.data) from public.site_content s where s.key = 'about'),        '{}'::jsonb)
    || coalesce((select jsonb_build_object('contact',      s.data) from public.site_content s where s.key = 'contact'),      '{}'::jsonb)
    || coalesce((select jsonb_build_object('footer',       s.data) from public.site_content s where s.key = 'footer'),       '{}'::jsonb)
    || coalesce((select jsonb_build_object('settings',     s.data) from public.site_content s where s.key = 'settings'),     '{}'::jsonb)
    || coalesce((select jsonb_build_object('design',       s.data) from public.site_content s where s.key = 'design'),       '{}'::jsonb)
    || coalesce((select jsonb_build_object('custom',       s.data) from public.site_content s where s.key = 'custom'),       '{}'::jsonb)
    || coalesce((
         select jsonb_build_object('projects',
           coalesce((select s.data from public.site_content s where s.key = 'projects'), '{}'::jsonb)
           || jsonb_build_object('items', coalesce((
                select jsonb_agg(x.j order by x.sort) from (
                  select jsonb_build_object('title', p.title, 'year', p.year, 'tag', p.tag, 'role', p.role,
                                               'visual', p.visual, 'bullets', to_jsonb(p.bullets),
                                               'github', p.github, 'demo', p.demo, 'code', p.code,
                                               'fields', p.fields) || coalesce(p.extra, '{}'::jsonb) as j,
                         p.sort
                    from public.site_projects p) x), '[]'::jsonb)))
         from public.site_meta m
        where m.id = 'main' and m.sections ? 'projects'), '{}'::jsonb)
    || coalesce((
         select jsonb_build_object('experience',
           coalesce((select s.data from public.site_content s where s.key = 'experience'), '{}'::jsonb)
           || jsonb_build_object('items', coalesce((
                select jsonb_agg(x.j order by x.sort) from (
                  select jsonb_build_object('title', e.title, 'role', e.role, 'when', e."when",
                                               'grade', e.grade, 'bullets', to_jsonb(e.bullets))
                         || coalesce(e.extra, '{}'::jsonb) as j,
                         e.sort
                    from public.site_experience e) x), '[]'::jsonb)))
         from public.site_meta m
        where m.id = 'main' and m.sections ? 'experience'), '{}'::jsonb)
    || coalesce((
         select jsonb_build_object('education',
           coalesce((select s.data from public.site_content s where s.key = 'education'), '{}'::jsonb)
           || jsonb_build_object('items', coalesce((
                select jsonb_agg(x.j order by x.sort) from (
                  select jsonb_build_object('title', d.title, 'role', d.role, 'when', d."when",
                                               'grade', d.grade, 'bullets', to_jsonb(d.bullets))
                         || coalesce(d.extra, '{}'::jsonb) as j,
                         d.sort
                    from public.site_education d) x), '[]'::jsonb)))
         from public.site_meta m
        where m.id = 'main' and m.sections ? 'education'), '{}'::jsonb)
    || coalesce((
         select jsonb_build_object('services',
           coalesce((select s.data from public.site_content s where s.key = 'services'), '{}'::jsonb)
           || jsonb_build_object('items', coalesce((
                select jsonb_agg(x.j order by x.sort) from (
                  select jsonb_build_object('icon', v.icon, 'title', v.title, 'body', v.body)
                         || coalesce(v.extra, '{}'::jsonb) as j,
                         v.sort
                    from public.site_services v) x), '[]'::jsonb)))
         from public.site_meta m
        where m.id = 'main' and m.sections ? 'services'), '{}'::jsonb)
    || coalesce((
         select jsonb_build_object('skills',
           coalesce((select s.data from public.site_content s where s.key = 'skills'), '{}'::jsonb)
           || jsonb_build_object('groups', coalesce((
                select jsonb_agg(x.j order by x.sort) from (
                  select jsonb_build_object('icon', g.icon, 'title', g.title, 'chips', to_jsonb(g.chips))
                         || coalesce(g.extra, '{}'::jsonb) as j,
                         g.sort
                    from public.site_skills g) x), '[]'::jsonb)))
         from public.site_meta m
        where m.id = 'main' and m.sections ? 'skills'), '{}'::jsonb)
    || coalesce((
         select jsonb_build_object('certifications',
           coalesce((select s.data from public.site_content s where s.key = 'certifications'), '{}'::jsonb)
           || jsonb_build_object('certs', coalesce((
                select jsonb_agg(x.j order by x.sort) from (
                  select jsonb_build_object('code', ct.code, 'issuer', ct.issuer, 'desc', ct."desc",
                                               'link', ct.link) || coalesce(ct.extra, '{}'::jsonb) as j,
                         ct.sort
                    from public.site_certifications ct) x), '[]'::jsonb)))
         from public.site_meta m
        where m.id = 'main' and m.sections ? 'certifications'), '{}'::jsonb)
    || coalesce((
         select jsonb_build_object('testimonials',
           coalesce((select s.data from public.site_content s where s.key = 'testimonials'), '{}'::jsonb)
           || jsonb_build_object('items', coalesce((
                select jsonb_agg(x.j order by x.sort) from (
                  select jsonb_build_object('name', t.name, 'role', t.role, 'text', t."text")
                         || coalesce(t.extra, '{}'::jsonb) as j,
                         t.sort
                    from public.site_testimonials t) x), '[]'::jsonb)))
         from public.site_meta m
        where m.id = 'main' and m.sections ? 'testimonials'), '{}'::jsonb);
$$;

create or replace function public.save_portfolio(p_password text, p_content jsonb)
returns timestamptz
language plpgsql security definer set search_path = public, extensions as $$
declare ts timestamptz;
begin
  if not public.check_password(p_password) then
    raise exception 'WRONG_PASSWORD';
  end if;
  perform public.write_portfolio_content(p_content);
  select sm.updated_at into ts from public.site_meta sm where sm.id = 'main';
  return ts;
end $$;

do $$
declare
  is_table bool;
  legacy   jsonb;
begin
  select exists (select 1
                   from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'portfolio' and c.relkind = 'r')
    into is_table;

  if is_table then
    select content into legacy from public.portfolio where id = 'main';

    if legacy is not null and legacy <> '{}'::jsonb
       and not exists (select 1 from public.site_meta where id = 'main') then
      perform public.write_portfolio_content(legacy);
    end if;

    if legacy is not null and legacy <> '{}'::jsonb
       and public.build_portfolio_content() is distinct from legacy then
      raise exception 'MIGRATION CHECK FAILED: rebuilt content differs from the original blob. Nothing was changed (rolled back).';
    end if;

    drop table if exists public.portfolio_legacy_backup cascade;
    alter table public.portfolio rename to portfolio_legacy_backup;
    raise notice 'Migrated old JSON content into organized tables OK (backup kept in portfolio_legacy_backup)';
  else
    raise notice 'No legacy portfolio table found - fresh organized setup OK';
  end if;
end $$;

drop view if exists public.portfolio;
create view public.portfolio as
select 'main'::text                                                    as id,
       coalesce(public.build_portfolio_content(), '{}'::jsonb)         as content,
       (select sm.updated_at from public.site_meta sm where sm.id = 'main') as updated_at;

alter table public.site_content        enable row level security;
alter table public.site_meta           enable row level security;
alter table public.site_projects       enable row level security;
alter table public.site_experience     enable row level security;
alter table public.site_education      enable row level security;
alter table public.site_services       enable row level security;
alter table public.site_skills         enable row level security;
alter table public.site_certifications enable row level security;
alter table public.site_testimonials   enable row level security;
alter table public.portfolio_auth      enable row level security;

revoke all on public.site_content, public.site_meta, public.site_projects,
             public.site_experience, public.site_education, public.site_services,
             public.site_skills, public.site_certifications, public.site_testimonials,
             public.portfolio_auth
  from anon, authenticated;
revoke all on function public.write_portfolio_content(jsonb) from public, anon, authenticated;
revoke all on function public.pb_minus(jsonb, text), public.pb_list(jsonb, text),
             public.pb_str_array(jsonb), public.pb_extra(jsonb, text[])
  from public, anon, authenticated;

grant usage on schema public to anon, authenticated;
grant select on public.portfolio to anon, authenticated;
grant execute on function public.build_portfolio_content() to anon, authenticated;
grant execute on function public.check_password(text)        to anon, authenticated;
grant execute on function public.save_portfolio(text, jsonb) to anon, authenticated;
grant execute on function public.change_password(text, text) to anon, authenticated;

create table if not exists public.portfolio_events (
  id          bigserial primary key,
  event       text not null,
  visitor_id  text,
  meta        jsonb default '{}'::jsonb,
  path        text,
  created_at  timestamptz not null default now()
);

create table if not exists public.portfolio_messages (
  id          bigserial primary key,
  name        text not null,
  email       text not null,
  message     text not null,
  visitor_id  text,
  status      text not null default 'new',   -- new / read / replied
  created_at  timestamptz not null default now()
);
alter table public.portfolio_messages add column if not exists status text not null default 'new';

create index if not exists portfolio_messages_created_idx on public.portfolio_messages (created_at desc);
create index if not exists portfolio_events_created_idx   on public.portfolio_events   (created_at desc);

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
      (select jsonb_build_object('id', t.pid, 'views', t.cnt)
         from (select coalesce(meta->>'project', meta->>'title', 'unknown') as pid,
                      count(*) as cnt
                 from ev where event = 'project_view'
                group by 1 order by cnt desc limit 1) t),
      'null'::jsonb) as j
  )
  select jsonb_build_object(
    'days',        coalesce(p_days, 30),
    'totals',      (select j from totals),
    'daily',       (select j from daily),
    'top_project', (select j from top)
  );
$$;

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

grant execute on function public.get_analytics(int)                   to anon, authenticated;
grant execute on function public.update_message(text, bigint, text)   to anon, authenticated;

do $$
declare r int;
begin
  raise notice '---------- ORGANIZED DATA READY ----------';
  raise notice 'site_content        : % rows', (select count(*) from public.site_content);
  raise notice 'site_projects       : % rows', (select count(*) from public.site_projects);
  raise notice 'site_experience     : % rows', (select count(*) from public.site_experience);
  raise notice 'site_education      : % rows', (select count(*) from public.site_education);
  raise notice 'site_services       : % rows', (select count(*) from public.site_services);
  raise notice 'site_skills         : % rows', (select count(*) from public.site_skills);
  raise notice 'site_certifications : % rows', (select count(*) from public.site_certifications);
  raise notice 'site_testimonials   : % rows', (select count(*) from public.site_testimonials);
  raise notice 'portfolio (view)    : content size = % chars',
              length((select content::text from public.portfolio where id = 'main'));
  raise notice 'Open Supabase -> Table Editor to see the new tables.';
  raise notice '------------------------------------------';
end $$;
