-- A match below half a percent shows no number rather than "0% match"; the
-- edge function rounds the same way. `wtw_match` is in every titles select:
-- a request with the anon key alone (no session yet) gets null, not an error.
create or replace function public.wtw_match(t public.titles)
returns integer
language sql
stable
set search_path = ''
as $$
  select round(least(s.match, 0.97) * 100)::integer
  from public.wtw_scores s
  where s.user_id = (select auth.uid()) and s.kind = t.kind and s.tmdb_id = t.tmdb_id
    and s.scored_at > now() - interval '12 hours' and s.match >= 0.005
$$;

grant execute on function public.wtw_match(public.titles) to anon;
