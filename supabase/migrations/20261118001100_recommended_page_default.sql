-- The category is optional: give it a default (it must then come last), so
-- the REST API can leave it out for the all-categories grid.
drop function public.recommended_page(text, integer, integer, integer);

create function public.recommended_page(p_kind text, p_offset integer, p_limit integer, p_category integer default null)
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

revoke execute on function public.recommended_page(text, integer, integer, integer) from public, anon;
grant execute on function public.recommended_page(text, integer, integer, integer) to authenticated;
