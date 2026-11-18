-- Search finds actors too: people whose name contains the query (two
-- characters at least) and who are in at least one available title (of one
-- kind, when the search is in Movies or Series). Names starting with the query
-- first, then the actors with the most titles. `%` and `_` in the query match
-- themselves.
create index if not exists people_name_trgm_idx on public.people using gin (name extensions.gin_trgm_ops);

create function public.search_people(p_query text, p_kind text default null, p_limit integer default 12)
returns table (tmdb_id integer, name text, profile text)
language sql stable security invoker set search_path = public
as $$
  with q as (select replace(replace(replace(trim(p_query), '\', '\\'), '%', '\%'), '_', '\_') as s),
  -- Counting titles is the slow part: only the first 500 name matches are counted
  -- (those starting with the query first), so a short query stays fast.
  matches as (
    select p.tmdb_id, p.name, p.profile, p.name ilike q.s || '%' as starts
    from people p, q
    where length(q.s) >= 2 and p.name ilike '%' || q.s || '%'
    order by starts desc
    limit 500
  ),
  hits as (
    select m.*,
      (select count(*) from title_cast tc join titles t on t.id = tc.title_id
       where tc.person_id = m.tmdb_id and t.available and t.is_primary and (p_kind is null or t.kind = p_kind)) as titles
    from matches m
  )
  select tmdb_id, name, profile from hits
  where titles > 0
  -- Names starting with the query, then the actors with the most titles here.
  order by starts desc, titles desc, name
  limit least(p_limit, 50)
$$;

revoke execute on function public.search_people(text, text, integer) from public, anon;
grant execute on function public.search_people(text, text, integer) to authenticated;
