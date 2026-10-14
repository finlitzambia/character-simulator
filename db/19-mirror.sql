-- FinLit Zambia — Financial Character Simulator
-- 19-mirror.sql  (safe to re-run)  Run AFTER 16 and 17.
--
-- "TAKE YOUR OWN ADVICE": the second half of practising with your yungsta.
--
-- WHY: teaching your yungsta is good for learning (explaining something makes you understand it). But people give
-- wiser advice about other people's money than they follow with their own. So after the learner has advised their
-- yungsta in the lesson's real-life moment, we hold up a mirror:
--   1. "You told your yungsta to do X. Would you do the same with your own money?"   (same / different / not sure / not relevant)
--   2. if not: "What would get in the way?"   (cost / other people / habit / trust)  and  "When will you try it?"
--   3. the yungsta remembers, and later asks on the dashboard: "Did you take your own advice?"
--      A yes earns a small reputation boost, because it rewards doing, not just knowing.
-- It is optional and never holds back a lesson's practice, certificate or anything else.
--
-- Functions:  practice_mirror_get(lesson)  practice_mirror_save(lesson, stance, barrier, when)  mirror_due()  mirror_check(id, done)
-- Adds one table. Changes or deletes nothing that exists.

create table if not exists learner_mirror (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  lesson_id text not null,
  practice_id bigint not null references learner_practice(id) on delete cascade,
  advice text not null,                    -- what the learner told their yungsta to do
  stance text not null,                    -- same | different | unsure | na
  barrier text,                            -- cost | people | habit | trust
  commit_when text,                        -- today | week | month
  status text not null default 'noted',    -- open (a promise is waiting) | done | dropped | noted (nothing promised)
  due_at timestamptz,
  nudges int not null default 0,
  created_at timestamptz not null default now(),
  checked_at timestamptz,
  unique (practice_id)
);
create index if not exists learner_mirror_due on learner_mirror (profile_id, status, due_at);

alter table learner_mirror enable row level security;
drop policy if exists "own mirror (read)" on learner_mirror;
create policy "own mirror (read)" on learner_mirror for select using (auth.uid() = profile_id);
revoke insert, update, delete, truncate on learner_mirror from anon, authenticated;

-- what did this learner tell their yungsta to do in this lesson's real-life moment?
create or replace function mirror_advice(p uuid, p_lesson text)
returns text language plpgsql stable security definer set search_path = public as $$
declare ev story_events; lg learner_event_log; nd story_nodes;
begin
  select * into ev from story_events where category = 'lesson_bridge' and trigger_config ->> 'lesson_id' = p_lesson and is_active order by id limit 1;
  if ev.id is null then return null; end if;
  select * into lg from learner_event_log where profile_id = p and event_id = ev.id and node_key = 'start' order by created_at desc, id desc limit 1;
  if lg.id is null or lg.choice_index is null then return null; end if;
  select * into nd from story_nodes where event_id = ev.id and node_key = 'start';
  return nullif(story_fill(p, nd.choices -> lg.choice_index ->> 'label'), '');
end $$;

