-- FinLit Zambia — Financial Character Simulator
-- 12-stress.sql  (safe to re-run)  Run AFTER 11.
--
-- STRESS SCORE: 0 (calm) to 100 (bankrupt). The main number the learner tries to keep low.
-- It is NOT set by the learner. It is worked out on the server from:
--   * five pressures: cash runway, debt load, shock cushion, goal drift, load (things to juggle)
--   * "effects": the lasting stress of decisions the learner made (see stress_flag_effects, seeded in 13)
--   * "scars": costly mistakes while unguided, defaulted loans
--   * lifestyle creep: upgrades the learner accepted raise the cost of living
-- Stress moves toward its target slowly, and up faster than down (per GAME month):
--   at most +10 up, -6 down. Collapse (bankruptcy) jumps straight to 100 until the learner restarts.
--
-- The browser calls stress_status(). Every weight and threshold is in sim_config (keys 'stress_*'),
-- so tuning never needs a code change. ALL NUMBERS ARE STARTING VALUES.
--
-- Order matters: 13 and 14 must run after this file. Re-running 02 later replaces functions that
-- 13 patches; if you ever re-run 02, run 13 again afterwards.

insert into sim_config (key, value) values
  ('stress_ess_student', '1500'), ('stress_ess_trader', '2500'),
  ('stress_ess_salaried', '3500'), ('stress_ess_farmer', '2000'), ('stress_ess_default', '2000'),
  ('stress_up_per_month', '10'), ('stress_down_per_month', '6'),
  ('stress_w_cash', '0.30'), ('stress_w_debt', '0.25'), ('stress_w_shock', '0.20'),
  ('stress_w_goal', '0.15'), ('stress_w_load', '0.10'),
  ('stress_scar_blunder', '6'), ('stress_scar_default', '8'),
  ('stress_infl_per_year', '0.12'),          -- idle cash loses this much real value per game year
  ('stress_creep_per_flag', '600'),          -- each accepted upgrade adds this to monthly essentials (max 3)
  ('stress_pattern_mult', '1.5'),            -- repeated impulse-type choices cost this much more
  ('stress_restart_cash', '3000'), ('stress_scar_restart', '20')
on conflict (key) do nothing;

alter table profiles add column if not exists stress numeric(5,2);
alter table profiles add column if not exists stress_updated_at timestamptz;
alter table profiles add column if not exists goal_started_at timestamptz;
alter table profiles add column if not exists goal_baseline numeric(14,2);
alter table profiles add column if not exists goal_cycle int not null default 0;
alter table profiles add column if not exists bankrupt_count int not null default 0;
alter table profiles add column if not exists comeback_at timestamptz;

-- Repayment schedule fields on debts (used by 15-debt-schedules.sql; defined here so the stress model can read them)
alter table debts add column if not exists product text;                       -- bank | microfinance | payday | family
alter table debts add column if not exists structure text not null default 'flexible';   -- installment | bullet | story | flexible
alter table debts add column if not exists term_months int;
alter table debts add column if not exists installment numeric(14,2);          -- monthly minimum payment
alter table debts add column if not exists billed_cycles int not null default 0;
alter table debts add column if not exists due_amount numeric(14,2) not null default 0;
alter table debts add column if not exists due_since timestamptz;
alter table debts add column if not exists last_accrual_at timestamptz not null default now();
alter table debts add column if not exists missed_count int not null default 0;
alter table debts add column if not exists rollovers int not null default 0;

-- The lasting stress of a decision. A decision is identified by the story flag it sets.
--   delta          stress points (negative = relief)
--   delay_months   game months after the flag before the effect starts
--   fade_months    game months it takes to fade to zero (0 = does not fade)
--   pattern_key    repeated use of the same pattern costs more (see stress_pattern_mult)
create table if not exists stress_flag_effects (
  id bigint generated always as identity primary key,
  flag_key text not null,
  delta numeric(5,2) not null,
  delay_months numeric(5,2) not null default 0,
  fade_months numeric(5,2) not null default 3,
  why text not null,
  pattern_key text
);
alter table stress_flag_effects add column if not exists cancelled_by text[];   -- flags that end this effect early (e.g. the loan was repaid)
create index if not exists stress_flag_effects_flag on stress_flag_effects (flag_key);

