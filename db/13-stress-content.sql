-- FinLit Zambia — Financial Character Simulator
-- 13-stress-content.sql  (safe to re-run)  Run AFTER 12.
--
-- 1. What each existing decision does to stress (stress_flag_effects).  All numbers are starting values.
-- 2. A default goal per starting story (sim_goals). EDIT THESE: they are proposals, not decisions.
-- 3. Five new scenarios that teach "more money does not always solve your problems":
--      windfall (+ the visitors it brings), the upgrade offer (lifestyle creep), a hospital bill
--      (cash vs borrowing), and a faulty phone (consumer rights).
-- 4. Engine hooks:
--      * when stress is 60 or more, scams and pressure offers show up more often (story_daily_roll)
--      * when stress is 60 or more, careful options marked needs_calm are not available (overloaded)
-- 5. Lesson links for the newer modules (1-4, 3-5, p1).
-- Run order: 02 ... 12, then this file. If 02 is ever re-run, run this file again.

delete from stress_flag_effects;
insert into stress_flag_effects (flag_key, delta, delay_months, fade_months, why, pattern_key, cancelled_by) values
($q$borrowed_from_chola$q$, -3, 0, 1, $q$The quick cash felt like relief$q$, null, null),
($q$borrowed_from_chola$q$, 6, 0.4, 3, $q$Chola's repayment date is getting close$q$, null, array[$q$repaid_chola_on_time$q$,$q$defaulted_chola$q$]),
($q$repaid_chola_on_time$q$, -5, 0, 3, $q$Paying the quick loan on time lifted a weight$q$, null, null),
($q$defaulted_chola$q$, 10, 0, 6, $q$Defaulting on Chola's loan hangs over every decision$q$, null, null),
($q$asked_chola_effective_rate$q$, -2, 0, 2, $q$Asking for the real rate paid off$q$, null, null),
($q$walked_away_from_chola_informed$q$, -3, 0, 2, $q$Walking away from an expensive loan felt right$q$, null, null),
($q$borrowed_microfinance_phone$q$, 3, 0, 3, $q$A new loan adds worry$q$, null, null),
($q$borrowed_microfinance_after_bank_attempt$q$, 4, 0, 3, $q$A loan taken after a failed bank try adds worry$q$, null, null),
($q$repaid_microfinance_on_time$q$, -4, 0, 3, $q$Clearing the microfinance loan on time brought relief$q$, null, null),
($q$defaulted_microfinance$q$, 10, 0, 6, $q$Missing the microfinance payment is a scar$q$, null, null),
($q$fell_for_scam$q$, 10, 0, 4, $q$Losing K2,000 to a fake scheme still stings$q$, null, null),
($q$spotted_scam$q$, -3, 0, 2, $q$Spotting the scam built confidence$q$, null, null),
($q$ignored_scam$q$, -1, 0, 1, $q$Ignoring the message kept things calm$q$, null, null),
($q$impulse_purchase$q$, -2, 0, 1, $q$The purchase felt good for a moment$q$, $q$impulse$q$, null),
($q$impulse_purchase$q$, 4, 1, 2, $q$The thrill faded and the money is still gone$q$, $q$impulse$q$, null),
($q$skipped_flash_sale$q$, -1, 0, 1, $q$Walking away from the sale was easy$q$, null, null),
($q$smart_shopper$q$, -2, 0, 2, $q$Not falling for 'today only' paid off$q$, null, null),
($q$helped_family_gift$q$, -1, 0, 2, $q$Helping family brings peace, even when it costs$q$, null, null),
($q$set_family_boundary$q$, -2, 0, 3, $q$A clear boundary kept the peace$q$, null, null),
($q$lent_cousin_with_terms$q$, -1, 0, 2, $q$Lending with agreed terms keeps both sides comfortable$q$, null, null),
($q$declined_family$q$, 4, 0, 3, $q$Saying no to family weighs on you$q$, null, null),
($q$cousin_repaid$q$, -2, 0, 2, $q$Getting money back from family lifted a worry$q$, null, null),
($q$generous_to_kunda$q$, -1, 0, 2, $q$Helping a friend felt good$q$, null, null),
($q$declined_kunda_coldly$q$, 3, 0, 3, $q$Brushing off a friend leaves a bad feeling$q$, null, null),
($q$kunda_repaid$q$, -2, 0, 2, $q$Kunda paying back was a relief$q$, null, null),
($q$bought_bulk_stock$q$, 3, 0, 3, $q$A big stock purchase with no test leaves you exposed$q$, null, null),
($q$tested_bulk_demand$q$, -2, 0, 3, $q$Testing demand first lets you sleep easy$q$, null, null),
($q$bulk_stock_slow_sale$q$, 4, 0, 3, $q$Stock that sells slowly ties up cash$q$, null, null),
($q$bulk_stock_sold_well$q$, -3, 0, 3, $q$The stock sold and cash is flowing$q$, null, null),
($q$learned_connectivity_cost_hard_way$q$, 3, 0, 2, $q$A phone with no airtime cost a day of work$q$, null, null),
($q$replaced_stolen_stock$q$, 3, 0, 2, $q$Replacing everything at once strained the cash$q$, null, null),
($q$partial_restock_after_theft$q$, 4, 0, 2, $q$A half-empty shop after the break-in is worrying$q$, null, null),
($q$claimed_insurance$q$, 2, 0, 2, $q$Cover turned a big loss into a small hassle$q$, null, null),
($q$secured_premises$q$, -2, 0, 4, $q$Better security means fewer sleepless nights$q$, null, null),
($q$absorbed_theft$q$, 8, 0, 3, $q$Absorbing the whole theft loss with no cover hurts$q$, null, null),
($q$invested_in_cooling$q$, -2, 0, 4, $q$Cold storage means spoilage worries are smaller$q$, null, null),
($q$sold_spoiling_stock$q$, 4, 0, 2, $q$Selling spoiling stock cheap saved a little$q$, null, null),
($q$wrote_off_spoiled_stock$q$, 7, 0, 3, $q$Throwing away stock hurts$q$, null, null),
($q$patched_equipment$q$, 5, 0, 2, $q$A cheap patch may fail again$q$, null, null),
($q$replaced_equipment$q$, 1, 0, 2, $q$Replacing equipment properly costs now but settles the worry$q$, null, null),
($q$borrowed_equipment$q$, 3, 0, 2, $q$Relying on borrowed equipment is a risk$q$, null, null),
($q$cut_prices$q$, 3, 0, 3, $q$Cutting prices squeezes the margin$q$, null, null),
($q$promoted_business$q$, 2, 0, 2, $q$Promotion is a bet on future customers$q$, null, null),
($q$held_prices_in_slump$q$, 5, 0, 3, $q$Waiting out a slump with no income is stressful$q$, null, null),
($q$took_big_order$q$, 6, 0, 3, $q$A big order with no deposit is a big risk$q$, null, null),
($q$took_big_order_with_deposit$q$, 1, 0, 2, $q$A deposit makes a big order safer$q$, null, null),
($q$withdrew_profits$q$, 4, 0, 3, $q$Taking all the profit home leaves the business with no buffer$q$, null, null),
($q$reinvested_profits$q$, 6, 0, 3, $q$Putting everything back in leaves no buffer$q$, null, null),
($q$split_profits$q$, 1, 0, 2, $q$Splitting profit balances today and tomorrow$q$, null, null),
($q$kept_profit_buffer$q$, -3, 0, 3, $q$A profit buffer means a bad month won't break you$q$, null, null),
($q$phone_theft_went_without$q$, 5, 0, 3, $q$Going without a phone makes everything harder$q$, null, null),
($q$phone_theft_went_without_after_bank_attempt$q$, 6, 0, 3, $q$Going without after a failed bank try is discouraging$q$, null, null),
($q$attempted_bank_first$q$, 1, 0, 2, $q$The bank route takes time$q$, null, null),
($q$goal_met$q$, -5, 0, 3, $q$Reaching the goal felt good$q$, null, null),
($q$goal_missed$q$, 5, 0, 3, $q$The goal deadline passed without reaching it$q$, null, null),
($q$windfall_planned$q$, -3, 0, 2, $q$Keeping a windfall quiet and planned feels like security$q$, null, null),
($q$windfall_splashed$q$, 5, 1, 3, $q$The celebration money is gone and the bills are not$q$, null, null),
($q$windfall_yes_to_all$q$, 4, 1, 3, $q$Saying yes to everyone drained the windfall$q$, null, null),
($q$windfall_boundary$q$, -1, 0, 2, $q$A one-off gift with clear limits kept the peace$q$, null, null),
($q$windfall_lent_all$q$, 5, 0, 3, $q$Lending a large amount with no terms is a worry$q$, null, null),
($q$windfall_said_no$q$, 3, 0, 2, $q$Saying no to people you care about weighs on you$q$, null, null),
($q$windfall_club$q$, 9, 0, 4, $q$The investment club took the money and vanished$q$, null, null),
($q$creep_upgrade$q$, 2, 0, 6, $q$A better life came with higher monthly bills$q$, null, null),
($q$kept_lifestyle$q$, -3, 0, 3, $q$Keeping costs steady kept things in control$q$, null, null),
($q$paid_medical_cash$q$, 1, 0, 2, $q$Paying cash for the emergency used up the cushion$q$, null, null),
($q$medical_quick_loan$q$, 7, 0, 4, $q$A quick loan for the hospital bill adds a heavy repayment$q$, null, null),
($q$medical_shared_cost$q$, 2, 0, 3, $q$Owing family and the group is its own pressure$q$, null, null),
($q$medical_delayed$q$, 9, 0, 3, $q$Delaying hospital care made everything worse$q$, null, null),
($q$accepted_faulty_phone$q$, 6, 0, 3, $q$Paying twice for the same phone$q$, null, null),
($q$claimed_consumer_rights$q$, -3, 0, 3, $q$Knowing your rights got the phone replaced$q$, null, null),
($q$vented_online$q$, 2, 0, 2, $q$Venting did not fix the phone$q$, null, null),
($q$bankruptcy_restart$q$, 20, 0, 12, $q$A fresh start after bankruptcy still feels heavy$q$, null, null),
($q$debt_missed_payment$q$, 6, 0, 3, $q$A missed loan payment adds a late fee and a lot of worry$q$, null, null),
($q$debt_defaulted_schedule$q$, 10, 0, 6, $q$Defaulting on a loan hangs over every decision$q$, null, null),
($q$debt_paid_on_time$q$, -1, 0, 2, $q$Paying on time keeps the lender off your back$q$, null, null),
($q$debt_cleared$q$, -4, 0, 3, $q$A debt cleared feels like a weight lifted$q$, null, null),
($q$debt_rolled_over$q$, 5, 0, 4, $q$Renewing a payday loan only pushes the problem forward$q$, null, null),
($q$used_avalanche$q$, -2, 0, 3, $q$A clear payoff plan, highest rate first, cuts the worry$q$, null, null),
($q$used_snowball$q$, -2, 0, 3, $q$Quick wins from clearing the smallest debt first keep you going$q$, null, null);

insert into sim_goals (backstory, title, emoji, amount, game_months) values
($q$student$q$, $q$Save for next term's fees$q$, $q$🎓$q$, 600, 6),
($q$trader$q$, $q$Build a bigger stall stock$q$, $q$🛒$q$, 800, 6),
($q$salaried$q$, $q$Save toward a plot deposit$q$, $q$🏡$q$, 800, 6),
($q$farmer$q$, $q$Buy inputs for next season$q$, $q$🌽$q$, 800, 6)
on conflict (backstory) do update set title = excluded.title, emoji = excluded.emoji, amount = excluded.amount, game_months = excluded.game_months;

insert into lesson_flag_map (lesson_id, flag_key, reputation_delta) values ('1-4','learned_village_banking',1),('3-5','learned_warranty_rights',1),('p1','learned_financial_concepts',1)
on conflict do nothing;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($q$ambient_windfall$q$, $q$ambient$q$, $q$dice_roll$q$, $j${"fire_probability": 0.3}$j$::jsonb, $j${"min_days_since_signup": 3}$j$::jsonb, $q$inner_voice$q$, $q$Good news for {name}$q$, $q${name} calls you, over the moon.$q$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $q$start$q$, $q${name} has just received K6,000: a bonus, a good harvest or a big sale. Word travels fast. What do you advise?$q$, $j$[{"label": "Advise {name} to keep quiet and plan what to do with it", "cash_delta": 6000, "sets_flag": "windfall_planned", "reputation_delta": 1, "narrative": "{name} tells almost nobody. K6,000 lands in the account and stays within reach while you work out a plan."}, {"label": "Advise {name} to celebrate and treat everyone", "cash_delta": 3000, "sets_flag": "windfall_splashed", "narrative": "A great weekend. Half the money is gone by Sunday night, and the bills are still the same size."}, {"label": "Advise {name} to say yes to everyone who asks", "cash_delta": 2000, "sets_flag": "windfall_yes_to_all", "narrative": "Relatives, friends and old classmates all had a good reason. K4,000 left in a week."}]$j$::jsonb from story_events where event_key = $q$ambient_windfall$q$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($q$consequence_windfall_visitors$q$, $q$consequence$q$, $q$flag_delay$q$, $j${"after_flag": ["windfall_planned", "windfall_splashed", "windfall_yes_to_all"], "delay_game_months": 1}$j$::jsonb, $j${}$j$::jsonb, $q$ba_grace$q$, $q$The phone will not stop ringing$q$, $q$$q$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $q$start$q$, $q$A month later, {name}'s phone is busy. A cousin needs K1,500 for school fees, and a neighbour is signing people up to an 'investment club' with a K2,000 joining fee. What do you advise?$q$, $j$[{"label": "Advise {name} to help with K500 and say it is a one-off", "cash_delta": -500, "sets_flag": "windfall_boundary", "reputation_delta": 1, "narrative": "The cousin is grateful. {name} was clear it will not become a habit."}, {"label": "Advise {name} to lend the whole K1,500, no questions", "cash_delta": -1500, "sets_flag": "windfall_lent_all", "narrative": "It feels generous. There was no talk of when it comes back."}, {"label": "Advise {name} to say no to both, kindly", "sets_flag": "windfall_said_no", "narrative": "{name} keeps the money and loses some goodwill. It is not an easy conversation."}, {"label": "Advise {name} to join the investment club with K2,000", "cash_delta": -2000, "sets_flag": "windfall_club", "reputation_delta": -2, "narrative": "There was one meeting. Then the phone went off and the group chat disappeared."}]$j$::jsonb from story_events where event_key = $q$consequence_windfall_visitors$q$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($q$consequence_upgrade_offer$q$, $q$consequence$q$, $q$flag_delay$q$, $j${"after_flag": ["windfall_planned", "windfall_splashed", "windfall_yes_to_all"], "delay_game_months": 1.8}$j$::jsonb, $j${}$j$::jsonb, $q$inner_voice$q$, $q$Offers for a better life$q$, $q$$q$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $q$start$q$, $q$Now that {name} has had some extra money, offers appear: a nicer flat for K800 more a month, and a phone plan for K450 more a month. {name} says, "I earned this." What do you advise?$q$, $j$[{"label": "Advise {name} to take the upgrades: it feels affordable now", "sets_flag": "creep_upgrade", "narrative": "Monthly costs go up by about K600. The windfall will not last as long as it feels like it will."}, {"label": "Advise {name} to keep the current place and bank the difference", "sets_flag": "kept_lifestyle", "reputation_delta": 1, "narrative": "Nothing changes on the outside. The monthly costs stay the same, and so does the margin."}]$j$::jsonb from story_events where event_key = $q$consequence_upgrade_offer$q$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($q$ambient_medical_bill$q$, $q$ambient$q$, $q$dice_roll$q$, $j${"fire_probability": 0.3}$j$::jsonb, $j${"min_days_since_signup": 5}$j$::jsonb, $q$inner_voice$q$, $q$A hospital needs a deposit$q$, $q${name}'s phone rings. It is a relative, and it is urgent.$q$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $q$start$q$, $q$A relative has been admitted. The hospital wants a K3,500 deposit today before treatment. {name} has no insurance for this. What do you advise?$q$, $j$[{"label": "Advise {name} to pay it from cash", "cash_delta": -3500, "sets_flag": "paid_medical_cash", "narrative": "Paid. The relative is safe. The cash cushion took a big hit."}, {"label": "Advise {name} to take a payday loan to cover it", "loan": {"lender_kind": "informal", "principal": 3500, "total": 3500, "rate": 35, "tag": "medical_quick_loan"}, "sets_flag": "medical_quick_loan", "narrative": "The money arrives within the hour. It is a payday loan: 35% a year or more, one payment due in a month, and a fee if {name} cannot pay and renews it. The safest source in an emergency would have been an emergency fund."}, {"label": "Advise {name} to ask family and the chilimba group to share the cost", "cash_delta": -1200, "sets_flag": "medical_shared_cost", "reputation_delta": 1, "narrative": "The group chips in K2,300 and {name} pays K1,200. It works, and {name} now owes people more than money."}, {"label": "Advise {name} to delay and hope the hospital can wait", "reputation_delta": -3, "sets_flag": "medical_delayed", "narrative": "The hospital does not wait. The delay makes things worse, and everyone in the family remembers it."}]$j$::jsonb from story_events where event_key = $q$ambient_medical_bill$q$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($q$ambient_faulty_phone$q$, $q$ambient$q$, $q$dice_roll$q$, $j${"fire_probability": 0.4}$j$::jsonb, $j${"requires_flag": ["learned_consumer_protection", "learned_warranty_rights"]}$j$::jsonb, $q$inner_voice$q$, $q${name}'s new phone has stopped working$q$, $q${name} is standing at the shop counter.$q$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro;
insert into story_nodes (event_id, node_key, body, choices)
select id, $q$start$q$, $q$The K1,800 phone {name} bought three weeks ago will not charge. The shop points at a sign on the wall: "No refunds. No exchanges." What do you advise?$q$, $j$[{"label": "Advise {name} to accept it and buy another phone", "cash_delta": -1800, "sets_flag": "accepted_faulty_phone", "narrative": "{name} pays for the same phone twice. The sign won, even though a sign like that is not allowed."}, {"label": "Advise {name} to politely ask for a repair or replacement: a \"No Refunds\" sign is not allowed", "sets_flag": "claimed_consumer_rights", "reputation_delta": 2, "narrative": "{name} calmly says that Section 48 of the Competition and Consumer Protection Act does not allow a \"No returns, no refunds, no exchanges\" sign. After a word with the manager, the shop replaces the phone. If it had refused, {name} could report it to the CCPC on 5678 (free, all networks) or at ccpc.org.zm."}, {"label": "Advise {name} to post an angry review and walk out", "reputation_delta": -2, "sets_flag": "vented_online", "narrative": "The review gets a few likes. The phone is still broken."}]$j$::jsonb from story_events where event_key = $q$ambient_faulty_phone$q$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- Mark the events that stress makes more likely, and the careful options that overload takes away.
update story_events set trigger_config = trigger_config || '{"predatory": true}'::jsonb
 where event_key in ('ambient_chola_quick_loan', 'ambient_whatsapp_guaranteed_returns', 'ambient_flash_sale');
update story_nodes n set choices = jsonb_set(n.choices, '{0,needs_calm}', 'true') from story_events e
 where e.id = n.event_id and e.event_key = 'ambient_chola_quick_loan' and n.node_key = 'start';
update story_nodes n set choices = jsonb_set(n.choices, '{2,needs_calm}', 'true') from story_events e
 where e.id = n.event_id and e.event_key in ('ambient_whatsapp_guaranteed_returns', 'ambient_flash_sale') and n.node_key = 'start';
update story_nodes n set choices = jsonb_set(n.choices, '{2,needs_calm}', 'true') from story_events e
 where e.id = n.event_id and e.event_key = 'ambient_bulk_stock_offer' and n.node_key = 'start';

-- Calm enough to dig into the details? (stress below 60)
create or replace function stress_calm_enough(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select stress from profiles where id = p), 0) < sim_cfg('stress_overload_at', 60)
$$;
insert into sim_config (key, value) values ('stress_overload_at', '60'), ('stress_predatory_boost', '1.8')
on conflict (key) do nothing;

-- Same as before, but careful options marked needs_calm disappear while overloaded
create or replace function story_visible_choices(p uuid, choices jsonb, ctx jsonb default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('index', t.ord - 1, 'label', story_fill(p, t.c->>'label', ctx)) order by t.ord), '[]'::jsonb)
  from jsonb_array_elements(choices) with ordinality as t(c, ord)
  where ((t.c->'requires_flag') is null or story_flag_any(p, t.c->'requires_flag'))
    and ((t.c->'requires_insured') is null or story_venture_insured(p, ctx))
    and ((t.c->'needs_calm') is null or stress_calm_enough(p))
$$;

-- Once per real day, maybe start an ambient life event. While overloaded, scams and pressure offers
-- are picked first and fire more often (stressed people get targeted).
create or replace function story_daily_roll(p uuid)
returns void language plpgsql security definer set search_path = public as $$
declare e story_events; v_over boolean := not stress_calm_enough(p); v_prob numeric;
begin
  insert into learner_daily_check (profile_id, check_date, rolled)
    values (p, current_date, true) on conflict do nothing;
  if not found then return; end if;
  if exists (select 1 from learner_pending_events where profile_id = p and status = 'pending') then return; end if;
  select se.* into e from story_events se
   where se.category = 'ambient' and se.is_active and se.trigger_type = 'dice_roll'
     and (se.repeatable or not exists (select 1 from learner_pending_events lp where lp.profile_id = p and lp.event_id = se.id))
     and story_eligible(p, se)
   order by (case when v_over and coalesce((se.trigger_config->>'predatory')::boolean, false) then 0 else 1 end), random() limit 1;
  if e.id is null then return; end if;
  v_prob := coalesce((e.trigger_config->>'fire_probability')::numeric, 0.3);
  if v_over and coalesce((e.trigger_config->>'predatory')::boolean, false) then
    v_prob := least(0.9, v_prob * sim_cfg('stress_predatory_boost', 1.8));
  end if;
  if random() < v_prob then
    insert into learner_pending_events (profile_id, event_id, node_key) values (p, e.id, e.entry_node);
    update learner_daily_check set fired_event_id = e.id where profile_id = p and check_date = current_date;
  end if;
end $$;

-- Wrap story_choose: a needs_calm option cannot be picked while overloaded. (The original keeps its
-- logic as story_choose_core, so re-running this file after 02 always wraps the newest version.)
do $$ begin
  if position('story_choose_core' in pg_get_functiondef('story_choose(bigint,int)'::regprocedure)) = 0 then
    drop function if exists story_choose_core(bigint, int);
    alter function story_choose(bigint, int) rename to story_choose_core;
  end if;
end $$;
create or replace function story_choose(p_pending_id bigint, p_choice_index int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_ch jsonb;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  select n.choices -> p_choice_index into v_ch
    from learner_pending_events pe join story_nodes n on n.event_id = pe.event_id and n.node_key = pe.node_key
   where pe.id = p_pending_id and pe.profile_id = uid and pe.status = 'pending';
  if v_ch is not null and (v_ch ? 'needs_calm') and not stress_calm_enough(uid) then
    return jsonb_build_object('error', 'overloaded');
  end if;
  return story_choose_core(p_pending_id, p_choice_index);
end $$;
revoke all on function story_choose_core(bigint, int) from public, anon, authenticated;
revoke all on function story_choose(bigint, int) from public, anon;
grant execute on function story_choose(bigint, int) to authenticated;

-- ─────────────────────────────────────────────
-- ROOTING IN THE LESSONS
-- Numbers that the lessons give are used as the lessons give them (see 15-debt-schedules.sql).
-- ─────────────────────────────────────────────
-- (a) The phone loan in the credit-and-debt bridge: microfinance is about 28% a year (Module 1.2), so K1,800 over
--     3 months is K1,800 x 28% x 3/12 = K126 of interest, K1,926 in total.
update story_nodes n set
  body = replace(replace(replace(replace(n.body, 'K2,160', 'K1,926'), '(20% interest included)', '(7% interest: 28% a year over 3 months)'),
                 'plus 20% interest', 'plus 7% interest'), '2160', '1926'),
  choices = replace(replace(replace(replace(n.choices::text, 'K2,160', 'K1,926'), '2160', '1926'), '(20% interest included)', '(7% interest: 28% a year over 3 months)'),
                    '"rate": 80', '"rate": 28')::jsonb
from story_events e
where e.id = n.event_id and e.event_key in ('lesson_bridge_credit_debt_phone', 'consequence_microfinance_due');

-- (b) Chola: say what the lesson says. Banks about 20%, microfinance about 28%, payday 35% or more a year.
update story_nodes n set body = 'At that rate this is one of the most expensive loans {name} could possibly take. In Module 1.2, banks charge about 20% a year, microfinance about 28% and payday lenders 35% or more. Chola''s "small fee" works out to about 690% a year. Chola smiles. "Take it or leave it."'
from story_events e where e.id = n.event_id and e.event_key = 'ambient_chola_quick_loan' and n.node_key = 'reveal';
update story_nodes n set choices = jsonb_set(n.choices, '{0,narrative}', to_jsonb('You work it out together: K600 extra on K1,500 over three weeks is 40%, which is about 690% a year. Module 1.2 puts payday lenders at 35% a year or more. Chola is far beyond even that.'::text))
from story_events e where e.id = n.event_id and e.event_key = 'ambient_chola_quick_loan' and n.node_key = 'start';

-- (c) Which lesson each scenario is rooted in, and the point it comes from.
create table if not exists lesson_titles (lesson_id text primary key, title text not null);
insert into lesson_titles (lesson_id, title) values
  ('0c','Staying Safe and Consumer Protection'), ('1-0','Income, Budgeting and Goal Setting'), ('1-2','Credit and Debt Management'),
  ('1-3','Emergency Funds and Financial Resilience'), ('1-4','Digital Village Banking'), ('2-0','Risk Management and Insurance'),
  ('2-1','Basics of Investing'), ('2-2','Housing and Major Purchases'), ('2-4','Entrepreneurship and Small Business Finance'),
  ('3-1','Behavioral Economics in Personal Finance'), ('3-2','Digital Finance and Cybersecurity'), ('3-3','Consumer Protection'),
  ('3-5','Warranties and Consumer Rights'), ('p1','Financial Concepts Explained')
on conflict (lesson_id) do update set title = excluded.title;
create table if not exists story_event_lessons (
  event_key text not null, ord int not null default 1, lesson_id text not null references lesson_titles(lesson_id), point text not null,
  primary key (event_key, ord)
);
delete from story_event_lessons;
insert into story_event_lessons (event_key, ord, lesson_id, point) values
  ('ambient_chola_quick_loan',1,'1-2','Payday lenders typically charge the highest rates, often 35% a year or more. Work out the total cost before you sign.'),
  ('ambient_chola_quick_loan',2,'3-3','Under the Banking and Financial Services Act, 2026, banks, microfinance institutions and digital lenders all need a licence.'),
  ('consequence_chola_due',1,'1-2','Consistently paying on time is the strongest signal of reliability to any lender.'),
  ('lesson_bridge_credit_debt_phone',1,'1-2','The safest source of funds in a true emergency is your own emergency fund. Borrowing under pressure is when people skip comparing rates.'),
  ('consequence_microfinance_due',1,'1-2','Microfinance is about 28% a year, between banks (about 20%) and payday lenders (35% or more).'),
  ('ambient_whatsapp_guaranteed_returns',1,'2-1','High return with no risk is not a real combination. It is almost certainly fraudulent.'),
  ('ambient_whatsapp_guaranteed_returns',2,'p1','Guaranteed high returns with zero risk do not exist. Walk away.'),
  ('consequence_scam_aftermath',1,'0c','A message that creates urgency and pressure is a textbook scam pattern.'),
  ('ambient_flash_sale',1,'3-1','The most reliable way to beat present bias is a system that removes the decision before the moment arrives.'),
  ('ambient_flash_sale',2,'2-2','Ask whether a purchase would deplete your emergency fund.'),
  ('ambient_family_emergency',1,'1-3','An emergency fund of 3 to 6 months of essential expenses, kept somewhere liquid, is built for moments like this.'),
  ('ambient_family_emergency',2,'1-2','The safest source of funds in a true emergency is your own emergency fund.'),
  ('consequence_cousin_repays',1,'1-4','Clear records of who owes what, and when, prevent disputes.'),
  ('ambient_kunda_needs_help',1,'1-4','Unreliable record-keeping is the root of most group money disputes. Write down who owes what, and when.'),
  ('consequence_kunda_repays',1,'1-4','Clear records of who owes what, and when, prevent disputes.'),
  ('ambient_bulk_stock_offer',1,'2-4','Break-even is fixed costs divided by (price minus cost per unit). Know it before you commit cash.'),
  ('ambient_bulk_stock_offer',2,'p1','Liquidity: cash stuck on a shelf cannot be used in an emergency.'),
  ('consequence_bulk_stock_full',1,'2-4','Break-even is fixed costs divided by (price minus cost per unit).'),
  ('consequence_bulk_stock_test',1,'2-4','Break-even is fixed costs divided by (price minus cost per unit).'),
  ('venture_big_order',1,'2-4','Separating business cash from personal cash is what lets you see whether an order is really profitable.'),
  ('venture_big_order_paid',1,'2-4','Separating business cash from personal cash is what lets you see the real position.'),
  ('venture_big_order_paid_deposit',1,'2-4','Separating business cash from personal cash is what lets you see the real position.'),
  ('venture_break_in',1,'2-0','Insurance covers a loss minus your excess. Without cover you pay the whole loss yourself.'),
  ('venture_spoilage',1,'2-0','Know exactly what your cover includes. Cover that does not match the loss does not help.'),
  ('venture_equipment_breaks',1,'2-0','Read what your policy excludes. Repairs are often not covered.'),
  ('venture_slump',1,'2-4','Fixed costs do not shrink when sales fall, so break-even gets harder to reach.'),
  ('venture_profit_decision',1,'2-4','An owner''s draw is a deliberate, recorded transfer of money from the business to personal use.'),
  ('consequence_phone_connectivity_loss',1,'3-2','Check your mobile money often and set a SIM port PIN so fraud is caught and prevented early.'),
  ('ambient_windfall',1,'3-1','Mental accounting: people spend a bonus more freely than the same money from salary.'),
  ('ambient_windfall',2,'1-0','The 50/30/20 rule sends 20% to savings. Plan a windfall before it arrives.'),
  ('consequence_windfall_visitors',1,'2-1','A club or scheme with big returns and no risk is almost certainly fraudulent.'),
  ('consequence_upgrade_offer',1,'1-0','Budget first. The 50/30/20 rule keeps needs and wants in check and sends 20% to savings.'),
  ('ambient_medical_bill',1,'1-3','An emergency fund of 3 to 6 months of essential expenses is meant for exactly this.'),
  ('ambient_medical_bill',2,'p1','Liquidity: wealth you cannot turn into cash quickly does not help in an emergency.'),
  ('ambient_medical_bill',3,'1-2','A payday lender is the most expensive way to borrow in an emergency.'),
  ('ambient_faulty_phone',1,'3-5','A "No Returns, No Refunds, No Exchanges" sign is illegal under Section 48 of the Competition and Consumer Protection Act. Report violations to the CCPC on 5678 or at ccpc.org.zm.');
alter table lesson_titles enable row level security; alter table story_event_lessons enable row level security;
drop policy if exists "read lesson_titles" on lesson_titles; create policy "read lesson_titles" on lesson_titles for select using (true);
drop policy if exists "read story_event_lessons" on story_event_lessons; create policy "read story_event_lessons" on story_event_lessons for select using (true);
revoke insert, update, delete, truncate on lesson_titles, story_event_lessons from anon, authenticated;

create or replace function story_lessons_for(k text) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('lesson_id', l.lesson_id, 'title', t.title, 'point', l.point) order by l.ord), '[]'::jsonb)
  from story_event_lessons l join lesson_titles t on t.lesson_id = l.lesson_id where l.event_key = k
$$;
revoke all on function story_lessons_for(text) from public, anon, authenticated;

-- The choice result now also says which lesson the scenario is rooted in
create or replace function story_choose(p_pending_id bigint, p_choice_index int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_ch jsonb; v_key text; r jsonb;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  select n.choices -> p_choice_index, e.event_key into v_ch, v_key
    from learner_pending_events pe join story_events e on e.id = pe.event_id
    join story_nodes n on n.event_id = pe.event_id and n.node_key = pe.node_key
   where pe.id = p_pending_id and pe.profile_id = uid and pe.status = 'pending';
  if v_ch is not null and (v_ch ? 'needs_calm') and not stress_calm_enough(uid) then
    return jsonb_build_object('error', 'overloaded');
  end if;
  r := story_choose_core(p_pending_id, p_choice_index);
  if v_key is not null and coalesce((r->>'done')::boolean, false) then
    r := r || jsonb_build_object('lessons', story_lessons_for(v_key));
  end if;
  return r;
end $$;
revoke all on function story_choose(bigint, int) from public, anon;
grant execute on function story_choose(bigint, int) to authenticated;
