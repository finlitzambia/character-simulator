-- FinLit Zambia — Financial Character Simulator
-- 03-story-seed.sql  (safe to re-run)
-- Content: unlock chain, lesson flags, lender ceilings, and the
-- Module 1.2 (Credit & Debt) reference scenario with its consequences.
-- Time: 1 game-year = 14 real days, so 3 game-months = 3.5 real days.

-- ── LESSON → FLAG (every lesson gets a quiet flag + small rep nudge) ──
-- lesson_id = the module key on the lesson site (module-1-2 -> '1-2')
insert into lesson_flag_map (lesson_id, flag_key, reputation_delta) values
 ('0a','learned_financial_foundations',1), ('0b','learned_mobile_money',1),
 ('0c','learned_scam_patterns',1),         ('0d','reflected_on_money_mindset',1),
 ('1-0','set_smart_goal',1),               ('1-1','learned_saving_habits',1),
 ('1-2','learned_credit_scores',2),        ('1-3','learned_emergency_fund',1),
 ('2-0','learned_insurance_basics',1),     ('2-1','learned_investing_fundamentals',2),
 ('2-2','learned_true_cost_of_buying',1),  ('2-3','learned_agricultural_finance',1),
 ('2-4','learned_breakeven_math',2),       ('3-0','learned_paye_taxation',1),
 ('3-1','learned_cognitive_biases',2),     ('3-2','learned_scam_patterns',1),
 ('3-3','learned_consumer_protection',1),  ('3-4','learned_remittances',1),
 ('4-0','learned_retirement_planning',1),  ('4-1','completed_comprehensive_review',1),
 ('4-2','learned_long_term_care',1),       ('4-3','learned_succession_law',1),
 ('u1','learned_reiz',1),                  ('u2','learned_stock_valuation',2),
 ('u3','learned_luse_ipo_mechanics',1),    ('u4','learned_crypto_basics',1),
 ('b1','learned_business_registration',1), ('b2','learned_vat_compliance',1)
on conflict (lesson_id) do update set flag_key = excluded.flag_key, reputation_delta = excluded.reputation_delta;

-- ── LENDER CEILINGS (highest satisfied rule wins) ──
delete from lender_limit_rules;
insert into lender_limit_rules (lender_kind, ceiling, requires_flag, excludes_flag, min_days_since_signup, note) values
 ('informal',     1000,  null, null, 0, 'family/friends, always available'),
 ('microfinance', 2000,  null, 'defaulted_microfinance', 0, 'available day one, small'),
 ('microfinance', 5000,  'repaid_microfinance_on_time', 'defaulted_microfinance', 0, 'earned by repaying on time'),
 ('microfinance',  500,  'defaulted_microfinance', null, 0, 'worse access after a default'),
 ('bank',         1000,  null, null, 0, 'small starter limit'),
 ('bank',         8000,  null, null, 7, 'time-only fallback after 7 real days'),
 ('bank',        15000,  'learned_credit_scores', null, 0, 'lesson 1.2 raises it immediately (preferred route)');

-- ── UNLOCK CHAIN: Ventures open day one. Lesson rows beat the fallbacks. ──
insert into story_events (event_key, category, trigger_type, trigger_config, unlocks_feature, title) values
 ('unlock_trade_lesson_investing',   'unlock', 'flag',        '{"flag":"learned_investing_fundamentals"}', 'trade', 'Trade unlocked'),
 ('unlock_trade_first_venture',      'unlock', 'action',      '{"action":"venture_first_activity"}',       'trade', 'Trade unlocked'),
 ('unlock_trade_day_fallback',       'unlock', 'day_fallback','{"min_days_since_signup":3}',               'trade', 'Trade unlocked'),
 ('unlock_debts_lesson_credit',      'unlock', 'flag',        '{"flag":"learned_credit_scores"}',          'debts', 'Debts unlocked'),
 ('unlock_debts_cash_crunch',        'unlock', 'threshold',   '{"field":"cash_balance","op":"<","value":2000}', 'debts', 'Debts unlocked'),
 ('unlock_debts_day_fallback',       'unlock', 'day_fallback','{"min_days_since_signup":7}',               'debts', 'Debts unlocked')
