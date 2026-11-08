-- Results table for the science exam-prep app.
-- Paste into Supabase: SQL Editor → New query → Run.
-- The page (anon key) can only call save_result() and read results_public; it never touches the table directly.

create table if not exists public.results (
  id        text primary key,
  name      text not null,
  cls       text,
  av        text,
  meter     int  not null default 0,
  lessons   int  not null default 0,
  best      int,
  attempts  int  not null default 0,
  updated   timestamptz not null default now()
);
alter table public.results enable row level security;   -- no policies: no direct access for anon
revoke all on public.results from anon, authenticated;

-- what everyone sees in the class table (no device id)
create or replace view public.results_public as
  select name, cls, av, meter, lessons, best, attempts, updated from public.results;
grant select on public.results_public to anon;

-- the only way to write: insert or update one child's row by its device id
create or replace function public.save_result(
  p_id text, p_name text, p_cls text, p_av text,
  p_meter int, p_lessons int, p_best int, p_attempts int
) returns void
language sql security definer set search_path = public as $$
  insert into results (id, name, cls, av, meter, lessons, best, attempts, updated)
  select left(p_id, 40), left(trim(p_name), 40), left(p_cls, 10), left(p_av, 8),
         least(greatest(coalesce(p_meter, 0), 0), 100),
         least(greatest(coalesce(p_lessons, 0), 0), 50),
         case when p_best is null then null else least(greatest(p_best, 0), 100) end,
         least(greatest(coalesce(p_attempts, 0), 0), 999),
         now()
  where length(coalesce(p_id, '')) >= 8 and length(trim(coalesce(p_name, ''))) >= 2
  on conflict (id) do update set
    name = excluded.name, cls = excluded.cls, av = excluded.av, meter = excluded.meter,
    lessons = excluded.lessons, best = excluded.best, attempts = excluded.attempts, updated = now();
$$;
revoke all on function public.save_result(text, text, text, text, int, int, int, int) from public;
grant execute on function public.save_result(text, text, text, text, int, int, int, int) to anon;

-- Added later: how many different bank questions a child has been tested on (exam = 24 of 64).
-- Additive: the 8-argument save_result above stays for pages that have not refreshed.
alter table public.results add column if not exists covered int not null default 0;

create or replace view public.results_public as
  select name, cls, av, meter, lessons, best, attempts, updated,
         case when attempts > 0 then greatest(covered, 24) else 0 end as covered
  from public.results;
grant select on public.results_public to anon;

create or replace function public.save_result(
  p_id text, p_name text, p_cls text, p_av text,
  p_meter int, p_lessons int, p_best int, p_attempts int, p_covered int
) returns void
language sql security definer set search_path = public as $$
  insert into results (id, name, cls, av, meter, lessons, best, attempts, covered, updated)
  select left(p_id, 40), left(trim(p_name), 40), left(p_cls, 10), left(p_av, 8),
         least(greatest(coalesce(p_meter, 0), 0), 100),
         least(greatest(coalesce(p_lessons, 0), 0), 50),
         case when p_best is null then null else least(greatest(p_best, 0), 100) end,
         least(greatest(coalesce(p_attempts, 0), 0), 999),
         least(greatest(coalesce(p_covered, 0), 0), 200),
         now()
  where length(coalesce(p_id, '')) >= 8 and length(trim(coalesce(p_name, ''))) >= 2
  on conflict (id) do update set
    name = excluded.name, cls = excluded.cls, av = excluded.av, meter = excluded.meter,
    lessons = excluded.lessons, best = excluded.best, attempts = excluded.attempts,
    covered = greatest(excluded.covered, results.covered), updated = now();
$$;
revoke all on function public.save_result(text, text, text, text, int, int, int, int, int) from public;
grant execute on function public.save_result(text, text, text, text, int, int, int, int, int) to anon;

-- Added later: active learning minutes. Additive again: the 8- and 9-argument save_result stay for older pages.
alter table public.results add column if not exists minutes int not null default 0;

create or replace view public.results_public as
  select name, cls, av, meter, lessons, best, attempts, updated,
         case when attempts > 0 then greatest(covered, 24) else 0 end as covered,
         minutes
  from public.results;
grant select on public.results_public to anon;

