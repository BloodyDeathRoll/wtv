-- "Customers also liked" (P4-5). WTW has no similar-titles feature, so the
-- row is built from WTW's own data: the titles nearest in WTW's taste space
-- (cosine of the taste vectors), then ordered by the user's own ranking.
create extension if not exists vector with schema extensions;

-- The taste vector as a unit pgvector, for the cosine index. Only vectors of
-- the current WTW taste version (1); a null version is unusable.
alter table public.titles
  add column wtw_taste_unit extensions.vector(25)
  generated always as (
    case when wtw_taste_version = 1 and wtw_taste_vec is not null
      then extensions.l2_normalize(wtw_taste_vec::extensions.vector(25)) end
  ) stored;

create index titles_wtw_taste_unit_idx on public.titles
  using hnsw (wtw_taste_unit extensions.vector_cosine_ops) where is_primary and available;

-- The 60 cards of the same kind nearest to `p_title`'s taste, the user's
-- unrated best first (by `s`), then the rest by nearness. Other copies of
-- the title itself are left out.
create function public.also_liked(p_title bigint, p_limit integer)
returns setof public.titles
language sql stable security invoker set search_path = public, extensions
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
  order by (r.wtw_reaction is null and r.s is not null) desc, r.s desc nulls last, near.d, (near.card_row).id
  limit least(p_limit, 50)
$$;

revoke execute on function public.also_liked(bigint, integer) from public, anon;
grant execute on function public.also_liked(bigint, integer) to authenticated;
