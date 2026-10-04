-- FinLit Zambia — Financial Character Simulator
-- 08-character-profile.sql  (safe to re-run)  Run AFTER 07.
--
-- Builds the "financial character" summary from what the learner has actually DONE.
-- Each decision leaves a flag. character_trait_rules says what each flag shows about
-- the learner's character. Four traits, each starting at 50 and moving up or down:
--   prudence   - looks before leaping, resists pressure and scams
--   discipline - repays debts, saves, plans, reinvests
--   generosity - helps others, ideally in a way that is sustainable
--   boldness   - takes sensible entrepreneurial risk
-- Knowledge (lessons completed) is shown separately. Edit this table to tune it.

create table if not exists character_trait_rules (
  flag_key text not null,
  trait text not null check (trait in ('prudence', 'discipline', 'generosity', 'boldness')),
  points int not null,
  note text not null,
  primary key (flag_key, trait)
);
alter table character_trait_rules enable row level security;
drop policy if exists "read trait rules" on character_trait_rules;
create policy "read trait rules" on character_trait_rules for select using (true);
revoke insert, update, delete, truncate on character_trait_rules from anon, authenticated;

delete from character_trait_rules;
insert into character_trait_rules (flag_key, trait, points, note) values
-- prudence
 ('spotted_scam','prudence',12,'Checked a "guaranteed returns" offer before trusting it'),
 ('ignored_scam','prudence',6,'Ignored a too-good-to-be-true offer'),
 ('fell_for_scam','prudence',-15,'Sent money to a "guaranteed returns" scheme'),
 ('walked_away_from_chola_informed','prudence',10,'Worked out the real cost of a quick loan and said no'),
 ('declined_chola','prudence',5,'Turned down an expensive quick loan'),
 ('borrowed_from_chola','prudence',-8,'Took an expensive informal loan'),
 ('smart_shopper','prudence',8,'Compared prices instead of rushing a "today only" deal'),
 ('skipped_flash_sale','prudence',4,'Walked away from pressure to buy'),
 ('impulse_purchase','prudence',-8,'Bought on impulse because of a "today only" deal'),
 ('claimed_insurance','prudence',6,'Had cover in place when a loss hit'),
 ('tested_bulk_demand','prudence',8,'Tested demand before committing to a big stock order'),
 ('bought_bulk_stock','prudence',-3,'Tied up a lot of cash in one big stock order'),
 ('learned_connectivity_cost_hard_way','prudence',-6,'Lost money because you could not watch your account'),
 ('secured_premises','prudence',6,'Secured the business after a break-in'),
 ('invested_in_cooling','prudence',5,'Acted fast to save spoiling stock'),
 ('absorbed_theft','prudence',-5,'Carried on with the business exposed after a theft'),
-- discipline
 ('repaid_microfinance_on_time','discipline',10,'Repaid a microfinance loan on time'),
 ('repaid_chola_on_time','discipline',8,'Repaid an informal loan on time'),
 ('defaulted_microfinance','discipline',-12,'Missed a microfinance repayment'),
 ('defaulted_chola','discipline',-12,'Missed an informal loan repayment'),
 ('reinvested_profits','discipline',8,'Reinvested profit to grow the business'),
 ('split_profits','discipline',6,'Balanced taking profit home with reinvesting'),
 ('kept_profit_buffer','discipline',8,'Kept a safety buffer inside the business'),
 ('withdrew_profits','discipline',1,'Took business profit home'),
 ('lent_cousin_with_terms','discipline',6,'Lent money with clear terms in writing'),
 ('cousin_repaid','discipline',4,'Got repaid because the terms were clear'),
 ('set_family_boundary','discipline',4,'Helped family within your own limits'),
 ('replaced_equipment','discipline',4,'Fixed equipment properly instead of patching'),
 ('patched_equipment','discipline',-3,'Chose a quick patch over a lasting fix'),
 ('promoted_business','discipline',4,'Invested in the business when sales slowed'),
 ('impulse_purchase','discipline',-4,'Spent unplanned money on a sale item'),
