-- FinLit Zambia — Financial Character Simulator
-- 04-lockdown-and-character.sql  (safe to re-run)
-- Run AFTER 01, 02 and 03.
--
-- 1. Learners can no longer write to ANY money table. They can only READ their
--    own rows. Every money movement now goes through a function that checks
--    the rules on the server (price comes from the instruments table, cash
--    can't go negative, loans have ceilings, and so on).
-- 2. Character creation (a yungsta the learner guides: name, look, backstory, relationship) via set_character().
-- 3. The profile row is created automatically when someone signs up.

-- ─────────────────────────────────────────────
-- CHARACTER COLUMNS
-- ─────────────────────────────────────────────
alter table profiles add column if not exists avatar text not null default '🙂';
alter table profiles add column if not exists backstory text;   -- null = character not created yet

-- ─────────────────────────────────────────────
-- AUTO-CREATE THE PROFILE AT SIGN-UP (replaces the client-side insert)
-- ─────────────────────────────────────────────
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), 'Learner'))
  on conflict (id) do nothing;
  insert into public.learner_feature_unlocks (profile_id, feature_key, unlocked_at) values
    (new.id, 'ventures', now()), (new.id, 'trade', null), (new.id, 'debts', null)
  on conflict (profile_id, feature_key) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ─────────────────────────────────────────────
-- LOCK THE TABLES: read-only for learners
-- ─────────────────────────────────────────────
drop policy if exists "own profile" on profiles;
drop policy if exists "own cash ledger" on cash_ledger;
drop policy if exists "own trades" on trades;
drop policy if exists "own holdings" on holdings;
drop policy if exists "own ventures" on ventures;
drop policy if exists "own venture events" on venture_events;
drop policy if exists "own debts" on debts;
drop policy if exists "own reputation events" on reputation_events;
drop policy if exists "own net worth" on net_worth_snapshots;

drop policy if exists "read own profile" on profiles;
create policy "read own profile" on profiles for select using (auth.uid() = id);
drop policy if exists "read own cash ledger" on cash_ledger;
create policy "read own cash ledger" on cash_ledger for select using (auth.uid() = profile_id);
drop policy if exists "read own trades" on trades;
create policy "read own trades" on trades for select using (auth.uid() = profile_id);
drop policy if exists "read own holdings" on holdings;
create policy "read own holdings" on holdings for select using (auth.uid() = profile_id);
drop policy if exists "read own ventures" on ventures;
create policy "read own ventures" on ventures for select using (auth.uid() = profile_id);
drop policy if exists "read own venture events" on venture_events;
create policy "read own venture events" on venture_events for select
  using (auth.uid() = (select v.profile_id from ventures v where v.id = venture_id));
drop policy if exists "read own debts" on debts;
create policy "read own debts" on debts for select using (auth.uid() = profile_id);
drop policy if exists "read own reputation events" on reputation_events;
create policy "read own reputation events" on reputation_events for select using (auth.uid() = profile_id);
drop policy if exists "read own net worth" on net_worth_snapshots;
create policy "read own net worth" on net_worth_snapshots for select using (auth.uid() = profile_id);

-- Catch-all: drop ANY remaining write policy on these tables, whatever it was called.
do $$
declare r record;
begin
  for r in select schemaname, tablename, policyname from pg_policies
           where schemaname = 'public' and cmd <> 'SELECT'
             and tablename in ('profiles','cash_ledger','trades','holdings','ventures','venture_events',
                               'debts','reputation_events','net_worth_snapshots')
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

-- Belt and braces: remove the write privileges themselves, not just the policies.
revoke insert, update, delete, truncate on
  profiles, cash_ledger, trades, holdings, ventures, venture_events, debts,
  reputation_events, net_worth_snapshots,
  learner_feature_unlocks, learner_flags, learner_pending_events,
  learner_event_log, learner_daily_check
from anon, authenticated;
revoke insert, update, delete, truncate on
  story_events, story_nodes, lesson_flag_map, lender_limit_rules, sim_config,
  instruments, instrument_price_history
from anon, authenticated;

