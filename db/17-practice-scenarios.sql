-- FinLit Zambia — Financial Character Simulator
-- 17-practice-scenarios.sql  (safe to re-run)  Run AFTER 16 (and after 13, so the lesson notes can be added).
--
-- MORE REAL-LIFE SCENARIOS FOR "PRACTICE WITH YOUR YUNGSTA".
-- Every lesson now has a real-life moment the learner lives through by advising their yungsta, so the
-- practice step is no longer only quiz questions. Lessons 1.4, 3.5 and P1 (which have no quiz questions)
-- now get real practice too. Each scenario has three choices with a different consequence for the yungsta's
-- cash and reputation, and a short note on why. Several choices also set a flag that triggers a follow-up
-- event a few days later, so decisions have consequences over time.
--
-- Many scenarios use ideas from "The Psychology of Money" by Morgan Housel (for example: luck and risk,
-- room for error, the "man in the car" paradox, compounding needs time, nothing is free, and being
-- reasonable rather than perfectly rational). The ideas are paraphrased in the course's own words.
--
-- Nothing here changes or deletes existing data. If you ever re-run 13-stress-content.sql, re-run this file
-- afterwards, because 13 clears and refills the lesson notes table.

-- ── 0a: chilimba_or_account ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_chilimba_or_account$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "0a"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name}'s chilimba money$t$, $t$A week after you finished Foundations, {name} asks you where their savings should live.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} has saved K1,500. Their friends run a chilimba and swear by it: you give, you wait your turn, you receive. A cousin says a bank account is safer. {name} does not want to look foolish either way. What do you advise?$t$, $j$[{"label": "Put all K1,500 into the chilimba", "narrative": "It works, because these friends are honest. But a chilimba has no regulator and no insurance, so if one member disappears before their turn there is nobody to complain to. Informal tools are not stupid, they are just unprotected.", "sets_flag": "chilimba_only"}, {"label": "Split it: some in the chilimba, the rest in a savings account", "narrative": "{name} keeps the social side they trust and adds a protected place for the rest. A plan you can actually live with beats a perfect plan you drop. (Psychology of Money: being reasonable beats being rational.)", "reputation_delta": 2, "sets_flag": "split_formal_informal"}, {"label": "Keep it all as cash at home", "narrative": "Nothing to join, nothing to fear, until a relative 'borrows' some and small spending nibbles away at the rest. About K200 disappears without anyone noticing.", "cash_delta": -200, "forced": true, "reputation_delta": -1, "sets_flag": "kept_cash_at_home"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_chilimba_or_account$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 0b: weekly_fees ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_weekly_fees$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "0b"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name} keeps losing money to fees$t$, $t${name} wants to know where their money keeps going.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Every Friday {name} sends K200 to their mother in the village. Each send carries a small fee plus the government levy, and over a month those little costs add up. {name} asks if there is a smarter way.$t$, $j$[{"label": "Send once a month instead of every week", "narrative": "Fewer transactions means fewer fees, and {name} plans the month's support in one go. The saving is small but real. (Psychology of Money: nothing is free, and small repeated costs are the ones nobody notices.)", "cash_delta": 60, "reputation_delta": 1, "sets_flag": "batched_transfers"}, {"label": "Keep sending weekly: each fee is tiny", "narrative": "Each fee looks harmless. Over a year they quietly cost {name} a few hundred kwacha that nobody remembers spending.", "cash_delta": -60, "forced": true}, {"label": "Give cash to a bus driver to carry home", "narrative": "The fee is gone, and so is the safety and the record. The envelope arrives K100 lighter and nobody can say why.", "cash_delta": -100, "forced": true, "reputation_delta": -1, "sets_flag": "sent_cash_by_driver"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_weekly_fees$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 0c: wrong_send_call ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_wrong_send_call$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "0c"}$j$::jsonb, $j${}$j$::jsonb, $k$chola$k$, $t$A stranger says they sent {name} money by mistake$t$, $t${name} gets a message and a phone call within minutes of each other.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$An SMS arrives that looks like a mobile money confirmation: K600 received. Minutes later a very polite caller begs {name} to send it back, it was meant for his sick mother. {name} wants to be kind. What do you advise?$t$, $j$[{"label": "Send the K600 back straight away, to be kind", "narrative": "The SMS was fake. No money ever arrived, so {name} just sent K600 of their own. Scammers sell a good story with a ticking clock. (Psychology of Money: when a story is appealing enough, people stop checking.)", "cash_delta": -600, "forced": true, "reputation_delta": -1, "sets_flag": "fell_for_wrong_send"}, {"label": "Check the real balance with the official USSD code first, then politely decline", "narrative": "The balance has not changed: nothing was ever sent. {name} ends the call and reports the number to the provider. A calm pause is the cheapest protection there is.", "reputation_delta": 2, "sets_flag": "verified_before_sending"}, {"label": "Hang up and block the number", "narrative": "Safe this time. Reporting the number as well would have protected the next person he calls.", "reputation_delta": 1, "sets_flag": "blocked_scammer"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_wrong_send_call$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 0d: money_script ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_money_script$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "0d"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name} feels guilty about money$t$, $t${name} asks you a question that is not really about numbers.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} grew up in a house where money was always short and always argued about. Now that they earn K2,000 a month, they either spend it all in the first week to make the worry go away, or panic and refuse to spend a ngwee. 'What is wrong with me?' they ask. What do you say?$t$, $j$[{"label": "Nothing is wrong. Your feelings come from what you lived through. Notice the habit, then set one small rule", "narrative": "No one is crazy about money: everyone's view was shaped by their own experience. {name} sets aside K100 the day pay lands, before the worry kicks in. A small rule beats a big promise.", "reputation_delta": 2, "sets_flag": "named_money_script"}, {"label": "Stop being so emotional and just follow a budget", "narrative": "The budget lasts nine days. Telling someone their feelings are wrong rarely changes what they do, and {name} overspends K150 to prove the point.", "cash_delta": -150, "forced": true, "reputation_delta": -1}, {"label": "Enjoy yourself. You only live once", "narrative": "A great week, then the old worry returns with an empty wallet. About K250 went on things {name} cannot even remember.", "cash_delta": -250, "forced": true, "reputation_delta": -1, "sets_flag": "spent_to_escape_worry"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_money_script$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 0d: man_in_the_car ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_man_in_the_car$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "0d"}$j$::jsonb, $j${}$j$::jsonb, $k$kunda$k$, $t${name} wants to look successful$t$, $t$A family wedding is coming up and {name} is nervous.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name}'s cousin is getting married and everyone will be there. {name} has K3,000 saved and sees a smart outfit plus a rented car for the day, K2,400 in all. 'People must see that I am doing well.' What do you advise?$t$, $j$[{"label": "Rent the car and buy the outfit", "narrative": "People glanced at the car and went back to worrying about how they themselves looked. K2,400 is gone, and so are most of the savings. (Psychology of Money: people admire the car, not the driver.)", "cash_delta": -500, "forced": true, "reputation_delta": -1, "sets_flag": "bought_status"}, {"label": "Wear your best clothes and spend K300 on a thoughtful gift", "narrative": "Nobody remembered who arrived in what. The gift was remembered, and K2,700 is still safe, quiet and growing. (Psychology of Money: wealth is the part you do not see.)", "reputation_delta": 2, "sets_flag": "skipped_status_spending"}, {"label": "Skip the wedding to save money", "narrative": "K3,000 saved, a family moment lost. Money is a tool for a good life, not a reason to miss one.", "sets_flag": "skipped_wedding"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_man_in_the_car$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 1-0: first_salary ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_first_salary$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "1-0"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name}'s first salary$t$, $t$It is payday, and {name} calls you before touching a thing.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} just started their first job on K4,000 gross. After NAPSA (5%), they take home K3,800 and feel rich. Friends want a celebration and a phone upgrade is calling. Where should the money go first?$t$, $j$[{"label": "Pay yourself first: move 20% (K760) to savings the day it lands, then budget the rest", "narrative": "Savings is what is left when ego is taken out of income, so {name} removes the temptation by moving it first. They still have plenty to enjoy. (Psychology of Money: saving does not need a fancy goal, it buys you options.)", "reputation_delta": 2, "sets_flag": "paid_self_first"}, {"label": "Save whatever is left at the end of the month", "narrative": "At the end of the month nothing is left. It never is, because spending expands to fill whatever is in the account.", "cash_delta": -150, "forced": true, "sets_flag": "saved_leftovers"}, {"label": "Celebrate big and sort out a budget next month", "narrative": "A great party. By Sunday K1,200 is gone, and 'next month' brings the same plan again.", "cash_delta": -400, "forced": true, "reputation_delta": -1, "sets_flag": "celebrated_first"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_first_salary$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 1-0: laptop_goal ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_laptop_goal$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "1-0"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$A goal that cannot be tracked$t$, $t${name} announces their big plan.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} says, 'This year I will be rich.' You ask what that means and they shrug. Which goal do you help them write?$t$, $j$[{"label": "Save K6,000 for a laptop deposit by 31 December: K500 each month", "narrative": "Specific, measurable, with a deadline. {name} can see at a glance whether they are on track and what to do if they slip.", "reputation_delta": 2, "sets_flag": "wrote_smart_goal"}, {"label": "Save a lot of money soon", "narrative": "No number, no date. By March it has drifted, and nobody notices because there was nothing to measure.", "reputation_delta": -1}, {"label": "Write 'GET RICH' on the wall and keep dreaming", "narrative": "Inspiring for a week. Without a number and a monthly step, a dream is only a wish."}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_laptop_goal$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 1-1: start_small_start_now ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_start_small_start_now$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "1-1"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$'K300 a month is nothing'$t$, $t${name} is thinking about giving up before starting.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} can only spare K300 a month and says, 'What is the point? It will never be enough.' A friend says to wait until they earn more. What do you advise?$t$, $j$[{"label": "Start now with K300 a month and do not touch it", "narrative": "The early years look tiny. The magic is in how long the money stays, not how big the start was. (Psychology of Money: the secret of compounding is time, so the best move is to start and stay.)", "reputation_delta": 2, "sets_flag": "started_saving_early"}, {"label": "Wait until you earn more, then save properly", "narrative": "Later arrives, but so do bigger bills. Every year of waiting is a year of growth {name} can never get back.", "reputation_delta": -1, "sets_flag": "waited_to_save"}, {"label": "Save K300 a month, but dip in whenever something comes up", "narrative": "A fund that keeps being raided never gets time to grow. After six months there is almost nothing there.", "cash_delta": -100, "forced": true}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_start_small_start_now$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 1-2: cosign_loan ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_cosign_loan$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "1-2"}$j$::jsonb, $j${}$j$::jsonb, $k$kunda$k$, $t$Kunda asks {name} to co-sign$t$, $t$Kunda catches {name} after work with a favour to ask.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Kunda's brother wants a K5,000 loan and the lender wants a co-signer. 'It is just a signature,' Kunda says. {name} does not want to seem disloyal. What do you advise?$t$, $j$[{"label": "Sign: family is family", "narrative": "Three months later the brother's business stalls and he cannot pay. {name} is now responsible, pays K600 and has a mark on their own record. (Psychology of Money: outcomes depend on luck and risk you cannot control.)", "cash_delta": -600, "forced": true, "reputation_delta": -2, "sets_flag": "cosigned_loan"}, {"label": "Decline kindly and offer another kind of help", "narrative": "{name} says no to the signature and helps the brother write a smaller, safer plan. It costs K100 and a hard conversation, and it keeps the friendship and the credit record intact.", "cash_delta": -100, "reputation_delta": 2, "sets_flag": "declined_cosign"}, {"label": "Ask to see the loan terms and the repayment plan first", "narrative": "The plan has holes in it. Kunda's brother goes back and asks for less. Asking questions turned a risky signature into a smaller, safer loan.", "reputation_delta": 1, "sets_flag": "questioned_cosign"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_cosign_loan$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 1-3: fund_or_phone ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_fund_or_phone$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "1-3"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$Is a new phone an emergency?$t$, $t${name} has a tempting idea and a cracked screen.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} has K2,500 in their emergency fund. Their phone still works but the screen is cracked, and they say a better phone would help their small business. 'This is an emergency,' they say. What do you advise?$t$, $j$[{"label": "No: that is a want. Repair the screen for about K250 and keep the fund", "narrative": "The phone works again and the fund stays whole. (Psychology of Money: money kept for surprises is what lets you ride out the ones you never predicted.)", "reputation_delta": 2, "sets_flag": "protected_emergency_fund"}, {"label": "Yes, use the fund for the upgrade", "narrative": "Two weeks later a medical bill of K500 arrives and the fund is gone. {name} has to borrow, and the interest costs more than the cracked screen ever did.", "cash_delta": -500, "forced": true, "reputation_delta": -1, "sets_flag": "spent_emergency_fund"}, {"label": "Buy the phone on instalments and keep the fund", "narrative": "The fund survives, but the instalments add up to about K300 in extra cost over six months.", "cash_delta": -300, "forced": true, "sets_flag": "phone_on_instalments"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_fund_or_phone$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 1-3: budget_no_wiggle ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_budget_no_wiggle$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "1-3"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$A budget with no wiggle room$t$, $t${name} is proud of a very neat spreadsheet.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} has planned every kwacha of a K3,500 salary down to the last ngwee and plans to live exactly on it. You know that taxi fares rise, relatives visit and phones break. What do you advise?$t$, $j$[{"label": "Build in a buffer: plan on 90% and keep the rest for surprises", "narrative": "When a wedding contribution and a faulty charger both land in the same week, the buffer absorbs them and the plan survives. (Psychology of Money: leave room for error, because plans rarely survive contact with real life.)", "reputation_delta": 2, "sets_flag": "built_buffer"}, {"label": "Keep the plan tight: discipline is all it takes", "narrative": "The first surprise breaks the plan, and the second makes {name} feel they have failed. A plan with no slack will fail on a normal week.", "cash_delta": -200, "forced": true, "reputation_delta": -1, "sets_flag": "no_buffer"}, {"label": "Skip budgeting: life is too unpredictable", "narrative": "No plan means no way of knowing where it went. K300 slips away without a trace.", "cash_delta": -300, "forced": true}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_budget_no_wiggle$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 1-4: village_bank_records ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_village_bank_records$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "1-4"}$j$::jsonb, $j${}$j$::jsonb, $k$ba_grace$k$, $t$The group that cannot agree who paid$t$, $t${name}'s village banking group has a problem at the meeting.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$A member says she repaid her K300 loan last month. The treasurer says she did not. Nothing was written down, only remembered. The group is splitting into sides. What do you advise?$t$, $j$[{"label": "Introduce a written record, read out at every meeting", "narrative": "Once every payment is written and read aloud, arguments shrink and trust grows. This dispute is settled by checking the mobile money statement, and it never happens again.", "reputation_delta": 2, "sets_flag": "introduced_group_records"}, {"label": "Trust the treasurer's memory", "narrative": "The member feels accused and leaves with her savings. The group shrinks, and K300 of contributions leave with her.", "cash_delta": -300, "forced": true, "reputation_delta": -1}, {"label": "Split the difference to keep the peace", "narrative": "Nobody is happy, and everyone remembers that unclear records mean someone always loses. K150 is lost to the settlement.", "cash_delta": -150, "forced": true}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_village_bank_records$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 2-0: stall_cover ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_stall_cover$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "2-0"}$j$::jsonb, $j${}$j$::jsonb, $k$ba_grace$k$, $t${name}'s market stall$t$, $t${name} runs a stall, and an insurance agent has just walked in.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name}'s stall holds K6,000 of stock. Last month a fire destroyed a stall two rows away. An agent offers cover for K180 a month. {name} says, 'It will not happen to me.' What do you advise?$t$, $j$[{"label": "Buy the cover, but first read what it covers and what it excludes", "narrative": "{name} learns that theft is covered only if the stall is locked, so they buy a good padlock too. Cheap peace of mind from reading the small print.", "cash_delta": -180, "reputation_delta": 2, "sets_flag": "bought_stall_cover"}, {"label": "Skip it: the odds are tiny", "narrative": "Three weeks later there is a break-in and K900 of stock is gone. 'Rare' is not 'never'. (Psychology of Money: the events that change things most are the ones nobody forecast.)", "cash_delta": -900, "forced": true, "reputation_delta": -1, "sets_flag": "skipped_cover_then_loss"}, {"label": "Buy the cheapest cover without reading it", "narrative": "The claim is rejected because the policy excludes theft from unlocked stalls. Cover that does not match the loss is not protection.", "cash_delta": -500, "forced": true, "sets_flag": "bought_wrong_cover"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_stall_cover$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 2-1: forty_percent_club ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_forty_percent_club$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "2-1"}$j$::jsonb, $j${}$j$::jsonb, $k$chola$k$, $t$A club that pays 40% a month$t$, $t$Chola has found a way to make {name}'s savings 'work harder'.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Chola, a smooth talker at the market, says his club pays 40% a month with no risk. Three of {name}'s friends have already been paid. {name} asks if they should put in K2,000. What do you advise?$t$, $j$[{"label": "Put in K500 as a small test", "narrative": "The first payout arrives, which is how these schemes hook people. Then the club closes and the K500 is gone. Early payouts are the bait. (Psychology of Money: nothing is free, and returns that look free usually hide the price.)", "cash_delta": -500, "forced": true, "reputation_delta": -1, "sets_flag": "tested_ponzi"}, {"label": "Ask for the licence and how the returns are produced, and walk away if there is no clear answer", "narrative": "There is no licence and no answer. Two months later the club vanishes with the money of everyone who stayed in. {name} lost nothing.", "reputation_delta": 2, "sets_flag": "questioned_scheme"}, {"label": "Put in the full K2,000 because friends got paid", "narrative": "The scheme collapses within weeks. Being paid by a scam does not prove it is real, it only proves it is paying early people with later people's money.", "cash_delta": -2000, "forced": true, "reputation_delta": -2, "sets_flag": "lost_to_ponzi"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_forty_percent_club$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 2-1: shares_drop ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_shares_drop$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "2-1"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name}'s shares drop 20%$t$, $t${name} is panicking about a number on a screen.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} bought K1,000 of shares in a LuSE-listed company six months ago. This month the price fell 20% and the news is gloomy. 'I should sell before it gets worse,' they say. What do you advise?$t$, $j$[{"label": "Hold, as long as the reason you bought still holds", "narrative": "A dip is the price of long-term returns. {name} pays it with patience instead of with a fire sale, and the price recovers over the next year. (Psychology of Money: returns are the fee for putting up with volatility.)", "reputation_delta": 2, "sets_flag": "held_through_dip"}, {"label": "Sell everything now to stop the pain", "narrative": "The loss is now real: K200 gone for good, and the price recovers a few months later without {name}.", "cash_delta": -200, "forced": true, "reputation_delta": -1, "sets_flag": "panic_sold"}, {"label": "Check the price every hour and decide each day", "narrative": "Constant checking makes every wobble feel like an emergency. {name} makes three small bad trades and pays K100 in fees and mistakes.", "cash_delta": -100, "forced": true}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_shares_drop$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 2-2: plot_with_loan ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_plot_with_loan$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "2-2"}$j$::jsonb, $j${}$j$::jsonb, $k$mr_daka$k$, $t${name} wants to buy a house$t$, $t${name} has fallen in love with a house.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} has found a house for K180,000 and says, 'The monthly payment is only a bit more than my rent!' They have not counted legal fees, transfer tax, insurance, repairs or service charges. What do you advise?$t$, $j$[{"label": "Add up every cost of owning, not just the monthly payment, then compare", "narrative": "The real cost is thousands of kwacha more up front, plus yearly upkeep. {name} decides to save for another year and buy with room to spare. (Psychology of Money: pick the choice you can stick with, not the one that looks best on paper.)", "reputation_delta": 2, "sets_flag": "counted_true_cost"}, {"label": "Buy now before prices rise", "narrative": "In month two the roof leaks. K800 of repairs, with no savings left to pay them. The cost that was not on the first page arrived on the second.", "cash_delta": -800, "forced": true, "reputation_delta": -1, "sets_flag": "bought_without_buffer"}, {"label": "Keep renting forever: buying is a trap", "narrative": "Maybe right for now. But rent rises every year, and 'never' is a long time. Owning is not always wrong, it is wrong when it stretches you too thin.", "sets_flag": "rent_forever"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_plot_with_loan$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 2-3: inputs_on_credit ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_inputs_on_credit$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "2-3"}$j$::jsonb, $j${}$j$::jsonb, $k$mr_daka$k$, $t$Inputs on credit for the season$t$, $t${name}'s uncle Mulenga needs advice before planting.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Uncle Mulenga farms maize. A lender offers seed and fertiliser on credit, repaid in kind at harvest. Rain is never certain and neither are harvest prices. He wants to plant the whole field with credit. What do you advise?$t$, $j$[{"label": "Take credit for half the field and plant the rest from his own savings", "narrative": "A mid-season dry spell cuts the harvest, but the savings-funded half and the lower repayment keep Mulenga afloat. Spreading risk is not weakness. (Psychology of Money: you control your decisions, not luck.)", "reputation_delta": 2, "sets_flag": "spread_farm_risk"}, {"label": "Borrow for the whole field and hope for rain", "narrative": "A dry spell cuts the harvest by a third and the repayment is due either way. Mulenga loses K700 and sells his goat.", "cash_delta": -700, "forced": true, "reputation_delta": -1, "sets_flag": "all_in_farm_credit"}, {"label": "Skip credit and plant a small plot with his own cash only", "narrative": "Safe, but the plot is too small to cover costs and school fees. The harvest is fine, the income is not."}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_inputs_on_credit$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 2-4: busy_not_profitable ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_busy_not_profitable$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "2-4"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name} is busy, but always broke$t$, $t${name} cannot work out why the shop never makes money.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name}'s tuck shop sells airtime and snacks. Each item earns K1 profit and they sell about 50 a day, roughly 1,500 a month. Rent is K800 and a helper costs K600 a month. 'I am busy all day, so why am I broke?' they ask. What do you advise?$t$, $j$[{"label": "Work out the break-even point first, then raise prices a little or cut a cost", "narrative": "K1,500 of profit minus K1,400 of fixed costs leaves almost nothing. A small price rise on the best sellers turns the shop around in a month. Busy is not the same as profitable.", "reputation_delta": 2, "sets_flag": "worked_out_breakeven"}, {"label": "Hire another helper to sell more", "narrative": "Another K600 a month of costs on the same thin margin. The shop now loses money every month, politely.", "cash_delta": -300, "forced": true, "reputation_delta": -1}, {"label": "Sell on credit to attract more customers", "narrative": "Sales go up and cash goes down. Three customers do not pay, and the shop absorbs K250 of bad debts.", "cash_delta": -250, "forced": true, "reputation_delta": -1, "sets_flag": "sold_on_credit_unwisely"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_busy_not_profitable$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 3-0: payslip_shock ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_payslip_shock$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "3-0"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name}'s first payslip$t$, $t${name} is angry at a piece of paper.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name}'s gross pay is K9,000 and they hate how much the tax takes. A colleague says to refuse overtime because it pushes you into a higher tax band and you end up with less. What do you advise?$t$, $j$[{"label": "Explain that only the extra slice is taxed at the higher rate, so overtime still pays", "narrative": "Only the part of income inside each band is taxed at that band's rate, not the whole salary. {name} takes the overtime and keeps most of it.", "reputation_delta": 2, "sets_flag": "understood_tax_bands"}, {"label": "Agree: refuse the overtime", "narrative": "{name} gives up K1,500 of overtime to avoid a few hundred kwacha of extra tax. Fear of a rule you do not understand can cost more than the rule.", "cash_delta": -500, "forced": true, "reputation_delta": -1}, {"label": "Ask to be paid in cash outside the payslip", "narrative": "No payslip, no NAPSA record, no proof of income when {name} later applies for a loan. K400 'saved' costs far more down the road.", "cash_delta": -400, "forced": true, "reputation_delta": -2, "sets_flag": "asked_cash_payment"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_payslip_shock$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 3-1: paid_for_nothing ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_paid_for_nothing$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "3-1"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name} already paid for it$t$, $t${name} cannot let go of a decision made weeks ago.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} paid K1,200 for a three-month online course and stopped after two weeks. They keep saying, 'I already paid, so I must push through.' Meanwhile, a K600 workshop that fits their job much better has come up. What do you advise?$t$, $j$[{"label": "Treat the K1,200 as gone and ask which option helps most from here", "narrative": "The money is spent either way, so only the future matters. {name} takes the workshop, which leads to a small side job. (Psychology of Money: you will change, so do not let a past choice trap you.)", "reputation_delta": 2, "sets_flag": "ignored_sunk_cost"}, {"label": "Finish the course out of principle", "narrative": "Three more months, another K200 of data and time, and nothing learned that {name} will use.", "cash_delta": -200, "forced": true, "reputation_delta": -1, "sets_flag": "fell_for_sunk_cost"}, {"label": "Pay for the workshop too, to feel less guilty", "narrative": "{name} now has two things they cannot finish and K600 less to show for it.", "cash_delta": -600, "forced": true}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_paid_for_nothing$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 3-2: otp_call ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_otp_call$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "3-2"}$j$::jsonb, $j${}$j$::jsonb, $k$chola$k$, $t$A call 'from the provider'$t$, $t${name}'s phone rings and the caller sounds official.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$A caller says he is from {name}'s mobile money provider: 'Your account will be blocked in ten minutes unless you read us the code we just sent.' {name} is frightened and begins to dial. What do you advise?$t$, $j$[{"label": "Read out the code to avoid being blocked", "narrative": "The code was a one-time password for moving money out. K800 vanishes in seconds. Urgency is the scammer's best tool. (Psychology of Money: fear makes any story believable.)", "cash_delta": -800, "forced": true, "reputation_delta": -2, "sets_flag": "shared_otp"}, {"label": "Hang up, then call the provider's official number yourself", "narrative": "The real provider confirms nothing is wrong and never asks for codes. {name} reports the number. Hanging up costs nothing.", "reputation_delta": 2, "sets_flag": "verified_caller"}, {"label": "Ask the caller to prove who they are by describing the account", "narrative": "The caller recites {name}'s name and town, easily found on social media, and sounds convincing. {name} reads out half the code before doubting and loses K300.", "cash_delta": -300, "forced": true, "reputation_delta": -1}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_otp_call$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 3-3: loan_contract_pressure ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_loan_contract_pressure$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "3-3"}$j$::jsonb, $j${}$j$::jsonb, $k$chola$k$, $t$'Sign today, the offer ends'$t$, $t${name} is holding a pen and a contract.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$A lender's agent offers {name} a K3,000 loan and says the offer ends today. The contract has fees {name} does not understand, and the agent says, 'Do not worry, I will explain later.' What do you advise?$t$, $j$[{"label": "Ask for the full terms in writing, take it home, and check that the lender is licensed", "narrative": "A licensed lender is happy to give written terms. The unlicensed one disappears. Pressure to decide now is a reason to slow down.", "reputation_delta": 2, "sets_flag": "checked_lender_licence"}, {"label": "Sign now: the offer is ending", "narrative": "The fees add K350 to the cost, much of it hidden in the small print. {name} signed what they did not understand.", "cash_delta": -350, "forced": true, "reputation_delta": -1, "sets_flag": "signed_under_pressure"}, {"label": "Sign, but get the agent to explain it out loud", "narrative": "A verbal promise is not in the contract. When the fees appear, the agent denies saying anything. {name} pays K200 extra.", "cash_delta": -200, "forced": true}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_loan_contract_pressure$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 3-4: diaspora_transfer ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_diaspora_transfer$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "3-4"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$Money from Johannesburg$t$, $t${name}'s brother wants to send support home.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name}'s brother works in Johannesburg and sends money home each month. A friend offers to 'bring it for you' at a rate that looks good. A licensed transfer service shows its fee upfront but a lower exchange rate. What do you advise?$t$, $j$[{"label": "Compare the total cost of each option for the same amount: fee plus exchange rate", "narrative": "The licensed service turns out cheaper overall once the rate is counted, and it leaves a record. Looking at the whole price beats looking at one number.", "reputation_delta": 2, "sets_flag": "compared_total_cost"}, {"label": "Use the informal courier: the rate looks better", "narrative": "The money arrives late and K300 short, with no record and nobody to complain to.", "cash_delta": -300, "forced": true, "reputation_delta": -1, "sets_flag": "used_informal_courier"}, {"label": "Pick whichever has the lowest advertised fee", "narrative": "A low fee with a poor exchange rate hides the real cost. {name} loses about K150 without noticing.", "cash_delta": -150, "forced": true}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_diaspora_transfer$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 3-5: fridge_warranty ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_fridge_warranty$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "3-5"}$j$::jsonb, $j${}$j$::jsonb, $k$mr_daka$k$, $t$The fridge that stopped working$t$, $t${name} has a warranty problem and a shop owner who does not want to hear it.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} bought a K2,400 fridge and its compressor failed in month eight, inside a one-year warranty. The shop says the warranty is void because the fridge was moved. {name} is ready to give up. What do you advise?$t$, $j$[{"label": "Keep the receipt and warranty card, write to the shop, and go to the consumer protection commission if refused", "narrative": "A written complaint with the receipt gets a fast answer. The shop repairs the fridge for free, and {name} learned that rights are only as strong as the paper behind them.", "reputation_delta": 2, "sets_flag": "claimed_warranty"}, {"label": "Pay K500 for a repair shop and forget it", "narrative": "The fridge works, but {name} paid for something the warranty should have covered.", "cash_delta": -500, "forced": true, "sets_flag": "paid_for_warranty_repair"}, {"label": "Post an angry message online and do nothing else", "narrative": "Lots of sympathy, no repair. Without a written complaint nobody has to answer.", "reputation_delta": -1}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_fridge_warranty$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 4-0: retire_later ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_retire_later$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "4-0"}$j$::jsonb, $j${}$j$::jsonb, $k$ba_grace$k$, $t$'I will think about retirement at 40'$t$, $t${name}, 24, brushes off the question.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} says, 'Retirement is too far away. I will start at 40 and save a lot more then.' NAPSA alone will replace only part of their income. What do you advise?$t$, $j$[{"label": "Start a small extra retirement saving now, K150 a month, and raise it with each pay rise", "narrative": "The small amount is easy to keep up, and the years it grows are years {name} can never buy back later. (Psychology of Money: time is the biggest lever in saving.)", "reputation_delta": 2, "sets_flag": "started_retirement_early"}, {"label": "Wait until 40 and save much more then", "narrative": "At 40 {name} has children, school fees and a bigger rent. Saving 'much more' never turns up, and fifteen years of growth are gone.", "reputation_delta": -1, "sets_flag": "postponed_retirement"}, {"label": "Rely on NAPSA alone", "narrative": "NAPSA gives a base, not the life {name} is used to. At 60 the gap between income and needs is obvious.", "sets_flag": "napsa_only"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_retire_later$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 4-1: year_end_bonus ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_year_end_bonus$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "4-1"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$A K6,000 year-end bonus$t$, $t${name} has been paid a bonus and everyone has an opinion.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} gets a K6,000 bonus. A cousin says spend it, a friend says invest it all in one exciting opportunity, and a colleague says to put it away. {name} asks what to do with money that feels like a gift. What do you advise?$t$, $j$[{"label": "Give every part a purpose: top up the emergency fund, clear the costliest debt, a small treat, invest the rest", "narrative": "Each kwacha has a job. {name} enjoys a small treat without guilt and finishes the year stronger. (Psychology of Money: the best plan is the one that is balanced enough to keep.)", "reputation_delta": 3, "sets_flag": "planned_the_bonus"}, {"label": "Spend it all: bonuses are for celebrating", "narrative": "People spend a bonus more freely than the same money from salary. By February it has vanished, about K700 of it on things {name} cannot name.", "cash_delta": -700, "forced": true, "reputation_delta": -1, "sets_flag": "spent_the_bonus"}, {"label": "Put all of it into one exciting investment", "narrative": "The 'sure thing' falls apart, and K1,500 of the bonus goes with it. Putting everything on one outcome is a bet, not a plan.", "cash_delta": -1500, "forced": true, "reputation_delta": -2, "sets_flag": "bet_the_bonus"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_year_end_bonus$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 4-2: health_bill ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_health_bill$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "4-2"}$j$::jsonb, $j${}$j$::jsonb, $k$ba_grace$k$, $t$A hospital bill nobody planned for$t$, $t${name}'s aunt has been taken ill.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name}'s aunt needs a hospital stay, and the bill could be K4,000. {name} has no plan for healthcare costs beyond hoping nobody gets sick. What do you advise they do before the next illness?$t$, $j$[{"label": "Find out what the national health insurance covers, then top up with a small separate health fund", "narrative": "The insurance covers part of the bill and the health fund covers the rest. {name} no longer has to beg relatives for help. Many surprises are cheaper when you have prepared for them.", "reputation_delta": 2, "sets_flag": "planned_for_health"}, {"label": "Hope nobody falls sick", "narrative": "Someone does. The family scrambles for K800 and sells a goat at a bad price.", "cash_delta": -800, "forced": true, "reputation_delta": -1, "sets_flag": "no_health_plan"}, {"label": "Plan to borrow from a payday lender if it happens", "narrative": "In a crisis the most expensive lender is the only one available. The interest on K1,500 costs K500 extra.", "cash_delta": -500, "forced": true, "reputation_delta": -1}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_health_bill$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── 4-3: uncle_no_will ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_uncle_no_will$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "4-3"}$j$::jsonb, $j${}$j$::jsonb, $k$ba_grace$k$, $t$The family fight over uncle's house$t$, $t${name} has just come home from a funeral.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name}'s uncle died without a will. Relatives are already arguing over his house and savings, and the widow fears being pushed out. {name} asks what they should do about their own affairs. What do you advise?$t$, $j$[{"label": "Write a simple will, name beneficiaries on accounts, store the will safely, and tell someone you trust", "narrative": "A clear will makes things easier for the family at their hardest moment. {name} also spares their loved ones the arguments they just witnessed.", "reputation_delta": 2, "sets_flag": "wrote_a_will"}, {"label": "Wait: wills are for rich old people", "narrative": "Anyone with something to leave benefits from a will. Without one, the family fights for months and legal costs reach K400.", "cash_delta": -400, "forced": true, "reputation_delta": -1, "sets_flag": "postponed_will"}, {"label": "Tell the family out loud what you want", "narrative": "Spoken wishes are not legally binding, and each relative remembers them differently. K150 goes on arguments and papers.", "cash_delta": -150, "forced": true}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_uncle_no_will$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── b1: register_catering ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_register_catering$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "b1"}$j$::jsonb, $j${}$j$::jsonb, $k$mr_daka$k$, $t$A catering business with no registration$t$, $t${name}'s side business is growing faster than its paperwork.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} runs a catering business from home. A company wants to hire them for a K12,000 event, but only from a registered supplier. They also want a bank loan. But the business is unregistered and {name} fears taxes. What do you advise?$t$, $j$[{"label": "Register the business and open a separate bank account", "narrative": "Registration costs about K250, but the company contract is signed, the bank treats {name} as a real business, and personal and business money stop mixing.", "cash_delta": -250, "reputation_delta": 2, "sets_flag": "registered_business"}, {"label": "Stay informal to avoid taxes", "narrative": "The company hires a registered caterer instead. {name} loses a K12,000 order and about K400 of margin in the process.", "cash_delta": -400, "forced": true, "reputation_delta": -1, "sets_flag": "stayed_informal"}, {"label": "Register later, when the business is bigger", "narrative": "Later is fine, until the next big order asks for it. {name} keeps small orders but misses the larger ones.", "sets_flag": "postponed_registration"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_register_catering$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── b2: vat_collected ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_vat_collected$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "b2"}$j$::jsonb, $j${}$j$::jsonb, $k$mr_daka$k$, $t$VAT is not profit$t$, $t${name}'s shop is registered for VAT and the month has ended.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} collected K9,000 of VAT from customers this month and paid K5,000 of VAT on supplies. They see K9,000 extra in the account and say, 'Business is booming!' What do you advise?$t$, $j$[{"label": "Set the VAT aside: you owe the difference between VAT charged and VAT paid", "narrative": "The tax owed is K4,000, kept ready and paid on time with no penalty. VAT collected is the tax authority's money, not the shop's, and the K5,000 of input VAT receipts reduced the bill.", "reputation_delta": 2, "sets_flag": "set_aside_vat"}, {"label": "Spend it: it is working capital", "narrative": "The tax bill arrives and the money is gone. {name} pays a K600 late penalty on top, and the shop is suddenly short on cash.", "cash_delta": -600, "forced": true, "reputation_delta": -2, "sets_flag": "spent_vat"}, {"label": "Ignore input VAT receipts: they are too much trouble", "narrative": "Without the receipts {name} cannot claim back what they paid on supplies, and overpays K250.", "cash_delta": -250, "forced": true}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_vat_collected$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── u1: plot_title_check ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_plot_title_check$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "u1"}$j$::jsonb, $j${}$j$::jsonb, $k$mr_daka$k$, $t$A plot with 'papers in process'$t$, $t${name} has K5,000 and a seller in a hurry.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$A seller offers {name} a plot of land for K5,000 cash: 'The title papers are in process, but I need the money today.' {name} could also put the same money into a listed property investment trust. What do you advise?$t$, $j$[{"label": "Get a lawyer to check the title first, and compare the plot's likely return with the trust", "narrative": "The title search shows a dispute with another buyer. {name} walks away and invests in the trust instead, which pays a modest steady distribution. Verified ownership comes before price.", "reputation_delta": 2, "sets_flag": "checked_land_title"}, {"label": "Pay cash now: the seller is in a hurry", "narrative": "Three months later another family produces the real title. {name}'s K5,000 is stuck in a court dispute and K2,000 is gone in costs.", "cash_delta": -2000, "forced": true, "reputation_delta": -2, "sets_flag": "bought_unverified_land"}, {"label": "Skip property and keep all the money in cash", "narrative": "Safe, but prices rise and the cash buys less each year. Doing nothing is also a choice with a cost.", "sets_flag": "avoided_property"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_plot_title_check$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── u2: cheap_share_trap ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_cheap_share_trap$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "u2"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$Which share is the bargain?$t$, $t${name} is comparing two companies on the LuSE.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Share A costs K2, and share B costs K40. Everyone says, 'A is cheap, so buy A.' {name} asks what you think. What do you advise?$t$, $j$[{"label": "Compare earnings, debt and dividend yield, not just the share price", "narrative": "Share A earns almost nothing and carries heavy debt, which is why it is cheap. Share B's price is higher, but its earnings justify it. A low price is not a bargain by itself.", "reputation_delta": 2, "sets_flag": "analysed_before_buying"}, {"label": "Buy the cheaper share", "narrative": "A cheap price often means a company is in trouble. The share falls further and {name} loses K300.", "cash_delta": -300, "forced": true, "reputation_delta": -1, "sets_flag": "bought_cheap_share"}, {"label": "Buy the one everyone is talking about", "narrative": "{name} joins the crowd late, at the top. (Psychology of Money: other people are playing different games from you, so be careful whose lead you follow.)", "cash_delta": -400, "forced": true, "reputation_delta": -1, "sets_flag": "followed_the_crowd"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_cheap_share_trap$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── u3: ipo_oversubscribed ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_ipo_oversubscribed$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "u3"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$An IPO that everyone wants$t$, $t${name} is excited about a company listing on the LuSE.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$A company is listing on the LuSE and {name} wants to apply for K4,000 of shares. Everyone says the issue will be oversubscribed, which means demand will exceed the shares on offer. What do you advise?$t$, $j$[{"label": "Apply for what you can afford to hold for years and expect to receive fewer shares than you asked for", "narrative": "{name} is allocated about half, the rest of the money stays in their account, and there is no borrowing, no stress and no forced selling. Oversubscription means scaled-back allocations.", "reputation_delta": 2, "sets_flag": "applied_within_means"}, {"label": "Borrow to apply for double, hoping to sell quickly", "narrative": "{name} gets a fraction of what they asked for and still owes interest on the full loan. About K350 is lost.", "cash_delta": -350, "forced": true, "reputation_delta": -1, "sets_flag": "borrowed_for_ipo"}, {"label": "Skip the IPO and buy on day one at any price", "narrative": "The first-day rush pushes the price up and {name} pays a premium of about K500 over what the issue price would have cost.", "cash_delta": -500, "forced": true, "reputation_delta": -1}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_ipo_oversubscribed$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── u4: crypto_screenshot ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_crypto_screenshot$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "u4"}$j$::jsonb, $j${}$j$::jsonb, $k$kunda$k$, $t$A screenshot that makes everyone jealous$t$, $t$Kunda shows {name} his phone with a very big grin.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Kunda's screenshot shows K500 turned into K5,000 in two weeks. 'Everyone is in,' he says. {name} is tempted by K3,000. What do you advise?$t$, $j$[{"label": "Learn how wallets and keys work first, and only put in an amount you could lose completely", "narrative": "{name} invests K100 as a test. The price falls 40% a month later, and the loss is small and the lesson is cheap. (Psychology of Money: stories of fast wealth hide the many who did not win.)", "cash_delta": -100, "reputation_delta": 1, "sets_flag": "tested_crypto_small"}, {"label": "Put in K3,000 before the price goes higher", "narrative": "The price drops by half within weeks. {name} loses K1,500 and learns that screenshots only show winners.", "cash_delta": -1500, "forced": true, "reputation_delta": -2, "sets_flag": "all_in_crypto"}, {"label": "Ignore it: all crypto is a scam", "narrative": "Sometimes right, but without understanding how it works {name} cannot tell real risk from outright fraud when the next offer arrives.", "sets_flag": "dismissed_crypto"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_crypto_screenshot$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── p1: cash_under_mattress ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$lesson_bridge_cash_under_mattress$k$, $k$lesson_bridge$k$, $k$external_signal$k$, $j${"lesson_id": "p1"}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$K5,000 under the mattress$t$, $t${name} is very proud of their hiding place.$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t${name} keeps K5,000 in a box under the mattress, 'to be safe'. A year later prices have risen and K5,000 buys noticeably less. What do you advise?$t$, $j$[{"label": "Keep part as a cash emergency buffer and put the rest where it can earn at least the rate of inflation", "narrative": "{name} keeps K1,500 within reach and puts the rest in a savings product. The cash buffer handles a surprise bill, and the rest has stopped shrinking in value.", "reputation_delta": 2, "sets_flag": "balanced_liquidity_and_growth"}, {"label": "Keep it all in cash: cash is safest", "narrative": "Not stolen, but each year it buys less. Inflation quietly takes about K250 of purchasing power.", "cash_delta": -250, "forced": true, "sets_flag": "cash_loses_to_inflation"}, {"label": "Lock all of it into something that cannot be sold quickly", "narrative": "When a hospital bill arrives {name} cannot reach the money in time and borrows at a high rate. K500 is lost to costs.", "cash_delta": -500, "forced": true, "reputation_delta": -1, "sets_flag": "no_liquidity"}]$j$::jsonb from story_events where event_key = $k$lesson_bridge_cash_under_mattress$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ═══════════ FOLLOW-UP EVENTS (arrive a few days after the matching decision) ═══════════

-- ── follow-up: paid_first_pays_off ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_practice_paid_first_pays_off$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": ["paid_self_first", "started_saving_early"], "delay_real_days": 2}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name}'s surprise bill$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$A bill of K600 arrives out of nowhere: a family member's school trip. Because {name} saved first, they pay it without borrowing and without panic.$t$, $j$[{"label": "Continue", "narrative": "The money that was set aside just did its job. {name} avoided about K150 of borrowing costs and slept well. (Psychology of Money: saving is for the surprises you cannot see coming.)", "cash_delta": 150, "reputation_delta": 1, "sets_flag": "saving_paid_off"}]$j$::jsonb from story_events where event_key = $k$consequence_practice_paid_first_pays_off$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── follow-up: chilimba_member_vanishes ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_practice_chilimba_member_vanishes$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": ["chilimba_only"], "delay_real_days": 2}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$A member of the chilimba disappears$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Three weeks later one member moves away before their turn comes and stops answering their phone. The pot is short.$t$, $j$[{"label": "Continue", "narrative": "{name} loses K400 and learns what 'no protection' means in practice. The group meant well, but trust was the only safety net.", "cash_delta": -400, "forced": true, "sets_flag": "chilimba_lost_money"}]$j$::jsonb from story_events where event_key = $k$consequence_practice_chilimba_member_vanishes$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── follow-up: stall_break_in_cover_paid ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_practice_stall_break_in_cover_paid$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": ["bought_stall_cover"], "delay_real_days": 2}$j$::jsonb, $j${}$j$::jsonb, $k$ba_grace$k$, $t$A break-in at {name}'s stall$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Someone breaks into {name}'s stall overnight. Because the stall had a good lock, as the policy required, the claim is valid.$t$, $j$[{"label": "Continue", "narrative": "The insurer pays K1,200 after the excess. {name} reopens in two days. The K180 a month suddenly looks like a bargain.", "cash_delta": 1200, "reputation_delta": 2, "sets_flag": "insurance_paid_out"}]$j$::jsonb from story_events where event_key = $k$consequence_practice_stall_break_in_cover_paid$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── follow-up: held_shares_recover ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_practice_held_shares_recover$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": ["held_through_dip"], "delay_real_days": 3}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t$The shares have recovered$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$A few months on, the company reports good results and the share price climbs back past where {name} bought.$t$, $j$[{"label": "Continue", "narrative": "{name} is up K250. The only price for it was patience. (Psychology of Money: the fee for long-term returns is paid in discomfort, not in cash.)", "cash_delta": 250, "reputation_delta": 1, "sets_flag": "patience_paid_off"}]$j$::jsonb from story_events where event_key = $k$consequence_practice_held_shares_recover$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── follow-up: no_will_dispute ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_practice_no_will_dispute$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": ["postponed_will"], "delay_real_days": 3}$j$::jsonb, $j${}$j$::jsonb, $k$ba_grace$k$, $t${name} gets a call from a lawyer$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$A relative has challenged how {name}'s own small estate would be shared out, and a lawyer needs a fee to keep things calm while the family decides.$t$, $j$[{"label": "Continue", "narrative": "{name} pays K300 to settle it quietly and writes a will that same week. A will is cheaper than a dispute.", "cash_delta": -300, "forced": true, "sets_flag": "wrote_will_after_scare"}]$j$::jsonb from story_events where event_key = $k$consequence_practice_no_will_dispute$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ── follow-up: bonus_plan_pays ──
insert into story_events (event_key, category, trigger_type, trigger_config, eligibility_config, character_key, title, intro, entry_node)
values ($k$consequence_practice_bonus_plan_pays$k$, $k$consequence$k$, $k$flag_delay$k$, $j${"after_flag": ["planned_the_bonus"], "delay_real_days": 3}$j$::jsonb, $j${}$j$::jsonb, $k$inner_voice$k$, $t${name} is calm at year end$t$, $t$$t$, 'start')
on conflict (event_key) do update set category = excluded.category, trigger_type = excluded.trigger_type, trigger_config = excluded.trigger_config,
  eligibility_config = excluded.eligibility_config, character_key = excluded.character_key, title = excluded.title, intro = excluded.intro, is_active = true;
