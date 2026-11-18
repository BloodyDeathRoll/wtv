-- A genre's page (side bar → Categories → a genre) sorts by Recommended like a
-- provider category's page: same function, filtered by a TMDB genre instead.
-- Dropped and made again: an overload with one more defaulted argument would
-- leave the REST API unable to choose between the two.
drop function public.recommended_page(text, integer, integer, integer);

create function public.recommended_page(p_kind text, p_offset integer, p_limit integer, p_category integer default null, p_genre integer default null)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  left join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  where t.kind = p_kind and t.available and t.is_primary
    and (p_category is null or t.group_category_ids @> array[p_category])
    and (p_genre is null or t.tmdb_genre_ids @> array[p_genre])
  order by
    case when r.s is null then 1 when r.wtw_reaction is null then 0 else 2 end,
    r.s desc nulls last, t.group_added_at desc nulls last, t.id
  offset p_offset limit least(p_limit, 200)
$$;

revoke execute on function public.recommended_page(text, integer, integer, integer, integer) from public, anon;
grant execute on function public.recommended_page(text, integer, integer, integer, integer) to authenticated;
