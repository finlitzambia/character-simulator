-- FinLit Zambia — Financial Character Simulator
-- 16-practice.sql  (safe to re-run)
--
-- PRACTICE WITH YOUR YUNGSTA — the "Start practice" step inside each lesson.
-- The lesson page opens sim/practice.html in a sheet. That page calls the two functions below:
--   practice_start(p_lesson)    begin (or carry on with) a practice round for a lesson, e.g. '1-1'
--   practice_status(p_lesson)   progress of the current round (the page checks this every few seconds)
--
-- A round = up to 3 of the lesson's own yungsta questions, asked one at a time, PLUS the lesson's
-- real-life scenario if the lesson has one (for example the credit-and-debt moment for lesson 1-2).
-- The learner answers inside the page, which uses the same question and scenario cards as the rest of
-- the simulator. When everything is answered the round is complete and the lesson is told so.
-- A lesson with no questions and no scenario completes straight away, so a certificate is never blocked.
--
-- RUN ORDER: this file needs 02, 03, 09 and 10 to have been run first. Run it after 15.
-- It only adds new things (one table, one column, four functions). It does not change or delete any data.

-- ─────────────────────────────────────────────
-- One row per practice round
-- ─────────────────────────────────────────────
create table if not exists learner_practice (
  id bigint generated always as identity primary key,
  profile_id uuid not null references profiles(id) on delete cascade,
  lesson_id text not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  correct_count int
);
create index if not exists learner_practice_lookup on learner_practice (profile_id, lesson_id, started_at desc);

-- questions asked as part of a round are tagged with the round
alter table learner_questions add column if not exists practice_id bigint references learner_practice(id) on delete set null;

alter table learner_practice enable row level security;
drop policy if exists "own practice (read)" on learner_practice;
create policy "own practice (read)" on learner_practice for select using (auth.uid() = profile_id);
revoke insert, update, delete, truncate on learner_practice from anon, authenticated;

-- ─────────────────────────────────────────────
-- The lesson's name, shown as the page heading
-- ─────────────────────────────────────────────
create or replace function practice_title(p_lesson text)
returns text language sql stable set search_path = public as $$
  select m.t from (values
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
      ('p1', 'Financial Concepts Explained')
  ) as m(k, t) where m.k = p_lesson
$$;

-- ─────────────────────────────────────────────
-- Progress of one round (internal: called by the two public functions)
-- ─────────────────────────────────────────────
create or replace function practice_progress(p uuid, p_lesson text, p_session bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_total int := 0; v_ans int := 0; v_ok int := 0;
  v_has boolean := false; v_sdone boolean := true; v_done boolean;
begin
  select count(*), count(*) filter (where lq.status = 'answered'), count(*) filter (where lq.correct is true)
    into v_total, v_ans, v_ok
    from learner_questions lq
   where lq.profile_id = p and lq.practice_id = p_session;

  -- the lesson's real-life scenario, if it has one
  select count(*) > 0, coalesce(bool_and(pe.status = 'done'), true)
    into v_has, v_sdone
    from learner_pending_events pe
    join story_events e on e.id = pe.event_id
   where pe.profile_id = p and e.category = 'lesson_bridge' and e.trigger_config ->> 'lesson_id' = p_lesson;

  v_done := (v_total = 0 and not v_has) or (v_ans >= v_total and v_sdone);

  if v_done and p_session is not null then
    update learner_practice
       set completed_at = coalesce(completed_at, now()), correct_count = v_ok
     where id = p_session and profile_id = p;
  end if;

  return jsonb_build_object(
    'available', not (v_total = 0 and not v_has),
    'done', v_done,
    'title', practice_title(p_lesson),
    'answered', v_ans,
    'total', v_total,
    'questions', jsonb_build_object('total', v_total, 'answered', v_ans, 'correct', v_ok),
    'scenario', jsonb_build_object('has', v_has, 'done', (v_has and v_sdone)));
end $$;

-- ─────────────────────────────────────────────
-- Start a round, or carry on with the one in progress (safe to call again after every answer)
-- ─────────────────────────────────────────────
create or replace function practice_start(p_lesson text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  s learner_practice;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  if p_lesson is null or p_lesson !~ '^[a-z0-9-]{1,8}$' then return jsonb_build_object('error', 'bad_lesson'); end if;
  if not exists (select 1 from profiles where id = uid) then return jsonb_build_object('error', 'no_profile'); end if;

  -- record the lesson as finished and queue its real-life scenario (does nothing the second time)
  perform story_fire_lesson(p_lesson);

  select * into s from learner_practice
   where profile_id = uid and lesson_id = p_lesson
   order by started_at desc, id desc limit 1;

  -- a new round: none yet, or the last one was finished more than 15 minutes ago ("Practice again")
  if s.id is null or (s.completed_at is not null and s.completed_at < now() - interval '15 minutes') then
    insert into learner_practice (profile_id, lesson_id) values (uid, p_lesson) returning * into s;

    -- up to 3 of this lesson's questions, the ones asked least recently first.
    -- They are given an early "available_at" so they come up before any other waiting question.
    insert into learner_questions (profile_id, question_id, option_order, available_at, practice_id)
    select uid, q.id,
           array(select i from generate_series(0, jsonb_array_length(q.options) - 1) i order by random()),
           timestamptz 'epoch' + (q.rn * interval '1 second'),
           s.id
      from (
        select yq.id, yq.options,
               row_number() over (
                 order by (select max(lq.created_at) from learner_questions lq
                            where lq.profile_id = uid and lq.question_id = yq.id) asc nulls first,
                          random()) as rn
          from yungsta_questions yq
         where yq.is_active and yq.lesson_id = p_lesson
      ) q
     where q.rn <= 3;
  end if;

  return practice_progress(uid, p_lesson, s.id);
end $$;

-- ─────────────────────────────────────────────
-- Progress of the current round (the page checks this every few seconds)
-- ─────────────────────────────────────────────
create or replace function practice_status(p_lesson text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  s learner_practice;
begin
  if uid is null then return jsonb_build_object('error', 'not_signed_in'); end if;
  select * into s from learner_practice
   where profile_id = uid and lesson_id = p_lesson
   order by started_at desc, id desc limit 1;
  if s.id is null then return practice_start(p_lesson); end if;
  return practice_progress(uid, p_lesson, s.id);
end $$;

-- only signed-in learners (including the automatic guest sign-in) may call the two public functions
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('practice_title', 'practice_progress', 'practice_start', 'practice_status')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    if r.proname in ('practice_start', 'practice_status') then
      execute format('grant execute on function %s to authenticated', r.sig);
    end if;
  end loop;
end $$;
