-- FinLit Zambia — Financial Character Simulator
-- Supabase / Postgres schema, v1
-- All money values in fake kwacha (numeric, 2dp). All monetary history is
-- append-only (ledger rows), never edited in place, so net worth at any
-- past date can always be reconstructed.

-- ─────────────────────────────────────────────
-- PROFILES
-- One row per learner, created on first login. `id` matches Supabase Auth's
-- own user id (auth.users.id) — do not invent a separate id here.
-- ─────────────────────────────────────────────
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  created_at timestamptz not null default now(),

  -- Derived/cached figures, recomputed periodically — never the source of
  -- truth (the ledgers are), just here so the dashboard loads fast.
  cash_balance numeric(14,2) not null default 10000.00,
  reputation_score numeric(6,2) not null default 50.00 -- 0–100 scale
);

-- ─────────────────────────────────────────────
-- CASH LEDGER
-- Every movement of liquid cash. Buying a share = one negative row here.
-- Selling a share = one positive row. Salary, venture income, debt
-- repayments, everything liquid passes through this table.
-- ─────────────────────────────────────────────
create table cash_ledger (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  amount numeric(14,2) not null,       -- positive = inflow, negative = outflow
  reason text not null,                -- 'trade_buy' | 'trade_sell' | 'salary'
                                        -- | 'venture_income' | 'venture_cost'
                                        -- | 'debt_drawdown' | 'debt_repayment'
                                        -- | 'interest_charge' | 'manual_adjustment'
  related_table text,                  -- e.g. 'trades', 'ventures', 'debts'
  related_id bigint,                   -- id of the row in related_table
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- INSTRUMENTS
-- The fixed list of things a learner can invest in. Seeded once by you,
-- not created by learners. Price is updated on a schedule (manual or a
-- simple randomized-walk script), never edited retroactively.
-- ─────────────────────────────────────────────
create table instruments (
  id bigint generated always as identity primary key,
  ticker text not null unique,         -- 'ZSUGAR', 'CECA', 'DCZ', 'REIZ'...
  name text not null,
  kind text not null,                  -- 'share' | 't_bill' | 'bond' | 'money_market'
  current_price numeric(14,4) not null,
  is_active boolean not null default true
);

create table instrument_price_history (
  id bigint generated always as identity primary key,
  instrument_id bigint not null references instruments(id) on delete cascade,
  price numeric(14,4) not null,
  recorded_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- HOLDINGS & TRADES
-- `holdings` is a derived/cached snapshot of current position size —
-- `trades` is the source of truth (append-only). A trigger or scheduled
-- job keeps holdings in sync; never write to holdings directly.
-- ─────────────────────────────────────────────
create table trades (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  instrument_id bigint not null references instruments(id),
  side text not null,                  -- 'buy' | 'sell'
  quantity numeric(14,4) not null,
  price_at_trade numeric(14,4) not null,
  total_value numeric(14,2) not null,  -- quantity * price_at_trade
  created_at timestamptz not null default now()
);

create table holdings (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  instrument_id bigint not null references instruments(id),
  quantity numeric(14,4) not null default 0,
  avg_buy_price numeric(14,4) not null default 0,
  unique (profile_id, instrument_id)
);

-- ─────────────────────────────────────────────
-- VENTURES
-- A learner's fake small business. Has its own mini P&L via
-- venture_events, separate from the cash_ledger (though income/costs
-- that touch real spendable cash also create a matching cash_ledger row).
-- ─────────────────────────────────────────────
create table ventures (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  name text not null,
  category text not null,              -- 'retail' | 'services' | 'agriculture' | ...
  status text not null default 'active', -- 'active' | 'closed' | 'failed'
  starting_capital numeric(14,2) not null,
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create table venture_events (
  id bigint generated always as identity primary key,
  venture_id bigint not null references ventures(id) on delete cascade,
  kind text not null,                  -- 'revenue' | 'expense' | 'shock' (e.g. theft, spoilage)
  amount numeric(14,2) not null,       -- positive or negative
  description text,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- DEBTS
-- Any borrowed fake money. Interest accrues via scheduled interest_charge
-- rows in cash_ledger (negative, reason='interest_charge', related to this).
-- ─────────────────────────────────────────────
create table debts (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  lender_kind text not null,           -- 'bank' | 'microfinance' | 'informal'
  principal numeric(14,2) not null,
  outstanding_balance numeric(14,2) not null,
  annual_interest_rate numeric(6,3) not null, -- e.g. 28.000 for 28%
  status text not null default 'active', -- 'active' | 'repaid' | 'defaulted'
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- REPUTATION EVENTS
-- Every action that nudges the visible Reputation score, append-only, so
-- you always have an audit trail of *why* someone's score is what it is.
-- ─────────────────────────────────────────────
create table reputation_events (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  delta numeric(6,2) not null,         -- e.g. +2 for consistent saving, -5 for default
  reason text not null,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- NET WORTH SNAPSHOTS
-- Precomputed daily (or on-login) rollup: cash + holdings value +
-- venture value − outstanding debt. This is what powers the "net worth
-- over time" chart without recalculating from scratch every page load.
-- ─────────────────────────────────────────────
create table net_worth_snapshots (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  cash numeric(14,2) not null,
  investments_value numeric(14,2) not null,
  ventures_value numeric(14,2) not null,
  debt_outstanding numeric(14,2) not null,
  net_worth numeric(14,2) not null,
  snapshot_date date not null,
  unique (profile_id, snapshot_date)
);

-- ─────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- Learners can only ever read/write their own rows. This is Supabase's
-- standard security model — must be enabled or the API is wide open.
-- ─────────────────────────────────────────────
alter table profiles enable row level security;
alter table cash_ledger enable row level security;
alter table trades enable row level security;
alter table holdings enable row level security;
alter table ventures enable row level security;
alter table venture_events enable row level security;
alter table debts enable row level security;
alter table reputation_events enable row level security;
alter table net_worth_snapshots enable row level security;

create policy "own profile" on profiles for all using (auth.uid() = id);
create policy "own cash ledger" on cash_ledger for all using (auth.uid() = profile_id);
create policy "own trades" on trades for all using (auth.uid() = profile_id);
create policy "own holdings" on holdings for all using (auth.uid() = profile_id);
create policy "own ventures" on ventures for all using (auth.uid() = profile_id);
create policy "own venture events" on venture_events for all
  using (auth.uid() = (select profile_id from ventures where ventures.id = venture_id));
create policy "own debts" on debts for all using (auth.uid() = profile_id);
create policy "own reputation events" on reputation_events for all using (auth.uid() = profile_id);
create policy "own net worth" on net_worth_snapshots for all using (auth.uid() = profile_id);

-- instruments and instrument_price_history are public read-only (no RLS
-- restriction needed beyond default deny-write to anon role).
alter table instruments enable row level security;
create policy "anyone can read instruments" on instruments for select using (true);
alter table instrument_price_history enable row level security;
create policy "anyone can read price history" on instrument_price_history for select using (true);
