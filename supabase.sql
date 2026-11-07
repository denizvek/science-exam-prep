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