insert into story_nodes (event_id, node_key, body, choices)
select id, $k$start$k$, $t$Rent goes up and a phone dies in the same month. {name}'s emergency fund, topped up from the bonus, covers both. Their costly debt is already cleared.$t$, $j$[{"label": "Continue", "narrative": "{name} saves about K300 in interest and avoids the stress that lands on everyone else this month. A plan with room in it is a plan that survives.", "cash_delta": 300, "reputation_delta": 1, "sets_flag": "plan_survived_surprise"}]$j$::jsonb from story_events where event_key = $k$consequence_practice_bonus_plan_pays$k$
on conflict (event_id, node_key) do update set body = excluded.body, choices = excluded.choices;

-- ═══════════ LESSON NOTES: the "From Module ..." box shown after each scenario ═══════════
-- Needs file 13 (it creates the two tables). If 13 has not been run, this block is skipped and the scenarios still work.
do $do$
begin
  if to_regclass('public.lesson_titles') is null or to_regclass('public.story_event_lessons') is null then
    raise notice 'Skipping lesson notes: run 13-stress-content.sql, then re-run this file.';
    return;
  end if;
  insert into lesson_titles (lesson_id, title) values
    ('0a', 'Foundations & Introduction to Mobile Money'),
    ('0b', 'Mobile Money in Practice'),
    ('0c', 'Staying Safe & Consumer Protection'),
    ('0d', 'Money Mindset & Inclusion'),
    ('1-0', 'Income, Budgeting & Goal Setting'),
    ('1-1', 'Saving and Banking'),
    ('1-2', 'Credit and Debt Management'),
    ('1-3', 'Emergency Funds & Resilience'),
    ('1-4', 'Digital Village Banking'),
    ('2-0', 'Risk Management and Insurance'),
    ('2-1', 'Basics of Investing'),
    ('2-2', 'Housing and Major Purchases'),
    ('2-3', 'Agricultural & Rural Finance'),
    ('2-4', 'Entrepreneurship & Small Business Finance'),
    ('3-0', 'Taxation and Financial Planning'),
    ('3-1', 'Behavioral Economics'),
    ('3-2', 'Digital Finance & Cybersecurity'),
    ('3-3', 'Consumer Protection'),
    ('3-4', 'Remittances & Diaspora Finance'),
    ('3-5', 'Warranties and Consumer Rights'),
    ('4-0', 'Retirement and Estate Planning'),
    ('4-1', 'Comprehensive Review'),
    ('4-2', 'Health & Long-Term Care Planning'),
    ('4-3', 'Succession Law and Wills'),
    ('u1', 'Real Estate in Zambia'),
    ('u2', 'Investment Analysis Fundamentals'),
    ('u3', 'The LuSE — Complete Guide'),
    ('u4', 'Cryptocurrency Fundamentals'),
    ('b1', 'Starting & Running a Business'),
    ('b2', 'VAT — Input, Output & Compliance'),
    ('p1', 'Financial Concepts Explained'),
    ('error', 'not_signed_in'),
    ('practice_start', 'practice_status')
  on conflict (lesson_id) do nothing;
  insert into story_event_lessons (event_key, ord, lesson_id, point) values
    ('lesson_bridge_chilimba_or_account', 1, '0a', 'Informal tools like a chilimba work on trust but carry no regulatory protection.'),
    ('lesson_bridge_weekly_fees', 1, '0b', 'Mobile money sends carry a fee plus the government levy, and the levy cannot be avoided by switching provider.'),
    ('lesson_bridge_wrong_send_call', 1, '0c', 'A ''wrong transfer'' request is a classic scam: check your own balance through official channels before sending anything back.'),
    ('lesson_bridge_money_script', 1, '0d', 'Money scripts are unconscious beliefs formed early in life that quietly shape how you spend and save.'),
    ('lesson_bridge_man_in_the_car', 1, '0d', 'Looking rich and being wealthy are different: the money you do not spend is the part that builds wealth.'),
    ('lesson_bridge_first_salary', 1, '1-0', 'The 50/30/20 rule sends 20% of take-home pay to savings. Plan it before the money arrives.'),
    ('lesson_bridge_laptop_goal', 1, '1-0', 'A SMART goal is Specific, Measurable, Achievable, Relevant and Time-bound.'),
    ('lesson_bridge_start_small_start_now', 1, '1-1', 'Compound interest rewards time: starting earlier and staying invested beats starting later with more.'),
    ('lesson_bridge_cosign_loan', 1, '1-2', 'Co-signing means you are fully responsible if the borrower cannot pay.'),
    ('lesson_bridge_fund_or_phone', 1, '1-3', 'An emergency fund of 3 to 6 months of essential expenses is for true emergencies, not wants.'),
    ('lesson_bridge_budget_no_wiggle', 1, '1-3', 'Plan for a plan that goes wrong: a buffer and an emergency fund protect a budget from normal surprises.'),
    ('lesson_bridge_village_bank_records', 1, '1-4', 'Clear written records of who owes what, and when, prevent most disputes in group savings.'),
    ('lesson_bridge_stall_cover', 1, '2-0', 'Insurance only pays for what the policy actually covers. Read the exclusions and your excess before you buy.'),
    ('lesson_bridge_forty_percent_club', 1, '2-1', 'A scheme that offers high returns with no risk is almost certainly fraudulent.'),
    ('lesson_bridge_shares_drop', 1, '2-1', 'Investing means accepting short-term ups and downs as the cost of long-term growth.'),
    ('lesson_bridge_plot_with_loan', 1, '2-2', 'The true cost of buying includes fees, tax, insurance, maintenance and the loan interest, not only the monthly payment.'),
    ('lesson_bridge_inputs_on_credit', 1, '2-3', 'Agricultural credit works best when repayment is matched to the harvest and risk is spread.'),
    ('lesson_bridge_busy_not_profitable', 1, '2-4', 'Break-even is fixed costs divided by (price minus cost per unit). Know it before you grow.'),
    ('lesson_bridge_payslip_shock', 1, '3-0', 'PAYE is charged band by band: only income above each threshold is taxed at the higher rate.'),
    ('lesson_bridge_paid_for_nothing', 1, '3-1', 'The sunk cost fallacy: money already spent should not drive a decision about what to do next.'),
    ('lesson_bridge_otp_call', 1, '3-2', 'A provider will never ask for your OTP or PIN. Hang up and call the official number yourself.'),
    ('lesson_bridge_loan_contract_pressure', 1, '3-3', 'Financial service providers must be licensed. Get every term in writing before you sign.'),
    ('lesson_bridge_diaspora_transfer', 1, '3-4', 'The cost of sending money home is the fee plus the exchange-rate margin. Compare both.'),
    ('lesson_bridge_fridge_warranty', 1, '3-5', 'Keep your receipt and warranty card. A written complaint, then the consumer protection commission, is the route when a seller refuses.'),
    ('lesson_bridge_retire_later', 1, '4-0', 'Time matters more than the amount: starting early with a small sum beats starting late with a large one.'),
    ('lesson_bridge_year_end_bonus', 1, '4-1', 'Plan a windfall before it arrives: emergency fund, expensive debt, a small reward, then investing.'),
    ('lesson_bridge_health_bill', 1, '4-2', 'Long-term care and health costs are far cheaper to prepare for than to meet by borrowing in a crisis.'),
    ('lesson_bridge_uncle_no_will', 1, '4-3', 'A written will makes your wishes legally clear. Without one, intestate succession rules decide, not you.'),
    ('lesson_bridge_register_catering', 1, 'b1', 'A registered business can sign contracts, open a business account and apply for credit.'),
    ('lesson_bridge_vat_collected', 1, 'b2', 'VAT payable is VAT charged on sales minus VAT paid on purchases. Keep every input VAT receipt.'),
    ('lesson_bridge_plot_title_check', 1, 'u1', 'Verify the land title before you pay. A property trust offers a way into property with a smaller entry point.'),
    ('lesson_bridge_cheap_share_trap', 1, 'u2', 'A share''s price says little by itself. Look at earnings, debt and dividends to judge value.'),
    ('lesson_bridge_ipo_oversubscribed', 1, 'u3', 'When an issue is oversubscribed, applicants are allocated fewer shares than they requested.'),
    ('lesson_bridge_crypto_screenshot', 1, 'u4', 'Never invest in something you do not understand. Only risk an amount you could lose completely.'),
    ('lesson_bridge_cash_under_mattress', 1, 'p1', 'Liquidity means being able to turn wealth into cash quickly. Inflation reduces what cash can buy over time.'),
    ('consequence_practice_paid_first_pays_off', 1, '1-1', 'Paying yourself first turns a surprise bill into an inconvenience instead of a crisis.'),
    ('consequence_practice_chilimba_member_vanishes', 1, '0a', 'A chilimba depends on trust alone: there is no deposit protection and no regulator to turn to.'),
    ('consequence_practice_stall_break_in_cover_paid', 1, '2-0', 'A valid insurance claim pays for the loss minus your excess, if you follow the conditions.'),
    ('consequence_practice_held_shares_recover', 1, '2-1', 'Short-term price falls are normal. What matters is whether the reason you invested still holds.'),
    ('consequence_practice_no_will_dispute', 1, '4-3', 'Intestate succession rules apply when there is no will. A written will keeps your wishes in your hands.'),
    ('consequence_practice_bonus_plan_pays', 1, '4-1', 'A windfall used for an emergency fund and costly debt first improves resilience immediately.')
  on conflict (event_key, ord) do update set lesson_id = excluded.lesson_id, point = excluded.point;
end $do$;

-- check: how many practice scenarios and follow-ups are now loaded (expect 36 and 6)
select
  (select count(*) from story_events where event_key like 'lesson_bridge_%' and is_active) as practice_scenarios,
  (select count(*) from story_events where event_key like 'consequence_practice_%' and is_active) as follow_ups;
