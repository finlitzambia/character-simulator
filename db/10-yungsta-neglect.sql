-- FinLit Zambia — Financial Character Simulator
-- 10-yungsta-neglect.sql  (safe to re-run)  Run AFTER 09.
--
-- WHEN YOU DON'T SHOW UP, THE YUNGSTA MAKES BAD DECISIONS.
-- A "check-in" is any real guidance in a day: finishing a lesson (via the bridge), answering
-- the yungsta's question, or settling a decision. If a day passes with none, the yungsta, left
-- alone, makes a costly mistake and loses a share of the learner's cash. When the learner returns
-- they see what happened and can "debrief": a correct answer wins back part of the loss.
--
-- Fair-play rules (all tunable in sim_config):
--   * nothing happens until the learner has finished a lesson, plus 3 free days
--   * at most 3 missed days are charged per return (older ones are forgiven)
--   * 10% of current cash per missed day (so the worst case is about 27%)
--   * a correct debrief wins back 50% of that mistake
--   * the learner can pause for 3 days once every 14 days (illness, exams, travel)

insert into sim_config (key, value) values
  ('neglect_loss_pct', '0.10'), ('neglect_max_days', '3'), ('neglect_free_days', '3'),
  ('neglect_recover_pct', '0.5'), ('pause_max_days', '3'), ('pause_cooldown_days', '14')
on conflict (key) do nothing;

alter table profiles add column if not exists last_guided_on date;   -- last day the learner guided the yungsta
alter table profiles add column if not exists neglect_through date;  -- last day already assessed
alter table profiles add column if not exists paused_until date;
alter table profiles add column if not exists last_pause_on date;

create table if not exists yungsta_blunders (
  id bigint generated always as identity primary key,
  blunder_key text not null unique,
  title text not null,
  story text not null,
  loss_mult numeric(4,2) not null default 1,
  debrief_question text not null,
  debrief_options jsonb not null,      -- [{"text":..., "fb":...}]
  correct_index int not null,
  recovery_text text not null,
  is_active boolean not null default true
);

create table if not exists learner_blunders (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  blunder_id bigint not null references yungsta_blunders(id),
  missed_on date not null,
  amount numeric(14,2) not null,
  option_order int[] not null,
  status text not null default 'new',     -- new | debriefed | skipped
  recovered numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  debriefed_at timestamptz
);
create index if not exists learner_blunders_lookup on learner_blunders (profile_id, status);

alter table yungsta_blunders enable row level security;
alter table learner_blunders enable row level security;
drop policy if exists "own blunders (read)" on learner_blunders;
create policy "own blunders (read)" on learner_blunders for select using (auth.uid() = profile_id);
revoke all on yungsta_blunders from anon, authenticated;
revoke insert, update, delete, truncate on learner_blunders from anon, authenticated;

create or replace function sim_today() returns date language sql stable as $$
  select (now() at time zone 'Africa/Lusaka')::date
$$;
create or replace function sim_cfg(k text, d numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select value::numeric from sim_config where key = k), d)
$$;

-- Charge the missed days (idempotent: each day is assessed once).
create or replace function yungsta_neglect_check(p uuid)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_today date := sim_today(); pr profiles; v_first date; v_start date; v_from date;
  v_max int; v_pct numeric; v_n int; i int; d date; b yungsta_blunders; v_cash numeric; v_amt numeric;
  v_id bigint; v_made int := 0; v_used bigint[] := '{}';
begin
  select * into pr from profiles where id = p;
  if not found then return 0; end if;
  select (min(completed_at) at time zone 'Africa/Lusaka')::date into v_first from learner_lessons where profile_id = p;
  if v_first is null then return 0; end if;                       -- hasn't started learning: nothing to miss
  v_start := v_first + sim_cfg('neglect_free_days', 3)::int;
  v_from := greatest(v_start, coalesce(pr.last_guided_on + 1, v_start),
                     coalesce(pr.neglect_through + 1, v_start), coalesce(pr.paused_until + 1, v_start));
  if v_from > v_today - 1 then return 0; end if;

  v_max := sim_cfg('neglect_max_days', 3)::int;
  v_pct := sim_cfg('neglect_loss_pct', 0.10);
  v_n := least((v_today - 1) - v_from + 1, v_max);                 -- only the most recent days are charged
  for i in 1..v_n loop
    d := (v_today - 1) - (v_n - i);
    select * into b from yungsta_blunders where is_active and id <> all (v_used) order by random() limit 1;
    if b.id is null then select * into b from yungsta_blunders where is_active order by random() limit 1; end if;
    exit when b.id is null;
    select cash_balance into v_cash from profiles where id = p;
    v_amt := least(v_cash, round(v_cash * v_pct * b.loss_mult, 2));
    if v_amt <= 0 then continue; end if;
    insert into learner_blunders (profile_id, blunder_id, missed_on, amount, option_order)
    values (p, b.id, d, v_amt, array(select k from generate_series(0, jsonb_array_length(b.debrief_options) - 1) k order by random()))
    returning id into v_id;
    perform adjust_cash_balance(p, -v_amt, 'yungsta_blunder', 'yungsta_blunders', v_id);
    v_used := v_used || b.id; v_made := v_made + 1;
  end loop;

  update profiles set neglect_through = v_today - 1 where id = p;
  if v_made > 0 and not story_has_flag(p, 'left_unguided') then perform story_set_flag(p, 'left_unguided', null); end if;
  return v_made;
