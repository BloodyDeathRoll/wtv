-- A title rated in WTV (Love, Like or Dislike) counts as seen, like one rated
-- in WTW: it leaves Top picks, New for you and Recommended for You, goes after
-- the unseen titles in the Recommended sort and in Customers also liked, and
-- (Loved or Liked) joins Watch it again. Disliked titles are seen but not
-- offered again. Ratings point at the card (the group's primary copy).
--
-- Also: how many titles each provider category and genre has, and the kind's
-- total, for the tags on the Categories page.

create or replace function public.recommended_page(p_kind text, p_offset integer, p_limit integer, p_category integer default null, p_genre integer default null)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  left join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  left join ratings x on x.title_id = t.id and x.user_id = (select auth.uid())
  where t.kind = p_kind and t.available and t.is_primary
    and (p_category is null or t.group_category_ids @> array[p_category])
    and (p_genre is null or t.tmdb_genre_ids @> array[p_genre])
  order by
    case when x.rating is not null or r.wtw_reaction is not null then 2 when r.s is null then 1 else 0 end,
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
    and not exists (select 1 from ratings x where x.title_id = t.id and x.user_id = (select auth.uid()))
  order by r.s desc, t.id
  limit least(p_limit, 50)
$$;

create or replace function public.top_picks_page(p_offset integer, p_limit integer, p_kind text default null)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  where t.available and t.is_primary and r.wtw_reaction is null
    and (p_kind is null or t.kind = p_kind)
    and not exists (select 1 from ratings x where x.title_id = t.id and x.user_id = (select auth.uid()))
  order by r.s desc, t.id
  offset p_offset limit least(p_limit, 200)
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
    and not exists (select 1 from ratings x where x.title_id = t.id and x.user_id = (select auth.uid()))
  order by r.s desc, t.id
  limit least(p_limit, 50)
$$;

-- With WTW: what the user Loved or Liked in WTV first (last rated first, so a
-- title just rated shows at the front), then WTW's Loved and Liked, loved
-- first, then best ranked.
create or replace function public.watch_again(p_limit integer)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  left join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  left join ratings x on x.title_id = t.id and x.user_id = (select auth.uid())
  where t.available and t.is_primary
    and (r.wtw_reaction in ('loved', 'liked') or x.rating in ('love', 'like'))
  order by x.rating is null, x.updated_at desc nulls last,
           r.wtw_reaction = 'loved' desc, r.s desc nulls last, t.id
  limit least(p_limit, 50)
$$;

-- Without WTW: what the user finished (last finished first), then what they
-- Loved or Liked in WTV and have not finished (last rated first).
create or replace function public.finished_titles(p_limit integer)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  with done as (
    select coalesce(t.group_id, t.id) as card, max(p.updated_at) as at
    from progress p
    join titles t on t.id = p.title_id
    left join episodes e on e.id = p.episode_id
    where p.user_id = (select auth.uid())
      and p.duration_secs > 0 and p.position_secs >= p.duration_secs * 0.95
      and (p.episode_id is null or not exists (
        select 1 from episodes later
        where later.title_id = e.title_id and later.available
          and (later.season, later.episode) > (e.season, e.episode)
      ))
    group by 1
  ), liked as (
    select x.title_id as card, x.updated_at as at from ratings x
    where x.user_id = (select auth.uid()) and x.rating in ('love', 'like')
      and x.title_id not in (select card from done)
  ), seen as (
    select card, at, 0 as part from done
    union all
    select card, at, 1 from liked
  )
  select c.* from seen
  join titles c on c.id = seen.card and c.available and c.is_primary
  order by seen.part, seen.at desc, c.id
  limit least(p_limit, 50)
$$;

-- Loads pgvector in this session, so its hnsw.ef_search setting is known below.
select '[1]'::extensions.vector;

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
  ), marked as (
    select near.*, r.s, (r.wtw_reaction is not null or x.rating is not null) as seen
    from near
    left join rankings r on r.title_id = (near.card_row).id and r.user_id = (select auth.uid())
    left join ratings x on x.title_id = (near.card_row).id and x.user_id = (select auth.uid())
  )
  select (card_row).* from marked
  order by (not seen and s is not null) desc,
           seen,
           case when not seen then s end desc nulls last,
           d, (card_row).id
  limit least(greatest(p_limit, 0), 50)
$$;

-- Tags on the Categories page: the kind's total ('all', id 0), then each
-- provider category and each genre with at least one title.
create or replace function public.category_counts(p_kind text)
returns table (tag text, id integer, n bigint)
language sql stable security invoker set search_path = public
as $$
  with cards as (
    select group_category_ids, tmdb_genre_ids from titles
    where kind = p_kind and available and is_primary
  )
  select 'all', 0, count(*) from cards
  union all
  select 'category', c, count(*) from cards, unnest(group_category_ids) c group by c
  union all
  select 'genre', g, count(*) from cards, unnest(tmdb_genre_ids) g group by g
$$;

revoke execute on function public.category_counts(text) from public, anon;
grant execute on function public.category_counts(text) to authenticated;
