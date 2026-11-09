-- Live duels between two children who are online (applied to the live project).
-- Run after supabase.sql. The answer key (duel_key) must match the app's question bank:
-- regenerate its rows whenever questions in index.html change (qid = question id, answer = the right option text).

alter table public.results add column if not exists wins int not null default 0;

create table if not exists public.duel_key (
  qid int primary key,
  answer text not null
);
alter table public.duel_key enable row level security;
revoke all on public.duel_key from anon, authenticated;

create table if not exists public.duels (
  id uuid primary key default gen_random_uuid(),
  a_id text not null, b_id text not null,
  a_name text, b_name text, a_av text, b_av text, a_cls text, b_cls text,
  status text not null default 'invited',          -- invited, active, done, declined, cancelled, expired
  qs int[] not null,
  q_index int not null default 0,
  q_started_at timestamptz,
  a_score int not null default 0, b_score int not null default 0,
  locked_a boolean not null default false, locked_b boolean not null default false,
  last_point text, last_qid int,
  a_seen timestamptz, b_seen timestamptz,
  winner text,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
create index if not exists duels_a on public.duels (a_id, status);
create index if not exists duels_b on public.duels (b_id, status);
alter table public.duels enable row level security;
revoke all on public.duels from anon, authenticated;

-- the class table gets wins (never losses) and an opaque handle to invite someone without exposing ids
create or replace view public.results_public as
  select name, cls, av, meter, lessons, best, attempts, updated,
         case when attempts > 0 then greatest(covered, 24) else 0 end as covered,
         minutes,
         case when attempts > 0 then greatest(correct, round(coalesce(best, 0) * 0.24)::int) else 0 end as correct,
         coalesce(last_seen > now() - interval '2 minutes', false) as online,
         greatest(updated, coalesce(last_seen, updated)) as active_at,
         greatest(
           case when today_date = (now() at time zone 'Asia/Jerusalem')::date then today_minutes else 0 end,
           case when day_base_date = (now() at time zone 'Asia/Jerusalem')::date then greatest(minutes - day_base_minutes, 0) else 0 end
         ) as today_minutes,
         wins,
         substr(md5('duel:' || id), 1, 12) as handle
  from public.results
  where not hidden and not is_parent;
grant select on public.results_public to anon;

-- internal: end a duel; a win goes to the winner (losses are never stored)
create or replace function public.duel_finish(p_duel uuid, p_winner text) returns void
language plpgsql security definer set search_path = public as $$
declare d duels%rowtype;
begin
  select * into d from duels where id = p_duel for update;
  if d.status <> 'active' then return; end if;
  update duels set status = 'done', winner = p_winner, finished_at = now() where id = p_duel;
  if p_winner = 'a' then update results set wins = wins + 1 where id = d.a_id;
  elsif p_winner = 'b' then update results set wins = wins + 1 where id = d.b_id; end if;
end $$;
revoke all on function public.duel_finish(uuid, text) from public;

-- internal: close the current question ('a' / 'b' scored, or 'none') and move on; first to 5 wins
create or replace function public.duel_next(p_duel uuid, p_by text) returns void
language plpgsql security definer set search_path = public as $$
declare d duels%rowtype; target int := 5;
begin
  select * into d from duels where id = p_duel for update;
  if d.status <> 'active' then return; end if;
  if p_by = 'a' then d.a_score := d.a_score + 1; elsif p_by = 'b' then d.b_score := d.b_score + 1; end if;
  update duels set a_score = d.a_score, b_score = d.b_score, last_point = p_by, last_qid = d.qs[d.q_index + 1],
    q_index = d.q_index + 1, locked_a = false, locked_b = false, q_started_at = now() where id = p_duel;
  if d.a_score >= target then perform duel_finish(p_duel, 'a');
  elsif d.b_score >= target then perform duel_finish(p_duel, 'b');
  elsif d.q_index + 1 >= array_length(d.qs, 1) then
    perform duel_finish(p_duel, case when d.a_score > d.b_score then 'a' when d.b_score > d.a_score then 'b' else 'draw' end);
  end if;
end $$;
revoke all on function public.duel_next(uuid, text) from public;

-- invite a child who is online now (by the handle shown in the table)
create or replace function public.duel_invite(p_me text, p_handle text) returns json
language plpgsql security definer set search_path = public as $$
declare me results%rowtype; them results%rowtype; new_id uuid;
begin
  select * into me from results where id = left(p_me, 40);
  if not found or me.is_parent then return json_build_object('ok', false, 'reason', 'not_kid'); end if;
  select * into them from results where substr(md5('duel:' || id), 1, 12) = p_handle and not hidden and not is_parent;
  if not found or them.id = me.id then return json_build_object('ok', false, 'reason', 'not_found'); end if;
  if them.last_seen is null or them.last_seen < now() - interval '2 minutes' then return json_build_object('ok', false, 'reason', 'offline'); end if;
  update duels set status = 'expired' where status = 'invited' and created_at < now() - interval '40 seconds' and (a_id in (me.id, them.id) or b_id in (me.id, them.id));
  if exists (select 1 from duels where status in ('invited', 'active') and (a_id in (me.id, them.id) or b_id in (me.id, them.id))
             and (status = 'invited' or greatest(coalesce(a_seen, created_at), coalesce(b_seen, created_at)) > now() - interval '30 seconds')) then
    return json_build_object('ok', false, 'reason', 'busy');
  end if;
  insert into duels (a_id, b_id, a_name, b_name, a_av, b_av, a_cls, b_cls, qs, a_seen)
    values (me.id, them.id, me.name, them.name, me.av, them.av, me.cls, them.cls,
            array(select qid from duel_key order by random() limit 30), now())
    returning id into new_id;
  return json_build_object('ok', true, 'id', new_id);
end $$;

-- what is waiting for me: an invite to me, or a duel I am in
create or replace function public.duel_inbox(p_me text) returns json
language plpgsql security definer set search_path = public as $$
declare d duels%rowtype;
begin
  select * into d from duels where b_id = left(p_me, 40) and status = 'invited' and created_at > now() - interval '40 seconds' order by created_at desc limit 1;
  if found then return json_build_object('invite', json_build_object('id', d.id, 'name', d.a_name, 'av', d.a_av, 'cls', d.a_cls)); end if;
  select * into d from duels where (a_id = left(p_me, 40) or b_id = left(p_me, 40)) and status = 'active'
    and greatest(coalesce(a_seen, created_at), coalesce(b_seen, created_at)) > now() - interval '30 seconds' order by created_at desc limit 1;
  if found then return json_build_object('active', d.id); end if;
  return '{}'::json;
end $$;

create or replace function public.duel_respond(p_me text, p_duel uuid, p_accept boolean) returns json
language plpgsql security definer set search_path = public as $$
declare d duels%rowtype;
begin
  select * into d from duels where id = p_duel for update;
  if not found or d.b_id <> left(p_me, 40) or d.status <> 'invited' or d.created_at < now() - interval '40 seconds' then
    return json_build_object('ok', false);
  end if;
  if p_accept then
    update duels set status = 'active', q_index = 0, q_started_at = now() + interval '3 seconds', a_seen = now(), b_seen = now() where id = p_duel;
  else
    update duels set status = 'declined' where id = p_duel;
  end if;
  return json_build_object('ok', true);
end $$;

-- the inviter cancels, or a player leaves an active duel (the other one wins)
create or replace function public.duel_leave(p_me text, p_duel uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d duels%rowtype;
begin
  select * into d from duels where id = p_duel for update;
  if not found then return; end if;
  if d.status = 'invited' and d.a_id = left(p_me, 40) then update duels set status = 'cancelled' where id = p_duel;
  elsif d.status = 'active' and d.a_id = left(p_me, 40) then perform duel_finish(p_duel, 'b');
  elsif d.status = 'active' and d.b_id = left(p_me, 40) then perform duel_finish(p_duel, 'a');
  end if;
end $$;

-- state of a duel for one player; also a heartbeat, and it applies the 20-second limits
create or replace function public.duel_state(p_me text, p_duel uuid) returns json
language plpgsql security definer set search_path = public as $$
declare d duels%rowtype; side text; me_id text := left(p_me, 40);
begin
  select * into d from duels where id = p_duel for update;
  if not found then return json_build_object('status', 'gone'); end if;
  if d.a_id = me_id then side := 'a'; elsif d.b_id = me_id then side := 'b'; else return json_build_object('status', 'gone'); end if;
  if side = 'a' then update duels set a_seen = now() where id = p_duel; else update duels set b_seen = now() where id = p_duel; end if;
  if d.status = 'invited' and d.created_at < now() - interval '40 seconds' then update duels set status = 'expired' where id = p_duel; end if;
  if d.status = 'active' then
    if side = 'a' and d.b_seen < now() - interval '20 seconds' then perform duel_finish(p_duel, 'a');
    elsif side = 'b' and d.a_seen < now() - interval '20 seconds' then perform duel_finish(p_duel, 'b');
    elsif d.q_started_at < now() - interval '20 seconds' then perform duel_next(p_duel, 'none');
    end if;
  end if;
  select * into d from duels where id = p_duel;
  return json_build_object(
    'status', d.status, 'side', side,
    'me', json_build_object('name', case when side = 'a' then d.a_name else d.b_name end, 'av', case when side = 'a' then d.a_av else d.b_av end,
                            'score', case when side = 'a' then d.a_score else d.b_score end, 'locked', case when side = 'a' then d.locked_a else d.locked_b end),
    'opp', json_build_object('name', case when side = 'a' then d.b_name else d.a_name end, 'av', case when side = 'a' then d.b_av else d.a_av end,
                             'cls', case when side = 'a' then d.b_cls else d.a_cls end,
                             'score', case when side = 'a' then d.b_score else d.a_score end, 'locked', case when side = 'a' then d.locked_b else d.locked_a end),
    'q_index', d.q_index, 'qid', case when d.status = 'active' then d.qs[d.q_index + 1] end,
    'q_age', extract(epoch from (now() - d.q_started_at)),
    'last_point', case when d.last_point is null then null when d.last_point = 'none' then 'none' when d.last_point = side then 'me' else 'opp' end,
    'last_qid', d.last_qid,
    'winner', case when d.winner is null then null when d.winner = 'draw' then 'draw' when d.winner = side then 'me' else 'opp' end);
end $$;

-- an answer: the first right one gets the point; a wrong one locks that player out of this question
create or replace function public.duel_answer(p_me text, p_duel uuid, p_qid int, p_answer text) returns json
language plpgsql security definer set search_path = public as $$
declare d duels%rowtype; side text; me_id text := left(p_me, 40); ok boolean;
begin
  select * into d from duels where id = p_duel for update;
  if not found then return json_build_object('result', 'gone'); end if;
  if d.a_id = me_id then side := 'a'; elsif d.b_id = me_id then side := 'b'; else return json_build_object('result', 'gone'); end if;
  if d.status <> 'active' or d.qs[d.q_index + 1] is distinct from p_qid or d.q_started_at > now() then return json_build_object('result', 'late'); end if;
  if (side = 'a' and d.locked_a) or (side = 'b' and d.locked_b) then return json_build_object('result', 'locked'); end if;
  select answer = p_answer into ok from duel_key where qid = p_qid;
  if coalesce(ok, false) then
    perform duel_next(p_duel, side);
    return json_build_object('result', 'point');
  end if;
  if side = 'a' then update duels set locked_a = true where id = p_duel; d.locked_a := true;
  else update duels set locked_b = true where id = p_duel; d.locked_b := true; end if;
  if d.locked_a and d.locked_b then perform duel_next(p_duel, 'none'); end if;
  return json_build_object('result', 'wrong');
end $$;

revoke all on function public.duel_invite(text, text) from public;
revoke all on function public.duel_inbox(text) from public;
revoke all on function public.duel_respond(text, uuid, boolean) from public;
revoke all on function public.duel_leave(text, uuid) from public;
revoke all on function public.duel_state(text, uuid) from public;
revoke all on function public.duel_answer(text, uuid, int, text) from public;
grant execute on function public.duel_invite(text, text) to anon;
grant execute on function public.duel_inbox(text) to anon;
grant execute on function public.duel_respond(text, uuid, boolean) to anon;
grant execute on function public.duel_leave(text, uuid) to anon;
grant execute on function public.duel_state(text, uuid) to anon;
grant execute on function public.duel_answer(text, uuid, int, text) to anon;

-- the answer key (135 questions, generated from index.html)
insert into public.duel_key (qid, answer) values
(0, 'כספית'),
(1, 'מוליכות חשמלית'),
(2, 'ברזל'),
(3, 'לא נכון'),
(4, 'אלומיניום קל וחזק'),
(5, 'כסף'),
(6, 'נחושת'),
(7, 'להגנה וציפוי של מתכות'),
(8, 'הנורה כבויה כי המעגל פתוח'),
(9, 'המסמר מוליך'),
(10, 'פלסטיק'),
(11, 'נכון'),
(12, 'סלע שמכיל מתכת'),
(13, 'צריפה'),
(14, 'מתכת שעורבבה עם חומרים אחרים'),
(15, 'נחושת ומעט בדיל'),
(16, 'ברזל ומעט פחמן'),
(17, 'עיבוד שבבי'),
(18, 'חתיכות קטנות שמוסרות מהמתכת בעיבוד'),
(19, 'רידוד מתכת ללוח שטוח'),
(20, 'ערגול – מתכת בין שני גלילים'),
(21, 'יציקה ואחריה עיבוד שבבי'),
(22, 'פסי רכבת עשויים מפלדה – חזקה וזולה'),
(23, 'נחושת לא נמשכת למגנט – צריך ברזל'),
(24, 'השכבה המוצקה העליונה של כדור הארץ'),
(25, 'גאולוגיה'),
(26, 'שורטים אותו במסמר'),
(27, 'תגובה לחומצה'),
(28, 'בנייה'),
(29, 'הם מוליכים חשמל'),
(30, 'מלט, חול, חצץ ומים'),
(31, 'נכון'),
(32, 'נכון'),
(33, 'מהתפוררות סלעים'),
(34, 'מים ואוויר'),
(35, 'טרה רוסה'),
(36, 'רנדזינה'),
(37, 'קוורץ מהתפוררות גרניט'),
(38, 'צנצנת א – המים עברו למטה'),
(39, 'חרסיתית'),
(40, 'חרסיתית'),
(41, 'נכון'),
(42, 'כריתת יערות'),
(43, 'שימוש מוגזם בדשנים וחומרי הדברה'),
(44, 'פגיעה בנוף, זיהום אוויר ורעש'),
(45, 'הוא המקום הנמוך בעולם'),
(46, 'כמעט פי 10'),
(47, 'בולענים'),
(48, 'אשלג'),
(49, 'דשנים לחקלאות'),
(50, 'דשן לחקלאות'),
(51, 'הוא מונע התפתחות חיידקים'),
(52, 'המלח'),
(53, 'המים'),
(54, 'אידוי המים'),
(55, 'בריכות אידוי להפקת מלח'),
(56, 'כדי שהמים יתאדו מהר'),
(57, 'נכון'),
(58, 'מזרחן – Phosphorus'),
(59, 'מאובנים של דגים ושיני כרישים'),
(60, 'שריד של יצור קדום שהשתמר בסלע'),
(61, 'בניית עצמות ושיניים'),
(62, 'נכון'),
(63, 'לא נכון'),
(64, 'חומרים לא רצויים שנמצאים בעפרה יחד עם המתכת'),
(65, 'סילוק חומרי הטפל'),
(66, 'סיגים'),
(67, 'כי מחירי הנחושת ירדו'),
(68, 'לא נכון'),
(69, 'היא חזקה יותר ופחות מחלידה'),
(70, 'התכה, ואחריה יציקה וקירור'),
(71, 'ארד חזק יותר ועמיד יותר בשחיקה'),
(72, 'עוגן צריך להיות כבד וחזק, ואלומיניום קל'),
(73, 'לכל מתכת יש תכונה ייחודית שמתאימה למטרה אחרת'),
(74, 'פלטינה'),
(75, 'זהב'),
(76, 'הזרם זורם בקלות ונוצר פחות חום'),
(77, 'כסף, נחושת, זהב, אלומיניום'),
(78, 'כי כסף יקר מאוד'),
(79, 'מוליכות חשמלית'),
(80, 'כ-90 מוכרים, ובכ-15 משתמשים הרבה'),
(81, 'יציקה'),
(82, 'עיבוד שבבי'),
(83, 'פחיות שימורים, דלתות מכונית וגגות'),
(84, 'גליל מרושת מניטינול שפותח עורק סתום'),
(85, 'אי אפשר לקבל כך לוחות כאלה – משתמשים בערגול'),
(86, 'אבן זמינה, זולה ועמידה במזג האוויר'),
(87, 'ירושלים, צפת וטבריה'),
(88, 'היא מאפשרת חדירת אור טבעי'),
(89, 'בעיקר לחיפוי קירות, לריצוף ולתקרות'),
(90, 'אבנים גרוסות (גסות)'),
(91, 'לא נכון'),
(92, 'נכון'),
(93, 'חומר רך מאוד, לבן-אפור וקל לעיבוד'),
(94, 'כוכבים וגלקסיות'),
(95, 'נפט גולמי'),
(96, 'כדי לקחת דגימה של סלע'),
(97, 'עיסתיות'),
(98, 'הגרניט לא מגיב לחומצה כמו הגיר'),
(99, 'גרגירים שנוצרו מסלעים'),
(100, 'סלעים נשברים, משתנים ומתפוררים'),
(101, 'קונכייה'),
(102, 'לא נכון'),
(103, 'באפיקי נחלים'),
(104, 'בחולית גדולים, בחרסיתית זעירים'),
(105, 'לא נכון'),
(106, 'קרקע עם חומרי מזון, יכולת לשמור מים ורווחי אוויר'),
(107, 'הגרגירים מתפרקים והיא נהיית פחות פורייה'),
(108, 'לא נכון'),
(109, 'יצורים חיים כבר לא יכולים לחיות בה'),
(110, 'חרסיתית'),
(111, 'יעל'),
(112, 'לא נכון'),
(113, 'גבישי מלח בצורת פטרייה בחוף ים המלח'),
(114, 'המים מתאדים והמלח נשאר'),
(115, 'נכון'),
(116, 'אנשים טובים במיוחד'),
(117, 'חיילי רומא קיבלו מלח כמשכורת'),
(118, 'לעמוד בפני גורמי מחלות'),
(119, 'חומצת לימון'),
(120, 'מלח בישול'),
(121, 'המזון והחומרים'),
(122, 'מים בלי מלחים'),
(123, 'המים'),
(124, 'התוצר שמתקבל כשחומר מתמוסס בנוזל'),
(125, 'כ-1,500 מטר'),
(126, 'מלח בישול וגם אשלג'),
(127, 'המלחים'),
(128, 'מחרסית וקרטון'),
(129, 'במכרות פתוחים'),
(130, 'לא נכון'),
(131, 'חוטי חשמל'),
(132, 'ערד'),
(133, 'ישראל מוכרת דשנים לארצות רבות'),
(134, 'שלדי דגים וכרישים ששקעו בו יצרו את הסלעים')
on conflict (qid) do update set answer = excluded.answer;

-- Added later: leaving before any point ends the duel with no result (no win);
-- the invite reaching the invited child is recorded so the inviter can be told.
alter table public.duels add column if not exists invite_seen_at timestamptz;

create or replace function public.duel_forfeit(p_duel uuid, p_winner text) returns void
language plpgsql security definer set search_path = public as $$
declare d duels%rowtype;
begin
  select * into d from duels where id = p_duel for update;
  if d.status <> 'active' then return; end if;
  if d.a_score + d.b_score > 0 then perform duel_finish(p_duel, p_winner);
  else update duels set status = 'abandoned', finished_at = now() where id = p_duel; end if;
end $$;
revoke all on function public.duel_forfeit(uuid, text) from public;

create or replace function public.duel_inbox(p_me text) returns json
language plpgsql security definer set search_path = public as $$
declare d duels%rowtype;
begin
  select * into d from duels where b_id = left(p_me, 40) and status = 'invited' and created_at > now() - interval '40 seconds' order by created_at desc limit 1;
  if found then
    update duels set invite_seen_at = coalesce(invite_seen_at, now()) where id = d.id;
    return json_build_object('invite', json_build_object('id', d.id, 'name', d.a_name, 'av', d.a_av, 'cls', d.a_cls));
  end if;
  select * into d from duels where (a_id = left(p_me, 40) or b_id = left(p_me, 40)) and status = 'active'
    and greatest(coalesce(a_seen, created_at), coalesce(b_seen, created_at)) > now() - interval '30 seconds' order by created_at desc limit 1;
  if found then return json_build_object('active', d.id); end if;
  return '{}'::json;
end $$;

create or replace function public.duel_leave(p_me text, p_duel uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d duels%rowtype;
begin
  select * into d from duels where id = p_duel for update;
  if not found then return; end if;
  if d.status = 'invited' and d.a_id = left(p_me, 40) then update duels set status = 'cancelled' where id = p_duel;
  elsif d.status = 'active' and d.a_id = left(p_me, 40) then perform duel_forfeit(p_duel, 'b');
  elsif d.status = 'active' and d.b_id = left(p_me, 40) then perform duel_forfeit(p_duel, 'a');
  end if;
end $$;

create or replace function public.duel_state(p_me text, p_duel uuid) returns json
language plpgsql security definer set search_path = public as $$
declare d duels%rowtype; side text; me_id text := left(p_me, 40);
begin
  select * into d from duels where id = p_duel for update;
  if not found then return json_build_object('status', 'gone'); end if;
  if d.a_id = me_id then side := 'a'; elsif d.b_id = me_id then side := 'b'; else return json_build_object('status', 'gone'); end if;
  if side = 'a' then update duels set a_seen = now() where id = p_duel; else update duels set b_seen = now() where id = p_duel; end if;
  if d.status = 'invited' and d.created_at < now() - interval '40 seconds' then update duels set status = 'expired' where id = p_duel; end if;
  if d.status = 'active' then
    if side = 'a' and d.b_seen < now() - interval '20 seconds' then perform duel_forfeit(p_duel, 'a');
    elsif side = 'b' and d.a_seen < now() - interval '20 seconds' then perform duel_forfeit(p_duel, 'b');
    elsif d.q_started_at < now() - interval '20 seconds' then perform duel_next(p_duel, 'none');
    end if;
  end if;
  select * into d from duels where id = p_duel;
  return json_build_object(
    'status', d.status, 'side', side,
    'invite_age', extract(epoch from (now() - d.created_at)), 'invite_seen', d.invite_seen_at is not null,
    'me', json_build_object('name', case when side = 'a' then d.a_name else d.b_name end, 'av', case when side = 'a' then d.a_av else d.b_av end,
                            'score', case when side = 'a' then d.a_score else d.b_score end, 'locked', case when side = 'a' then d.locked_a else d.locked_b end),
    'opp', json_build_object('name', case when side = 'a' then d.b_name else d.a_name end, 'av', case when side = 'a' then d.b_av else d.a_av end,
                             'cls', case when side = 'a' then d.b_cls else d.a_cls end,
                             'score', case when side = 'a' then d.b_score else d.a_score end, 'locked', case when side = 'a' then d.locked_b else d.locked_a end),
    'q_index', d.q_index, 'qid', case when d.status = 'active' then d.qs[d.q_index + 1] end,
    'q_age', extract(epoch from (now() - d.q_started_at)),
    'last_point', case when d.last_point is null then null when d.last_point = 'none' then 'none' when d.last_point = side then 'me' else 'opp' end,
    'last_qid', d.last_qid,
    'winner', case when d.winner is null then null when d.winner = 'draw' then 'draw' when d.winner = side then 'me' else 'opp' end);
end $$;

-- Added later: a child's own duel history (wins, losses, draws, no-result, and against whom).
-- Only the device holding the child's id can ask for it; losses are shown only there, never in the class table.
create or replace function public.duel_history(p_me text) returns json
language sql security definer set search_path = public as $$
  select coalesce(json_agg(x order by x.at desc), '[]'::json) from (
    select d.finished_at as at,
      case when d.a_id = left(p_me, 40) then d.b_name else d.a_name end as opp_name,
      case when d.a_id = left(p_me, 40) then d.b_cls else d.a_cls end as opp_cls,
      case when d.a_id = left(p_me, 40) then d.b_av else d.a_av end as opp_av,
      case when d.a_id = left(p_me, 40) then d.a_score else d.b_score end as my_score,
      case when d.a_id = left(p_me, 40) then d.b_score else d.a_score end as opp_score,
      case when d.status = 'abandoned' then 'none'
           when d.winner = 'draw' then 'draw'
           when (d.winner = 'a') = (d.a_id = left(p_me, 40)) then 'win' else 'loss' end as result
    from duels d
    where (d.a_id = left(p_me, 40) or d.b_id = left(p_me, 40)) and d.status in ('done', 'abandoned')
    order by d.finished_at desc limit 50) x;
$$;
revoke all on function public.duel_history(text) from public;
grant execute on function public.duel_history(text) to anon;
