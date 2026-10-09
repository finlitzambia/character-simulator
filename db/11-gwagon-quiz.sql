-- FinLit Zambia — 11-gwagon-quiz.sql  (v2, safe to re-run)  Run AFTER 10.
--
-- "WHO GETS IN MY G-WAGON?"  A shareable, funny money-character quiz.
--   * 18 dilemmas with NO right answer. Every option reveals something (caution, discipline,
--     generosity, boldness, show-off, shortcut-taking), and the answers add up to one of
--     10 funny money characters (from "The Master Builder" to "The Smooth Operator").
--   * The creator picks 6 dilemmas and answers each as themselves. For any answer they can
--     mark "I'm bluffing".
--   * Friends: answer for themselves, then judge whether the creator was telling the truth.
--     They get a COMPATIBILITY % with the creator, a seat in the G-wagon, their own money
--     character, a lie-detector score, and two leaderboards.
--   * Every result leads to a lesson. Anonymous usage tracking (no names, no IPs) shows the funnel.

-- ── tables (also upgrades the first version in place) ──
create table if not exists quiz_presets (
  id int primary key, question_key text not null unique, emoji text not null, prompt text not null,
  options jsonb not null, wise_index int not null default 0, is_active boolean not null default true
);
create table if not exists quizzes (
  id bigint generated always as identity primary key, code text not null unique, creator_name text not null,
  theme text not null default 'gwagon', question_ids int[] not null, token_hash text not null,
  response_count int not null default 0, is_active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists quiz_responses (
  id bigint generated always as identity primary key, quiz_id bigint not null references quizzes(id) on delete cascade,
  name text not null, name_key text not null, answers int[] not null, traits jsonb not null,
  matches int not null default 0, character text, created_at timestamptz not null default now(), unique (quiz_id, name_key)
);
alter table quizzes add column if not exists picks int[];
alter table quizzes add column if not exists bluffs boolean[];
alter table quizzes add column if not exists creator_traits jsonb;
alter table quizzes add column if not exists creator_archetype text;
alter table quiz_responses add column if not exists guesses boolean[];
alter table quiz_responses add column if not exists compat int;
alter table quiz_responses add column if not exists judge int;
alter table quiz_responses add column if not exists archetype text;
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'quizzes' and column_name = 'accepted') then
    alter table quizzes alter column accepted drop not null;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'quiz_responses' and column_name = 'character') then
    alter table quiz_responses alter column character drop not null;
  end if;
end $$;
update quizzes set is_active = false where picks is null;     -- quizzes from the first version cannot be played any more
create index if not exists quiz_responses_board on quiz_responses (quiz_id, created_at);

create table if not exists quiz_rate (ip_hash text not null, kind text not null, bucket timestamptz not null, n int not null default 1, primary key (ip_hash, kind, bucket));
create table if not exists quiz_archetypes (
  key text primary key, emoji text not null, title text not null, blurb text not null, power text not null, blind text not null,
  likely text not null, lesson_file text not null, lesson_title text not null, lesson_pitch text not null,
  z jsonb not null, bias numeric not null default 0, sort int not null
);
create table if not exists quiz_dim_stats (dim text primary key, mean numeric not null, std numeric not null);
create table if not exists quiz_events (
  id bigint generated always as identity primary key, kind text not null, code text, vid text, meta jsonb, created_at timestamptz not null default now()
);
create index if not exists quiz_events_kind on quiz_events (kind, created_at);

alter table quiz_presets enable row level security; alter table quizzes enable row level security;
alter table quiz_responses enable row level security; alter table quiz_rate enable row level security;
alter table quiz_archetypes enable row level security; alter table quiz_dim_stats enable row level security;
alter table quiz_events enable row level security;
revoke all on quiz_presets, quizzes, quiz_responses, quiz_rate, quiz_archetypes, quiz_dim_stats, quiz_events from anon, authenticated;

drop function if exists quiz_create(text, text[], int[]);
drop function if exists quiz_submit(text, text, int[]);

-- ── helpers ──
create or replace function quiz_rate_ok(p_kind text, p_limit int)
returns boolean language plpgsql security definer set search_path = public as $$
declare h json; ip text; v_n int; b timestamptz := date_trunc('hour', now());
begin
  begin h := current_setting('request.headers', true)::json; exception when others then h := null; end;
  ip := nullif(trim(split_part(coalesce(h->>'x-forwarded-for', h->>'cf-connecting-ip', ''), ',', 1)), '');
  if ip is null then return true; end if;
  ip := md5(ip || ':finlit');
  insert into quiz_rate (ip_hash, kind, bucket) values (ip, p_kind, b)
    on conflict (ip_hash, kind, bucket) do update set n = quiz_rate.n + 1 returning n into v_n;
  if random() < 0.02 then delete from quiz_rate where bucket < now() - interval '2 days'; end if;
  return v_n <= p_limit;
end $$;