-- ─────────────────────────────────────────────
-- CHARACTER
-- ─────────────────────────────────────────────
drop function if exists set_character(text, text, text);
create or replace function set_character(p_name text, p_avatar text, p_backstory text, p_relationship text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); v_name text := trim(coalesce(p_name, ''));
  avatars text[] := array['🧒🏾','👦🏾','👧🏾','🧑🏾','👩🏾','👨🏾','🧕🏾','👷🏾','👩🏾‍🌾','👨🏾‍🌾','🧑🏾‍💻','🧑🏾‍🔧'];
  stories text[] := array['student','trader','salaried','farmer'];
  rels text[] := array['younger_brother','younger_sister','son','daughter','apprentice'];
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  if char_length(v_name) < 2 or char_length(v_name) > 24 then
    return jsonb_build_object('error', 'bad_name');
  end if;
  if not (p_avatar = any (avatars)) then return jsonb_build_object('error', 'bad_avatar'); end if;
  if not (p_backstory = any (stories)) then return jsonb_build_object('error', 'bad_backstory'); end if;
  if not (p_relationship = any (rels)) then return jsonb_build_object('error', 'bad_relationship'); end if;

  -- character_name is the YUNGSTA the learner is guiding; display_name stays the learner's own name
  update profiles set character_name = v_name, avatar = p_avatar, backstory = p_backstory, relationship = p_relationship
   where id = uid;
  delete from learner_flags where profile_id = uid and flag_key like 'bg\_%';
  perform story_set_flag(uid, 'bg_' || p_backstory, null);
  return jsonb_build_object('ok', true);
end $$;