-- generosity
 ('generous_to_kunda','generosity',10,'Lent a friend money when he needed it'),
 ('kunda_repaid','generosity',4,'Your kindness was repaid'),
 ('declined_kunda_kindly','generosity',2,'Said no kindly'),
 ('declined_kunda_coldly','generosity',-6,'Brushed off a friend who asked for help'),
 ('helped_family_gift','generosity',10,'Paid for a family emergency in full'),
 ('set_family_boundary','generosity',6,'Helped family within what you could afford'),
 ('lent_cousin_with_terms','generosity',8,'Helped family in a way that protects you both'),
 ('declined_family','generosity',-6,'Could not help family in an emergency'),
 ('borrowed_equipment','generosity',2,'Leaned on a neighbour and kept the goodwill'),
-- boldness
 ('started_venture','boldness',8,'Started your own business'),
 ('took_big_order','boldness',10,'Took on a big order'),
 ('took_big_order_with_deposit','boldness',8,'Took a big order and protected yourself with a deposit'),
 ('declined_big_order','boldness',-3,'Passed on a growth opportunity'),
 ('bought_bulk_stock','boldness',8,'Backed demand with a big stock order'),
 ('tested_bulk_demand','boldness',4,'Grew in measured steps'),
 ('passed_bulk_offer','boldness',-2,'Passed on a supplier discount'),
 ('promoted_business','boldness',6,'Spent to win customers'),
 ('reinvested_profits','boldness',6,'Put profit back to grow'),
 ('invested_own_cash','boldness',5,'Put more of your own cash into the business'),
 ('borrowed_from_chola','boldness',3,'Took a financing risk'),
-- guidance
 ('left_unguided','prudence',-4,'Made costly mistakes while left unguided'),
 ('debriefed_after_mistakes','discipline',4,'Learned from mistakes after a debrief');