create or replace function quiz_clean_name(t text)
returns text language sql immutable as $$
  select left(trim(regexp_replace(regexp_replace(coalesce(t, ''), '[<>&"`\\]', '', 'g'), '\s+', ' ', 'g')), 24)
$$;

-- Turn a set of answers into six percentage scores and the nearest money character.
create or replace function quiz_profile(p_ids int[], p_picks int[])
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  dims text[] := array['prudence','discipline','generosity','boldness','status','shortcut'];
  d text; i int; pr quiz_presets; s int; m int; a quiz_archetypes; st quiz_dim_stats; dd numeric; dist numeric;
  sums jsonb := '{}'::jsonb; maxs jsonb := '{}'::jsonb; pct jsonb := '{}'::jsonb; best text; bestd numeric;
begin
  foreach d in array dims loop sums := sums || jsonb_build_object(d, 0); maxs := maxs || jsonb_build_object(d, 0); end loop;
  for i in 1..array_length(p_ids, 1) loop
    select * into pr from quiz_presets where id = p_ids[i];
    foreach d in array dims loop
      s := coalesce((pr.options -> p_picks[i] -> 'traits' ->> d)::int, 0);
      select coalesce(max(coalesce((o -> 'traits' ->> d)::int, 0)), 0) into m from jsonb_array_elements(pr.options) o;
      sums := jsonb_set(sums, array[d], to_jsonb((sums ->> d)::int + s));
      maxs := jsonb_set(maxs, array[d], to_jsonb((maxs ->> d)::int + m));
    end loop;
  end loop;
  foreach d in array dims loop
    pct := pct || jsonb_build_object(d, case when (maxs ->> d)::int > 0 then round(100.0 * (sums ->> d)::numeric / (maxs ->> d)::numeric) else 0 end);
  end loop;
  for a in select * from quiz_archetypes order by sort loop
    dist := a.bias;
    foreach d in array dims loop
      select * into st from quiz_dim_stats where dim = d;
      dd := ((pct ->> d)::numeric - st.mean) / greatest(st.std, 1) - coalesce((a.z ->> d)::numeric, 0);
      dist := dist + dd * dd;
    end loop;
    if bestd is null or dist < bestd then bestd := dist; best := a.key; end if;
  end loop;
  return jsonb_build_object('traits', pct, 'archetype', best);
end $$;

create or replace function quiz_arch_json(p_key text)
returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(t) from (select key, emoji, title, blurb, power, blind, likely, lesson_file, lesson_title, lesson_pitch
                             from quiz_archetypes where key = p_key) t
$$;

-- ── the dilemmas (options only; trait points stay on the server) ──
create or replace function quiz_presets()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('key', question_key, 'emoji', emoji, 'prompt', prompt,
    'options', (select jsonb_agg(o -> 'text') from jsonb_array_elements(options) o)) order by id), '[]'::jsonb)
  from quiz_presets where is_active
$$;

-- ── create: the creator answers as themselves; any answer can be marked as a bluff ──
create or replace function quiz_create(p_name text, p_keys text[], p_picks int[], p_bluffs boolean[] default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_name text := quiz_clean_name(p_name); v_ids int[] := '{}'; v_bl boolean[] := '{}'; i int; r quiz_presets;
  v_code text; v_token text := replace(gen_random_uuid()::text, '-', ''); tries int := 0; prof jsonb;
  alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
begin
  if not quiz_rate_ok('create', 40) then return jsonb_build_object('error', 'rate_limited'); end if;
  if char_length(v_name) < 1 then return jsonb_build_object('error', 'bad_name'); end if;
  if p_keys is null or array_length(p_keys, 1) <> 6 or (select count(distinct k) from unnest(p_keys) k) <> 6
     or p_picks is null or array_length(p_picks, 1) <> 6 then
    return jsonb_build_object('error', 'need_six_questions');
  end if;
  for i in 1..6 loop
    select * into r from quiz_presets where question_key = p_keys[i] and is_active;
    if not found then return jsonb_build_object('error', 'bad_question'); end if;
    if p_picks[i] < 0 or p_picks[i] >= jsonb_array_length(r.options) then return jsonb_build_object('error', 'bad_answer'); end if;
    v_ids := v_ids || r.id;
    v_bl := v_bl || coalesce(case when p_bluffs is not null and array_length(p_bluffs, 1) = 6 then p_bluffs[i] end, false);
  end loop;
  prof := quiz_profile(v_ids, p_picks);

  loop
    v_code := '';
    for i in 1..6 loop v_code := v_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from quizzes where code = v_code);
    tries := tries + 1; if tries > 20 then return jsonb_build_object('error', 'try_again'); end if;
  end loop;

  insert into quizzes (code, creator_name, question_ids, picks, bluffs, creator_traits, creator_archetype, token_hash)
  values (v_code, v_name, v_ids, p_picks, v_bl, prof -> 'traits', prof ->> 'archetype', md5(v_token || ':finlit'));
  insert into quiz_events (kind, code) values ('quiz_created', v_code);
  return jsonb_build_object('code', v_code, 'token', v_token, 'archetype', quiz_arch_json(prof ->> 'archetype'), 'traits', prof -> 'traits');