end $$;

-- Record that the learner guided the yungsta today (settles any earlier missed days first).
create or replace function yungsta_mark_guided(p uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform yungsta_neglect_check(p);
  update profiles set last_guided_on = sim_today() where id = p and (last_guided_on is null or last_guided_on < sim_today());
end $$;

create or replace function yungsta_status(p uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pr profiles; v_first date; v_today date := sim_today();
begin
  select * into pr from profiles where id = p;
  select (min(completed_at) at time zone 'Africa/Lusaka')::date into v_first from learner_lessons where profile_id = p;
  return jsonb_build_object(
    'active', (v_first is not null and v_today >= v_first + sim_cfg('neglect_free_days', 3)::int),
    'guided_today', (pr.last_guided_on = v_today),
    'paused', (pr.paused_until is not null and pr.paused_until >= v_today),
    'can_pause', (pr.last_pause_on is null or pr.last_pause_on <= v_today - sim_cfg('pause_cooldown_days', 14)::int),
    'pause_days', sim_cfg('pause_max_days', 3)::int,
    'loss_pct', sim_cfg('neglect_loss_pct', 0.10));
end $$;

-- What the learner sees on return: each mistake, with its debrief question (never the answer).
create or replace function yungsta_blunders_new(p uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', lb.id, 'title', story_fill(p, b.title), 'story', story_fill(p, b.story),
      'amount', lb.amount, 'missed_on', lb.missed_on,
      'question', story_fill(p, b.debrief_question),
      'options', (select jsonb_agg(jsonb_build_object('index', t.ord - 1, 'text', story_fill(p, b.debrief_options -> t.idx ->> 'text')) order by t.ord)
                    from unnest(lb.option_order) with ordinality as t(idx, ord))
    ) order by lb.missed_on), '[]'::jsonb)
  from learner_blunders lb join yungsta_blunders b on b.id = lb.blunder_id
  where lb.profile_id = p and lb.status = 'new'
$$;

create or replace function yungsta_debrief(p_id bigint, p_choice int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); lb learner_blunders; b yungsta_blunders; v_orig int; v_ok boolean; v_rec numeric := 0;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  select * into lb from learner_blunders where id = p_id and profile_id = uid and status = 'new' for update;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  if p_choice is null or p_choice < 0 or p_choice >= array_length(lb.option_order, 1) then
    return jsonb_build_object('error', 'bad_choice');
  end if;
  select * into b from yungsta_blunders where id = lb.blunder_id;
  v_orig := lb.option_order[p_choice + 1];
  v_ok := (v_orig = b.correct_index);
  if v_ok then
    v_rec := round(lb.amount * sim_cfg('neglect_recover_pct', 0.5), 2);
    if v_rec > 0 then perform adjust_cash_balance(uid, v_rec, 'yungsta_recovery', 'learner_blunders', lb.id); end if;
    perform adjust_reputation_score(uid, 1, 'debriefed: ' || b.blunder_key);
    if not story_has_flag(uid, 'debriefed_after_mistakes') then perform story_set_flag(uid, 'debriefed_after_mistakes', null); end if;
  end if;
  update learner_blunders set status = 'debriefed', recovered = v_rec, debriefed_at = now() where id = lb.id;
  perform yungsta_mark_guided(uid);
  return jsonb_build_object('correct', v_ok, 'recovered', v_rec,
    'feedback', story_fill(uid, b.debrief_options -> v_orig ->> 'fb'),
    'right_text', story_fill(uid, b.debrief_options -> b.correct_index ->> 'text'),
    'explanation', story_fill(uid, b.debrief_options -> b.correct_index ->> 'fb'),
    'recovery_text', case when v_ok then story_fill(uid, b.recovery_text) else null end,
    'cash', (select cash_balance from profiles where id = uid));