on conflict (event_key) do update set trigger_type = excluded.trigger_type,
  trigger_config = excluded.trigger_config, unlocks_feature = excluded.unlocks_feature, title = excluded.title;

-- ── REFERENCE SCENARIO: Module 1.2 — {name}'s stolen phone (told from the mentor's side) ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_credit_debt_phone$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "1-2"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name}'s phone was stolen$t$, $t$Two days after you finished Credit and Debt Management, {name} calls you in a panic.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Someone stole {name}'s phone on the minibus home. Tomorrow morning they fly to South Africa for a family emergency, and they need a working phone to stay reachable and handle money while away. A replacement costs K1,800, and they have until tonight to sort it out. What do you advise?$t$, $j$[{"label": "Advise {name} to travel without a phone", "sets_flag": "phone_theft_went_without", "narrative": "{name} decides to travel without a phone. No cash spent, no debt taken on. It feels like the safe choice."}, {"label": "Advise {name} to borrow K1,800 from a microfinance lender", "loan": {"lender_kind": "microfinance", "principal": 1800, "total": 2160, "rate": 80, "tag": "phone_loan"}, "sets_flag": "borrowed_microfinance_phone", "narrative": "Approved on the spot. K1,800 lands in {name}'s account and a new phone follows. The K2,160 owed (20% interest included) is due in about 3 months."}, {"label": "Send {name} to the bank", "sets_flag": "attempted_bank_first", "next_node": "bank", "narrative": "{name} heads to the bank counter."}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_credit_debt_phone$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$bank$k$, $t$The bank tells {name} that loan approval takes 3 to 5 business days, and their flight is tomorrow morning. The formal route is not available in time. That is a limit of the system, not a mistake on {name}'s part. What now?$t$, $j$[{"label": "Advise {name} to fall back to microfinance anyway", "loan": {"lender_kind": "microfinance", "principal": 1800, "total": 2160, "rate": 80, "tag": "phone_loan"}, "sets_flag": "borrowed_microfinance_after_bank_attempt", "narrative": "Same terms as any microfinance loan: K1,800 now, K2,160 due in about 3 months."}, {"label": "Advise {name} to go without after all", "sets_flag": "phone_theft_went_without_after_bank_attempt", "narrative": "{name} gives up on the phone and packs for the trip."}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_credit_debt_phone$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_phone_connectivity_loss$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": ["phone_theft_went_without", "phone_theft_went_without_after_bank_attempt"], "delay_real_days": 2}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name} is back from the trip$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Without a phone to check the mobile money app while away, {name} did not notice a fraudulent transfer draining their account until they got back.$t$, $j$[{"label": "Continue", "cash_delta": -400, "forced": true, "sets_flag": "learned_connectivity_cost_hard_way", "narrative": "K400 is gone. Some costs of inattention are not negotiable, and {name} will remember this."}]$j$::jsonb from story_events where event_key = $k$consequence_phone_connectivity_loss$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_microfinance_due$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": ["borrowed_microfinance_phone", "borrowed_microfinance_after_bank_attempt"], "delay_game_months": 3, "cancel_on_repay_tag": "phone_loan", "repay_flag": "repaid_microfinance_on_time", "repay_reputation": 3}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name}'s loan repayment is due$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name}'s K1,800 microfinance loan, plus 20% interest (K2,160 in total), is due today. What do you advise?$t$, $j$[{"label": "Advise {name} to repay in full (K2,160)", "repay_tag": "phone_loan", "reputation_delta": 3, "sets_flag": "repaid_microfinance_on_time", "narrative": "Paid on time. {name}'s reputation improves and microfinance lenders will offer them more next time."}, {"label": "Advise {name} to miss the payment", "fee_tag": "phone_loan", "fee": 200, "reputation_delta": -5, "sets_flag": "defaulted_microfinance", "narrative": "A K200 late fee is added to what {name} owes, their reputation drops, and microfinance lenders will now offer them much less."}]$j$::jsonb from story_events where event_key = $k$consequence_microfinance_due$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