-- A goal gives choices meaning. One per starting story; the learner grows what they own by `amount`
-- within `game_months`. Falling behind raises stress; missing the deadline leaves a scar.
create table if not exists sim_goals (
  backstory text primary key,
  title text not null,
  emoji text not null default '🎯',
  amount numeric(14,2) not null,
  game_months numeric(5,2) not null default 6
);

create table if not exists bankruptcies (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  turning_points jsonb not null default '[]',
  note text,
  resolved_at timestamptz
);
create index if not exists bankruptcies_lookup on bankruptcies (profile_id, resolved_at);

-- One row per learner per day. The leaderboard ranks the average over a stretch of days.
create table if not exists stress_history (
  profile_id uuid not null references profiles(id) on delete cascade,
  day date not null,
  stress numeric(5,2) not null,          -- last reading of the day
  stress_sum numeric(10,2) not null,     -- running sum + count, so the day's average is stress_sum / samples
  samples int not null default 1,
  primary key (profile_id, day)
);

alter table stress_flag_effects enable row level security;
alter table sim_goals enable row level security;
alter table bankruptcies enable row level security;
alter table stress_history enable row level security;
revoke all on stress_flag_effects from anon, authenticated;
revoke all on sim_goals from anon, authenticated;
revoke insert, update, delete, truncate on bankruptcies from anon, authenticated;
revoke insert, update, delete, truncate on stress_history from anon, authenticated;
drop policy if exists "own bankruptcies (read)" on bankruptcies;
create policy "own bankruptcies (read)" on bankruptcies for select using (auth.uid() = profile_id);
drop policy if exists "own stress history (read)" on stress_history;
create policy "own stress history (read)" on stress_history for select using (auth.uid() = profile_id);

create or replace function stress_band(s numeric) returns text
language sql immutable as $$
  select case when round(s) >= 100 then 'bankrupt' when round(s) >= 80 then 'crisis'
              when round(s) >= 60 then 'overloaded' when round(s) >= 40 then 'strained'
              when round(s) >= 20 then 'manageable' else 'calm' end
$$;

-- What the learner owns beyond cash: investments + business value - debts. Cash is returned separately
-- because idle cash is the part inflation eats.
create or replace function stress_other_assets(p uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select sum(h.quantity * i.current_price) from holdings h join instruments i on i.id = h.instrument_id
                   where h.profile_id = p), 0)
       + coalesce((select sum(coalesce(v.capital, v.starting_capital) + coalesce(v.retained, 0)) from ventures v
                   where v.profile_id = p and v.status = 'active'), 0)
       - coalesce((select sum(d.outstanding_balance) from debts d where d.profile_id = p and d.status = 'active'), 0)
$$;