end $$;

create or replace function yungsta_blunders_skip()
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  update learner_blunders set status = 'skipped' where profile_id = uid and status = 'new';
  return jsonb_build_object('ok', true);
end $$;

create or replace function yungsta_pause(p_days int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); pr profiles; v_today date := sim_today(); v_max int := sim_cfg('pause_max_days', 3)::int; v_d int;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  v_d := least(coalesce(p_days, v_max), v_max);
  select * into pr from profiles where id = uid;
  if pr.last_pause_on is not null and pr.last_pause_on > v_today - sim_cfg('pause_cooldown_days', 14)::int then
    return jsonb_build_object('error', 'cooldown', 'available_on', pr.last_pause_on + sim_cfg('pause_cooldown_days', 14)::int);
  end if;
  perform yungsta_neglect_check(uid);          -- settle anything already missed first
  update profiles set paused_until = v_today + v_d - 1, last_pause_on = v_today where id = uid;
  return jsonb_build_object('ok', true, 'days', v_d);
end $$;

do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in
             ('yungsta_neglect_check','yungsta_mark_guided','yungsta_status','yungsta_blunders_new','yungsta_debrief','yungsta_blunders_skip','yungsta_pause')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    if r.proname in ('yungsta_debrief','yungsta_blunders_skip','yungsta_pause') then
      execute format('grant execute on function %s to authenticated', r.sig);
    end if;
  end loop;
end $$;