create or replace function public.save_result(
  p_id text, p_name text, p_cls text, p_av text,
  p_meter int, p_lessons int, p_best int, p_attempts int, p_covered int, p_minutes int
) returns void
language sql security definer set search_path = public as $$
  insert into results (id, name, cls, av, meter, lessons, best, attempts, covered, minutes, updated)
  select left(p_id, 40), left(trim(p_name), 40), left(p_cls, 10), left(p_av, 8),
         least(greatest(coalesce(p_meter, 0), 0), 100),
         least(greatest(coalesce(p_lessons, 0), 0), 50),
         case when p_best is null then null else least(greatest(p_best, 0), 100) end,
         least(greatest(coalesce(p_attempts, 0), 0), 999),
         least(greatest(coalesce(p_covered, 0), 0), 200),
         least(greatest(coalesce(p_minutes, 0), 0), 100000),
         now()
  where length(coalesce(p_id, '')) >= 8 and length(trim(coalesce(p_name, ''))) >= 2
  on conflict (id) do update set
    name = excluded.name, cls = excluded.cls, av = excluded.av, meter = excluded.meter,
    lessons = excluded.lessons, best = excluded.best, attempts = excluded.attempts,
    covered = greatest(excluded.covered, results.covered),
    minutes = greatest(excluded.minutes, results.minutes), updated = now();
$$;
revoke all on function public.save_result(text, text, text, text, int, int, int, int, int, int) from public;
grant execute on function public.save_result(text, text, text, text, int, int, int, int, int, int) to anon;

