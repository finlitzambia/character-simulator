-- FinLit Zambia — Financial Character Simulator
-- Atomic ledger-write functions for the story_events engine.
--
-- Both functions do two things in one transaction: write the
-- append-only ledger row (the source of truth) AND update the cached
-- figure on `profiles` (cash_balance / reputation_score) that the
-- dashboard actually reads. Doing both in a single function call —
-- rather than the Edge Function doing two separate .insert()/.update()
-- calls — is what makes this atomic: either both happen or neither
-- does, and two learners triggering events at the same instant can't
-- race each other into a wrong final balance.
--
-- SECURITY DEFINER is required here: these run as the function owner
-- (not the calling learner), so they can update `profiles` even
-- though a learner's own RLS policy wouldn't normally let them write
-- to cash_balance directly. This is the standard, safe Supabase
-- pattern for "the only door into a protected column is through a
-- controlled function" — learners never get direct UPDATE rights on
-- profiles.cash_balance or profiles.reputation_score.

create or replace function adjust_cash_balance(
  p_profile_id uuid,
  p_delta numeric(14,2),
  p_reason text,
  p_related_table text default null,
  p_related_id bigint default null
)
returns numeric(14,2)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_balance numeric(14,2);
begin
  if p_delta = 0 then
    select cash_balance into v_new_balance from profiles where id = p_profile_id;
    return v_new_balance;
  end if;

  insert into cash_ledger (profile_id, amount, reason, related_table, related_id)
  values (p_profile_id, p_delta, p_reason, p_related_table, p_related_id);

  update profiles
    set cash_balance = cash_balance + p_delta
    where id = p_profile_id
    returning cash_balance into v_new_balance;

  return v_new_balance;
end;
$$;

create or replace function adjust_reputation_score(
  p_profile_id uuid,
  p_delta numeric(6,2),
  p_reason text
)
returns numeric(6,2)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_score numeric(6,2);
begin
  if p_delta = 0 then
    select reputation_score into v_new_score from profiles where id = p_profile_id;
    return v_new_score;
  end if;

  insert into reputation_events (profile_id, delta, reason)
  values (p_profile_id, p_delta, p_reason);

  update profiles
    -- clamp to the documented 0–100 scale so a long streak of
    -- negative events can't push the cached score below 0 (or a
    -- long positive streak above 100), even though the ledger
    -- itself keeps the true uncapped history.
    set reputation_score = greatest(0, least(100, reputation_score + p_delta))
    where id = p_profile_id
    returning reputation_score into v_new_score;

  return v_new_score;
end;
$$;

-- Only the service role (used by the Edge Function, never the
-- learner's own browser session) should be able to call these.
revoke execute on function adjust_cash_balance from public, authenticated;
revoke execute on function adjust_reputation_score from public, authenticated;
grant execute on function adjust_cash_balance to service_role;
grant execute on function adjust_reputation_score to service_role;