-- ── the mistakes ──
insert into yungsta_blunders (blunder_key, title, story, loss_mult, debrief_question, debrief_options, correct_index, recovery_text) values
($k$scheme$k$, $t$Sent money to a 'double your money' scheme$t$, $t$Left on their own, {name} saw a WhatsApp offer to 'double your money in 48 hours' and sent the money before asking anyone. The group disappeared by morning.$t$, 1.2, $t$What should {name} have done before sending money to a 'guaranteed returns' offer?$t$, $j$[{"text": "Checked the company's licence and registration with the regulator, and waited a day", "fb": "Promises of guaranteed returns are the classic scam sign. Checking registration and waiting a day exposes most of them."}, {"text": "Sent a small amount first to test it", "fb": "Scammers often pay a small amount at first to build trust before taking much more."}, {"text": "Asked the group members if it really works", "fb": "Members are often part of the scam, or victims who have not yet realised."}]$j$::jsonb, 0, $t${name} reported the scheme quickly because of your advice, and part of the money was frozen and returned.$t$),
($k$impulse$k$, $t$Bought an expensive gadget on a 'today only' deal$t$, $t$Without you around, {name} gave in to a 'TODAY ONLY' banner and bought a flashy gadget they did not need.$t$, 0.9, $t$What is the best defence against 'today only' pressure?$t$, $j$[{"text": "Wait 24 hours and compare prices before buying", "fb": "A real bargain survives a day. Pressure to decide now is a sales tactic."}, {"text": "Buy it now before it sells out", "fb": "Urgency is designed to stop you thinking. Buying fast is exactly what the seller wants."}, {"text": "Buy two and resell one", "fb": "Resale is uncertain, and this doubles the spending you are trying to avoid."}]$j$::jsonb, 0, $t${name} returned the item within the shop's return window and got part of the money back.$t$),
($k$upfront_fee$k$, $t$Paid an upfront 'processing fee' for a loan$t$, $t${name} was told a loan was 'guaranteed' if they paid a processing fee first. They paid, and the loan never came.$t$, 0.7, $t$What is the red flag when a lender asks for a fee before paying out a loan?$t$, $j$[{"text": "Genuine, regulated lenders deduct costs from the loan, so an upfront fee is a classic scam sign", "fb": "Regulated lenders do not ask you to send money first to receive a loan."}, {"text": "Nothing. It shows you are serious about the loan", "fb": "Paying first does not show commitment. It is how scammers collect money."}, {"text": "It means the loan is guaranteed", "fb": "No lender can guarantee a loan without checking you, and scammers love the word 'guaranteed'."}]$j$::jsonb, 0, $t$Because you taught {name} the warning sign, they reported the lender and recovered part of the fee.$t$),
($k$betting$k$, $t$Put money on a 'sure win' bet$t$, $t${name} followed a betting tipster's 'sure win' and put a big stake on it. The match did not go the tipster's way.$t$, 1.0, $t$Why can no betting tipster guarantee a win?$t$, $j$[{"text": "Outcomes are uncertain, and bookmakers build in a margin so the house wins over time", "fb": "Nobody can know the result in advance, and the odds are set so the bookmaker profits."}, {"text": "Tipsters do have inside information, but they make mistakes", "fb": "Genuine inside information would be illegal, and no tipster can remove the uncertainty."}, {"text": "It is guaranteed if you bet a larger amount", "fb": "A bigger stake only means a bigger loss when it goes wrong."}]$j$::jsonb, 0, $t${name} stopped betting after your debrief and a refund from a promotion covered part of the loss.$t$),
($k$lend_no_terms$k$, $t$Lent a large amount with no terms$t$, $t${name} lent a big sum to someone they barely knew, with no amount agreed, no date and nothing written down.$t$, 1.1, $t$What makes lending money to someone safer?$t$, $j$[{"text": "Agree the amount and repayment date, write it down, and only lend what you can afford to lose", "fb": "Clear, written terms prevent misunderstandings and protect both the money and the relationship."}, {"text": "Trust is enough, so there is no need for terms", "fb": "Even honest people forget or disagree about what was promised."}, {"text": "Lend more so they take it seriously", "fb": "A bigger loan only increases your risk."}]$j$::jsonb, 0, $t$With a clear conversation, {name} agreed a repayment plan and got part of the money back.$t$),
($k$night_out$k$, $t$Spent a month's budget on a night out$t$, $t${name} wanted to look successful, and a night out with friends took a big chunk of the month's money.$t$, 0.8, $t$What helps when spending to impress other people?$t$, $j$[{"text": "Decide a spending limit beforehand, and set aside savings first", "fb": "A limit set before you go out is much easier to keep than one made in the moment."}, {"text": "Spend freely now and worry about the bills later", "fb": "Bills still arrive, and you start the month behind."}, {"text": "Put it all on a quick-loan app so cash is never a problem", "fb": "This turns one night's spending into expensive debt."}]$j$::jsonb, 0, $t${name} agreed a spending limit with you and got some of the money back by cancelling an upcoming outing.$t$),
($k$ignored_bill$k$, $t$Ignored a bill until late fees piled up$t$, $t${name} ignored a utility bill, and late fees and a reconnection charge turned a small bill into a big one.$t$, 0.6, $t$What is the cheapest way to handle a bill you cannot pay in full?$t$, $j$[{"text": "Contact the provider early and ask for a payment plan", "fb": "Providers often agree to instalments if you ask before the bill is overdue."}, {"text": "Ignore it until they chase you", "fb": "Late fees and reconnection charges grow while you wait."}, {"text": "Borrow from a quick-loan app to pay it", "fb": "A quick loan usually costs far more than the late fee you are trying to avoid."}]$j$::jsonb, 0, $t${name} phoned the provider after your debrief and got part of the late fees waived.$t$),
($k$trending_token$k$, $t$Bought a crypto token because it was trending$t$, $t${name} saw a token going viral online and bought it near the top without understanding it. The price fell the next day.$t$, 1.2, $t$What should be checked before buying something just because it is trending?$t$, $j$[{"text": "Whether you understand it and could afford to lose the money; hype is not research", "fb": "Hype is not evidence. Only invest what you understand and can afford to lose."}, {"text": "How many people are talking about it", "fb": "Popularity is not safety, and prices often fall after the crowd arrives."}, {"text": "Whether a famous person owns it", "fb": "Famous people can promote assets they profit from, and fame says nothing about the risk."}]$j$::jsonb, 0, $t${name} sold quickly after your debrief and avoided a deeper loss, which got back part of the money.$t$),
($k$cosign$k$, $t$Co-signed a friend's loan$t$, $t${name} co-signed a loan for a friend to be kind. The friend stopped paying, and the lender came to {name} for the money.$t$, 1.0, $t$What happens if you co-sign a loan and the friend stops paying?$t$, $j$[{"text": "You become responsible for the debt", "fb": "A co-signer promises to pay if the borrower does not."}, {"text": "Nothing, it is not your responsibility", "fb": "Co-signing means you are legally liable too."}, {"text": "Only the bank is affected", "fb": "The lender can pursue the co-signer for the full amount."}]$j$::jsonb, 0, $t$With your help {name} negotiated a repayment plan, which got back part of the money.$t$)
on conflict (blunder_key) do update set title = excluded.title, story = excluded.story, loss_mult = excluded.loss_mult,
  debrief_question = excluded.debrief_question, debrief_options = excluded.debrief_options, correct_index = excluded.correct_index,
  recovery_text = excluded.recovery_text;
