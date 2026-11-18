-- Review fixes for also_liked: titles the user already rated go after the
-- unseen ones (they were sorted by `s` ahead of unranked neighbours), and the
-- HNSW search looks at more than its default 40 candidates so the 60 nearest
-- survive the kind/card filters.
create or replace function public.also_liked(p_title bigint, p_limit integer)
returns setof public.titles
language sql stable security invoker
set search_path = public, extensions
set hnsw.ef_search = 200
as $$
  with seed as (
    select kind, coalesce(group_id, id) as card, wtw_taste_unit as v from titles where id = p_title
  ), near as (
    select t as card_row, t.wtw_taste_unit <=> seed.v as d
    from titles t, seed
    where seed.v is not null and t.is_primary and t.available and t.kind = seed.kind
      and coalesce(t.group_id, t.id) <> seed.card and t.wtw_taste_unit is not null
    order by t.wtw_taste_unit <=> seed.v
    limit 60
  )
  select (near.card_row).* from near
  left join rankings r on r.title_id = (near.card_row).id and r.user_id = (select auth.uid())
  order by (r.wtw_reaction is null and r.s is not null) desc,
           r.wtw_reaction is not null,
           case when r.wtw_reaction is null then r.s end desc nulls last,
           near.d, (near.card_row).id
  limit least(greatest(p_limit, 0), 50)
$$;