end $$;

-- ── load a quiz: questions, plus what the creator CLAIMS (never whether it is a bluff) ──
create or replace function quiz_get(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q quizzes; v_qs jsonb;
begin
  select * into q from quizzes where code = upper(trim(p_code)) and is_active;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  select jsonb_agg(jsonb_build_object('emoji', pr.emoji, 'prompt', pr.prompt,
           'claim', pr.options -> q.picks[x.n::int] ->> 'text',
           'options', (select jsonb_agg(jsonb_build_object('index', ord - 1, 'text', o ->> 'text') order by ord)
                         from jsonb_array_elements(pr.options) with ordinality as t(o, ord))) order by x.n)
    into v_qs from unnest(q.question_ids) with ordinality as x(id, n) join quiz_presets pr on pr.id = x.id;
  return jsonb_build_object('creator', q.creator_name, 'theme', q.theme, 'count', q.response_count, 'questions', v_qs);
end $$;

-- ── leaderboards ──
create or replace function quiz_board(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q quizzes; v_c jsonb; v_j jsonb;
begin
  select * into q from quizzes where code = upper(trim(p_code)) and is_active;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'compat', t.compat, 'emoji', t.emoji) order by t.compat desc, t.created_at), '[]'::jsonb)
    into v_c from (select r.name, r.compat, r.created_at, a.emoji from quiz_responses r left join quiz_archetypes a on a.key = r.archetype
                    where r.quiz_id = q.id order by r.compat desc, r.created_at limit 25) t;
  select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'judge', t.judge, 'emoji', t.emoji) order by t.judge desc, t.created_at), '[]'::jsonb)
    into v_j from (select r.name, r.judge, r.created_at, a.emoji from quiz_responses r left join quiz_archetypes a on a.key = r.archetype
                    where r.quiz_id = q.id order by r.judge desc, r.created_at limit 25) t;
  return jsonb_build_object('creator', q.creator_name, 'total', q.response_count, 'compat', v_c, 'judge', v_j,
                            'creator_archetype', quiz_arch_json(q.creator_archetype));
end $$;