-- ─────────────────────────────────────────────
-- TRADING (price is read on the server; the browser can't set it)
-- ─────────────────────────────────────────────
create or replace function sim_trade(p_instrument_id bigint, p_side text, p_qty numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); ins instruments; v_cash numeric; v_total numeric;
  h holdings; v_trade_id bigint; v_new_qty numeric; v_avg numeric;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  if not story_feature_open(uid, 'trade') then return jsonb_build_object('error', 'locked'); end if;
  if p_side not in ('buy', 'sell') then return jsonb_build_object('error', 'bad_side'); end if;
  if p_qty is null or p_qty <= 0 or p_qty > 1000000 then return jsonb_build_object('error', 'bad_quantity'); end if;

  select * into ins from instruments where id = p_instrument_id and is_active;
  if not found then return jsonb_build_object('error', 'bad_instrument'); end if;

  v_total := round(p_qty * ins.current_price, 2);
  select cash_balance into v_cash from profiles where id = uid for update;
  select * into h from holdings where profile_id = uid and instrument_id = ins.id;

  if p_side = 'buy' then
    if v_total > v_cash then return jsonb_build_object('error', 'insufficient_cash', 'cash', v_cash); end if;
  else
    if h.id is null or h.quantity < p_qty then
      return jsonb_build_object('error', 'insufficient_holding', 'held', coalesce(h.quantity, 0));
    end if;
  end if;

  insert into trades (profile_id, instrument_id, side, quantity, price_at_trade, total_value)
  values (uid, ins.id, p_side, p_qty, ins.current_price, v_total) returning id into v_trade_id;

  perform adjust_cash_balance(uid, case when p_side = 'buy' then -v_total else v_total end,
                              case when p_side = 'buy' then 'trade_buy' else 'trade_sell' end, 'trades', v_trade_id);

  if p_side = 'buy' then
    v_new_qty := coalesce(h.quantity, 0) + p_qty;
    v_avg := (coalesce(h.quantity, 0) * coalesce(h.avg_buy_price, 0) + p_qty * ins.current_price) / v_new_qty;
  else
    v_new_qty := h.quantity - p_qty;
    v_avg := h.avg_buy_price;
  end if;

  insert into holdings (profile_id, instrument_id, quantity, avg_buy_price)
  values (uid, ins.id, v_new_qty, v_avg)
  on conflict (profile_id, instrument_id) do update
    set quantity = excluded.quantity, avg_buy_price = excluded.avg_buy_price;

  return jsonb_build_object('ok', true, 'total', v_total, 'cash', (select cash_balance from profiles where id = uid));
end $$;

-- ─────────────────────────────────────────────
-- VENTURES
-- Venture income is generated by the server (see 06-venture-income.sql).
-- Learners can start ventures and record expenses, but cannot award themselves revenue.
-- ─────────────────────────────────────────────
create or replace function sim_create_venture(p_name text, p_category text, p_capital numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_cash numeric; v_id bigint; v_name text := trim(coalesce(p_name, ''));
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  if char_length(v_name) < 1 or char_length(v_name) > 60 then return jsonb_build_object('error', 'bad_name'); end if;
  if p_category is null or char_length(p_category) > 30 then return jsonb_build_object('error', 'bad_category'); end if;
  if p_capital is null or p_capital <= 0 or p_capital > 1000000 then return jsonb_build_object('error', 'bad_amount'); end if;

  select cash_balance into v_cash from profiles where id = uid for update;
  if p_capital > v_cash then return jsonb_build_object('error', 'insufficient_cash', 'cash', v_cash); end if;

  insert into ventures (profile_id, name, category, starting_capital, capital)
  values (uid, v_name, p_category, round(p_capital, 2), round(p_capital, 2)) returning id into v_id;
  perform adjust_cash_balance(uid, -round(p_capital, 2), 'venture_cost', 'ventures', v_id);
  if not story_has_flag(uid, 'started_venture') then perform story_set_flag(uid, 'started_venture', null); end if;
  return jsonb_build_object('ok', true, 'venture_id', v_id);
end $$;

create or replace function sim_log_venture_event(p_venture_id bigint, p_kind text, p_amount numeric, p_desc text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v ventures; v_cash numeric; v_amt numeric := round(coalesce(p_amount, 0), 2);
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  -- Revenue is generated by the server (sim_collect_income). Learners can only record spending.
  if p_kind <> 'expense' then return jsonb_build_object('error', 'revenue_is_automatic'); end if;
  if v_amt <= 0 or v_amt > 1000000 then return jsonb_build_object('error', 'bad_amount'); end if;

  select * into v from ventures where id = p_venture_id and profile_id = uid and status = 'active';
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  select cash_balance into v_cash from profiles where id = uid for update;
  if v_amt > v_cash then return jsonb_build_object('error', 'insufficient_cash', 'cash', v_cash); end if;

  insert into venture_events (venture_id, kind, amount, description)
  values (v.id, 'expense', -v_amt, left(nullif(trim(p_desc), ''), 200));
  perform adjust_cash_balance(uid, -v_amt, 'venture_cost', 'ventures', v.id);
  return jsonb_build_object('ok', true);
end $$;

-- ─────────────────────────────────────────────
-- REPAYING A DEBT (early repayment of a story loan settles its waiting consequence)
-- ─────────────────────────────────────────────
create or replace function sim_repay(p_debt_id bigint, p_amount numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); d debts; v_cash numeric; v_amt numeric; e story_events; v_rep numeric;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  select * into d from debts where id = p_debt_id and profile_id = uid and status = 'active' for update;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  select cash_balance into v_cash from profiles where id = uid for update;
  v_amt := least(round(coalesce(p_amount, 0), 2), d.outstanding_balance);
  if v_amt <= 0 then return jsonb_build_object('error', 'bad_amount'); end if;
  if v_amt > v_cash then return jsonb_build_object('error', 'insufficient_cash', 'cash', v_cash); end if;

  perform adjust_cash_balance(uid, -v_amt, 'debt_repayment', 'debts', d.id);
  update debts set outstanding_balance = outstanding_balance - v_amt,
                   status = case when outstanding_balance - v_amt <= 0 then 'repaid' else 'active' end
   where id = d.id;

  if d.outstanding_balance - v_amt <= 0 and d.story_tag is not null then
    for e in select * from story_events where trigger_config->>'cancel_on_repay_tag' = d.story_tag loop
      update learner_pending_events set status = 'done', resolved_at = now()
       where profile_id = uid and event_id = e.id and status = 'pending';
      if (e.trigger_config->>'repay_flag') is not null then
        perform story_set_flag(uid, e.trigger_config->>'repay_flag', e.id);
      end if;
      v_rep := coalesce((e.trigger_config->>'repay_reputation')::numeric, 0);
      if v_rep <> 0 then perform adjust_reputation_score(uid, v_rep, 'repaid early: ' || d.story_tag); end if;
    end loop;
  end if;

  return jsonb_build_object('ok', true, 'paid', v_amt);
end $$;

-- ─────────────────────────────────────────────
-- PERMISSIONS for the new browser-facing functions
-- ─────────────────────────────────────────────
revoke all on function handle_new_user() from public, anon, authenticated;
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in
             ('set_character', 'sim_trade', 'sim_create_venture', 'sim_log_venture_event', 'sim_repay')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $$;