-- Added later: hide a row from the class table without deleting it (the child's device keeps saving, but the row stays hidden).
-- Hide:   update public.results set hidden = true  where id = '<id>';
-- Unhide: update public.results set hidden = false where id = '<id>';
alter table public.results add column if not exists hidden boolean not null default false;

create or replace view public.results_public as
  select name, cls, av, meter, lessons, best, attempts, updated,
         case when attempts > 0 then greatest(covered, 24) else 0 end as covered,
         minutes
  from public.results
  where not hidden;
grant select on public.results_public to anon;

-- Added later: distinct exam questions answered right (all attempts together); the class table ranks by
-- best score, then this count, then the learning meter. Additive: older save_result overloads stay.
alter table public.results add column if not exists correct int not null default 0;

create or replace view public.results_public as
  select name, cls, av, meter, lessons, best, attempts, updated,
         case when attempts > 0 then greatest(covered, 24) else 0 end as covered,
         minutes,
         case when attempts > 0 then greatest(correct, round(coalesce(best, 0) * 0.24)::int) else 0 end as correct
  from public.results
  where not hidden;
grant select on public.results_public to anon;

create or replace function public.save_result(
  p_id text, p_name text, p_cls text, p_av text,
  p_meter int, p_lessons int, p_best int, p_attempts int, p_covered int, p_minutes int, p_correct int
) returns void
language sql security definer set search_path = public as $$
  insert into results (id, name, cls, av, meter, lessons, best, attempts, covered, minutes, correct, updated)
  select left(p_id, 40), left(trim(p_name), 40), left(p_cls, 10), left(p_av, 8),
         least(greatest(coalesce(p_meter, 0), 0), 100),
         least(greatest(coalesce(p_lessons, 0), 0), 50),
         case when p_best is null then null else least(greatest(p_best, 0), 100) end,
         least(greatest(coalesce(p_attempts, 0), 0), 999),
         least(greatest(coalesce(p_covered, 0), 0), 200),
         least(greatest(coalesce(p_minutes, 0), 0), 100000),
         least(greatest(coalesce(p_correct, 0), 0), 200),
         now()
  where length(coalesce(p_id, '')) >= 8 and length(trim(coalesce(p_name, ''))) >= 2
  on conflict (id) do update set
    name = excluded.name, cls = excluded.cls, av = excluded.av, meter = excluded.meter,
    lessons = excluded.lessons, best = excluded.best, attempts = excluded.attempts,
    covered = greatest(excluded.covered, results.covered),
    minutes = greatest(excluded.minutes, results.minutes),
    correct = greatest(excluded.correct, results.correct), updated = now();
$$;
revoke all on function public.save_result(text, text, text, text, int, int, int, int, int, int, int) from public;
grant execute on function public.save_result(text, text, text, text, int, int, int, int, int, int, int) to anon;

-- Added later: "learning now". The page calls ping() once a minute while the child is active;
-- the view shows online = active in the last 2 minutes (the exact time is not exposed).
alter table public.results add column if not exists last_seen timestamptz;

create or replace view public.results_public as
  select name, cls, av, meter, lessons, best, attempts, updated,
         case when attempts > 0 then greatest(covered, 24) else 0 end as covered,
         minutes,
         case when attempts > 0 then greatest(correct, round(coalesce(best, 0) * 0.24)::int) else 0 end as correct,
         coalesce(last_seen > now() - interval '2 minutes', false) as online
  from public.results
  where not hidden;
grant select on public.results_public to anon;

create or replace function public.ping(p_id text) returns void
language sql security definer set search_path = public as $$
  update results set last_seen = now() where id = left(p_id, 40);
$$;
revoke all on function public.ping(text) from public;
grant execute on function public.ping(text) to anon;

-- Added later: active_at = the latest of the last save and the last heartbeat; used by the "learning now and lately" tab.
create or replace view public.results_public as
  select name, cls, av, meter, lessons, best, attempts, updated,
         case when attempts > 0 then greatest(covered, 24) else 0 end as covered,
         minutes,
         case when attempts > 0 then greatest(correct, round(coalesce(best, 0) * 0.24)::int) else 0 end as correct,
         coalesce(last_seen > now() - interval '2 minutes', false) as online,
         greatest(updated, coalesce(last_seen, updated)) as active_at
  from public.results
  where not hidden;
grant select on public.results_public to anon;

-- Added later: learning minutes for the current day (Israel time), for the "who learned most today" podium.
-- Additive: older save_result overloads stay; a call without p_today keeps the stored day's minutes.
alter table public.results add column if not exists today_minutes int not null default 0;
alter table public.results add column if not exists today_date date;

create or replace view public.results_public as
  select name, cls, av, meter, lessons, best, attempts, updated,
         case when attempts > 0 then greatest(covered, 24) else 0 end as covered,
         minutes,
         case when attempts > 0 then greatest(correct, round(coalesce(best, 0) * 0.24)::int) else 0 end as correct,
         coalesce(last_seen > now() - interval '2 minutes', false) as online,
         greatest(updated, coalesce(last_seen, updated)) as active_at,
         case when today_date = (now() at time zone 'Asia/Jerusalem')::date then today_minutes else 0 end as today_minutes
  from public.results
  where not hidden;
grant select on public.results_public to anon;

create or replace function public.save_result(
  p_id text, p_name text, p_cls text, p_av text,
  p_meter int, p_lessons int, p_best int, p_attempts int, p_covered int, p_minutes int, p_correct int,
  p_today_minutes int, p_today date
) returns void
language sql security definer set search_path = public as $$
  insert into results (id, name, cls, av, meter, lessons, best, attempts, covered, minutes, correct, today_minutes, today_date, updated)
  select left(p_id, 40), left(trim(p_name), 40), left(p_cls, 10), left(p_av, 8),
         least(greatest(coalesce(p_meter, 0), 0), 100),
         least(greatest(coalesce(p_lessons, 0), 0), 50),
         case when p_best is null then null else least(greatest(p_best, 0), 100) end,
         least(greatest(coalesce(p_attempts, 0), 0), 999),
         least(greatest(coalesce(p_covered, 0), 0), 200),
         least(greatest(coalesce(p_minutes, 0), 0), 100000),
         least(greatest(coalesce(p_correct, 0), 0), 200),
         least(greatest(coalesce(p_today_minutes, 0), 0), 1440),
         p_today,
         now()
  where length(coalesce(p_id, '')) >= 8 and length(trim(coalesce(p_name, ''))) >= 2
  on conflict (id) do update set
    name = excluded.name, cls = excluded.cls, av = excluded.av, meter = excluded.meter,
    lessons = excluded.lessons, best = excluded.best, attempts = excluded.attempts,
    covered = greatest(excluded.covered, results.covered),
    minutes = greatest(excluded.minutes, results.minutes),
    correct = greatest(excluded.correct, results.correct),
    today_minutes = case when excluded.today_date is null then results.today_minutes
                         when results.today_date is null or excluded.today_date > results.today_date then excluded.today_minutes
                         when excluded.today_date = results.today_date then greatest(excluded.today_minutes, results.today_minutes)
                         else results.today_minutes end,
    today_date = case when excluded.today_date is null then results.today_date
                      else greatest(excluded.today_date, coalesce(results.today_date, excluded.today_date)) end,
    updated = now();
$$;
revoke all on function public.save_result(text, text, text, text, int, int, int, int, int, int, int, int, date) from public;
grant execute on function public.save_result(text, text, text, text, int, int, int, int, int, int, int, int, date) to anon;
