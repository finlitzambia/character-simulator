-- FinLit Zambia — 11-gwagon-quiz.sql  (safe to re-run)  Run AFTER 10.
--
-- "WHO GETS IN MY G-WAGON?"  A shareable money-personality quiz.
--   * A creator picks 6 preset questions and the answer that "gets you in" for each.
--   * Friends open the link, enter a name (no account), answer, and get a seat in the
--     G-wagon plus a money personality (the same four traits as the yungsta game).
--   * Everything runs through functions callable by anyone (anon). The answer key and the
--     scoring tables are never readable directly.
--   * Basic abuse limits: per-IP hourly limits (generous, since mobile networks share IPs),
--     500 responses per quiz, and no free text except short names.

create table if not exists quiz_presets (
  id int primary key,
  question_key text not null unique,
  emoji text not null,
  prompt text not null,
  options jsonb not null,        -- [{"text":..., "traits": {"prudence": 2}}]
  wise_index int not null,       -- the default "gets you in" answer
  is_active boolean not null default true
);

create table if not exists quizzes (
  id bigint generated always as identity primary key,
  code text not null unique,
  creator_name text not null,
  theme text not null default 'gwagon',
  question_ids int[] not null,
  accepted int[] not null,       -- creator's "gets you in" option per question
  token_hash text not null,
  response_count int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists quiz_responses (
  id bigint generated always as identity primary key,
  quiz_id bigint not null references quizzes(id) on delete cascade,
  name text not null,
  name_key text not null,
  answers int[] not null,
  traits jsonb not null,
  matches int not null,
  character text not null,
  created_at timestamptz not null default now(),
  unique (quiz_id, name_key)
);
create index if not exists quiz_responses_board on quiz_responses (quiz_id, matches desc, created_at);

create table if not exists quiz_rate (
  ip_hash text not null, kind text not null, bucket timestamptz not null, n int not null default 1,
  primary key (ip_hash, kind, bucket)
);

alter table quiz_presets enable row level security;
alter table quizzes enable row level security;
alter table quiz_responses enable row level security;
alter table quiz_rate enable row level security;
revoke all on quiz_presets, quizzes, quiz_responses, quiz_rate from anon, authenticated;

-- ── rate limit (returns false when the caller is over the limit) ──
create or replace function quiz_rate_ok(p_kind text, p_limit int)
returns boolean language plpgsql security definer set search_path = public as $$
declare h json; ip text; v_n int; b timestamptz := date_trunc('hour', now());
begin
  begin h := current_setting('request.headers', true)::json; exception when others then h := null; end;
  ip := nullif(trim(split_part(coalesce(h->>'x-forwarded-for', h->>'cf-connecting-ip', ''), ',', 1)), '');
  if ip is null then return true; end if;                       -- cannot identify the caller: allow
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

-- ── the preset questions (no trait points, no answer key) ──
create or replace function quiz_presets()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'key', question_key, 'emoji', emoji, 'prompt', prompt, 'wise', wise_index,
    'options', (select jsonb_agg(o -> 'text') from jsonb_array_elements(options) o)) order by id), '[]'::jsonb)
  from quiz_presets where is_active
$$;

