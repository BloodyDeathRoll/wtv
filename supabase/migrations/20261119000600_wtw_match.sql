-- WTW's "% match" for a title, as WTW shows it: round(composite * 100).
-- A computed column: any titles select can ask for `wtw_match`, rows from the
-- list RPCs included. Null when the user has no ranking for the title.
create function public.wtw_match(t public.titles)
returns integer
language sql
stable
set search_path = ''
as $$
  select round(r.score * 100)::integer
  from public.rankings r
  where r.user_id = (select auth.uid()) and r.title_id = t.id
$$;

revoke execute on function public.wtw_match(public.titles) from public, anon;
grant execute on function public.wtw_match(public.titles) to authenticated;
