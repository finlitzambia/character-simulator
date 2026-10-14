-- FinLit Zambia — Financial Character Simulator
-- 15-debt-schedules.sql  (safe to re-run)  Run AFTER 14.
--
-- REAL REPAYMENT SCHEDULES, rooted in Module 1.2 (Credit and Debt Management).
--
-- What comes from the lesson (do not change without changing the lesson):
--   * Lender rates per year: bank about 20%, microfinance about 28%, payday lenders 35% or more.
--   * "What a loan really costs": Total interest = Principal x Rate x Years. Monthly payment = (principal + interest) / months.
--     debt_quote() shows exactly this.
--   * "Avalanche vs Snowball": every month interest is added to each debt, minimum payments are made on all debts,
--     and the rest of the monthly budget goes to one priority debt. Avalanche = highest rate first. Snowball = smallest
--     balance first. debt_run_strategy() does exactly this. (One fix: when the first debt is cleared in a month and
--     money is left over, it goes to the NEXT priority debt. The lesson's script skips one.)
--   * Co-signing, on-time payment as the strongest credit signal, and an emergency fund as the safest source.
--
-- GAME RULES (not in the lesson, tune in sim_config / lender_products): grace period, late fee, rollover fee,
-- default after N missed, terms offered, the payday limit, and the one-plan-per-game-month rule.
--
-- How it works: each game month, interest is added to the balance owed (as in the lesson's simulator) and a bill is
-- raised for the scheduled payment. Pay it within the grace period, or a late fee is added and a payment is "missed".
-- Three missed payments means default. A payday loan is one payment at the end; renewing it ("rollover") adds a fee
-- and pushes the problem forward, as in Bwalya's story.
-- Story loans keep their own story-managed due dates (chola_loan, phone_loan) and are not billed here.

insert into sim_config (key, value) values
  ('debt_grace_months', '1'),           -- game months after a bill before it counts as missed
  ('debt_default_after_missed', '3'),
  ('debt_payday_limit', '2000'),
  ('debt_plan_cooldown_months', '1')    -- the payoff plan can be run once per game month
on conflict (key) do nothing;

alter table profiles add column if not exists debt_strategy text not null default 'avalanche';
alter table profiles add column if not exists debt_autopay boolean not null default false;
alter table profiles add column if not exists debt_plan_at timestamptz;

create table if not exists lender_products (
  product text primary key,                       -- bank | microfinance | payday | family
  label text not null,
  annual_rate numeric(6,2) not null,
  structure text not null,                        -- installment | bullet | flexible
  term_default int,
  term_options int[],
  late_fee_pct numeric(5,2) not null default 5,
  rollover_fee_pct numeric(5,2),
  lesson_id text not null default '1-2',
  note text
);
insert into lender_products (product, label, annual_rate, structure, term_default, term_options, late_fee_pct, rollover_fee_pct, note) values
  ('bank',         'Commercial bank',          20, 'installment', 12, array[6,12,24], 5,  null, 'Rate from Module 1.2: formal bank loans around 20% a year. Terms and fees are game rules.'),
  ('microfinance', 'Microfinance institution', 28, 'installment', 6,  array[3,6,12],  5,  null, 'Rate from Module 1.2: microfinance around 28% a year. Terms and fees are game rules.'),
  ('payday',       'Payday lender',            35, 'bullet',      1,  array[1],       10, 15,   'Rate from Module 1.2: payday lenders 35% a year or more. One payment at the end. Rollover fee is a game rule (Bwalya renewed several times).'),
  ('family',       'Family and friends',        0, 'flexible',    null, null,         0,  null, 'No interest and no schedule. Trust is the cost.')
on conflict (product) do update set label = excluded.label, annual_rate = excluded.annual_rate, structure = excluded.structure,
  term_default = excluded.term_default, term_options = excluded.term_options, late_fee_pct = excluded.late_fee_pct,
  rollover_fee_pct = excluded.rollover_fee_pct, note = excluded.note;
alter table lender_products enable row level security;
drop policy if exists "read lender_products" on lender_products;
create policy "read lender_products" on lender_products for select using (true);
revoke insert, update, delete, truncate on lender_products from anon, authenticated;

-- Which story loans are billed by this system (payday/medical) and which keep their own story due date
create table if not exists story_loan_products (
  story_tag text primary key,
  product text not null,                          -- a lender_products key, or 'story' (story-managed)
  term_months int
);
insert into story_loan_products (story_tag, product, term_months) values
  ('chola_loan', 'story', null), ('phone_loan', 'story', null), ('medical_quick_loan', 'payday', 1)
on conflict (story_tag) do update set product = excluded.product, term_months = excluded.term_months;
alter table story_loan_products enable row level security;
revoke all on story_loan_products from anon, authenticated;

-- The lesson's monthly payment: (principal + principal x rate x years) / months
create or replace function debt_installment(p numeric, rate numeric, n int) returns numeric
language sql immutable as $$ select round((p + p * rate / 100.0 * n / 12.0) / n, 2) $$;

-- Fill in the schedule when a story loan is created (the story engine inserts debts directly)
create or replace function debts_set_schedule() returns trigger
language plpgsql as $$
declare sl story_loan_products; lp lender_products;
begin
  if new.story_tag is null then return new; end if;
  select * into sl from story_loan_products where story_tag = new.story_tag;
  if not found then return new; end if;
  if sl.product = 'story' then
    new.structure := 'story';
    new.product := case when new.lender_kind = 'microfinance' then 'microfinance' else 'payday' end;
  else
    select * into lp from lender_products where product = sl.product;
    new.product := lp.product; new.structure := lp.structure; new.annual_interest_rate := lp.annual_rate;
    new.term_months := sl.term_months; new.last_accrual_at := now();
    if lp.structure = 'installment' then new.installment := debt_installment(new.principal, lp.annual_rate, sl.term_months); end if;
  end if;
  return new;
end $$;
drop trigger if exists debts_set_schedule_t on debts;
create trigger debts_set_schedule_t before insert on debts for each row execute function debts_set_schedule();

-- Interest-free legacy loans keep behaving as before ('flexible'); new ones get their product.

-- ─────────────────────────────────────────────
-- QUOTE: "What does a loan really cost?" exactly as the lesson's calculator
-- ─────────────────────────────────────────────
create or replace function debt_quote(p_product text, p_amount numeric, p_term_months int default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare lp lender_products; n int; v_int numeric; v_total numeric;
begin
  select * into lp from lender_products where product = p_product;
  if not found then return jsonb_build_object('error', 'bad_product'); end if;
  if p_amount is null or p_amount <= 0 then return jsonb_build_object('error', 'bad_amount'); end if;
  n := coalesce(p_term_months, lp.term_default, 1);
  if lp.term_options is not null and not (n = any (lp.term_options)) then return jsonb_build_object('error', 'bad_term'); end if;
  v_int := round(p_amount * lp.annual_rate / 100.0 * n / 12.0, 2);
  v_total := p_amount + v_int;
  return jsonb_build_object('product', lp.product, 'label', lp.label, 'rate', lp.annual_rate, 'term_months', n, 'structure', lp.structure,
    'total_interest', v_int, 'total_repay', v_total,
    'monthly_payment', case when lp.structure = 'installment' then round(v_total / n, 2) when lp.structure = 'bullet' then v_total else 0 end,
    'rollover_fee_pct', lp.rollover_fee_pct, 'lesson', lp.lesson_id, 'terms', lp.term_options);
end $$;

-- ─────────────────────────────────────────────
-- BORROW
-- ─────────────────────────────────────────────
create or replace function debt_borrow(p_product text, p_amount numeric, p_term_months int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); lp lender_products; q jsonb; v_kind text; v_ceiling numeric; v_used numeric; v_left numeric; v_id bigint; n int;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  if not story_feature_open(uid, 'debts') then return jsonb_build_object('error', 'locked'); end if;
  q := debt_quote(p_product, p_amount, p_term_months);
  if q ? 'error' then return q; end if;
  select * into lp from lender_products where product = p_product;
  n := (q->>'term_months')::int;
  v_kind := case p_product when 'bank' then 'bank' when 'microfinance' then 'microfinance' else 'informal' end;
  if p_product = 'payday' then
    v_ceiling := sim_cfg('debt_payday_limit', 2000);
    select coalesce(sum(outstanding_balance), 0) into v_used from debts where profile_id = uid and product = 'payday' and status = 'active';
  elsif p_product = 'family' then
    v_ceiling := story_lender_ceiling(uid, 'informal');
    select coalesce(sum(outstanding_balance), 0) into v_used from debts where profile_id = uid and lender_kind = 'informal' and annual_interest_rate = 0 and status = 'active';
  else
    v_ceiling := story_lender_ceiling(uid, v_kind);
    select coalesce(sum(outstanding_balance), 0) into v_used from debts where profile_id = uid and lender_kind = v_kind and status = 'active';
  end if;
  v_left := greatest(0, v_ceiling - v_used);
  if p_amount > v_left then return jsonb_build_object('error', 'over_limit', 'limit', v_left); end if;

  insert into debts (profile_id, lender_kind, principal, outstanding_balance, annual_interest_rate, product, structure, term_months, installment, last_accrual_at)
  values (uid, v_kind, p_amount, p_amount, lp.annual_rate, lp.product, lp.structure, case when lp.structure = 'flexible' then null else n end,
          case when lp.structure = 'installment' then debt_installment(p_amount, lp.annual_rate, n) end, now())
  returning id into v_id;
  perform adjust_cash_balance(uid, p_amount, 'debt_drawdown', 'debts', v_id);
  return jsonb_build_object('ok', true, 'debt_id', v_id, 'quote', q);
end $$;

-- The old two-argument call keeps working, now with the lesson's rates and a default term
create or replace function story_borrow(p_kind text, p_amount numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  return debt_borrow(case p_kind when 'bank' then 'bank' when 'microfinance' then 'microfinance' when 'informal' then 'family' else p_kind end, p_amount, null);
end $$;

-- ─────────────────────────────────────────────
-- PAYMENTS
-- ─────────────────────────────────────────────
create or replace function debt_apply_payment(p uuid, p_debt_id bigint, p_amount numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d debts; v_cash numeric; v_amt numeric; v_due_cleared numeric; v_new_due numeric; v_on_time boolean; v_new_bal numeric;
  v_grace numeric := greatest(sim_cfg('real_days_per_game_year', 14) / 12.0, 0.1) * sim_cfg('debt_grace_months', 1);
begin
  select * into d from debts where id = p_debt_id and profile_id = p and status = 'active' for update;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  v_amt := least(round(coalesce(p_amount, 0), 2), d.outstanding_balance);
  if v_amt <= 0 then return jsonb_build_object('error', 'bad_amount'); end if;
  select cash_balance into v_cash from profiles where id = p for update;
  if v_amt > v_cash then return jsonb_build_object('error', 'insufficient_cash', 'cash', v_cash); end if;

  perform adjust_cash_balance(p, -v_amt, 'debt_repayment', 'debts', d.id);
  v_due_cleared := least(v_amt, d.due_amount);
  v_new_due := d.due_amount - v_due_cleared;
  v_on_time := d.due_amount > 0 and v_due_cleared >= d.due_amount - 0.005
               and (d.due_since is null or now() <= d.due_since + make_interval(secs => v_grace * 86400));
  v_new_bal := greatest(0, d.outstanding_balance - v_amt);
  update debts set outstanding_balance = v_new_bal, due_amount = v_new_due,
         due_since = case when v_new_due <= 0.005 then null else due_since end,
         status = case when v_new_bal <= 0.005 then 'repaid' else 'active' end
   where id = d.id;
  if v_on_time then perform story_set_flag(p, 'debt_paid_on_time', null); end if;
  if v_new_bal <= 0.005 then
    perform story_set_flag(p, 'debt_cleared', null);
    -- Module 1.2: consistently paying on time is the strongest signal of reliability. Clean repayment raises the ceiling.
    if d.product = 'microfinance' and d.missed_count = 0 then perform story_set_flag(p, 'repaid_microfinance_on_time', null); end if;
  end if;
  return jsonb_build_object('ok', true, 'paid', v_amt, 'repaid', v_new_bal <= 0.005, 'balance', v_new_bal);
end $$;

-- The learner-facing repay: scheduled debts go through the schedule, everything else behaves as before
do $$ begin
  if position('sim_repay_core' in pg_get_functiondef('sim_repay(bigint,numeric)'::regprocedure)) = 0 then
    drop function if exists sim_repay_core(bigint, numeric);
    alter function sim_repay(bigint, numeric) rename to sim_repay_core;
  end if;
end $$;
create or replace function sim_repay(p_debt_id bigint, p_amount numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_s text;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  select structure into v_s from debts where id = p_debt_id and profile_id = uid and status = 'active';
  if v_s in ('installment', 'bullet') then return debt_apply_payment(uid, p_debt_id, p_amount); end if;
  return sim_repay_core(p_debt_id, p_amount);
end $$;

-- ─────────────────────────────────────────────
-- BILLING AND INTEREST (one pass per learner; called by stress_tick, debt_overview and the plan functions)
--   each game month: interest is added to the balance owed, then the scheduled payment is billed
--   a bill not paid within the grace period is MISSED: a late fee is added; the third missed payment is default
-- ─────────────────────────────────────────────
create or replace function debt_tick(p uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  d record; lp lender_products; v_gm numeric := greatest(sim_cfg('real_days_per_game_year', 14) / 12.0, 0.1);
  v_grace_s numeric := greatest(sim_cfg('real_days_per_game_year', 14) / 12.0, 0.1) * sim_cfg('debt_grace_months', 1) * 86400;
  v_n int; v_bal numeric; v_due numeric; v_since timestamptz; v_cycles int; v_acc timestamptz; v_missed int; v_status text;
  v_autopay boolean; v_cash numeric; v_fee numeric;
begin
  select debt_autopay into v_autopay from profiles where id = p;
  -- pass 1: add interest and raise bills
  for d in select * from debts where profile_id = p and status = 'active' and structure in ('installment', 'bullet') order by id loop
    v_bal := d.outstanding_balance; v_due := d.due_amount; v_since := d.due_since; v_cycles := d.billed_cycles; v_acc := d.last_accrual_at; v_n := 0;
    while v_acc + make_interval(secs => v_gm * 86400) <= now() and v_n < 48 loop
      v_n := v_n + 1;
      v_bal := v_bal + round(v_bal * d.annual_interest_rate / 1200.0, 2);
      v_acc := v_acc + make_interval(secs => v_gm * 86400);
      v_cycles := v_cycles + 1;
      if d.structure = 'installment' then
        if v_cycles >= d.term_months then v_due := v_bal; else v_due := least(v_bal, v_due + d.installment); end if;
      elsif v_cycles >= d.term_months * (d.rollovers + 1) then
        v_due := v_bal;
      end if;
      if v_due > 0 and v_since is null then v_since := v_acc; end if;
    end loop;
    update debts set outstanding_balance = v_bal, due_amount = v_due, due_since = v_since, billed_cycles = v_cycles, last_accrual_at = v_acc where id = d.id;
  end loop;

  -- standing order: pay what is due, oldest first, while cash lasts
  if v_autopay then
    for d in select * from debts where profile_id = p and status = 'active' and due_amount > 0 order by due_since, id loop
      select cash_balance into v_cash from profiles where id = p;
      exit when v_cash <= 0;
      perform debt_apply_payment(p, d.id, least(d.due_amount, v_cash));
    end loop;
  end if;

  -- pass 2: missed payments (at most one per debt per visit, so a learner who returns gets a fresh grace period)
  for d in select * from debts where profile_id = p and status = 'active' and due_amount > 0 and due_since is not null
              and now() > due_since + make_interval(secs => v_grace_s) loop
    select * into lp from lender_products where product = d.product;
    v_fee := round(d.due_amount * coalesce(lp.late_fee_pct, 5) / 100.0, 2);
    v_missed := d.missed_count + 1;
    v_status := case when v_missed >= sim_cfg('debt_default_after_missed', 3)::int then 'defaulted' else 'active' end;
    update debts set outstanding_balance = outstanding_balance + v_fee, due_amount = due_amount + v_fee, due_since = now(),
           missed_count = v_missed, status = v_status where id = d.id;
    perform story_set_flag(p, 'debt_missed_payment', null);
    if v_status = 'defaulted' then
      perform story_set_flag(p, 'debt_defaulted_schedule', null);
      if d.product = 'microfinance' then perform story_set_flag(p, 'defaulted_microfinance', null); end if;   -- lowers the microfinance ceiling (lender_limit_rules)
    end if;
  end loop;
end $$;

-- ─────────────────────────────────────────────
-- THE LESSON'S AVALANCHE vs SNOWBALL SIMULATION
-- Input: [{id, balance, rate, min}], monthly budget, strategy: minimum | avalanche | snowball
-- Each month: add interest to every debt, pay minimums, then give the rest of the budget to the priority debt
-- (and on to the next if it is cleared). 'minimum' pays only minimums (no extra, no rolling of freed money).
-- Returns { months (null = never), total_interest, first_cleared_month, first_month: [{id, pay}], order: [ids] }
-- ─────────────────────────────────────────────
create or replace function debt_run_strategy(p_debts jsonb, p_budget numeric, p_strategy text)
returns jsonb language plpgsql immutable as $$
declare
  n int := jsonb_array_length(p_debts); ids bigint[]; bal numeric[]; rt numeric[]; mn numeric[]; pay1 numeric[];
  i int; j int; k int; months int := 0; total_int numeric := 0; first_cleared int := null; remaining numeric; v_pay numeric; ord int[]; tmp int;
  alive boolean; v_first_order jsonb := '[]'::jsonb; v_fm jsonb := '[]'::jsonb; target int; extra numeric;
begin
  if n = 0 then return jsonb_build_object('months', 0, 'total_interest', 0, 'first_cleared_month', null, 'first_month', '[]'::jsonb, 'order', '[]'::jsonb); end if;
  for i in 0 .. n - 1 loop
    ids[i + 1] := (p_debts->i->>'id')::bigint; bal[i + 1] := (p_debts->i->>'balance')::numeric;
    rt[i + 1] := (p_debts->i->>'rate')::numeric; mn[i + 1] := (p_debts->i->>'min')::numeric; pay1[i + 1] := 0;
  end loop;
  loop
    alive := false; for i in 1 .. n loop if bal[i] > 0.01 then alive := true; end if; end loop;
    exit when not alive or months >= 600;
    months := months + 1;
    for i in 1 .. n loop
      if bal[i] > 0 then total_int := total_int + bal[i] * rt[i] / 1200.0; bal[i] := bal[i] + bal[i] * rt[i] / 1200.0; end if;
    end loop;
    remaining := case when p_strategy = 'minimum' then 0 else p_budget end;
    for i in 1 .. n loop
      if bal[i] > 0 then
        v_pay := least(mn[i], bal[i]); bal[i] := bal[i] - v_pay; remaining := remaining - v_pay;
        if months = 1 then pay1[i] := pay1[i] + v_pay; end if;
      end if;
    end loop;
    if p_strategy <> 'minimum' then
      loop
        exit when remaining <= 0.01;
        target := null;
        for i in 1 .. n loop
          if bal[i] > 0.01 then
            if target is null then target := i;
            elsif p_strategy = 'avalanche' and (rt[i] > rt[target] or (rt[i] = rt[target] and bal[i] < bal[target])) then target := i;
            elsif p_strategy = 'snowball' and (bal[i] < bal[target] or (bal[i] = bal[target] and rt[i] > rt[target])) then target := i;
            end if;
          end if;
        end loop;
        exit when target is null;
        extra := least(remaining, bal[target]); bal[target] := bal[target] - extra; remaining := remaining - extra;
        if months = 1 then pay1[target] := pay1[target] + extra; end if;
      end loop;
    end if;
    if first_cleared is null then
      for i in 1 .. n loop if bal[i] <= 0.01 then first_cleared := months; end if; end loop;
    end if;
  end loop;
  alive := false; for i in 1 .. n loop if bal[i] > 0.01 then alive := true; end if; end loop;
  -- priority order at the start (for display)
  for i in 1 .. n loop ord[i] := i; end loop;
  for i in 1 .. n - 1 loop for j in i + 1 .. n loop
    if (p_strategy = 'avalanche' and (rt[ord[j]] > rt[ord[i]] or (rt[ord[j]] = rt[ord[i]] and (p_debts->(ord[j]-1)->>'balance')::numeric < (p_debts->(ord[i]-1)->>'balance')::numeric)))
       or (p_strategy = 'snowball' and ((p_debts->(ord[j]-1)->>'balance')::numeric < (p_debts->(ord[i]-1)->>'balance')::numeric
            or ((p_debts->(ord[j]-1)->>'balance')::numeric = (p_debts->(ord[i]-1)->>'balance')::numeric and rt[ord[j]] > rt[ord[i]]))) then
      tmp := ord[i]; ord[i] := ord[j]; ord[j] := tmp;
    end if;
  end loop; end loop;
  for i in 1 .. n loop v_first_order := v_first_order || to_jsonb(ids[ord[i]]); end loop;
  for i in 1 .. n loop v_fm := v_fm || jsonb_build_array(jsonb_build_object('id', ids[i], 'pay', round(pay1[i], 2))); end loop;
  return jsonb_build_object('months', case when alive then null else months end, 'total_interest', round(total_int, 2),
    'first_cleared_month', first_cleared,
    'first_month', v_fm, 'order', v_first_order);
end $$;

-- The debts that take part in a payoff plan (story-managed loans keep their story due dates)
create or replace function debt_plan_inputs(p uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id, 'label', coalesce(lp.label, initcap(d.lender_kind)), 'product', d.product, 'balance', d.outstanding_balance, 'rate', d.annual_interest_rate,
    'min', least(d.outstanding_balance, greatest(
        case d.structure when 'installment' then d.installment
                         when 'bullet' then d.outstanding_balance / greatest(1, coalesce(d.term_months, 1) * (d.rollovers + 1) - d.billed_cycles)
                         else 0 end, d.due_amount))) order by d.id), '[]'::jsonb)
  from debts d left join lender_products lp on lp.product = d.product
  where d.profile_id = p and d.status = 'active' and d.structure <> 'story' and d.outstanding_balance > 0.01
$$;

-- ─────────────────────────────────────────────
-- PLAN: compare minimum / avalanche / snowball for a monthly budget (the lesson's tool, on the learner's real debts)
-- ─────────────────────────────────────────────
create or replace function debt_plan(p_budget numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_in jsonb; v_min numeric; v_m jsonb; v_a jsonb; v_s jsonb; v_cash numeric;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  perform debt_tick(uid);
  v_in := debt_plan_inputs(uid);
  if jsonb_array_length(v_in) = 0 then return jsonb_build_object('error', 'no_debts'); end if;
  select coalesce(sum((x->>'min')::numeric), 0) into v_min from jsonb_array_elements(v_in) x;
  select cash_balance into v_cash from profiles where id = uid;
  if p_budget is null or p_budget < v_min then
    return jsonb_build_object('error', 'below_minimums', 'min_total', round(v_min, 2), 'debts', v_in);
  end if;
  v_m := debt_run_strategy(v_in, v_min, 'minimum');
  v_a := debt_run_strategy(v_in, p_budget, 'avalanche');
  v_s := debt_run_strategy(v_in, p_budget, 'snowball');
  return jsonb_build_object('debts', v_in, 'budget', p_budget, 'min_total', round(v_min, 2), 'cash', v_cash,
    'minimum', v_m, 'avalanche', v_a, 'snowball', v_s,
    'avalanche_saves', greatest(0, round((v_s->>'total_interest')::numeric - (v_a->>'total_interest')::numeric, 2)),
    'extra_saves_vs_minimum', greatest(0, round((v_m->>'total_interest')::numeric - (v_a->>'total_interest')::numeric, 2)));
end $$;

-- Run this month's plan: minimums on every debt, then the rest to the priority debt. Once per game month.
create or replace function debt_execute_plan(p_budget numeric, p_strategy text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); pr profiles; v_in jsonb; v_min numeric; v_run jsonb; a jsonb; v_total numeric := 0; r jsonb;
  v_gm numeric := greatest(sim_cfg('real_days_per_game_year', 14) / 12.0, 0.1); v_next timestamptz;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  if p_strategy not in ('minimum', 'avalanche', 'snowball') then return jsonb_build_object('error', 'bad_strategy'); end if;
  select * into pr from profiles where id = uid for update;
  v_next := pr.debt_plan_at + make_interval(secs => v_gm * 86400 * sim_cfg('debt_plan_cooldown_months', 1));
  if pr.debt_plan_at is not null and now() < v_next then return jsonb_build_object('error', 'already_done', 'next_at', v_next); end if;
  perform debt_tick(uid);
  v_in := debt_plan_inputs(uid);
  if jsonb_array_length(v_in) = 0 then return jsonb_build_object('error', 'no_debts'); end if;
  select coalesce(sum((x->>'min')::numeric), 0) into v_min from jsonb_array_elements(v_in) x;
  if p_budget is null or p_budget < v_min then return jsonb_build_object('error', 'below_minimums', 'min_total', round(v_min, 2)); end if;
  v_run := debt_run_strategy(v_in, p_budget, p_strategy);
  select coalesce(sum((x->>'pay')::numeric), 0) into v_total from jsonb_array_elements(v_run->'first_month') x;
  if v_total > pr.cash_balance then return jsonb_build_object('error', 'insufficient_cash', 'needed', v_total, 'cash', pr.cash_balance); end if;
  for a in select * from jsonb_array_elements(v_run->'first_month') loop
    if (a->>'pay')::numeric > 0 then r := debt_apply_payment(uid, (a->>'id')::bigint, (a->>'pay')::numeric); end if;
  end loop;
  update profiles set debt_plan_at = now(), debt_strategy = p_strategy where id = uid;
  if p_strategy = 'avalanche' then perform story_set_flag(uid, 'used_avalanche', null);
  elsif p_strategy = 'snowball' then perform story_set_flag(uid, 'used_snowball', null); end if;
  return jsonb_build_object('ok', true, 'paid', round(v_total, 2), 'strategy', p_strategy, 'allocations', v_run->'first_month');
end $$;

-- Pay everything that is due now, oldest first
create or replace function debt_pay_due()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d record; v_cash numeric; v_paid numeric := 0; v_left numeric := 0; r jsonb;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  perform debt_tick(uid);
  for d in select * from debts where profile_id = uid and status = 'active' and due_amount > 0 order by due_since, id loop
    select cash_balance into v_cash from profiles where id = uid;
    if v_cash >= d.due_amount then r := debt_apply_payment(uid, d.id, d.due_amount); v_paid := v_paid + d.due_amount;
    else v_left := v_left + d.due_amount; end if;
  end loop;
  return jsonb_build_object('ok', true, 'paid', round(v_paid, 2), 'still_due', round(v_left, 2));
end $$;

create or replace function debt_set_prefs(p_strategy text, p_autopay boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  if p_strategy not in ('minimum', 'avalanche', 'snowball') then return jsonb_build_object('error', 'bad_strategy'); end if;
  update profiles set debt_strategy = p_strategy, debt_autopay = coalesce(p_autopay, false) where id = uid;
  return jsonb_build_object('ok', true);
end $$;

-- Renew a payday loan: a fee is added and the due date moves back one term (the trap in Bwalya's story)
create or replace function debt_rollover(p_debt_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d debts; lp lender_products; v_fee numeric;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  perform debt_tick(uid);
  select * into d from debts where id = p_debt_id and profile_id = uid and status = 'active' for update;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  select * into lp from lender_products where product = d.product;
  if d.structure <> 'bullet' or lp.rollover_fee_pct is null then return jsonb_build_object('error', 'not_renewable'); end if;
  if d.due_amount <= 0 then return jsonb_build_object('error', 'not_due_yet'); end if;
  v_fee := round(d.outstanding_balance * lp.rollover_fee_pct / 100.0, 2);
  update debts set outstanding_balance = outstanding_balance + v_fee, due_amount = 0, due_since = null, rollovers = rollovers + 1 where id = d.id;
  perform story_set_flag(uid, 'debt_rolled_over', null);
  return jsonb_build_object('ok', true, 'fee', v_fee, 'new_balance', d.outstanding_balance + v_fee, 'rollovers', d.rollovers + 1);
end $$;

-- ─────────────────────────────────────────────
-- SCHEDULE: month by month if only the scheduled payments are made (a projection, changes nothing)
-- ─────────────────────────────────────────────
create or replace function debt_schedule(p_debt_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); d debts; bal numeric; i int := 0; v_int numeric; v_pay numeric; v_tot_int numeric := 0; rows jsonb := '[]'::jsonb;
  v_mins numeric; v_left_months int;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  perform debt_tick(uid);
  select * into d from debts where id = p_debt_id and profile_id = uid;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  bal := d.outstanding_balance;
  if d.structure not in ('installment', 'bullet') then return jsonb_build_object('rows', '[]'::jsonb, 'note', 'flexible'); end if;
  v_left_months := case d.structure when 'installment' then greatest(1, d.term_months - d.billed_cycles) else greatest(1, d.term_months * (d.rollovers + 1) - d.billed_cycles) end;
  while bal > 0.01 and i < 60 loop
    i := i + 1;
    v_int := round(bal * d.annual_interest_rate / 1200.0, 2); bal := bal + v_int; v_tot_int := v_tot_int + v_int;
    v_pay := case when d.structure = 'installment' and i < v_left_months then least(bal, d.installment) else case when i >= v_left_months then bal else 0 end end;
    bal := bal - v_pay;
    rows := rows || jsonb_build_array(jsonb_build_object('month', i, 'interest', v_int, 'payment', round(v_pay, 2), 'balance', round(bal, 2)));
  end loop;
  return jsonb_build_object('rows', rows, 'total_interest', round(v_tot_int, 2), 'months', i);
end $$;

-- ─────────────────────────────────────────────
-- OVERVIEW for the Debts page
-- ─────────────────────────────────────────────
create or replace function debt_overview()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); pr profiles; v_gm numeric := greatest(sim_cfg('real_days_per_game_year', 14) / 12.0, 0.1);
  v_grace numeric := sim_cfg('debt_grace_months', 1); v_debts jsonb; v_next timestamptz;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  perform debt_tick(uid);
  select * into pr from profiles where id = uid;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', d.id, 'product', d.product, 'label', coalesce(lp.label, initcap(d.lender_kind)), 'structure', d.structure, 'status', d.status,
      'principal', d.principal, 'balance', d.outstanding_balance, 'rate', d.annual_interest_rate, 'term_months', d.term_months,
      'installment', d.installment, 'due_amount', d.due_amount, 'due_since', d.due_since,
      'overdue', d.due_amount > 0 and d.due_since is not null and now() > d.due_since + make_interval(secs => v_gm * v_grace * 86400),
      'next_due_at', case d.structure
          when 'installment' then d.created_at + make_interval(secs => v_gm * 86400 * least(d.billed_cycles + 1, d.term_months))
          when 'bullet' then d.created_at + make_interval(secs => v_gm * 86400 * d.term_months * (d.rollovers + 1)) end,
      'months_left', case d.structure when 'installment' then greatest(0, d.term_months - d.billed_cycles)
                                      when 'bullet' then greatest(0, d.term_months * (d.rollovers + 1) - d.billed_cycles) end,
      'missed_count', d.missed_count, 'rollovers', d.rollovers, 'story_managed', d.structure = 'story',
      'can_rollover', d.structure = 'bullet' and lp.rollover_fee_pct is not null and d.due_amount > 0,
      'rollover_fee', case when lp.rollover_fee_pct is not null then round(d.outstanding_balance * lp.rollover_fee_pct / 100.0, 2) end,
      'created_at', d.created_at) order by (d.status = 'active') desc, d.id desc), '[]'::jsonb)
    into v_debts
  from debts d left join lender_products lp on lp.product = d.product
  where d.profile_id = uid and d.status in ('active', 'defaulted');
  v_next := pr.debt_plan_at + make_interval(secs => v_gm * 86400 * sim_cfg('debt_plan_cooldown_months', 1));
  return jsonb_build_object('cash', pr.cash_balance, 'strategy', pr.debt_strategy, 'autopay', pr.debt_autopay, 'debts', v_debts,
    'plan_next_at', case when pr.debt_plan_at is not null and now() < v_next then v_next end,
    'due_total', (select coalesce(sum(due_amount), 0) from debts where profile_id = uid and status = 'active'),
    'monthly_min', (select coalesce(sum((x->>'min')::numeric), 0) from jsonb_array_elements(debt_plan_inputs(uid)) x),
    'products', (select jsonb_agg(jsonb_build_object('product', product, 'label', label, 'rate', annual_rate, 'structure', structure,
                  'term_default', term_default, 'terms', term_options, 'rollover_fee_pct', rollover_fee_pct, 'note', note) order by annual_rate) from lender_products),
    'limits', story_borrow_limits(), 'payday_left', greatest(0, sim_cfg('debt_payday_limit', 2000) - (select coalesce(sum(outstanding_balance), 0) from debts where profile_id = uid and product = 'payday' and status = 'active')));
end $$;

-- ─────────────────────────────────────────────
-- PERMISSIONS: only these are callable from the browser
-- ─────────────────────────────────────────────
revoke all on function debt_installment(numeric, numeric, int) from public, anon, authenticated;
revoke all on function debt_tick(uuid) from public, anon, authenticated;
revoke all on function debt_apply_payment(uuid, bigint, numeric) from public, anon, authenticated;
revoke all on function debt_run_strategy(jsonb, numeric, text) from public, anon, authenticated;
revoke all on function debt_plan_inputs(uuid) from public, anon, authenticated;
revoke all on function sim_repay_core(bigint, numeric) from public, anon, authenticated;
revoke all on function debts_set_schedule() from public, anon, authenticated;
do $$ declare f text; begin
  foreach f in array array['debt_quote(text,numeric,int)', 'debt_borrow(text,numeric,int)', 'debt_overview()', 'debt_plan(numeric)',
      'debt_execute_plan(numeric,text)', 'debt_pay_due()', 'debt_set_prefs(text,boolean)', 'debt_rollover(bigint)', 'debt_schedule(bigint)',
      'story_borrow(text,numeric)', 'sim_repay(bigint,numeric)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