-- ── create a quiz ──
create or replace function quiz_create(p_name text, p_keys text[], p_accepted int[] default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_name text := quiz_clean_name(p_name); v_ids int[] := '{}'; v_acc int[] := '{}';
  i int; r quiz_presets; v_code text; v_token text := replace(gen_random_uuid()::text, '-', ''); tries int := 0;
  alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
begin
  if not quiz_rate_ok('create', 40) then return jsonb_build_object('error', 'rate_limited'); end if;
  if char_length(v_name) < 1 then return jsonb_build_object('error', 'bad_name'); end if;
  if p_keys is null or array_length(p_keys, 1) <> 6 or (select count(distinct k) from unnest(p_keys) k) <> 6 then
    return jsonb_build_object('error', 'need_six_questions');
  end if;
  for i in 1..6 loop
    select * into r from quiz_presets where question_key = p_keys[i] and is_active;
    if not found then return jsonb_build_object('error', 'bad_question'); end if;
    v_ids := v_ids || r.id;
    if p_accepted is not null and array_length(p_accepted, 1) = 6 then
      if p_accepted[i] < 0 or p_accepted[i] >= jsonb_array_length(r.options) then return jsonb_build_object('error', 'bad_answer'); end if;
      v_acc := v_acc || p_accepted[i];
    else
      v_acc := v_acc || r.wise_index;
    end if;
  end loop;

  loop
    v_code := '';
    for i in 1..6 loop v_code := v_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from quizzes where code = v_code);
    tries := tries + 1; if tries > 20 then return jsonb_build_object('error', 'try_again'); end if;
  end loop;

  insert into quizzes (code, creator_name, question_ids, accepted, token_hash)
  values (v_code, v_name, v_ids, v_acc, md5(v_token || ':finlit'));
  return jsonb_build_object('code', v_code, 'token', v_token);
end $$;

-- ── load a quiz for a friend (never includes the answer key) ──
create or replace function quiz_get(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q quizzes; v_qs jsonb;
begin
  select * into q from quizzes where code = upper(trim(p_code)) and is_active;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  select jsonb_agg(jsonb_build_object('emoji', pr.emoji, 'prompt', pr.prompt,
           'options', (select jsonb_agg(jsonb_build_object('index', ord - 1, 'text', o ->> 'text') order by ord)
                         from jsonb_array_elements(pr.options) with ordinality as t(o, ord))) order by x.n)
    into v_qs
    from unnest(q.question_ids) with ordinality as x(id, n) join quiz_presets pr on pr.id = x.id;
  return jsonb_build_object('creator', q.creator_name, 'theme', q.theme, 'count', q.response_count, 'questions', v_qs);
end $$;

-- ── the leaderboard ──
create or replace function quiz_board(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q quizzes; v_rows jsonb;
begin
  select * into q from quizzes where code = upper(trim(p_code)) and is_active;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('name', t.name, 'matches', t.matches, 'character', t.character)
                            order by t.matches desc, t.created_at), '[]'::jsonb)
    into v_rows from (select name, matches, character, created_at from quiz_responses
                       where quiz_id = q.id order by matches desc, created_at limit 25) t;
  return jsonb_build_object('creator', q.creator_name, 'total', q.response_count, 'rows', v_rows);
end $$;

