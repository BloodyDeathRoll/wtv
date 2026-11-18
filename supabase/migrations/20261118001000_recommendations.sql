-- What the app shows from a user's ranking (P4-4, P4-6).
--   rankings.wtw_reaction  the user's own WTW Love / Like / Dislike for the
--                          title (loved, liked, disliked), copied by `rank`;
--                          a rated title has been watched.
alter table public.rankings
  add column wtw_reaction text check (wtw_reaction in ('loved', 'liked', 'disliked'));

-- Cards (one per group of copies, as the app lists them) of one kind, and
-- optionally one category, best first: ranked titles the user has not rated
-- by `s`, then everything else newest first. Without a ranking it is the
-- newest-first list. Paged here, so the order holds across pages.
create function public.recommended_page(p_kind text, p_category integer, p_offset integer, p_limit integer)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  left join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  where t.kind = p_kind and t.available and t.is_primary
    and (p_category is null or t.group_category_ids @> array[p_category])
  order by (r.s is not null and r.wtw_reaction is null) desc, r.s desc nulls last, t.group_added_at desc nulls last, t.id
  offset p_offset limit p_limit
$$;

-- Home: the best ranked cards the user has not rated, movies and series.
create function public.top_picks(p_limit integer)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  where t.available and t.is_primary and r.wtw_reaction is null
  order by r.s desc, t.id
  limit p_limit
$$;

-- Home: of the newest cards, the ones the ranking likes best, unrated.
create function public.new_for_you(p_limit integer, p_recent integer default 300)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from (
    select * from titles where available and is_primary
    order by group_added_at desc nulls last, id limit p_recent
  ) t
  join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  where r.wtw_reaction is null
  order by r.s desc, t.id
  limit p_limit
$$;

-- Home: titles the user loved or liked in WTW, loved first, then by `s`.
create function public.watch_again(p_limit integer)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  where t.available and t.is_primary and r.wtw_reaction in ('loved', 'liked')
  order by r.wtw_reaction = 'loved' desc, r.s desc, t.id
  limit p_limit
$$;

revoke execute on function public.recommended_page(text, integer, integer, integer), public.top_picks(integer),
  public.new_for_you(integer, integer), public.watch_again(integer) from public, anon;
grant execute on function public.recommended_page(text, integer, integer, integer), public.top_picks(integer),
  public.new_for_you(integer, integer), public.watch_again(integer) to authenticated;
