-- "Recommended for You": the user's WTW ranking, best first, titles they have
-- not rated; one kind, or both (Home's Top picks → More). Paged for the
-- recommendations page, 50 at a time.
create function public.top_picks_page(p_offset integer, p_limit integer, p_kind text default null)
returns setof public.titles
language sql stable security invoker set search_path = public
as $$
  select t.* from titles t
  join rankings r on r.title_id = t.id and r.user_id = (select auth.uid())
  where t.available and t.is_primary and r.wtw_reaction is null
    and (p_kind is null or t.kind = p_kind)
  order by r.s desc, t.id
  offset p_offset limit least(p_limit, 200)
$$;

-- "Watch it again" without WTW: what the user finished, last finished first.
-- A movie is finished at 95% (as the app counts it); a series when its last
-- available episode is. Cards, so a finished copy shows as its group's card.
create function public.finished_titles(p_limit integer)
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
  )
  select c.* from done
  join titles c on c.id = done.card and c.available and c.is_primary
  order by done.at desc, c.id
  limit least(p_limit, 50)
$$;

revoke execute on function public.top_picks_page(integer, integer, text), public.finished_titles(integer) from public, anon;
grant execute on function public.top_picks_page(integer, integer, text), public.finished_titles(integer) to authenticated;
