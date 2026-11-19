-- WTW's "% match" as WTW shows it, which `score` is not: `score` is the
-- composite over the provider's whole catalogue (it orders well but runs high,
-- 188 titles at 100%), `match` is the title placed against WTW's own pool, or
-- the score WTW last served it with. Null until the next ranking.
alter table public.rankings add column match real;

create or replace function public.wtw_match(t public.titles)
returns integer
language sql
stable
set search_path = ''
as $$
  select round(r.match * 100)::integer
  from public.rankings r
  where r.user_id = (select auth.uid()) and r.title_id = t.id
$$;