-- the page asks: is there advice to mirror, and have they answered already?
create or replace function practice_mirror_get(p_lesson text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s learner_practice; m learner_mirror; v_adv text;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  if p_lesson is null or p_lesson !~ '^[a-z0-9-]{1,8}$' then return jsonb_build_object('error', 'bad_lesson'); end if;
  select * into s from learner_practice where profile_id = uid and lesson_id = p_lesson order by started_at desc, id desc limit 1;
  if s.id is null then return jsonb_build_object('available', false); end if;
  v_adv := mirror_advice(uid, p_lesson);
  if v_adv is null then return jsonb_build_object('available', false); end if;
  select * into m from learner_mirror where practice_id = s.id and profile_id = uid;
  return jsonb_build_object('available', true, 'advice', v_adv,
    'name', coalesce((select nullif(character_name, '') from profiles where id = uid), 'Your yungsta'),
    'saved', m.id is not null, 'stance', m.stance, 'when', m.commit_when);
end $$;

-- the learner answers
create or replace function practice_mirror_save(p_lesson text, p_stance text, p_barrier text default null, p_when text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s learner_practice; v_adv text; v_due timestamptz; v_status text; v_react text; v_when text;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  if p_lesson is null or p_lesson !~ '^[a-z0-9-]{1,8}$' then return jsonb_build_object('error', 'bad_lesson'); end if;
  if p_stance is null or p_stance <> all (array['same', 'different', 'unsure', 'na']) then return jsonb_build_object('error', 'bad_stance'); end if;
  if p_barrier is not null and p_barrier <> all (array['cost', 'people', 'habit', 'trust']) then return jsonb_build_object('error', 'bad_barrier'); end if;
  if p_when is not null and p_when <> all (array['today', 'week', 'month']) then return jsonb_build_object('error', 'bad_when'); end if;
  select * into s from learner_practice where profile_id = uid and lesson_id = p_lesson order by started_at desc, id desc limit 1;
  if s.id is null then return jsonb_build_object('error', 'no_practice'); end if;
  v_adv := mirror_advice(uid, p_lesson);
  if v_adv is null then return jsonb_build_object('error', 'no_advice'); end if;
  if exists (select 1 from learner_mirror where practice_id = s.id) then return jsonb_build_object('error', 'already_saved'); end if;

  if p_stance in ('different', 'unsure') then
    v_when := coalesce(p_when, 'week');
    v_status := 'open';
    v_due := now() + case v_when when 'today' then interval '1 day' when 'week' then interval '7 days' else interval '30 days' end;
    v_react := '{name}: "Deal. We both try it ' || case v_when when 'today' then 'today' when 'week' then 'this week' else 'this month' end || '. I will ask you how it went."';
  elsif p_stance = 'same' then
    v_status := 'noted'; p_barrier := null; v_when := null;
    v_react := '{name}: "Then we are on the same page. I will be watching you do it too."';
  else
    v_status := 'noted'; p_barrier := null; v_when := null;
    v_react := '{name}: "Fair enough. Maybe it will matter for you one day. I will remember it."';
  end if;
  if p_stance not in ('different', 'unsure') then p_barrier := null; end if;

  insert into learner_mirror (profile_id, lesson_id, practice_id, advice, stance, barrier, commit_when, status, due_at)
  values (uid, p_lesson, s.id, v_adv, p_stance, p_barrier, v_when, v_status, v_due);

  return jsonb_build_object('ok', true, 'promise', v_status = 'open', 'reaction', story_fill(uid, v_react));
end $$;

-- the dashboard asks: is a promise due for a check-in?
create or replace function mirror_due()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); m learner_mirror;
begin
  if uid is null then return null; end if;
  select * into m from learner_mirror where profile_id = uid and status = 'open' and due_at <= now() order by due_at limit 1;
  if m.id is null then return null; end if;
  return jsonb_build_object('id', m.id, 'advice', m.advice, 'lesson', m.lesson_id,
    'name', coalesce((select nullif(character_name, '') from profiles where id = uid), 'Your yungsta'));
end $$;

-- "Did you take your own advice?"  yes / not yet
create or replace function mirror_check(p_id bigint, p_done boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m learner_mirror;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  select * into m from learner_mirror where id = p_id and profile_id = uid and status = 'open' for update;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  if p_done then
    update learner_mirror set status = 'done', checked_at = now() where id = m.id;
    perform adjust_reputation_score(uid, 1.0, 'took own advice: lesson ' || m.lesson_id);
    return jsonb_build_object('ok', true, 'status', 'done', 'reaction', story_fill(uid, '{name}: "You did it yourself. That is the hard part. I am proud of you."'));
  end if;
  if m.nudges >= 1 then
    update learner_mirror set status = 'dropped', nudges = m.nudges + 1, checked_at = now() where id = m.id;
    return jsonb_build_object('ok', true, 'status', 'dropped', 'reaction', story_fill(uid, '{name}: "No stress. Maybe try it after your next lesson. I am not going anywhere."'));
  end if;
  update learner_mirror set nudges = m.nudges + 1, due_at = now() + interval '3 days', checked_at = now() where id = m.id;
  return jsonb_build_object('ok', true, 'status', 'open', 'reaction', story_fill(uid, '{name}: "No stress. I will ask again in a few days."'));
end $$;

do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('mirror_advice', 'practice_mirror_get', 'practice_mirror_save', 'mirror_due', 'mirror_check')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    if r.proname <> 'mirror_advice' then
      execute format('grant execute on function %s to authenticated', r.sig);
    end if;
  end loop;
end $$;