-- ── submit answers: returns the seat, the money character and the leaderboard ──
create or replace function quiz_submit(p_code text, p_name text, p_answers int[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  q quizzes; v_name text := quiz_clean_name(p_name); pr quiz_presets; i int; n int;
  sums jsonb := '{"prudence":0,"discipline":0,"generosity":0,"boldness":0}'::jsonb;
  maxes jsonb := '{"prudence":0,"discipline":0,"generosity":0,"boldness":0}'::jsonb;
  t text; opt jsonb; v_pts int; v_best int; v_matches int := 0; v_top text; v_low text; v_pct jsonb := '{}'::jsonb;
  v_rank int; v_new boolean := false; v_id bigint; v_hi int;
begin
  if not quiz_rate_ok('submit', 400) then return jsonb_build_object('error', 'rate_limited'); end if;
  select * into q from quizzes where code = upper(trim(p_code)) and is_active;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  if char_length(v_name) < 1 then return jsonb_build_object('error', 'bad_name'); end if;
  n := array_length(q.question_ids, 1);
  if p_answers is null or array_length(p_answers, 1) <> n then return jsonb_build_object('error', 'bad_answers'); end if;
  if q.response_count >= 500 and not exists (select 1 from quiz_responses where quiz_id = q.id and name_key = lower(v_name)) then
    return jsonb_build_object('error', 'full');
  end if;

  for i in 1..n loop
    select * into pr from quiz_presets where id = q.question_ids[i];
    if p_answers[i] < 0 or p_answers[i] >= jsonb_array_length(pr.options) then return jsonb_build_object('error', 'bad_answers'); end if;
    opt := pr.options -> p_answers[i];
    foreach t in array array['prudence', 'discipline', 'generosity', 'boldness'] loop
      v_pts := coalesce((opt -> 'traits' ->> t)::int, 0);
      sums := jsonb_set(sums, array[t], to_jsonb((sums ->> t)::int + v_pts));
      select coalesce(max(coalesce((o -> 'traits' ->> t)::int, 0)), 0) into v_best from jsonb_array_elements(pr.options) o;
      maxes := jsonb_set(maxes, array[t], to_jsonb((maxes ->> t)::int + v_best));
    end loop;
    if p_answers[i] = q.accepted[i] then v_matches := v_matches + 1; end if;
  end loop;

  -- percentage of the best possible score on each trait; strongest = character, weakest = blind spot
  foreach t in array array['prudence', 'discipline', 'generosity', 'boldness'] loop
    v_pct := v_pct || jsonb_build_object(t, case when (maxes ->> t)::int > 0 then round(100.0 * (sums ->> t)::int / (maxes ->> t)::int) else 0 end);
  end loop;
  select k into v_top from (values ('prudence'), ('discipline'), ('generosity'), ('boldness')) a(k)
    order by (v_pct ->> k)::numeric desc, (sums ->> k)::int desc, k limit 1;
  select k into v_low from (values ('prudence'), ('discipline'), ('generosity'), ('boldness')) a(k)
    where k <> v_top order by (v_pct ->> k)::numeric asc, k limit 1;

  insert into quiz_responses (quiz_id, name, name_key, answers, traits, matches, character)
  values (q.id, v_name, lower(v_name), p_answers, v_pct, v_matches, v_top)
  on conflict (quiz_id, name_key) do update
    set answers = excluded.answers, traits = excluded.traits, matches = excluded.matches,
        character = excluded.character, created_at = now()
  returning id, (xmax = 0) into v_id, v_new;
  if v_new then update quizzes set response_count = response_count + 1 where id = q.id; end if;

  select 1 + count(*) into v_rank from quiz_responses
   where quiz_id = q.id and (matches > v_matches or (matches = v_matches and created_at < (select created_at from quiz_responses where id = v_id)));

  return jsonb_build_object('matches', v_matches, 'total', n, 'character', v_top, 'blind_spot', v_low,
                            'traits', v_pct, 'rank', v_rank, 'creator', q.creator_name,
                            'board', quiz_board(q.code) -> 'rows', 'players', (select response_count from quizzes where id = q.id));
end $$;

-- ── the creator can close their quiz with the private token ──
create or replace function quiz_close(p_code text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update quizzes set is_active = false
   where code = upper(trim(p_code)) and token_hash = md5(coalesce(p_token, '') || ':finlit');
  return jsonb_build_object('ok', found);
end $$;

do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'quiz\_%'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
    if r.proname in ('quiz_presets', 'quiz_create', 'quiz_get', 'quiz_board', 'quiz_submit', 'quiz_close') then
      execute format('grant execute on function %s to anon, authenticated', r.sig);
    end if;
  end loop;
end $$;

-- ── the questions ──
insert into quiz_presets (id, question_key, emoji, prompt, options, wise_index) values
(1, $k$windfall$k$, $k$💸$k$, $t$A surprise K2,000 lands in your mobile money. First move?$t$, $j$[{"text": "Pay what I owe, save the rest", "traits": {"discipline": 2, "prudence": 1}}, {"text": "Treat the squad tonight", "traits": {"generosity": 2}}, {"text": "Flip it into stock for my side hustle", "traits": {"boldness": 2}}, {"text": "Leave it until I'm sure what to do", "traits": {"prudence": 2}}]$j$::jsonb, 0),
(2, $k$scam_chat$k$, $k$📱$k$, $t$WhatsApp: "Double your money in 48 hours, guaranteed!"$t$, $j$[{"text": "Send K500 to test it", "traits": {"boldness": 2}}, {"text": "Ask for their company registration first", "traits": {"prudence": 3}}, {"text": "Forward it so all my friends win", "traits": {"generosity": 1, "boldness": 1}}, {"text": "Ignore and delete", "traits": {"prudence": 2}}]$j$::jsonb, 1),
(3, $k$flash_sale$k$, $k$🏷️$k$, $t$"TODAY ONLY!" Sound system at half price. You...$t$, $j$[{"text": "Buy it. Deals don't wait", "traits": {"boldness": 2}}, {"text": "Sleep on it and compare prices", "traits": {"prudence": 2, "discipline": 1}}, {"text": "Buy two and resell one", "traits": {"boldness": 2}}, {"text": "Ask a friend what they think", "traits": {"generosity": 1, "prudence": 1}}]$j$::jsonb, 1),
(4, $k$friend_loan$k$, $k$🤝$k$, $t$A friend asks to borrow K500 "till Friday".$t$, $j$[{"text": "Lend it, no questions", "traits": {"generosity": 3}}, {"text": "Lend half and say it's all I can", "traits": {"generosity": 2, "prudence": 1}}, {"text": "Say no, kindly", "traits": {"discipline": 2, "prudence": 1}}, {"text": "Lend it, agree a date and write it down", "traits": {"generosity": 1, "discipline": 1, "prudence": 1}}]$j$::jsonb, 3),
(5, $k$payday$k$, $k$💼$k$, $t$Payday! What happens first?$t$, $j$[{"text": "I save some before anything else", "traits": {"discipline": 3}}, {"text": "Pay the bills, spend what's left", "traits": {"discipline": 1, "prudence": 1}}, {"text": "Celebrate. It was a long month", "traits": {"boldness": 1, "generosity": 1}}, {"text": "Send money home to family", "traits": {"generosity": 3}}]$j$::jsonb, 0),
(6, $k$phone_dies$k$, $k$🔌$k$, $t$Your phone dies and you need K1,500 today.$t$, $j$[{"text": "Dip into my emergency stash", "traits": {"discipline": 3}}, {"text": "Quick-loan app, done in minutes", "traits": {"boldness": 2}}, {"text": "Ask family to help", "traits": {"generosity": 1, "prudence": 1}}, {"text": "Repair the old one cheaply", "traits": {"prudence": 2}}]$j$::jsonb, 0),
(7, $k$side_hustle$k$, $k$🛒$k$, $t$You have K3,000 to start a side hustle.$t$, $j$[{"text": "Go all in with K3,000", "traits": {"boldness": 3}}, {"text": "Start with K500 and test demand", "traits": {"prudence": 2, "boldness": 1}}, {"text": "Wait until I have more saved", "traits": {"prudence": 2}}, {"text": "Team up with a friend", "traits": {"generosity": 1, "boldness": 1}}]$j$::jsonb, 1),
(8, $k$night_out$k$, $k$🎉$k$, $t$Friends plan a big night out. It's month end.$t$, $j$[{"text": "I'm in. YOLO!", "traits": {"boldness": 2}}, {"text": "I'll come, with a fixed budget", "traits": {"discipline": 3}}, {"text": "I'll skip this one", "traits": {"prudence": 2, "discipline": 1}}, {"text": "I'll pay for everyone", "traits": {"generosity": 3}}]$j$::jsonb, 1),
(9, $k$loan_app$k$, $k$⚡$k$, $t$A loan app approves you in 2 minutes.$t$, $j$[{"text": "Take it, speed matters", "traits": {"boldness": 2}}, {"text": "Check the real interest first", "traits": {"prudence": 3}}, {"text": "Ask a friend instead", "traits": {"generosity": 1}}, {"text": "Borrow, then repay early", "traits": {"discipline": 2}}]$j$::jsonb, 1),
(10, $k$chilimba$k$, $k$👯$k$, $t$A chilimba (savings group) invites you to join.$t$, $j$[{"text": "Join. The group keeps me honest", "traits": {"discipline": 2, "generosity": 1}}, {"text": "Join, if I get an early turn", "traits": {"boldness": 2}}, {"text": "Skip. I'll save alone", "traits": {"discipline": 1, "prudence": 1}}, {"text": "Join and bring friends too", "traits": {"generosity": 2, "boldness": 1}}]$j$::jsonb, 0),
(11, $k$spare_k1000$k$, $k$💰$k$, $t$You have K1,000 spare for a year. Where does it go?$t$, $j$[{"text": "A savings account, safe and steady", "traits": {"prudence": 2, "discipline": 1}}, {"text": "A bold bet that could 3x", "traits": {"boldness": 3}}, {"text": "T-bills or a money market fund", "traits": {"prudence": 1, "discipline": 2}}, {"text": "A friend's new business", "traits": {"generosity": 2, "boldness": 1}}]$j$::jsonb, 2),
(12, $k$bill_short$k$, $k$🧾$k$, $t$A bill is due and you're K300 short.$t$, $j$[{"text": "Call them and ask for a payment plan", "traits": {"prudence": 2, "discipline": 1}}, {"text": "Ignore it and hope", "traits": {"boldness": 1}}, {"text": "Borrow from a quick-loan app", "traits": {"boldness": 2}}, {"text": "Pay part now, the rest soon", "traits": {"discipline": 2}}]$j$::jsonb, 0),
(13, $k$coin_tip$k$, $k$🪙$k$, $t$A friend swears a coin will "moon" tomorrow.$t$, $j$[{"text": "Buy now before it pumps", "traits": {"boldness": 3}}, {"text": "Read about it first", "traits": {"prudence": 3}}, {"text": "Put in a little, just for fun", "traits": {"boldness": 1, "prudence": 1}}, {"text": "Tell everyone I know", "traits": {"generosity": 1, "boldness": 1}}]$j$::jsonb, 1),
(14, $k$cash_gig$k$, $k$💵$k$, $t$You're paid cash for a gig.$t$, $j$[{"text": "Record it and set some aside", "traits": {"discipline": 3}}, {"text": "Spend it by evening", "traits": {"boldness": 1, "generosity": 1}}, {"text": "Hide it somewhere safe at home", "traits": {"prudence": 2}}, {"text": "Share it with the team", "traits": {"generosity": 2}}]$j$::jsonb, 0),
(15, $k$budget$k$, $k$📒$k$, $t$Your monthly budget is...$t$, $j$[{"text": "Written down, exact", "traits": {"discipline": 3}}, {"text": "In my head, roughly", "traits": {"prudence": 1, "discipline": 1}}, {"text": "What budget?", "traits": {"boldness": 2}}, {"text": "The family decides together", "traits": {"generosity": 2}}]$j$::jsonb, 0),
(16, $k$shop_cover$k$, $k$🏪$k$, $t$Insurance for your shop costs K300 a month.$t$, $j$[{"text": "Worth it. It protects my stock", "traits": {"prudence": 3}}, {"text": "Maybe once I'm bigger", "traits": {"boldness": 1, "prudence": 1}}, {"text": "Never needed it so far", "traits": {"boldness": 2}}, {"text": "Ask other owners first", "traits": {"generosity": 1, "prudence": 1}}]$j$::jsonb, 0)
on conflict (id) do update set question_key = excluded.question_key, emoji = excluded.emoji, prompt = excluded.prompt,
  options = excluded.options, wise_index = excluded.wise_index, is_active = true;