-- ── submit: friend's own answers + whether they think each claim is honest ──
create or replace function quiz_submit(p_code text, p_name text, p_picks int[], p_guesses boolean[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  q quizzes; v_name text := quiz_clean_name(p_name); n int; i int; pr quiz_presets; prof jsonb; v_tr jsonb; d text;
  v_matches int := 0; v_judge int := 0; v_sim numeric := 0; v_compat int; v_id bigint; v_new boolean; v_rank int;
  v_reveal jsonb := '[]'::jsonb; v_when timestamptz;
begin
  if not quiz_rate_ok('submit', 400) then return jsonb_build_object('error', 'rate_limited'); end if;
  select * into q from quizzes where code = upper(trim(p_code)) and is_active;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  if char_length(v_name) < 1 then return jsonb_build_object('error', 'bad_name'); end if;
  n := array_length(q.question_ids, 1);
  if p_picks is null or array_length(p_picks, 1) <> n or p_guesses is null or array_length(p_guesses, 1) <> n then
    return jsonb_build_object('error', 'bad_answers');
  end if;
  if q.response_count >= 500 and not exists (select 1 from quiz_responses where quiz_id = q.id and name_key = lower(v_name)) then
    return jsonb_build_object('error', 'full');
  end if;

  for i in 1..n loop
    select * into pr from quiz_presets where id = q.question_ids[i];
    if p_picks[i] < 0 or p_picks[i] >= jsonb_array_length(pr.options) then return jsonb_build_object('error', 'bad_answers'); end if;
    if p_picks[i] = q.picks[i] then v_matches := v_matches + 1; end if;
    if p_guesses[i] = (not q.bluffs[i]) then v_judge := v_judge + 1; end if;
    v_reveal := v_reveal || jsonb_build_array(jsonb_build_object(
      'emoji', pr.emoji, 'prompt', pr.prompt, 'claim', pr.options -> q.picks[i] ->> 'text', 'bluff', q.bluffs[i],
      'mine', pr.options -> p_picks[i] ->> 'text', 'matched', p_picks[i] = q.picks[i], 'guess_ok', p_guesses[i] = (not q.bluffs[i])));
  end loop;

  prof := quiz_profile(q.question_ids, p_picks);
  v_tr := prof -> 'traits';
  foreach d in array array['prudence','discipline','generosity','boldness','status','shortcut'] loop
    v_sim := v_sim + abs((v_tr ->> d)::numeric - (q.creator_traits ->> d)::numeric);
  end loop;
  v_sim := 1 - v_sim / 600.0;                                    -- how similar the two profiles are, 0 to 1
  v_compat := round(100 * (0.5 * v_matches / n::numeric + 0.5 * least(1, greatest(0, (v_sim - 0.6) / 0.4))));

  insert into quiz_responses (quiz_id, name, name_key, answers, traits, matches, character, guesses, compat, judge, archetype)
  values (q.id, v_name, lower(v_name), p_picks, v_tr, v_matches, prof ->> 'archetype', p_guesses, v_compat, v_judge, prof ->> 'archetype')
  on conflict (quiz_id, name_key) do update
    set answers = excluded.answers, traits = excluded.traits, matches = excluded.matches, character = excluded.character,
        guesses = excluded.guesses, compat = excluded.compat, judge = excluded.judge, archetype = excluded.archetype, created_at = now()
  returning id, (xmax = 0), created_at into v_id, v_new, v_when;
  if v_new then update quizzes set response_count = response_count + 1 where id = q.id; end if;
  insert into quiz_events (kind, code, meta) values ('quiz_scored', q.code, jsonb_build_object('compat', v_compat, 'judge', v_judge, 'archetype', prof ->> 'archetype'));

  select 1 + count(*) into v_rank from quiz_responses
   where quiz_id = q.id and (compat > v_compat or (compat = v_compat and created_at < v_when));

  return jsonb_build_object('creator', q.creator_name, 'matches', v_matches, 'total', n, 'compat', v_compat, 'judge', v_judge,
    'archetype', quiz_arch_json(prof ->> 'archetype'), 'traits', v_tr, 'rank', v_rank,
    'creator_archetype', quiz_arch_json(q.creator_archetype), 'reveal', v_reveal,
    'board', quiz_board(q.code), 'players', (select response_count from quizzes where id = q.id));
end $$;

create or replace function quiz_close(p_code text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update quizzes set is_active = false where code = upper(trim(p_code)) and token_hash = md5(coalesce(p_token, '') || ':finlit');
  return jsonb_build_object('ok', found);
end $$;

-- ── anonymous usage tracking (no names, no IPs; "vid" is a random id kept on the device) ──
create or replace function track_event(p_kind text, p_code text default null, p_vid text default null, p_meta jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_kind is null or p_kind <> all (array['quiz_page','quiz_open','quiz_start','quiz_finish','share_creator','share_result','copy_link',
       'lesson_click','make_own','sim_click','board_view','lesson_open','home_view','home_quiz_click','retake','quiz_made','social_click','social_popup']) then return; end if;
  if not quiz_rate_ok('track', 1500) then return; end if;
  insert into quiz_events (kind, code, vid, meta)
  values (p_kind, left(upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')), 8), left(coalesce(p_vid, ''), 40),
          case when p_meta is not null and pg_column_size(p_meta) < 500 then p_meta end);
end $$;

-- ── the owner's dashboard (needs the admin key) ──
insert into sim_config (key, value) values ('quiz_admin_hash', md5($k$CccBLpFV8bqTQWAIrtw3$k$ || ':finlit')) on conflict (key) do nothing;

create or replace function quiz_admin_stats(p_key text, p_days int default 14)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_since timestamptz := now() - (greatest(1, least(p_days, 90)) || ' days')::interval; v_out jsonb;
begin
  if md5(coalesce(p_key, '') || ':finlit') <> (select value from sim_config where key = 'quiz_admin_hash') then
    return jsonb_build_object('error', 'forbidden');
  end if;
  select jsonb_build_object(
    'since', v_since,
    'totals', (select coalesce(jsonb_object_agg(kind, n), '{}'::jsonb) from (select kind, count(*) n from quiz_events where created_at >= v_since group by kind) t),
    'uniques', (select coalesce(jsonb_object_agg(kind, n), '{}'::jsonb) from (select kind, count(distinct vid) n from quiz_events where created_at >= v_since and vid <> '' group by kind) t),
    'by_day', (select coalesce(jsonb_agg(t order by t.day), '[]'::jsonb) from (
        select created_at::date as day,
               count(*) filter (where kind = 'quiz_created') created,
               count(*) filter (where kind = 'quiz_open') opens,
               count(*) filter (where kind = 'quiz_scored') finished,
               count(*) filter (where kind in ('share_creator','share_result')) shares,
               count(*) filter (where kind = 'lesson_click') lesson_clicks,
               count(*) filter (where kind = 'lesson_open') lesson_opens
          from quiz_events where created_at >= v_since group by 1) t),
    'archetypes', (select coalesce(jsonb_object_agg(a, n), '{}'::jsonb) from (select meta ->> 'archetype' a, count(*) n from quiz_events
                    where kind = 'quiz_scored' and created_at >= v_since group by 1) t),
    'avg_compat', (select round(avg((meta ->> 'compat')::numeric)) from quiz_events where kind = 'quiz_scored' and created_at >= v_since),
    'quizzes', (select count(*) from quizzes), 'players_total', (select coalesce(sum(response_count), 0) from quizzes),
    'top_quizzes', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (select code, creator_name, response_count from quizzes order by response_count desc limit 8) t),
    'players_who_made_quiz', (select count(distinct f.vid) from quiz_events f join quiz_events c on c.vid = f.vid and c.kind = 'quiz_made' and c.created_at > f.created_at
                               where f.kind = 'quiz_finish' and f.vid <> '' and f.created_at >= v_since)
  ) into v_out;
  return v_out;
end $$;

do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'quiz\_%' or p.proname = 'track_event')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    if r.proname in ('quiz_presets','quiz_create','quiz_get','quiz_board','quiz_submit','quiz_close','track_event','quiz_admin_stats') then
      execute format('grant execute on function %s to anon, authenticated', r.sig);
    end if;
  end loop;
end $$;

-- ── content ──
-- the first version used some of the same keys (cash_gig, coin_tip): rename them so the new questions can reuse them
update quiz_presets set question_key = 'old_' || question_key where id < 100 and question_key not like 'old\_%';
update quiz_presets set is_active = false where id < 100;
insert into quiz_presets (id, question_key, emoji, prompt, options, wise_index) values
(101, $k$tender$k$, $k$🏗️$k$, $t$A cousin in government whispers: "I can get you the road-repair contract. Small 'facilitation fee' needed."$t$, $j$[{"text": "Pay the fee. That's how things move", "traits": {"shortcut": 3, "boldness": 1}}, {"text": "Ask for the paperwork before I decide anything", "traits": {"prudence": 3}}, {"text": "Bid openly. If I lose, I lose", "traits": {"discipline": 3}}, {"text": "Take it and subcontract to the loudest person I know", "traits": {"shortcut": 2, "status": 1, "generosity": 1}}]$j$::jsonb, 0),
(102, $k$inheritance$k$, $k$🐄$k$, $t$Uncle leaves you K50,000 and a cow named Fiona. Fiona is not negotiable.$t$, $j$[{"text": "Buy a car. Obviously", "traits": {"status": 3}}, {"text": "Share it with my siblings. It's family money", "traits": {"generosity": 3}}, {"text": "Fixed deposit for most, and Fiona stays", "traits": {"prudence": 2, "discipline": 2}}, {"text": "Buy five more cows. Fiona needs a team", "traits": {"boldness": 3}}]$j$::jsonb, 0),
(103, $k$invest_club$k$, $k$📲$k$, $t$A group chat's 'investment club' pays 30% a month. Everyone's posting screenshots.$t$, $j$[{"text": "Join with K2,000. Screenshots don't lie", "traits": {"boldness": 3}}, {"text": "Ask for their licence first, join only if it's real", "traits": {"prudence": 3}}, {"text": "Wait until others cash out, then join", "traits": {"shortcut": 2, "prudence": 1}}, {"text": "Start my own group. The money is at the top", "traits": {"shortcut": 3, "boldness": 1, "status": 1}}]$j$::jsonb, 0),
(104, $k$wedding_season$k$, $k$👰$k$, $t$Three weddings this month, budget K1,000. A talk-of-the-town outfit costs K800.$t$, $j$[{"text": "Buy the outfit. Reputation is currency", "traits": {"status": 3}}, {"text": "Rent an outfit and give modest gifts", "traits": {"discipline": 2, "prudence": 1}}, {"text": "Attend one, send love to the rest", "traits": {"discipline": 3}}, {"text": "Same dress, new accessories, tell everyone it's new", "traits": {"status": 2, "shortcut": 1, "prudence": 1}}]$j$::jsonb, 0),
(105, $k$invoice$k$, $k$🧾$k$, $t$Your boss asks you to 'adjust' an invoice by K500. "Everyone does it."$t$, $j$[{"text": "Do it. Bosses remember loyal people", "traits": {"shortcut": 3, "status": 1}}, {"text": "Do it, but keep a screenshot as insurance", "traits": {"shortcut": 2, "prudence": 2}}, {"text": "Politely refuse and risk the relationship", "traits": {"discipline": 3}}, {"text": "Pretend I didn't understand the request", "traits": {"prudence": 2, "shortcut": 1}}]$j$::jsonb, 0),
(106, $k$goat_uber$k$, $k$🐐$k$, $t$A friend wants K5,000 for 'Uber for goats'.$t$, $j$[{"text": "Invest. Goats are underserved", "traits": {"boldness": 3, "generosity": 1}}, {"text": "Lend it, with a repayment date", "traits": {"prudence": 2, "discipline": 1, "generosity": 1}}, {"text": "Give advice, not money", "traits": {"prudence": 2, "discipline": 1}}, {"text": "Put in K500 and call myself an 'early investor'", "traits": {"status": 2, "boldness": 1}}]$j$::jsonb, 0),
(107, $k$loan_shark$k$, $k$🦈$k$, $t$Rent is due and payday is 10 days away. A lender offers K1,000 at 40% for two weeks.$t$, $j$[{"text": "Take it. Rent can't wait", "traits": {"boldness": 2, "shortcut": 1}}, {"text": "Sell something I own", "traits": {"discipline": 2, "prudence": 1}}, {"text": "Charm the landlord into waiting (bring snacks)", "traits": {"prudence": 1, "shortcut": 1, "generosity": 1}}, {"text": "Borrow quietly from three friends so nobody knows", "traits": {"status": 3}}]$j$::jsonb, 0),
(108, $k$bet_win$k$, $k$🎰$k$, $t$You win K10,000 on a bet. Everyone knows.$t$, $j$[{"text": "Treat everybody tonight. You only win once", "traits": {"generosity": 2, "status": 2}}, {"text": "Double down. This is a lucky streak", "traits": {"boldness": 3}}, {"text": "Bank it tomorrow and tell nobody", "traits": {"prudence": 2, "discipline": 2}}, {"text": "Buy a very visible gift for my mother", "traits": {"generosity": 2, "status": 1}}]$j$::jsonb, 0),
(109, $k$chilimba_short$k$, $k$👛$k$, $t$You hold the chilimba money. You're K400 short, and no one will notice for a week.$t$, $j$[{"text": "'Borrow' it and repay next week", "traits": {"shortcut": 3, "boldness": 1}}, {"text": "Cover it from my own savings", "traits": {"discipline": 2, "generosity": 1}}, {"text": "Tell the group the truth and ask for help", "traits": {"discipline": 2, "prudence": 1}}, {"text": "Delay the payout and blame the network", "traits": {"shortcut": 2, "status": 1}}]$j$::jsonb, 0),
(110, $k$handshake$k$, $k$🤝$k$, $t$Your business partner says: "We're brothers. No need to sign anything."$t$, $j$[{"text": "Handshake. Trust is everything", "traits": {"generosity": 2, "boldness": 2}}, {"text": "Insist on a written agreement, even if it's awkward", "traits": {"prudence": 3, "discipline": 1}}, {"text": "Agree, and quietly keep my own records", "traits": {"prudence": 2, "shortcut": 1}}, {"text": "Agree, and make sure I'm the one holding the money", "traits": {"shortcut": 2, "status": 1, "prudence": 1}}]$j$::jsonb, 0),
(111, $k$new_phone$k$, $k$📱$k$, $t$Everyone has the new phone. Yours cracks when you laugh.$t$, $j$[{"text": "Get it on instalments. You only live once", "traits": {"status": 2, "boldness": 1}}, {"text": "Buy a second-hand one that works fine", "traits": {"prudence": 2, "discipline": 1}}, {"text": "Keep the cracked one. It's a personality", "traits": {"discipline": 3}}, {"text": "Buy the new one and skip lunch for two months", "traits": {"status": 3, "discipline": 1}}]$j$::jsonb, 0),
(112, $k$birthday$k$, $k$🎂$k$, $t$Your birthday is coming. Budget: K1,500. Your friends expect 'big'.$t$, $j$[{"text": "Go big. Memories over money", "traits": {"status": 2, "generosity": 1, "boldness": 1}}, {"text": "Small dinner for K500, save the rest", "traits": {"discipline": 3}}, {"text": "Let friends 'sponsor' it and call it a collaboration", "traits": {"shortcut": 2, "status": 1}}, {"text": "Potluck. Everyone brings something", "traits": {"prudence": 1, "generosity": 1, "discipline": 1}}]$j$::jsonb, 0),
(113, $k$found_wallet$k$, $k$👛$k$, $t$You find a wallet with K3,000 and an ID card.$t$, $j$[{"text": "Return it, untouched", "traits": {"discipline": 3}}, {"text": "Return it, minus a 'finder's fee'", "traits": {"shortcut": 3}}, {"text": "Return it and film it for TikTok", "traits": {"status": 3}}, {"text": "Return it and politely mention a reward", "traits": {"prudence": 1, "status": 1, "discipline": 1}}]$j$::jsonb, 0),
(114, $k$rush_order$k$, $k$⚡$k$, $t$A customer offers double your price if you rush the order. You'd have to skip quality checks.$t$, $j$[{"text": "Take it. Money is money", "traits": {"boldness": 2, "shortcut": 2}}, {"text": "Take it, but warn them it'll be rough", "traits": {"discipline": 1, "boldness": 1, "prudence": 1}}, {"text": "Refuse. My reputation is my business", "traits": {"discipline": 2, "prudence": 2}}, {"text": "Take it and quietly outsource to my cousin", "traits": {"shortcut": 2, "generosity": 1, "boldness": 1}}]$j$::jsonb, 0),
(115, $k$family_ask$k$, $k$🏠$k$, $t$A relative asks for K2,000 'for a small emergency'. It's the fourth 'small emergency' this year.$t$, $j$[{"text": "Give it. Family is family", "traits": {"generosity": 3}}, {"text": "Give K500 and set a limit", "traits": {"generosity": 1, "discipline": 2}}, {"text": "Say no. I'm not the family bank", "traits": {"discipline": 1, "prudence": 2}}, {"text": "Give it, and mention it at the next family meeting", "traits": {"generosity": 1, "status": 2}}]$j$::jsonb, 0),
(116, $k$cash_gig$k$, $k$💵$k$, $t$You're paid cash for a gig. No receipt needed.$t$, $j$[{"text": "Record it and set some aside", "traits": {"discipline": 3}}, {"text": "Spend it by tonight", "traits": {"status": 1, "boldness": 1, "generosity": 1}}, {"text": "Don't declare it. It's just cash", "traits": {"shortcut": 3}}, {"text": "Hide it safely at home", "traits": {"prudence": 2, "discipline": 1}}]$j$::jsonb, 0),
(117, $k$coin_tip$k$, $k$🪙$k$, $t$A friend swears a coin will 'moon' tomorrow.$t$, $j$[{"text": "Buy now before it pumps", "traits": {"boldness": 3}}, {"text": "Read about it first", "traits": {"prudence": 3}}, {"text": "Buy a little, just so I can say I'm in", "traits": {"status": 2, "boldness": 1}}, {"text": "Tell everyone, then buy when they do", "traits": {"generosity": 1, "shortcut": 1, "boldness": 1, "status": 1}}]$j$::jsonb, 0),
(118, $k$promotion$k$, $k$📈$k$, $t$You're promoted with a K2,000/month raise. First move?$t$, $j$[{"text": "Upgrade my lifestyle: better place, better clothes", "traits": {"status": 3}}, {"text": "Live the same and invest the raise", "traits": {"discipline": 3, "prudence": 1}}, {"text": "Help family with the extra", "traits": {"generosity": 3}}, {"text": "Start a side business with the raise", "traits": {"boldness": 3}}]$j$::jsonb, 0)
on conflict (id) do update set question_key = excluded.question_key, emoji = excluded.emoji, prompt = excluded.prompt,
  options = excluded.options, is_active = true;

insert into quiz_dim_stats (dim, mean, std) values
($k$prudence$k$, 32.90, 19.32),
($k$discipline$k$, 32.77, 19.48),
($k$generosity$k$, 32.34, 24.11),
($k$boldness$k$, 30.13, 21.40),
($k$status$k$, 30.79, 19.73),
($k$shortcut$k$, 37.02, 24.13)
on conflict (dim) do update set mean = excluded.mean, std = excluded.std;

insert into quiz_archetypes (key, emoji, title, blurb, power, blind, likely, lesson_file, lesson_title, lesson_pitch, z, bias, sort) values
($k$master_builder$k$, $t$🏗️$t$, $t$The Master Builder$t$, $t$You plan, you build, you keep receipts. Contractors fear your spreadsheets.$t$, $t$Turning a plan into something that actually gets finished$t$, $t$Can be so careful that fun money never happens$t$, $t$win the tender, finish the road, and still have the paperwork$t$, $k$module-2-4-full.html$k$, $t$Entrepreneurship & Small Business Finance$t$, $t$Learn the money maths behind every successful build.$t$, $j${"prudence": 1.41, "discipline": 2.25, "generosity": -0.85, "boldness": -0.75, "status": -1.25, "shortcut": -1.43}$j$::jsonb, -0.794, 1),
($k$smooth_operator$k$, $t$🕴️$t$, $t$The Smooth Operator$t$, $t$You know a guy for everything, and the guy knows a guy. Rules are more like suggestions.$t$, $t$Opening doors nobody else can find$t$, $t$Shortcuts feel clever until the paperwork catches up$t$, $t$be 'consulting' for three ministries and own none of the paperwork$t$, $k$module-3-3-full.html$k$, $t$Consumer Protection$t$, $t$Learn how money rules protect you, before they catch up with you.$t$, $j${"prudence": -1.28, "discipline": -1.58, "generosity": -0.3, "boldness": 0.36, "status": 1.48, "shortcut": 1.97}$j$::jsonb, -0.239, 2),
($k$chilimba_royalty$k$, $t$👑$t$, $t$The Chilimba Royalty$t$, $t$Everyone's money is safe with you. You run the group fund, the group chat and probably the group.$t$, $t$Building trust that people actually pay into$t$, $t$Your own goals can wait while you look after everyone$t$, $t$run the savings group, the WhatsApp group and your whole street$t$, $k$module-1-1-full.html$k$, $t$Saving and Banking$t$, $t$Learn how to grow the group money and your own.$t$, $j${"prudence": 0.23, "discipline": 1.65, "generosity": 0.76, "boldness": -0.66, "status": -0.99, "shortcut": -1.31}$j$::jsonb, 1.098, 3),
($k$hype_believer$k$, $t$📣$t$, $t$The Hype Believer$t$, $t$Anything with a screenshot and a deadline gets your attention. You always say, "This one is legit."$t$, $t$Moving fast when everyone else is still thinking$t$, $t$Scams love your energy$t$, $t$be first in the group chat that says 'it's legit'$t$, $k$module-3-2-full.html$k$, $t$Digital Finance & Cybersecurity$t$, $t$Learn to spot a scam in under a minute.$t$, $j${"prudence": -1.54, "discipline": -1.09, "generosity": -0.05, "boldness": 2.25, "status": 0.33, "shortcut": 0.48}$j$::jsonb, -0.156, 4),
($k$quiet_millionaire$k$, $t$🤫$t$, $t$The Quiet Millionaire$t$, $t$No fuss, no show, just compound interest. People think you're broke. You're not.$t$, $t$Growing money while nobody is watching$t$, $t$You may forget money is also for enjoying$t$, $t$own three houses and drive a 2009 Toyota$t$, $k$module-2-1-full.html$k$, $t$Basics of Investing$t$, $t$Learn how to make your careful savings grow faster.$t$, $j${"prudence": 2.23, "discipline": 2.24, "generosity": -0.95, "boldness": -1.24, "status": -1.53, "shortcut": -1.34}$j$::jsonb, -1.128, 5),
($k$showpiece$k$, $t$💎$t$, $t$The Showpiece$t$, $t$Great outfit, great photos, and a balance that says "loading..."$t$, $t$Making every moment look like an event$t$, $t$Looking rich and being rich are different things$t$, $t$have a perfect profile picture and a very small balance$t$, $k$module-1-3-full.html$k$, $t$Emergency Funds & Resilience$t$, $t$Learn how to build a safety net that actually shows up on payday.$t$, $j${"prudence": -1.3, "discipline": -1.5, "generosity": 0.01, "boldness": -0.1, "status": 2.81, "shortcut": 0.5}$j$::jsonb, -0.267, 6),
($k$everyones_bank$k$, $t$🏦$t$, $t$Everyone's Bank$t$, $t$Your heart is big and your wallet is open. You have lent money to people whose names you can't remember.$t$, $t$Making everyone around you feel supported$t$, $t$Nobody has repaid you since 2019$t$, $t$fund the whole group and call it 'a small thing'$t$, $k$module-1-2-full.html$k$, $t$Credit and Debt Management$t$, $t$Learn to help people without going broke yourself.$t$, $j${"prudence": -1.17, "discipline": -0.69, "generosity": 1.93, "boldness": 0.17, "status": 0.44, "shortcut": 0.07}$j$::jsonb, 1.08, 7),
($k$side_hustle$k$, $t$⚙️$t$, $t$The Side-Hustle Machine$t$, $t$Airtime, eggs and insurance in one conversation. You see a gap and fill it with a WhatsApp status.$t$, $t$Turning small chances into steady income$t$, $t$Burning out before the business pays you back$t$, $t$sell you airtime, eggs and insurance before you finish your tea$t$, $k$module-b1-full.html$k$, $t$Starting & Running a Business$t$, $t$Learn how to turn the hustle into a real, lasting business.$t$, $j${"prudence": -0.79, "discipline": 0.44, "generosity": -0.54, "boldness": 1.71, "status": -0.84, "shortcut": -0.15}$j$::jsonb, 1.767, 8),
($k$fortress$k$, $t$🛡️$t$, $t$The Fortress$t$, $t$Nothing gets in, and nothing gets out. Your money is very, very safe and very, very bored.$t$, $t$Staying calm when everyone else is panicking$t$, $t$Playing safe forever can cost you growth$t$, $t$keep K50 under the mattress 'just in case' since 2011$t$, $k$module-2-1-full.html$k$, $t$Basics of Investing$t$, $t$Learn how to make money work harder without losing sleep.$t$, $j${"prudence": 2.8, "discipline": 1.35, "generosity": -0.81, "boldness": -1.38, "status": -1.34, "shortcut": -1.0}$j$::jsonb, -0.602, 9),
($k$free_spirit$k$, $t$🌈$t$, $t$The Free Spirit$t$, $t$Money comes, money goes, vibes stay. You're the reason "month end" feels long.$t$, $t$Making life feel good, right now$t$, $t$Future you keeps getting the bill$t$, $t$be broke, happy and unbothered$t$, $k$module-1-0-full.html$k$, $t$Income, Budgeting & Goal Setting$t$, $t$Learn a budget that still leaves room for fun.$t$, $j${"prudence": -1.44, "discipline": -1.56, "generosity": 0.85, "boldness": 1.12, "status": 1.07, "shortcut": 0.69}$j$::jsonb, -0.758, 10)
on conflict (key) do update set emoji = excluded.emoji, title = excluded.title, blurb = excluded.blurb, power = excluded.power,
  blind = excluded.blind, likely = excluded.likely, lesson_file = excluded.lesson_file, lesson_title = excluded.lesson_title,
  lesson_pitch = excluded.lesson_pitch, z = excluded.z, bias = excluded.bias, sort = excluded.sort;
