-- FinLit Zambia — Financial Character Simulator
-- 02-story-engine.sql  (safe to re-run)
--
-- The whole story engine lives inside Postgres as RPC functions, so there
-- is NO Edge Function to deploy and NO cron job to run. The browser calls:
--   story_bootstrap()          create the 3 unlock rows
--   story_fire_lesson(id)      a lesson was completed on the lesson site
--   story_pending()            unlock check + daily dice roll + due events
--   story_choose(id, index)    the learner picked a choice
--   story_borrow(kind, amt)    borrow, with per-lender ceilings
--   story_borrow_limits()      remaining ceiling per lender
-- Run 01 (adjust-balance-functions.sql) BEFORE this file.

-- ─────────────────────────────────────────────
-- TIME COMPRESSION: 1 game-year = 14 real days (change here, nowhere else)
-- ─────────────────────────────────────────────
create table if not exists sim_config (
  key text primary key,
  value text not null
);
insert into sim_config (key, value) values ('real_days_per_game_year', '14')
  on conflict (key) do nothing;

-- Story loans carry a tag so a later event can find and settle them.
alter table debts add column if not exists story_tag text;

-- The character is a YUNGSTA the learner guides. display_name = the learner (mentor);
-- character_name = the person they are guiding.
alter table profiles add column if not exists character_name text;
alter table profiles add column if not exists relationship text;

-- Venture state that learners' decisions can change
alter table ventures add column if not exists capital numeric(14,2);           -- money working in the business now
alter table ventures add column if not exists retained numeric(14,2) not null default 0;  -- profit sitting in the business
update ventures set capital = starting_capital where capital is null;
alter table ventures add column if not exists insured_until timestamptz;       -- cover bought via sim_buy_cover()
alter table ventures add column if not exists shock_guard_until timestamptz;   -- e.g. after fitting a lock
alter table ventures add column if not exists income_mult numeric(4,2) not null default 1;
alter table ventures add column if not exists income_mult_until timestamptz;   -- income x income_mult until this time