-- Work out the target score and the reasons behind it. Changes no data.
create or replace function stress_compute(p uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  pr profiles; g sim_goals;
  v_gm numeric := greatest(sim_cfg('real_days_per_game_year', 14) / 12.0, 0.1);   -- real days per game month
  v_ess numeric; v_cash numeric; v_runway numeric; v_creep int;
  v_months_alive numeric; v_income numeric; v_base numeric;
  v_debt_out numeric; v_burden numeric; v_informal boolean; v_overdue boolean; v_def int; v_dsr numeric;
  v_vent int; v_vent_ins int; v_pend int; v_items int;
  c_cash numeric; c_debt numeric; c_shock numeric; c_load numeric; c_goal numeric := 0;
  w_cash numeric := sim_cfg('stress_w_cash', 0.30); w_debt numeric := sim_cfg('stress_w_debt', 0.25);
  w_shock numeric := sim_cfg('stress_w_shock', 0.20); w_load numeric := sim_cfg('stress_w_load', 0.10);
  w_goal numeric := 0; w_sum numeric;
  v_scar numeric := 0; v_blunders int := 0; v_eff numeric := 0; v_target numeric; v_collapse boolean;
  v_items_json jsonb; v_drivers jsonb; v_changes jsonb := '[]'::jsonb; v_goal jsonb := null;
  v_age numeric; v_fade numeric; v_mult numeric; v_val numeric; v_n int; v_effect_rows jsonb := '[]'::jsonb;
  v_elapsed numeric; v_nw numeric; v_prog numeric; v_exp numeric; v_infl numeric := sim_cfg('stress_infl_per_year', 0.12);
  fe record; d record;
begin
  select * into pr from profiles where id = p;
  if not found then return null; end if;

  select count(*) into v_creep from learner_flags where profile_id = p and flag_key = 'creep_upgrade';
  v_creep := least(3, v_creep);
  v_ess := sim_cfg('stress_ess_' || coalesce(pr.backstory, 'default'), sim_cfg('stress_ess_default', 2000))
           + v_creep * sim_cfg('stress_creep_per_flag', 600);
  v_cash := greatest(coalesce(pr.cash_balance, 0), 0);
  v_runway := v_cash / v_ess;
  c_cash := least(1, greatest(0, (6 - v_runway) / 5.75));                  -- 1 at <=0.25 months, 0 at >=6 months

  -- Income: average of salary and venture income over up to the last 6 game months (never below essentials)
  v_months_alive := greatest(1, least(6, extract(epoch from (now() - pr.created_at)) / 86400.0 / v_gm));
  select coalesce(sum(amount), 0) / v_months_alive into v_income
  from cash_ledger
  where profile_id = p and amount > 0 and reason in ('salary', 'venture_income', 'venture_payout')
    and created_at > now() - make_interval(secs => v_gm * 6 * 86400);
  v_base := greatest(coalesce(v_income, 0), v_ess);

  -- Debt: monthly repayments are approximated as 1/12 of the balance plus a month of interest
  -- Monthly repayments: the scheduled instalment where there is one; a one-payment loan is spread over the
  -- months it has left; story loans and flexible loans use balance/12 plus a month of interest.
  -- "Expensive" means 35% a year or more (payday level in Module 1.2).
  select coalesce(sum(outstanding_balance), 0),
         coalesce(sum(case structure
                when 'installment' then least(coalesce(installment, outstanding_balance), outstanding_balance)
                when 'bullet' then outstanding_balance / greatest(1, coalesce(term_months, 1) * (rollovers + 1) - billed_cycles)
                else outstanding_balance / 12.0 + outstanding_balance * annual_interest_rate / 1200.0 end), 0),
         coalesce(bool_or(annual_interest_rate >= 35), false),
         coalesce(bool_or(due_amount > 0 and due_since is not null and due_since < now() - make_interval(secs => v_gm * sim_cfg('debt_grace_months', 1) * 86400)), false)
    into v_debt_out, v_burden, v_informal, v_overdue
  from debts where profile_id = p and status = 'active';
  select count(*) into v_def from debts where profile_id = p and status = 'defaulted';
  v_dsr := v_burden / v_base;
  c_debt := least(1, greatest(0, (v_dsr - 0.10) / 0.50));
  if v_informal then c_debt := least(1, c_debt * 1.3); end if;
  if v_def > 0 or v_overdue then c_debt := least(1, c_debt + 0.3); end if;

  -- Shock cushion: 3 months of essentials in cash = fully cushioned. Covered businesses soften it.
  c_shock := 1 - least(1, v_runway / 3);
  select count(*), count(*) filter (where insured_until is not null and insured_until > now())
    into v_vent, v_vent_ins from ventures where profile_id = p and status = 'active';
  if v_vent > 0 then c_shock := c_shock * (1 - 0.3 * (v_vent_ins::numeric / v_vent)); end if;

  -- Load: businesses + loans + decisions waiting, beyond about 3 things
  select count(*) into v_pend from learner_pending_events
  where profile_id = p and status = 'pending' and available_at <= now();
  v_items := v_vent + (select count(*) from debts where profile_id = p and status = 'active') + v_pend;
  c_load := least(1, greatest(0, (v_items - 3) / 5.0));

  -- Goal drift: how far behind the learner is on growing what they own (idle cash loses real value)
  select * into g from sim_goals where backstory = coalesce(pr.backstory, '');
  if g.backstory is not null and pr.goal_started_at is not null then
    v_elapsed := extract(epoch from (now() - pr.goal_started_at)) / 86400.0 / v_gm;           -- game months
    v_nw := coalesce(pr.cash_balance, 0) / power(1 + v_infl, v_elapsed / 12.0) + stress_other_assets(p);
    v_prog := (v_nw - pr.goal_baseline) / g.amount;
    v_exp := least(1, v_elapsed / g.game_months);
    c_goal := least(1, greatest(0, v_exp - v_prog));
    w_goal := sim_cfg('stress_w_goal', 0.15);
    v_goal := jsonb_build_object('title', g.title, 'emoji', g.emoji, 'amount', g.amount,
                'progress', round(least(1, greatest(0, v_prog)), 3), 'expected', round(v_exp, 3),
                'months_left', round(greatest(0, g.game_months - v_elapsed), 1), 'cycle', pr.goal_cycle);
  end if;

  -- Scars: costly mistakes while unguided fade over 3 game months; each defaulted loan counts
  for d in select created_at from learner_blunders where profile_id = p
           and created_at > now() - make_interval(secs => v_gm * 3 * 86400) loop
    v_blunders := v_blunders + 1;
    v_scar := v_scar + sim_cfg('stress_scar_blunder', 6) *
              (1 - least(1, extract(epoch from (now() - d.created_at)) / 86400.0 / (v_gm * 3)));
  end loop;
  v_scar := least(30, v_scar + least(2, v_def) * sim_cfg('stress_scar_default', 8));

  -- Effects of decisions: each flag the learner set that has an entry in stress_flag_effects
  for fe in select f.created_at, m.delta, m.delay_months, m.fade_months, m.why, m.pattern_key, m.cancelled_by
            from learner_flags f join stress_flag_effects m on m.flag_key = f.flag_key
            where f.profile_id = p loop
    continue when fe.cancelled_by is not null and exists (
      select 1 from learner_flags f3 where f3.profile_id = p and f3.flag_key = any (fe.cancelled_by) and f3.created_at >= fe.created_at);
    v_age := extract(epoch from (now() - fe.created_at)) / 86400.0 / v_gm;
    continue when v_age < fe.delay_months;
    v_fade := case when fe.fade_months <= 0 then 1 else greatest(0, 1 - (v_age - fe.delay_months) / fe.fade_months) end;
    continue when v_fade <= 0;
    v_mult := 1;
    if fe.pattern_key is not null and fe.delta > 0 then
      select count(*) into v_n from learner_flags f2 join stress_flag_effects m2 on m2.flag_key = f2.flag_key
       where f2.profile_id = p and m2.pattern_key = fe.pattern_key and m2.delta > 0
         and f2.created_at > now() - make_interval(secs => v_gm * 6 * 86400);
      if v_n >= 3 then v_mult := sim_cfg('stress_pattern_mult', 1.5); end if;
    end if;
    v_val := fe.delta * v_fade * v_mult;
    v_eff := v_eff + v_val;
    if abs(v_val) >= 1 then
      v_effect_rows := v_effect_rows || jsonb_build_array(jsonb_build_object('key', 'effect', 'points', round(v_val, 1), 'text', fe.why));
    end if;
    -- "just happened": the effect started within the last 5 minutes
    if (v_age - fe.delay_months) * v_gm * 1440 <= 5 then
      v_changes := v_changes || jsonb_build_array(jsonb_build_object('delta', round(v_val, 1), 'why', fe.why));
    end if;
  end loop;
  v_eff := least(40, greatest(-15, v_eff));

  w_sum := w_cash + w_debt + w_shock + w_load + w_goal;
  v_target := 100 * (w_cash * c_cash + w_debt * c_debt + w_shock * c_shock + w_load * c_load + w_goal * c_goal) / w_sum
              + v_scar + v_eff;
  v_target := least(99, greatest(0, v_target));

  v_collapse := (v_cash < 0.1 * v_ess) and (v_debt_out > 6 * v_base);
  if v_collapse then v_target := 100; end if;

  v_items_json := jsonb_build_array(
    jsonb_build_object('key', 'cash', 'points', round(100 * w_cash * c_cash / w_sum, 1),
      'text', case when v_cash <= 0 then 'No cash left'
                   when v_runway < 1 then 'Cash covers about ' || greatest(1, round(v_runway * 4.33)) ||
                        case when greatest(1, round(v_runway * 4.33)) = 1 then ' week' else ' weeks' end || ' of costs'
                   else 'Cash covers about ' || round(v_runway, 1) || ' months of costs' end),
    jsonb_build_object('key', 'debt', 'points', round(100 * w_debt * c_debt / w_sum, 1),
      'text', case when v_def > 0 then 'A loan was defaulted'
                   when v_overdue then 'A loan payment is overdue'
                   when v_informal then 'Repayments take about ' || round(v_dsr * 100) || '% of income, mostly from a payday-style lender'
                   else 'Repayments take about ' || round(v_dsr * 100) || '% of income' end),
    jsonb_build_object('key', 'shock', 'points', round(100 * w_shock * c_shock / w_sum, 1),
      'text', case when v_runway < 0.5 then 'No cushion for a surprise'
                   when v_vent > 0 and v_vent_ins < v_vent then 'A business has no cover against theft or loss'
                   else 'Cushion covers ' || round(least(3, v_runway), 1) || ' of 3 months' end),
    jsonb_build_object('key', 'goal', 'points', round(100 * w_goal * c_goal / w_sum, 1),
      'text', case when g.title is null then 'No goal set' else 'The goal "' || g.title || '" is falling behind' end),
    jsonb_build_object('key', 'load', 'points', round(100 * w_load * c_load / w_sum, 1),
      'text', v_items || ' things to keep track of'),
    jsonb_build_object('key', 'scars', 'points', round(v_scar, 1),
      'text', case when v_blunders > 0 then 'Left alone, they made ' || v_blunders || ' costly ' ||
                        case when v_blunders = 1 then 'mistake' else 'mistakes' end
                   else 'Lingering worry from a past mistake' end),
    jsonb_build_object('key', 'creep', 'points', round(least(10, v_creep * 3.0), 1),
      'text', 'Upgrades have raised the monthly cost of living by about K' || (v_creep * sim_cfg('stress_creep_per_flag', 600))::int));
  v_items_json := v_items_json || v_effect_rows;

  select coalesce(jsonb_agg(x.item), '[]'::jsonb) into v_drivers
  from (select item from jsonb_array_elements(v_items_json) item
        where (item->>'points')::numeric >= 2 order by (item->>'points')::numeric desc limit 3) x;

  return jsonb_build_object(
    'target', round(v_target, 2), 'collapse', v_collapse, 'drivers', v_drivers, 'changes', v_changes, 'goal', v_goal,
    'components', jsonb_build_object('cash', round(c_cash * 100), 'debt', round(c_debt * 100), 'shock', round(c_shock * 100),
                  'goal', round(c_goal * 100), 'load', round(c_load * 100), 'scars', round(v_scar), 'effects', round(v_eff)),
    'goal_active', v_goal is not null);
end $$;

-- Move the stored score toward its target (slowly), roll goal cycles, handle bankruptcy, record the day.
create or replace function stress_tick(p uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  pr profiles; g sim_goals; v_c jsonb; v_target numeric; v_old numeric; v_new numeric; v_m numeric;
  v_gm numeric := greatest(sim_cfg('real_days_per_game_year', 14) / 12.0, 0.1);
  v_elapsed numeric; v_nw numeric; v_open bankruptcies; v_tp jsonb; v_bk jsonb := null; v_comeback boolean;
begin
  select * into pr from profiles where id = p for update;
  if not found then return jsonb_build_object('error', 'no_profile'); end if;

  -- Goal cycle: start the first one, or close a finished one (met or missed) and start the next
  select * into g from sim_goals where backstory = coalesce(pr.backstory, '');
  if g.backstory is not null then
    if pr.goal_started_at is null then
      update profiles set goal_started_at = now(), goal_cycle = 1,
             goal_baseline = coalesce(pr.cash_balance, 0) + stress_other_assets(p) where id = p;
    else
      v_elapsed := extract(epoch from (now() - pr.goal_started_at)) / 86400.0 / v_gm;
      if v_elapsed >= g.game_months then
        v_nw := coalesce(pr.cash_balance, 0) / power(1 + sim_cfg('stress_infl_per_year', 0.12), v_elapsed / 12.0) + stress_other_assets(p);
        perform story_set_flag(p, case when (v_nw - pr.goal_baseline) >= g.amount then 'goal_met' else 'goal_missed' end, null);
        update profiles set goal_started_at = now(), goal_cycle = goal_cycle + 1,
               goal_baseline = coalesce(pr.cash_balance, 0) + stress_other_assets(p) where id = p;
      end if;
    end if;
    select * into pr from profiles where id = p;
  end if;

  if to_regprocedure('debt_tick(uuid)') is not null then perform debt_tick(p); end if;   -- bills and interest first (15-debt-schedules.sql)
  v_c := stress_compute(p);
  v_target := (v_c->>'target')::numeric;
  v_old := pr.stress;

  -- Bankruptcy: open one on collapse, and stay at 100 until the learner restarts
  select * into v_open from bankruptcies where profile_id = p and resolved_at is null order by id desc limit 1;
  if v_open.id is null and (v_c->>'collapse')::boolean then
    select coalesce(jsonb_agg(t.why), '[]'::jsonb) into v_tp from (
      select m.why from learner_flags f join stress_flag_effects m on m.flag_key = f.flag_key
       where f.profile_id = p and m.delta > 0 order by f.created_at desc limit 3) t;
    v_tp := coalesce((select jsonb_agg(x->>'text') from jsonb_array_elements(v_c->'drivers') x), '[]'::jsonb) || v_tp;
    insert into bankruptcies (profile_id, turning_points) values (p, v_tp) returning * into v_open;
  end if;

  if v_open.id is not null then
    v_new := 100;
    v_bk := jsonb_build_object('id', v_open.id, 'turning_points', v_open.turning_points);
  elsif v_old is null then
    v_new := v_target;                                              -- first reading: no easing
  else
    v_m := least(6, greatest(0, extract(epoch from (now() - coalesce(pr.stress_updated_at, now()))) / 86400.0 / v_gm));
    v_new := v_old + least(sim_cfg('stress_up_per_month', 10) * v_m,
                           greatest(-sim_cfg('stress_down_per_month', 6) * v_m, v_target - v_old));
    v_new := least(99, greatest(0, v_new));
  end if;

  -- Comeback: calm again at least a game month after a restart
  if pr.bankrupt_count > 0 and pr.comeback_at is null and v_open.id is null and v_new < 40
     and exists (select 1 from bankruptcies where profile_id = p and resolved_at < now() - make_interval(secs => v_gm * 86400)) then
    update profiles set comeback_at = now() where id = p;
    pr.comeback_at := now();
  end if;
  v_comeback := pr.comeback_at is not null;

  update profiles set stress = v_new, stress_updated_at = now() where id = p;
  insert into stress_history (profile_id, day, stress, stress_sum, samples)
  values (p, sim_today(), v_new, v_new, 1)
  on conflict (profile_id, day) do update
    set stress = excluded.stress, stress_sum = stress_history.stress_sum + excluded.stress,
        samples = stress_history.samples + 1;

  return jsonb_build_object(
    'stress', round(v_new), 'band', stress_band(v_new), 'target', round(v_target),
    'drivers', v_c->'drivers', 'changes', v_c->'changes', 'components', v_c->'components', 'goal', v_c->'goal',
    'collapse', (v_c->>'collapse')::boolean, 'bankrupt', v_open.id is not null, 'bankruptcy', v_bk,
    'comeback', v_comeback, 'bankrupt_count', pr.bankrupt_count,
    'name', coalesce(pr.character_name, 'Your yungsta'), 'avatar', pr.avatar);
end $$;

-- Called by the browser. Safe to call on every page load.
create or replace function stress_status()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  return stress_tick(uid);
end $$;

revoke all on function stress_compute(uuid) from public, anon, authenticated;
revoke all on function stress_tick(uuid) from public, anon, authenticated;
revoke all on function stress_other_assets(uuid) from public, anon, authenticated;
revoke all on function stress_status() from public, anon;
grant execute on function stress_status() to authenticated;
