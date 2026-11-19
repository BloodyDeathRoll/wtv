-- WTW never shows a match above 97% (WTW src/modules/engine/match-display.ts,
-- displayMatch: MATCH_V2_CAP = 0.97, DEC-10), and a composite of 0 shows no claim.
create or replace function public.wtw_match(t public.titles)
returns integer
language sql
stable
set search_path = ''
as $$
  select round(least(r.match, 0.97) * 100)::integer
  from public.rankings r
  where r.user_id = (select auth.uid()) and r.title_id = t.id and r.match > 0
$$;