-- ─────────────────────────────────────────────
-- DEFINITIONS (public read, written only by you via SQL)
-- ─────────────────────────────────────────────
create table if not exists story_events (
  id bigint generated always as identity primary key,
  event_key text not null unique,
  category text not null,            -- unlock | ambient | lesson_bridge | consequence
  trigger_type text not null,        -- action | day_fallback | threshold | flag | dice_roll
                                     -- | external_signal | flag_delay
  trigger_config jsonb not null default '{}',
  eligibility_config jsonb not null default '{}',
  unlocks_feature text,              -- for category 'unlock': ventures | trade | debts
  character_key text,
  title text,
  intro text,
  entry_node text not null default 'start',
  repeatable boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- One row per decision screen. A choice is a jsonb object:
--   label, narrative, cash_delta, reputation_delta, sets_flag,
--   next_node (go to another screen), requires_flag (only shown if set),
--   loan {lender_kind, principal, total, rate, tag},
--   repay_tag (settle that loan in full), fee_tag + fee (add a late fee)
create table if not exists story_nodes (
  id bigint generated always as identity primary key,
  event_id bigint not null references story_events(id) on delete cascade,
  node_key text not null,
  body text,
  choices jsonb not null default '[]',
  unique (event_id, node_key)
);

-- Lesson (module key on the lesson site, e.g. '1-2') -> flag + small rep nudge
create table if not exists lesson_flag_map (
  lesson_id text primary key,
  flag_key text not null,
  reputation_delta numeric(6,2) not null default 1
);

-- Per-lender borrowing ceilings. The highest rule whose conditions are met wins.
create table if not exists lender_limit_rules (
  id bigint generated always as identity primary key,
  lender_kind text not null,         -- bank | microfinance | informal
  ceiling numeric(14,2) not null,
  requires_flag text,
  excludes_flag text,
  min_days_since_signup int not null default 0,
  note text
);

-- ─────────────────────────────────────────────
-- LEARNER STATE (learners can read their own rows; all writes go via functions)
-- ─────────────────────────────────────────────
create table if not exists learner_feature_unlocks (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  feature_key text not null,
  unlocked_at timestamptz,
  unlocked_via_event_id bigint references story_events(id),
  unique (profile_id, feature_key)
);

create table if not exists learner_flags (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  flag_key text not null,
  set_by_event_id bigint references story_events(id),
  created_at timestamptz not null default now()
);
create index if not exists learner_flags_lookup on learner_flags (profile_id, flag_key);

-- A scheduled/active scenario. available_at in the future = a delayed consequence.
create table if not exists learner_pending_events (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  event_id bigint not null references story_events(id),
  node_key text not null,
  status text not null default 'pending',   -- pending | done
  available_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
alter table learner_pending_events add column if not exists context jsonb;   -- e.g. which venture a shock belongs to
create index if not exists learner_pending_lookup on learner_pending_events (profile_id, status, available_at);

create table if not exists learner_event_log (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  event_id bigint references story_events(id),
  node_key text,
  choice_index int,
  cash_delta numeric(14,2),
  reputation_delta numeric(6,2),
  flag_set text,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists learner_daily_check (
  profile_id uuid not null references profiles(id) on delete cascade,
  check_date date not null,
  rolled boolean not null default false,
  fired_event_id bigint references story_events(id),
  primary key (profile_id, check_date)
);

-- ─────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────────
alter table sim_config enable row level security;
alter table story_events enable row level security;
alter table story_nodes enable row level security;
alter table lesson_flag_map enable row level security;
alter table lender_limit_rules enable row level security;
alter table learner_feature_unlocks enable row level security;
alter table learner_flags enable row level security;
alter table learner_pending_events enable row level security;
alter table learner_event_log enable row level security;
alter table learner_daily_check enable row level security;

drop policy if exists "read sim_config" on sim_config;
create policy "read sim_config" on sim_config for select using (true);
drop policy if exists "read story_events" on story_events;
create policy "read story_events" on story_events for select using (true);
drop policy if exists "read story_nodes" on story_nodes;
create policy "read story_nodes" on story_nodes for select using (true);
drop policy if exists "read lesson_flag_map" on lesson_flag_map;
create policy "read lesson_flag_map" on lesson_flag_map for select using (true);
drop policy if exists "read lender_limit_rules" on lender_limit_rules;
create policy "read lender_limit_rules" on lender_limit_rules for select using (true);

drop policy if exists "own unlocks (read)" on learner_feature_unlocks;
create policy "own unlocks (read)" on learner_feature_unlocks for select using (auth.uid() = profile_id);
drop policy if exists "own flags (read)" on learner_flags;
create policy "own flags (read)" on learner_flags for select using (auth.uid() = profile_id);
drop policy if exists "own pending (read)" on learner_pending_events;
create policy "own pending (read)" on learner_pending_events for select using (auth.uid() = profile_id);
drop policy if exists "own event log (read)" on learner_event_log;
create policy "own event log (read)" on learner_event_log for select using (auth.uid() = profile_id);
drop policy if exists "own daily check (read)" on learner_daily_check;
create policy "own daily check (read)" on learner_daily_check for select using (auth.uid() = profile_id);

-- ─────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────
create or replace function story_game_months_to_days(m numeric)
returns numeric language sql stable as $$
  select m / 12.0 * coalesce((select value::numeric from sim_config where key = 'real_days_per_game_year'), 14)
$$;

create or replace function story_has_flag(p uuid, f text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from learner_flags where profile_id = p and flag_key = f)
$$;

create or replace function story_venture_insured(p uuid, ctx jsonb)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select insured_until > now() from ventures
                   where id = (ctx->>'venture_id')::bigint and profile_id = p), false)
$$;

create or replace function story_fill(p uuid, t text, ctx jsonb default null)
returns text language sql stable security definer set search_path = public as $$
  select replace(replace(replace(replace(coalesce(t, ''),
           '{name}',     coalesce((select nullif(character_name, '') from profiles where id = p), 'your yungsta')),
           '{mentor}',   coalesce((select nullif(display_name, '') from profiles where id = p), 'you')),
           '{venture}',  coalesce(ctx->>'venture_name', 'the business')),
           '{retained}', coalesce(ctx->>'retained_text', 'some profit'))
$$;

-- j may be a single flag name or an array of names (OR-matched)
create or replace function story_flag_any(p uuid, j jsonb)
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  if j is null or jsonb_typeof(j) = 'null' then return false; end if;
  if jsonb_typeof(j) = 'string' then return story_has_flag(p, j #>> '{}'); end if;
  return exists (select 1 from jsonb_array_elements_text(j) f where story_has_flag(p, f));
end $$;

create or replace function story_set_flag(p uuid, f text, ev bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if f is null or f = '' then return; end if;
  insert into learner_flags (profile_id, flag_key, set_by_event_id) values (p, f, ev);
end $$;

create or replace function story_feature_open(p uuid, f text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select unlocked_at is not null from learner_feature_unlocks
                   where profile_id = p and feature_key = f), false)
$$;

create or replace function story_days_since_signup(p uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(extract(epoch from (now() - created_at)) / 86400.0, 0) from profiles where id = p
$$;

create or replace function story_eligible(p uuid, e story_events)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare c jsonb := e.eligibility_config;
begin
  if c ? 'requires_feature_unlocked' and not story_feature_open(p, c->>'requires_feature_unlocked') then return false; end if;
  if c ? 'requires_flag' and not story_flag_any(p, c->'requires_flag') then return false; end if;
  if c ? 'excludes_flag' and story_flag_any(p, c->'excludes_flag') then return false; end if;
  if c ? 'min_days_since_signup' and story_days_since_signup(p) < (c->>'min_days_since_signup')::numeric then return false; end if;
  if c ? 'requires_active_venture' and not exists (select 1 from ventures where profile_id = p and status = 'active') then return false; end if;
  return true;
end $$;

create or replace function story_trigger_met(p uuid, e story_events)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare c jsonb := e.trigger_config; v numeric;
begin
  if e.trigger_type = 'day_fallback' then
    return story_days_since_signup(p) >= (c->>'min_days_since_signup')::numeric;
  elsif e.trigger_type = 'threshold' then
    select case c->>'field'
             when 'cash_balance' then cash_balance
             when 'reputation_score' then reputation_score
           end into v from profiles where id = p;
    if v is null then return false; end if;
    return case c->>'op'
      when '<'  then v <  (c->>'value')::numeric
      when '<=' then v <= (c->>'value')::numeric
      when '>'  then v >  (c->>'value')::numeric
      when '>=' then v >= (c->>'value')::numeric
      else false end;
  elsif e.trigger_type = 'action' then
    if c->>'action' = 'venture_first_activity' then
      return exists (select 1 from ventures where profile_id = p);
    end if;
    return false;
  elsif e.trigger_type = 'flag' then
    return story_flag_any(p, c->'flag');
  end if;
  return false;
end $$;

drop function if exists story_visible_choices(uuid, jsonb);
create or replace function story_visible_choices(p uuid, choices jsonb, ctx jsonb default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('index', t.ord - 1, 'label', story_fill(p, t.c->>'label', ctx)) order by t.ord), '[]'::jsonb)
  from jsonb_array_elements(choices) with ordinality as t(c, ord)
  where ((t.c->'requires_flag') is null or story_flag_any(p, t.c->'requires_flag'))
    and ((t.c->'requires_insured') is null or story_venture_insured(p, ctx))
$$;

-- ─────────────────────────────────────────────
-- UNLOCK CHAIN (lesson-driven rows and day/threshold fallbacks compete;
-- whichever is met first wins — lessons are the faster, preferred route)
-- ─────────────────────────────────────────────
create or replace function story_run_unlocks(p uuid)
returns text[] language plpgsql security definer set search_path = public as $$
declare e story_events; got text[] := '{}';
begin
  for e in select * from story_events
           where category = 'unlock' and is_active and unlocks_feature is not null order by id loop
    if story_feature_open(p, e.unlocks_feature) then continue; end if;
    if story_eligible(p, e) and story_trigger_met(p, e) then
      update learner_feature_unlocks
         set unlocked_at = now(), unlocked_via_event_id = e.id
       where profile_id = p and feature_key = e.unlocks_feature and unlocked_at is null;
      if found then
        got := got || e.unlocks_feature;
        perform story_set_flag(p, 'unlocked_' || e.unlocks_feature, e.id);
        insert into learner_event_log (profile_id, event_id, note)
          values (p, e.id, 'unlocked ' || e.unlocks_feature);
      end if;
    end if;
  end loop;
  return got;
end $$;

-- After flags are set, schedule any consequence events waiting on them.
drop function if exists story_schedule_followups(uuid, text[]);
create or replace function story_schedule_followups(p uuid, new_flags text[], ctx jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare e story_events; af jsonb; v_days numeric;
begin
  if new_flags is null or array_length(new_flags, 1) is null then return; end if;
  for e in select * from story_events
           where trigger_type = 'flag_delay' and is_active order by id loop
    af := e.trigger_config->'after_flag';
    if af is null then continue; end if;
    if jsonb_typeof(af) = 'string' then af := jsonb_build_array(af); end if;
    if not exists (select 1 from jsonb_array_elements_text(af) f where f = any (new_flags)) then continue; end if;
    if not e.repeatable and exists (select 1 from learner_pending_events where profile_id = p and event_id = e.id) then continue; end if;
    if not story_eligible(p, e) then continue; end if;
    v_days := coalesce(
      (e.trigger_config->>'delay_real_days')::numeric,
      story_game_months_to_days((e.trigger_config->>'delay_game_months')::numeric),
      0);
    insert into learner_pending_events (profile_id, event_id, node_key, available_at, context)
      values (p, e.id, e.entry_node, now() + (v_days * interval '1 day'), ctx);
  end loop;
end $$;

-- Once per real day, maybe start an ambient life event.
create or replace function story_daily_roll(p uuid)
returns void language plpgsql security definer set search_path = public as $$
declare e story_events;
begin
  insert into learner_daily_check (profile_id, check_date, rolled)
    values (p, current_date, true) on conflict do nothing;
  if not found then return; end if;
  if exists (select 1 from learner_pending_events where profile_id = p and status = 'pending') then return; end if;
  select se.* into e from story_events se
   where se.category = 'ambient' and se.is_active and se.trigger_type = 'dice_roll'
     and (se.repeatable or not exists (select 1 from learner_pending_events lp where lp.profile_id = p and lp.event_id = se.id))
     and story_eligible(p, se)
   order by random() limit 1;
  if e.id is null then return; end if;
  if random() < coalesce((e.trigger_config->>'fire_probability')::numeric, 0.3) then
    insert into learner_pending_events (profile_id, event_id, node_key) values (p, e.id, e.entry_node);
    update learner_daily_check set fired_event_id = e.id where profile_id = p and check_date = current_date;
  end if;
end $$;

-- ─────────────────────────────────────────────
-- PUBLIC FUNCTIONS (called from the browser)
-- ─────────────────────────────────────────────
create or replace function story_feature_state()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  return jsonb_build_object(
    'ventures', story_feature_open(uid, 'ventures'),
    'trade',    story_feature_open(uid, 'trade'),
    'debts',    story_feature_open(uid, 'debts'));
end $$;

create or replace function story_bootstrap()
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null or not exists (select 1 from profiles where id = uid) then return; end if;
  insert into learner_feature_unlocks (profile_id, feature_key, unlocked_at) values
    (uid, 'ventures', now()), (uid, 'trade', null), (uid, 'debts', null)
  on conflict (profile_id, feature_key) do nothing;
end $$;

create or replace function story_fire_lesson(p_lesson text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  m lesson_flag_map; e story_events;
  v_new int := 0; v_flags text[] := '{}';
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  perform story_bootstrap();
  insert into learner_lessons (profile_id, lesson_id) values (uid, p_lesson) on conflict do nothing;
  perform yungsta_mark_guided(uid);

  select * into m from lesson_flag_map where lesson_id = p_lesson;
  if found and not story_has_flag(uid, m.flag_key) then
    perform story_set_flag(uid, m.flag_key, null);
    perform adjust_reputation_score(uid, m.reputation_delta, 'lesson_completed:' || p_lesson);
    v_flags := array[m.flag_key];
  end if;

  for e in select * from story_events
           where category = 'lesson_bridge' and is_active and trigger_type = 'external_signal'
             and trigger_config->>'lesson_id' = p_lesson order by id loop
    if (e.repeatable or not exists (select 1 from learner_pending_events where profile_id = uid and event_id = e.id))
       and story_eligible(uid, e) then
      insert into learner_pending_events (profile_id, event_id, node_key) values (uid, e.id, e.entry_node);
      v_new := v_new + 1;
    end if;
  end loop;

  perform story_schedule_followups(uid, v_flags);
  perform story_run_unlocks(uid);
  return jsonb_build_object('ok', true, 'scenarios', v_new);
end $$;

create or replace function story_pending()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_events jsonb; v_unlocked text[]; v_name text; v_q jsonb := null;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  perform story_bootstrap();
  select display_name into v_name from profiles where id = uid;
  v_name := coalesce(v_name, 'Learner');
  perform yungsta_neglect_check(uid);   -- charge any days the learner missed
  v_unlocked := story_run_unlocks(uid);
  perform story_daily_roll(uid);
  v_unlocked := v_unlocked || story_run_unlocks(uid);

  select coalesce(jsonb_agg(s.item order by s.created_at), '[]'::jsonb) into v_events
  from (
    select pe.created_at,
      jsonb_build_object(
        'pending_id', pe.id,
        'event_key', e.event_key,
        'title', story_fill(uid, e.title, pe.context),
        'character', e.character_key,
        'intro', case when pe.node_key = e.entry_node then story_fill(uid, e.intro, pe.context) else null end,
        'node_key', n.node_key,
        'body', story_fill(uid, n.body, pe.context),
        'choices', story_visible_choices(uid, n.choices, pe.context)) as item
    from learner_pending_events pe
    join story_events e on e.id = pe.event_id
    join story_nodes n on n.event_id = e.id and n.node_key = pe.node_key
    where pe.profile_id = uid and pe.status = 'pending' and pe.available_at <= now()
  ) s;

  -- no life event waiting? then the yungsta may have a question about a lesson
  if jsonb_array_length(v_events) = 0 then
    perform yungsta_schedule(uid);
    v_q := yungsta_current(uid);
  end if;

  return jsonb_build_object('features', story_feature_state(), 'unlocked', to_jsonb(v_unlocked), 'events', v_events,
                            'question', v_q, 'avatar', (select avatar from profiles where id = uid),
                            'blunders', yungsta_blunders_new(uid), 'neglect', yungsta_status(uid),
                            'yungsta', story_fill(uid, '{name}'), 'mentor', story_fill(uid, '{mentor}'));
end $$;

create or replace function story_choose(p_pending_id bigint, p_choice_index int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  pe learner_pending_events; ev story_events; nd story_nodes; ch jsonb;
  v_cash numeric; v_amt numeric; v_debt debts; v_debt_id bigint;
  v_flags text[] := '{}'; v_cd numeric := 0; v_rd numeric := 0;
  v_unlocked text[] := '{}'; v_flag text; v_name text; v_capital numeric;
  v_biz numeric := 0; v_ret numeric := 0; v_cashpart numeric := 0; v_w numeric := 0; v_r numeric := 0;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;

  select * into pe from learner_pending_events
   where id = p_pending_id and profile_id = uid and status = 'pending' and available_at <= now()
   for update;
  if not found then return jsonb_build_object('error', 'not_found'); end if;

  select * into ev from story_events where id = pe.event_id;
  select * into nd from story_nodes where event_id = ev.id and node_key = pe.node_key;
  ch := nd.choices -> p_choice_index;
  if ch is null then return jsonb_build_object('error', 'bad_choice'); end if;
  if ch ? 'requires_flag' and not story_flag_any(uid, ch->'requires_flag') then
    return jsonb_build_object('error', 'locked_choice');
  end if;
  if ch ? 'requires_insured' and not story_venture_insured(uid, pe.context) then
    return jsonb_build_object('error', 'locked_choice');
  end if;

  select cash_balance, display_name into v_cash, v_name from profiles where id = uid;
  v_name := coalesce(v_name, 'Learner');

  -- A choice can't push cash below zero. A "forced" loss (fraud, a fee) takes
  -- whatever you have instead of blocking the story.
  v_amt := coalesce((ch->>'cash_delta')::numeric, 0);
  if ch ? 'cash_pct_capital' and pe.context ? 'capital' then
    v_capital := (pe.context->>'capital')::numeric;
    v_amt := round(v_capital * (ch->>'cash_pct_capital')::numeric, 2);
  end if;
  -- Money in a venture decision moves through the BUSINESS first: income goes into the
  -- business's retained profit, and losses are paid from it before touching personal cash.
  if pe.context ? 'venture_id' and v_amt <> 0 then
    select retained into v_ret from ventures
     where id = (pe.context->>'venture_id')::bigint and profile_id = uid for update;
    v_ret := coalesce(v_ret, 0);
    if v_amt > 0 then v_biz := v_amt; else v_biz := -least(-v_amt, v_ret); end if;
  end if;
  v_cashpart := v_amt - v_biz;
  if v_cashpart < 0 and ch ? 'forced' then v_cashpart := greatest(v_cashpart, -v_cash); end if;
  if v_cashpart < 0 and v_cash + v_cashpart < 0 then
    return jsonb_build_object('error', 'insufficient_cash', 'needed', -v_cashpart, 'cash', v_cash);
  end if;

  -- Settling a story loan needs the cash up front: fail before changing anything.
  if ch ? 'repay_tag' then
    select * into v_debt from debts
     where profile_id = uid and story_tag = ch->>'repay_tag' and status = 'active'
     order by id desc limit 1;
    if v_debt.id is not null and v_cash < v_debt.outstanding_balance then
      return jsonb_build_object('error', 'insufficient_cash',
                                'needed', v_debt.outstanding_balance, 'cash', v_cash);
    end if;
  end if;

  if ch ? 'repay_tag' and v_debt.id is not null then
    perform adjust_cash_balance(uid, -v_debt.outstanding_balance, 'debt_repayment', 'debts', v_debt.id);
    v_cd := v_cd - v_debt.outstanding_balance;
    update debts set outstanding_balance = 0, status = 'repaid' where id = v_debt.id;
  end if;

  if ch ? 'fee_tag' then
    update debts set outstanding_balance = outstanding_balance + coalesce((ch->>'fee')::numeric, 0)
     where profile_id = uid and story_tag = ch->>'fee_tag' and status = 'active';
  end if;

  if ch ? 'loan' then
    insert into debts (profile_id, lender_kind, principal, outstanding_balance, annual_interest_rate, story_tag)
    values (uid, ch #>> '{loan,lender_kind}', (ch #>> '{loan,principal}')::numeric,
            (ch #>> '{loan,total}')::numeric, (ch #>> '{loan,rate}')::numeric, ch #>> '{loan,tag}')
    returning id into v_debt_id;
    perform adjust_cash_balance(uid, (ch #>> '{loan,principal}')::numeric, 'debt_drawdown', 'debts', v_debt_id);
    v_cd := v_cd + (ch #>> '{loan,principal}')::numeric;
  end if;

  if v_cashpart <> 0 then
    perform adjust_cash_balance(uid, v_cashpart, 'story_event', 'story_events', ev.id);
    v_cd := v_cd + v_cashpart;
  end if;

  -- Venture side-effects: books, retained profit, slower/faster sales, protection, payouts
  if pe.context ? 'venture_id' then
    if v_amt <> 0 then
      insert into venture_events (venture_id, kind, amount, description)
      values ((pe.context->>'venture_id')::bigint, case when v_amt < 0 then 'shock' else 'revenue' end, v_amt,
              left(coalesce(ch->>'venture_note', ch->>'label'), 200));
    end if;
    if v_biz <> 0 then
      update ventures set retained = retained + v_biz
       where id = (pe.context->>'venture_id')::bigint and profile_id = uid;
    end if;
    if ch ? 'venture_mult' then
      update ventures set income_mult = (ch #>> '{venture_mult,mult}')::numeric,
             income_mult_until = now() + ((ch #>> '{venture_mult,days}')::numeric * interval '1 day')
       where id = (pe.context->>'venture_id')::bigint and profile_id = uid;
    end if;
    if ch ? 'venture_guard_days' then
      update ventures set shock_guard_until = now() + ((ch->>'venture_guard_days')::numeric * interval '1 day')
       where id = (pe.context->>'venture_id')::bigint and profile_id = uid;
    end if;
    -- Profit decision: take some home, plough some back in, leave the rest as a buffer
    if ch ? 'retained_withdraw_pct' or ch ? 'retained_reinvest_pct' then
      select retained into v_ret from ventures
       where id = (pe.context->>'venture_id')::bigint and profile_id = uid for update;
      v_w := round(coalesce(v_ret, 0) * coalesce((ch->>'retained_withdraw_pct')::numeric, 0), 2);
      v_r := round(coalesce(v_ret, 0) * coalesce((ch->>'retained_reinvest_pct')::numeric, 0), 2);
      update ventures set retained = retained - v_w - v_r,
                          capital = coalesce(capital, starting_capital) + v_r
       where id = (pe.context->>'venture_id')::bigint and profile_id = uid;
      if v_w > 0 then
        perform adjust_cash_balance(uid, v_w, 'venture_withdrawal', 'ventures', (pe.context->>'venture_id')::bigint);
        v_cd := v_cd + v_w;
        insert into venture_events (venture_id, kind, amount, description)
          values ((pe.context->>'venture_id')::bigint, 'withdrawal', -v_w, 'Profit taken home');
      end if;
      if v_r > 0 then
        insert into venture_events (venture_id, kind, amount, description)
          values ((pe.context->>'venture_id')::bigint, 'reinvest', -v_r, 'Profit reinvested in the business');
      end if;
    end if;
  end if;

  v_rd := coalesce((ch->>'reputation_delta')::numeric, 0);
  if v_rd <> 0 then
    perform adjust_reputation_score(uid, v_rd, 'story: ' || ev.event_key);
  end if;

  v_flag := ch->>'sets_flag';
  if v_flag is not null and v_flag <> '' then
    perform story_set_flag(uid, v_flag, ev.id);
    v_flags := array[v_flag];
  end if;

  insert into learner_event_log (profile_id, event_id, node_key, choice_index, cash_delta, reputation_delta, flag_set)
  values (uid, ev.id, nd.node_key, p_choice_index, v_cd, v_rd, v_flag);

  select cash_balance into v_cash from profiles where id = uid;

  if ch ? 'next_node' then
    update learner_pending_events set node_key = ch->>'next_node' where id = pe.id;
    select * into nd from story_nodes where event_id = ev.id and node_key = ch->>'next_node';
    return jsonb_build_object('done', false, 'narrative', story_fill(uid, ch->>'narrative', pe.context), 'cash', v_cash,
      'node', jsonb_build_object('node_key', nd.node_key, 'body', story_fill(uid, nd.body, pe.context),
                                 'choices', story_visible_choices(uid, nd.choices, pe.context)));
  end if;

  update learner_pending_events set status = 'done', resolved_at = now() where id = pe.id;
  perform yungsta_mark_guided(uid);
  perform story_schedule_followups(uid, v_flags, pe.context);
  v_unlocked := story_run_unlocks(uid);
  return jsonb_build_object('done', true, 'narrative', story_fill(uid, ch->>'narrative', pe.context), 'cash', v_cash,
                            'cash_delta', v_cd, 'business_delta', v_biz, 'reputation_delta', v_rd, 'unlocked', to_jsonb(v_unlocked));
end $$;

-- ─────────────────────────────────────────────
-- BORROWING CEILINGS (feature-level unlock is handled above; this is the
-- lender-level layer underneath it)
-- ─────────────────────────────────────────────
create or replace function story_lender_ceiling(p uuid, p_kind text)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(max(r.ceiling), 0) from lender_limit_rules r
   where r.lender_kind = p_kind
     and (r.requires_flag is null or story_has_flag(p, r.requires_flag))
     and (r.excludes_flag is null or not story_has_flag(p, r.excludes_flag))
     and story_days_since_signup(p) >= r.min_days_since_signup
$$;

create or replace function story_borrow_limits()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); k text; v_out jsonb := '{}'::jsonb; used numeric;
begin
  foreach k in array array['bank', 'microfinance', 'informal'] loop
    select coalesce(sum(outstanding_balance), 0) into used
      from debts where profile_id = uid and lender_kind = k and status = 'active';
    v_out := v_out || jsonb_build_object(k, greatest(0, story_lender_ceiling(uid, k) - used));
  end loop;
  return v_out;
end $$;

create or replace function story_borrow(p_kind text, p_amount numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); v_left numeric; v_rate numeric; v_id bigint; v_used numeric;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  if p_amount is null or p_amount <= 0 then return jsonb_build_object('error', 'bad_amount'); end if;
  v_rate := case p_kind when 'bank' then 28 when 'microfinance' then 180 when 'informal' then 0 else null end;
  if v_rate is null then return jsonb_build_object('error', 'bad_lender'); end if;
  if not story_feature_open(uid, 'debts') then return jsonb_build_object('error', 'locked'); end if;

  select coalesce(sum(outstanding_balance), 0) into v_used
    from debts where profile_id = uid and lender_kind = p_kind and status = 'active';
  v_left := greatest(0, story_lender_ceiling(uid, p_kind) - v_used);
  if p_amount > v_left then
    return jsonb_build_object('error', 'over_limit', 'limit', v_left);
  end if;

  insert into debts (profile_id, lender_kind, principal, outstanding_balance, annual_interest_rate)
  values (uid, p_kind, p_amount, p_amount, v_rate) returning id into v_id;
  perform adjust_cash_balance(uid, p_amount, 'debt_drawdown', 'debts', v_id);
  return jsonb_build_object('ok', true, 'debt_id', v_id);
end $$;

-- ─────────────────────────────────────────────
-- PERMISSIONS: only the 7 browser-facing functions are callable by learners.
-- Everything else is internal and only reachable from inside those.
-- ─────────────────────────────────────────────
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'story\_%'
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    if r.proname in ('story_bootstrap', 'story_fire_lesson', 'story_pending', 'story_choose',
                     'story_borrow', 'story_borrow_limits', 'story_feature_state') then
      execute format('grant execute on function %s to authenticated', r.sig);
    end if;
  end loop;
end $$;
