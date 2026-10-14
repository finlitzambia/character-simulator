-- FinLit Zambia — 18-referrals.sql  (safe to re-run)  Run AFTER 11 (it reuses the quiz rate limiter).
--
-- REFERRALS: the first 70 people who bring friends to learn get their first 2 weeks free from 23 October.
--   * A learner gets a personal link (yoursite/?ref=CODE) by giving a first name and a WhatsApp number or email.
--   * A friend COUNTS once they open a lesson through that link and finish at least 3 sections of it.
--     (Merely clicking the link counts for nothing.) Each friend's device counts once, ever, and nobody can count for themselves.
--   * When someone reaches the number of friends needed, and fewer than 70 people have already, they are a WINNER:
--     rank 1..70 is stored with the free period (free_from to free_until).
--   * To see the winners: Supabase > Table Editor > referrers, sort by reward_rank.
--
-- THE KNOBS (change them in Table Editor > sim_config, no code change needed):
--   referral_cap        how many winners          (70)
--   referral_needed     friends each must bring   (3)
--   referral_free_from  first free day            (2026-10-23)
--   referral_free_days  length of the free period (14)  -> free 23 Oct up to and including 5 Nov
--
-- Nothing here changes or deletes existing data.

create table if not exists referrers (
  id bigint generated always as identity primary key,
  code text not null unique,
  token text not null,
  name text not null,
  contact text not null,
  vid text not null unique,
  created_at timestamptz not null default now(),
  qualified_count int not null default 0,
  reward_rank int unique,
  rewarded_at timestamptz,
  free_from date,
  free_until date
);
create table if not exists referral_claims (
  id bigint generated always as identity primary key,
  referrer_id bigint not null references referrers(id) on delete cascade,
  vid text not null unique,
  created_at timestamptz not null default now()
);
create index if not exists referral_claims_referrer on referral_claims (referrer_id);

alter table referrers enable row level security;
alter table referral_claims enable row level security;
revoke all on referrers, referral_claims from anon, authenticated;

insert into sim_config (key, value) values ('referral_cap', '70') on conflict (key) do nothing;
insert into sim_config (key, value) values ('referral_needed', '3') on conflict (key) do nothing;
insert into sim_config (key, value) values ('referral_free_from', '2026-10-23') on conflict (key) do nothing;
insert into sim_config (key, value) values ('referral_free_days', '14') on conflict (key) do nothing;

create or replace function ref_cfg(p_key text, p_default text)
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select value from sim_config where key = p_key), p_default) $$;

-- public numbers for the "spots left" line
create or replace function ref_public()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_cap int := ref_cfg('referral_cap', '70')::int; v_won int; v_from date := ref_cfg('referral_free_from', '2026-10-23')::date; v_days int := ref_cfg('referral_free_days', '14')::int;
begin
  select count(*) into v_won from referrers where reward_rank is not null;
  return jsonb_build_object('cap', v_cap, 'won', v_won, 'spots_left', greatest(0, v_cap - v_won),
    'needed', ref_cfg('referral_needed', '3')::int, 'free_from', v_from, 'free_days', v_days, 'free_last_day', v_from + v_days - 1);
end $$;

-- get (or fetch again) a personal link
create or replace function ref_join(p_name text, p_contact text, p_vid text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_vid text := left(coalesce(p_vid, ''), 40); v_name text; v_contact text; r referrers; v_code text; i int := 0;
  v_alpha constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
begin
  if length(v_vid) < 8 then return jsonb_build_object('error', 'bad_request'); end if;
  select * into r from referrers where vid = v_vid;
  if found then return jsonb_build_object('code', r.code, 'token', r.token); end if;
  if not quiz_rate_ok('ref_join', 20) then return jsonb_build_object('error', 'slow_down'); end if;
  v_name := left(trim(regexp_replace(coalesce(p_name, ''), '[<>&"]', '', 'g')), 40);
  v_contact := left(trim(coalesce(p_contact, '')), 60);
  if length(v_name) < 2 then return jsonb_build_object('error', 'name'); end if;
  if not (v_contact ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(regexp_replace(v_contact, '\D', '', 'g')) between 8 and 15) then
    return jsonb_build_object('error', 'contact');
  end if;
  loop
    i := i + 1;
    v_code := '';
    for k in 1..6 loop v_code := v_code || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1); end loop;
    exit when not exists (select 1 from referrers where code = v_code) or i > 20;
  end loop;
  begin
    insert into referrers (code, token, name, contact, vid) values (v_code, replace(gen_random_uuid()::text, '-', ''), v_name, v_contact, v_vid) returning * into r;
  exception when unique_violation then
    select * into r from referrers where vid = v_vid;
    if not found then return jsonb_build_object('error', 'try_again'); end if;
  end;
  return jsonb_build_object('code', r.code, 'token', r.token);
end $$;

-- a referrer checks their own progress (needs their private token)
create or replace function ref_status(p_code text, p_token text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r referrers;
begin
  select * into r from referrers where code = upper(coalesce(p_code, '')) and token = coalesce(p_token, '');
  if not found then return jsonb_build_object('error', 'forbidden'); end if;
  return ref_public() || jsonb_build_object('code', r.code, 'name', r.name, 'qualified', r.qualified_count,
    'winner', r.reward_rank is not null, 'rank', r.reward_rank, 'your_from', r.free_from, 'your_last_day', r.free_until - 1);
end $$;

-- a friend has finished enough of a lesson: count them for the person who invited them
create or replace function ref_claim(p_code text, p_vid text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')); v_vid text := left(coalesce(p_vid, ''), 40);
  r referrers; v_cap int := ref_cfg('referral_cap', '70')::int; v_needed int := ref_cfg('referral_needed', '3')::int; v_won int; v_from date; v_days int;
begin
  if v_code = '' or length(v_vid) < 8 then return jsonb_build_object('ok', false, 'reason', 'bad_request'); end if;
  if not quiz_rate_ok('ref_claim', 60) then return jsonb_build_object('ok', false, 'reason', 'slow_down'); end if;
  select * into r from referrers where code = v_code for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no_such_code'); end if;
  if r.vid = v_vid then return jsonb_build_object('ok', false, 'reason', 'self'); end if;
  begin
    insert into referral_claims (referrer_id, vid) values (r.id, v_vid);
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'reason', 'already');
  end;
  update referrers set qualified_count = qualified_count + 1 where id = r.id returning * into r;
  if r.qualified_count >= v_needed and r.reward_rank is null then
    perform pg_advisory_xact_lock(7018);
    select count(*) into v_won from referrers where reward_rank is not null;
    if v_won < v_cap then
      v_from := ref_cfg('referral_free_from', '2026-10-23')::date; v_days := ref_cfg('referral_free_days', '14')::int;
      update referrers set reward_rank = (select coalesce(max(reward_rank), 0) + 1 from referrers), rewarded_at = now(),
             free_from = v_from, free_until = v_from + v_days where id = r.id;
    end if;
  end if;
  return jsonb_build_object('ok', true);
end $$;

do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('ref_cfg', 'ref_public', 'ref_join', 'ref_status', 'ref_claim')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;
grant execute on function ref_public() to anon, authenticated;
grant execute on function ref_join(text, text, text) to anon, authenticated;
grant execute on function ref_status(text, text) to anon, authenticated;
grant execute on function ref_claim(text, text) to anon, authenticated;