create or replace function sim_teachback(p_pending_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_ev bigint; v_log bigint;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  select event_id into v_ev from learner_pending_events where id = p_pending_id and profile_id = uid;
  if v_ev is null then return jsonb_build_object('error', 'not_found'); end if;
  select id into v_log from learner_event_log
   where profile_id = uid and event_id = v_ev and choice_index is not null
   order by id desc limit 1;
  if v_log is not null then update learner_event_log set note = 'teachback' where id = v_log and note is null; end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function sim_teachback(bigint) from public, anon;
grant execute on function sim_teachback(bigint) to authenticated;

create or replace function sim_character_summary()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p profiles; v_pru int; v_dis int; v_gen int; v_bol int;
  v_know int; v_total_lessons int; v_decisions int; v_taught int; v_top text; v_low text; v_qa int; v_qc int;
  v_title text; v_blurb text; v_tip text; v_high jsonb; v_moments jsonb;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  select * into p from profiles where id = uid;

  with f as (select distinct flag_key from learner_flags where profile_id = uid),
       t as (select r.trait, sum(r.points) as pts from character_trait_rules r join f on f.flag_key = r.flag_key group by r.trait)
  select
    least(100, greatest(0, 50 + coalesce((select pts from t where trait = 'prudence'), 0)))::int,
    least(100, greatest(0, 50 + coalesce((select pts from t where trait = 'discipline'), 0)))::int,
    least(100, greatest(0, 50 + coalesce((select pts from t where trait = 'generosity'), 0)))::int,
    least(100, greatest(0, 50 + coalesce((select pts from t where trait = 'boldness'), 0)))::int
  into v_pru, v_dis, v_gen, v_bol;

  select count(distinct m.flag_key) into v_know from lesson_flag_map m
    join learner_flags lf on lf.flag_key = m.flag_key and lf.profile_id = uid;
  select count(*) into v_total_lessons from (select distinct flag_key from lesson_flag_map) x;
  select count(*) into v_decisions from learner_event_log where profile_id = uid and choice_index is not null;
  select count(*) into v_taught from learner_event_log where profile_id = uid and note = 'teachback';
  select count(*) filter (where status = 'answered'), count(*) filter (where correct) into v_qa, v_qc
    from learner_questions where profile_id = uid;

  select k into v_top from (values ('prudence', v_pru), ('discipline', v_dis), ('generosity', v_gen), ('boldness', v_bol)) a(k, s)
    order by s desc, k limit 1;
  select k into v_low from (values ('prudence', v_pru), ('discipline', v_dis), ('generosity', v_gen), ('boldness', v_bol)) a(k, s)
    order by s asc, k limit 1;

  if v_decisions < 3 then
    v_title := 'Just getting started';
    v_blurb := '{name}''s story has only just begun. Every piece of advice you give shapes who they become.';
  else
    select title, blurb into v_title, v_blurb from (values
      ('prudence',   'The Careful Planner',  'With your guidance, {name} looks before leaping. Pressure, hype and "limited time" offers do not rush them.'),
      ('discipline', 'The Steady Builder',   '{name} pays what they owe, keeps a buffer and builds step by step, because you taught them to.'),
      ('generosity', 'The Community Pillar', 'People can count on {name}. The challenge now is helping in ways that do not hurt them.'),
      ('boldness',   'The Bold Builder',     '{name} backs themselves and takes chances. Your job is to help turn that courage into sound decisions.')
    ) c(k, title, blurb) where k = v_top;
  end if;

  select tip into v_tip from (values
    ('prudence',   'Coach {name} to slow down before a deal: what does it really cost, and who is asking? Waiting a day is free.'),
    ('discipline', 'Coach {name} to pay debts on time and leave some profit inside the business as a buffer for the next surprise.'),
    ('generosity', 'Helping others builds goodwill. Show {name} how to do it with clear terms so it stays kind to everyone.'),
    ('boldness',   'Growth needs some risk. Encourage {name} to test small first, then scale up what works.')
  ) t(k, tip) where k = v_low;

  select coalesce(jsonb_agg(jsonb_build_object('trait', x.trait, 'points', x.points, 'note', x.note)), '[]'::jsonb) into v_high
  from (select r.trait, r.points, r.note from character_trait_rules r
         join (select distinct flag_key from learner_flags where profile_id = uid) f on f.flag_key = r.flag_key
        order by abs(r.points) desc, r.note limit 6) x;

  select coalesce(jsonb_agg(m.item order by m.created_at desc), '[]'::jsonb) into v_moments
  from (select l.created_at, jsonb_build_object(
            'event', story_fill(uid, coalesce(e.title, e.event_key)),
            'choice', story_fill(uid, n.choices -> l.choice_index ->> 'label'),
            'cash', l.cash_delta, 'reputation', l.reputation_delta, 'taught', (l.note = 'teachback')) as item
          from learner_event_log l
          join story_events e on e.id = l.event_id
          left join story_nodes n on n.event_id = l.event_id and n.node_key = l.node_key
         where l.profile_id = uid and l.choice_index is not null
         order by l.created_at desc limit 8) m;

  return jsonb_build_object(
    'name', coalesce(p.character_name, 'Your yungsta'), 'mentor', p.display_name, 'relationship', p.relationship,
    'avatar', p.avatar, 'backstory', p.backstory, 'reputation', p.reputation_score,
    'archetype', jsonb_build_object('title', v_title, 'blurb', story_fill(uid, v_blurb)),
    'traits', jsonb_build_object('prudence', v_pru, 'discipline', v_dis, 'generosity', v_gen, 'boldness', v_bol),
    'knowledge', jsonb_build_object('done', v_know, 'total', v_total_lessons),
    'decisions', v_decisions, 'taught', v_taught,
    'questions', jsonb_build_object('answered', coalesce(v_qa, 0), 'correct', coalesce(v_qc, 0)), 'growth_trait', v_low, 'growth_tip', story_fill(uid, v_tip),
    'highlights', v_high, 'moments', v_moments);
end $$;

revoke all on function sim_character_summary() from public, anon;
grant execute on function sim_character_summary() to authenticated;
