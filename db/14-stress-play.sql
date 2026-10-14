-- FinLit Zambia — Financial Character Simulator
-- 14-stress-play.sql  (safe to re-run)  Run AFTER 13.
--
--   yungsta_warning()   a warning BEFORE the missed-day loss (in-app only, for now)
--   stress_restart()    start again after bankruptcy (the learner sees the turning points first)
--   stress_board()      the leaderboard: calmest players first, never richest
--
-- All numbers are starting values. Board rules live in sim_config keys 'stress_board_*'.

insert into sim_config (key, value) values
  ('stress_board_days', '14'),          -- how many real days the average covers (one game year)
  ('stress_board_min_days', '3'),       -- a player needs this many days of readings...
  ('stress_board_min_choices', '3'),    -- ...and this many decisions in that window to be ranked
  ('stress_board_top', '10'),
  ('warn_firm_after_hour', '16')        -- Lusaka hour after which the warning turns firm
on conflict (key) do nothing;

-- ─────────────────────────────────────────────
-- WARNINGS
-- stage: none | soft | last_free | firm
--   soft       two days before missed days start costing money
--   last_free  the last free day: from tomorrow, a day without guidance costs money
--   firm       a day without guidance now costs money. Before 16:00 Lusaka time it is shown as soft.
-- ─────────────────────────────────────────────
create or replace function yungsta_warning()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); pr profiles; v_first date; v_start date; v_from date; v_today date := sim_today();
  v_hour int := extract(hour from (now() at time zone 'Africa/Lusaka'))::int; v_stage text := 'none';
  v_pct numeric := sim_cfg('neglect_loss_pct', 0.10); v_hours_left numeric;
begin
  if uid is null then return jsonb_build_object('stage', 'none'); end if;
  select * into pr from profiles where id = uid;
  select (min(completed_at) at time zone 'Africa/Lusaka')::date into v_first from learner_lessons where profile_id = uid;
  if v_first is null then return jsonb_build_object('stage', 'none'); end if;      -- hasn't started learning: nothing to miss

  v_start := v_first + sim_cfg('neglect_free_days', 3)::int;
  v_from := greatest(v_start, coalesce(pr.last_guided_on + 1, v_start),
                     coalesce(pr.neglect_through + 1, v_start), coalesce(pr.paused_until + 1, v_start));

  if (pr.paused_until is not null and pr.paused_until >= v_today) or pr.last_guided_on = v_today then
    v_stage := 'none';
  elsif v_today >= v_from then
    v_stage := case when v_hour >= sim_cfg('warn_firm_after_hour', 16) then 'firm' else 'soft' end;
  elsif v_from - v_today = 1 then v_stage := 'last_free';
  elsif v_from - v_today = 2 then v_stage := 'soft';
  end if;

  v_hours_left := 24 - extract(hour from (now() at time zone 'Africa/Lusaka')) - extract(minute from (now() at time zone 'Africa/Lusaka')) / 60.0;
  return jsonb_build_object('stage', v_stage, 'loss_pct', v_pct, 'est_loss', round(coalesce(pr.cash_balance, 0) * v_pct),
    'hours_left', round(v_hours_left, 1), 'name', coalesce(pr.character_name, 'Your yungsta'),
    'can_pause', (pr.last_pause_on is null or pr.last_pause_on <= v_today - sim_cfg('pause_cooldown_days', 14)::int),
    'pause_days', sim_cfg('pause_max_days', 3)::int);
end $$;

