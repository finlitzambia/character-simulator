-- FinLit Zambia — 05-ambient-events.sql (safe to re-run)
-- Everyday life events, told from the MENTOR's side: {name} is the yungsta, 'you' is the learner.

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$ambient_kunda_needs_help$k$, $k$ambient$k$, $k$dice_roll$k$, $j${"fire_probability": 0.35}$j$::jsonb, $j${}$j$::jsonb, $k$kunda$k$, $t$Kunda asks {name} for a favour$t$, $t${name} calls you from the bus stop.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Kunda, a trader {name} knows from the market, says a supplier is selling stock cheaply today, but he is K300 short. He promises to pay {name} back soon. {name} likes him, though he has been late with things before. What do you advise?$t$, $j$[{"label": "Advise {name} to lend him K300", "cash_delta": -300, "sets_flag": "generous_to_kunda", "narrative": "{name} hands over K300. Kunda thanks them and hurries off to the supplier."}, {"label": "Advise {name} to say no, kindly", "sets_flag": "declined_kunda_kindly", "narrative": "{name} explains they are keeping their cash for their own plans. Kunda nods. No hard feelings."}, {"label": "Advise {name} to brush him off", "reputation_delta": -1, "sets_flag": "declined_kunda_coldly", "narrative": "{name} waves him away. He does not ask again, and word gets around the market."}]$j$::jsonb from story_events where event_key = $k$ambient_kunda_needs_help$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_kunda_repays$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": "generous_to_kunda", "delay_game_months": 2}$j$::jsonb, $j${}$j$::jsonb, $k$kunda$k$, $t$Kunda pays {name} back$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Kunda finds {name} at the market, grinning. His stock sold out fast.$t$, $j$[{"label": "Accept the money", "cash_delta": 350, "reputation_delta": 2, "sets_flag": "kunda_repaid", "narrative": "He repays the K300 and adds K50 as thanks. Helping a friend paid off, and people remember who helped."}]$j$::jsonb from story_events where event_key = $k$consequence_kunda_repays$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$ambient_chola_quick_loan$k$, $k$ambient$k$, $k$dice_roll$k$, $j${"fire_probability": 0.35}$j$::jsonb, $j${"min_days_since_signup": 1}$j$::jsonb, $k$chola$k$, $t$Chola has an offer for {name}$t$, $t$Chola always seems to know who needs money.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$He offers {name} K1,500 in quick cash. No forms, no waiting, no questions. {name} would repay K2,100 in three weeks. "It's just a small fee," he says. What do you advise?$t$, $j$[{"label": "Ask: what interest rate is that, really?", "requires_flag": "learned_credit_scores", "sets_flag": "asked_chola_effective_rate", "next_node": "reveal", "narrative": "You work it out together: K600 extra on K1,500 over three weeks is 40%. That is about 690% a year."}, {"label": "Advise {name} to take the K1,500", "loan": {"lender_kind": "informal", "principal": 1500, "total": 2100, "rate": 690, "tag": "chola_loan"}, "sets_flag": "borrowed_from_chola", "narrative": "K1,500 lands in {name}'s account straight away. They owe K2,100 in about three weeks."}, {"label": "Advise {name} to say no thanks", "sets_flag": "declined_chola", "narrative": "{name} thanks him and walks on. He shrugs; there is always someone else."}]$j$::jsonb from story_events where event_key = $k$ambient_chola_quick_loan$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$reveal$k$, $t$At that rate this is one of the most expensive loans {name} could possibly take. Chola smiles. "Take it or leave it."$t$, $j$[{"label": "Advise {name} to walk away", "reputation_delta": 2, "sets_flag": "walked_away_from_chola_informed", "narrative": "{name} says no, and can now name exactly what the 'small fee' would have cost."}, {"label": "Let {name} take it anyway, eyes open", "loan": {"lender_kind": "informal", "principal": 1500, "total": 2100, "rate": 690, "tag": "chola_loan"}, "sets_flag": "borrowed_from_chola", "narrative": "{name} takes the K1,500, knowing exactly what it costs. They must find K2,100 in three weeks."}]$j$::jsonb from story_events where event_key = $k$ambient_chola_quick_loan$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_chola_due$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": "borrowed_from_chola", "delay_game_months": 0.75, "cancel_on_repay_tag": "chola_loan", "repay_flag": "repaid_chola_on_time", "repay_reputation": 1}$j$::jsonb, $j${}$j$::jsonb, $k$chola$k$, $t$Chola wants his money$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Chola finds {name}. "K2,100, as we agreed." What do you advise?$t$, $j$[{"label": "Advise {name} to pay K2,100 in full", "repay_tag": "chola_loan", "reputation_delta": 2, "sets_flag": "repaid_chola_on_time", "narrative": "Paid. Chola nods and moves on to the next person."}, {"label": "Advise {name} to say they can't pay yet", "fee_tag": "chola_loan", "fee": 300, "reputation_delta": -5, "sets_flag": "defaulted_chola", "narrative": "Chola adds K300 to what {name} owes, and he isn't patient. {name}'s reputation takes a hit."}]$j$::jsonb from story_events where event_key = $k$consequence_chola_due$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$ambient_whatsapp_guaranteed_returns$k$, $k$ambient$k$, $k$dice_roll$k$, $j${"fire_probability": 0.3}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$A message {name} doesn't recognise$t$, $t${name} forwards you a WhatsApp message and asks if it is real.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$"Double your money in 30 days. GUARANTEED. Join 2,000 members already earning. Only K2,000 to start. Spots close today!" What do you tell {name}?$t$, $j$[{"label": "Tell {name} to send K2,000 and join", "cash_delta": -2000, "sets_flag": "fell_for_scam", "narrative": "{name} sends it. A 'confirmation' arrives within minutes. It looks very professional."}, {"label": "Tell {name} to ignore it and block the number", "sets_flag": "ignored_scam", "narrative": "{name} blocks the number and gets on with the day."}, {"label": "Tell {name} to ask for their company registration and licence first", "requires_flag": "learned_scam_patterns", "reputation_delta": 3, "sets_flag": "spotted_scam", "narrative": "No registration, no licence, and they get angry that {name} asked. That tells you everything. {name} blocks and reports the number."}]$j$::jsonb from story_events where event_key = $k$ambient_whatsapp_guaranteed_returns$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_scam_aftermath$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": "fell_for_scam", "delay_real_days": 1}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$The group chat is gone$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$The group chat has disappeared and the number no longer exists. There is nobody to ask for {name}'s money back.$t$, $j$[{"label": "Continue", "reputation_delta": -2, "sets_flag": "lost_money_to_scam", "narrative": "The K2,000 is gone for good. 'Guaranteed' returns almost never are. This might be a good moment to talk it through with {name}."}]$j$::jsonb from story_events where event_key = $k$consequence_scam_aftermath$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$ambient_flash_sale$k$, $k$ambient$k$, $k$dice_roll$k$, $j${"fire_probability": 0.3}$j$::jsonb, $j${"min_days_since_signup": 1}$j$::jsonb, $k$inner_voice$k$, $t$A "today only" sale$t$, $t${name} calls you from outside an appliance shop.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$A banner shouts: SOUND SYSTEM K1,200 (was K2,000), TODAY ONLY! The salesman says only two are left, and {name} really wants it. What do you advise?$t$, $j$[{"label": "Advise {name} to buy it now for K1,200", "cash_delta": -1200, "sets_flag": "impulse_purchase", "narrative": "It sounds great. {name}'s cash is K1,200 lighter, and nothing was checked first."}, {"label": "Advise {name} to walk away", "sets_flag": "skipped_flash_sale", "narrative": "{name} keeps walking. Nothing lost, nothing gained."}, {"label": "Advise {name} to notice the 'today only' pressure and compare prices first", "requires_flag": "learned_cognitive_biases", "cash_delta": -1000, "reputation_delta": 1, "sets_flag": "smart_shopper", "narrative": "Another shop has the same one for K1,000, with no pressure. {name} buys it there and beats the 'sale' price by K200."}]$j$::jsonb from story_events where event_key = $k$ambient_flash_sale$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$ambient_family_emergency$k$, $k$ambient$k$, $k$dice_roll$k$, $j${"fire_probability": 0.3}$j$::jsonb, $j${"min_days_since_signup": 2}$j$::jsonb, $k$ba_grace$k$, $t$A call from Ba Grace$t$, $t$Ba Grace, {name}'s aunt, calls you both, and she sounds worried.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name}'s cousin Mwansa's child is in hospital. The family needs K1,500 today for treatment and medicine, and everyone is looking at {name}. What do you advise?$t$, $j$[{"label": "Advise {name} to send K1,500 and not mention repayment", "cash_delta": -1500, "reputation_delta": 1, "sets_flag": "helped_family_gift", "narrative": "{name} sends it without a second thought. Family comes first, though it is a big chunk of their cash."}, {"label": "Advise {name} to send K500 and explain what they can afford", "cash_delta": -500, "sets_flag": "set_family_boundary", "narrative": "{name} helps with what they can and is honest about their limits. It is uncomfortable, but it is sustainable."}, {"label": "Advise {name} to lend K1,000 with an agreed repayment date, in writing", "requires_flag": "learned_emergency_fund", "cash_delta": -1000, "sets_flag": "lent_cousin_with_terms", "narrative": "{name} agrees it is a loan, to be repaid in a few months, and writes it down on WhatsApp so nobody is confused later."}, {"label": "Advise {name} to say they can't help this time", "reputation_delta": -1, "sets_flag": "declined_family", "narrative": "It is a hard call. The family is disappointed, and {name} feels it."}]$j$::jsonb from story_events where event_key = $k$ambient_family_emergency$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_cousin_repays$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": "lent_cousin_with_terms", "delay_game_months": 3}$j$::jsonb, $j${}$j$::jsonb, $k$ba_grace$k$, $t$Mwansa keeps his word$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Mwansa messages {name}: he has the K1,000, exactly as agreed.$t$, $j$[{"label": "Accept the repayment", "cash_delta": 1000, "reputation_delta": 2, "sets_flag": "cousin_repaid", "narrative": "Because {name} set clear terms, they helped without damaging the relationship or their own finances. That is worth remembering."}]$j$::jsonb from story_events where event_key = $k$consequence_cousin_repays$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$ambient_bulk_stock_offer$k$, $k$ambient$k$, $k$dice_roll$k$, $j${"fire_probability": 0.35}$j$::jsonb, $j${"requires_active_venture": true}$j$::jsonb, $k$mr_daka$k$, $t$A supplier discount for {name}$t$, $t$Mr Daka, {name}'s supplier, catches them at the stall.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$He offers 30% off if {name} buys three months of stock now: K1,500 instead of K2,100. But if it sits unsold, that is cash stuck on a shelf. What do you advise?$t$, $j$[{"label": "Advise {name} to buy the full K1,500 of stock", "cash_delta": -1500, "sets_flag": "bought_bulk_stock", "narrative": "{name} commits K1,500 to stock that needs to sell over the next three months."}, {"label": "Advise {name} to pass on the offer", "sets_flag": "passed_bulk_offer", "narrative": "{name} sticks with small orders. It costs a little more per item, but their cash stays free."}, {"label": "Work out the break-even together, then buy half to test demand (K750)", "requires_flag": "learned_breakeven_math", "cash_delta": -750, "reputation_delta": 1, "sets_flag": "tested_bulk_demand", "narrative": "Break-even needs {name} to sell about 60% of the stock at the usual price. Buying half tests demand before committing."}]$j$::jsonb from story_events where event_key = $k$ambient_bulk_stock_offer$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_bulk_stock_full$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": "bought_bulk_stock", "delay_game_months": 2}$j$::jsonb, $j${}$j$::jsonb, $k$mr_daka$k$, $t$How {name}'s stock sold$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Demand was slower than hoped. Most of {name}'s stock sold, but slowly, and some of it spoiled.$t$, $j$[{"label": "Count up what was recovered", "cash_delta": 1300, "sets_flag": "bulk_stock_slow_sale", "narrative": "{name} recovers K1,300 of the K1,500 tied up: a K200 loss, plus months of cash that could not be used for anything else."}]$j$::jsonb from story_events where event_key = $k$consequence_bulk_stock_full$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_bulk_stock_test$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": "tested_bulk_demand", "delay_game_months": 2}$j$::jsonb, $j${}$j$::jsonb, $k$mr_daka$k$, $t$How {name}'s stock sold$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$The half-order sold out well before the month ended.$t$, $j$[{"label": "Count up the takings", "cash_delta": 1050, "sets_flag": "bulk_stock_sold_well", "narrative": "K1,050 back on K750: a K300 profit. Now {name} can reorder with real evidence behind them."}]$j$::jsonb from story_events where event_key = $k$consequence_bulk_stock_test$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

