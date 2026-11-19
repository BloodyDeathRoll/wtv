-- Review fix: a title Disliked in WTV is never offered in Watch it again,
-- even when it was finished (without WTW) or Loved or Liked in WTW (with WTW).

create or replace function public.watch_again(p_limit integer)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  left join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  left join ratings x on x.title_id = t.id and x.user_id = (select auth.uid())
  where t.available and t.is_primary
    and (r.wtw_reaction in ('loved', 'liked') or x.rating in ('love', 'like'))
    and x.rating is distinct from 'dislike'
  order by x.rating is null, x.updated_at desc nulls last,
           r.wtw_reaction = 'loved' desc, r.s desc nulls last, t.id
  limit least(p_limit, 50)
$$;

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
  ), finished as (
    select done.* from done
    where not exists (
      select 1 from ratings x
      where x.user_id = (select auth.uid()) and x.title_id = done.card and x.rating = 'dislike'
    )
  ), liked as (
    select x.title_id as card, x.updated_at as at from ratings x
    where x.user_id = (select auth.uid()) and x.rating in ('love', 'like')
      and x.title_id not in (select card from finished)
  ), seen as (
    select card, at, 0 as part from finished
    union all
    select card, at, 1 from liked
  )
  select c.* from seen
  join titles c on c.id = seen.card and c.available and c.is_primary
  order by seen.part, seen.at desc, c.id
  limit least(p_limit, 50)
$$;