-- ─────────────────────────────────────────────
-- BANKRUPTCY: start again. The learner has already seen the turning points (stress_status returns them).
-- Debts are written off, businesses close, investments are sold off, and cash restarts small.
-- It is a chapter, not game over: a fresh start with a scar, and a Comeback mark when calm returns.
-- ─────────────────────────────────────────────
create or replace function stress_restart(p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_open bankruptcies; v_cash numeric; v_restart numeric := sim_cfg('stress_restart_cash', 3000);
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  select * into v_open from bankruptcies where profile_id = uid and resolved_at is null order by id desc limit 1 for update;
  if v_open.id is null then return jsonb_build_object('error', 'not_bankrupt'); end if;

  select cash_balance into v_cash from profiles where id = uid for update;
  perform adjust_cash_balance(uid, v_restart - coalesce(v_cash, 0), 'bankruptcy_restart', 'bankruptcies', v_open.id);
  update debts set status = 'written_off', outstanding_balance = 0 where profile_id = uid and status in ('active', 'defaulted');
  update ventures set status = 'failed', closed_at = now() where profile_id = uid and status = 'active';
  delete from holdings where profile_id = uid;
  perform adjust_reputation_score(uid, -10, 'bankruptcy');
  update bankruptcies set resolved_at = now(), note = left(coalesce(p_note, ''), 300) where id = v_open.id;
  update profiles set bankrupt_count = bankrupt_count + 1, stress = null, stress_updated_at = null,
         goal_started_at = null, comeback_at = null where id = uid;
  perform story_set_flag(uid, 'bankruptcy_restart', null);
  return jsonb_build_object('ok', true, 'cash', v_restart);
end $$;

-- ─────────────────────────────────────────────
-- LEADERBOARD: lowest average stress first.
--   * Group: same starting story AND same chapter (the highest core lesson group finished)
--   * Window: the last N real days; the average of each day's average reading
--   * To be ranked: enough days of readings AND enough decisions in the window (so "do nothing" cannot win)
--   * Names: the yungsta's name only. A learner in an open bankruptcy shows without a name.
--   * Rank for the caller is shown as a percentile ("calmer than X% of players"), never as a wealth figure.
-- ─────────────────────────────────────────────
create or replace function stress_board()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); v_days int := sim_cfg('stress_board_days', 14)::int;
  v_min_days int := sim_cfg('stress_board_min_days', 3)::int; v_min_ch int := sim_cfg('stress_board_min_choices', 3)::int;
  v_story text; v_chapter int; v_top jsonb; v_me jsonb; v_total int; v_my record; v_days_n int; v_ch_n int;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  select backstory into v_story from profiles where id = uid;
  select coalesce(max(substring(lesson_id from '^([0-4])')::int), 0) into v_chapter from learner_lessons where profile_id = uid;

  create temp table if not exists _sb (profile_id uuid, name text, avatar text, avg numeric, comeback boolean, bankrupt boolean) on commit drop;
  truncate _sb;
  insert into _sb
  select p.id, p.character_name, p.avatar, h.avg, p.comeback_at is not null,
         exists (select 1 from bankruptcies b where b.profile_id = p.id and b.resolved_at is null)
  from profiles p
  join (select profile_id, sum(stress_sum) / nullif(sum(samples), 0) as avg, count(*) as n
          from stress_history where day >= sim_today() - v_days group by profile_id) h on h.profile_id = p.id
  where p.backstory is not distinct from v_story
    and coalesce((select max(substring(lesson_id from '^([0-4])')::int) from learner_lessons l where l.profile_id = p.id), 0) = v_chapter
    and h.n >= v_min_days
    and (select count(*) from learner_event_log e where e.profile_id = p.id and e.choice_index is not null
            and e.created_at > now() - make_interval(days => v_days)) >= v_min_ch;

  select count(*) into v_total from _sb;
  select coalesce(jsonb_agg(jsonb_build_object('rank', t.rk, 'name', case when t.bankrupt then null else t.name end,
          'avatar', case when t.bankrupt then null else t.avatar end, 'avg', round(t.avg), 'comeback', t.comeback,
          'bankrupt', t.bankrupt, 'me', t.profile_id = uid) order by t.rk), '[]'::jsonb) into v_top
  from (select s.*, rank() over (order by s.avg, s.profile_id) as rk from _sb s order by s.avg, s.profile_id
        limit sim_cfg('stress_board_top', 10)::int) t;

  select * into v_my from (select s.*, rank() over (order by s.avg, s.profile_id) as rk from _sb s) r where r.profile_id = uid;
  if v_my.profile_id is not null then
    v_me := jsonb_build_object('ranked', true, 'rank', v_my.rk, 'of', v_total, 'avg', round(v_my.avg),
      'calmer_than', case when v_total > 1 then round(100.0 * (select count(*) from _sb where avg > v_my.avg) / (v_total - 1)) else null end);
  else
    select count(*) into v_days_n from stress_history where profile_id = uid and day >= sim_today() - v_days;
    select count(*) into v_ch_n from learner_event_log where profile_id = uid and choice_index is not null
       and created_at > now() - make_interval(days => v_days);
    v_me := jsonb_build_object('ranked', false, 'days', v_days_n, 'need_days', v_min_days, 'choices', v_ch_n, 'need_choices', v_min_ch);
  end if;

  return jsonb_build_object('group', jsonb_build_object('backstory', v_story, 'chapter', v_chapter), 'total', v_total,
                            'window_days', v_days, 'top', v_top, 'me', v_me);
end $$;

revoke all on function yungsta_warning() from public, anon;
revoke all on function stress_restart(text) from public, anon;
revoke all on function stress_board() from public, anon;
grant execute on function yungsta_warning() to authenticated;
grant execute on function stress_restart(text) to authenticated;
grant execute on function stress_board() to authenticated;
