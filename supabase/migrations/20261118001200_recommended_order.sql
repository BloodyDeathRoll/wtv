-- Recommended, in three groups: ranked titles the user has not rated (best
-- first), then titles the ranking does not know (newest first), then titles
-- the user rated in WTW, i.e. has watched (best first). Home rows are capped.
create or replace function public.recommended_page(p_kind text, p_offset integer, p_limit integer, p_category integer default null)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  left join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  where t.kind = p_kind and t.available and t.is_primary
    and (p_category is null or t.group_category_ids @> array[p_category])
  order by
    case when r.s is null then 1 when r.wtw_reaction is null then 0 else 2 end,
    r.s desc nulls last, t.group_added_at desc nulls last, t.id
  offset p_offset limit least(p_limit, 200)
$$;

create or replace function public.top_picks(p_limit integer)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  where t.available and t.is_primary and r.wtw_reaction is null
  order by r.s desc, t.id
  limit least(p_limit, 50)
$$;

create or replace function public.new_for_you(p_limit integer, p_recent integer default 300)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from (
    select * from titles where available and is_primary
    order by group_added_at desc nulls last, id limit least(p_recent, 1000)
  ) t
  join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  where r.wtw_reaction is null
  order by r.s desc, t.id
  limit least(p_limit, 50)
$$;

create or replace function public.watch_again(p_limit integer)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  where t.available and t.is_primary and r.wtw_reaction in ('loved', 'liked')
  order by r.wtw_reaction = 'loved' desc, r.s desc, t.id
  limit least(p_limit, 50)
$$;
