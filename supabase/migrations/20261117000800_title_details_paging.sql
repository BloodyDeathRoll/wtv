-- The REST API returns at most 1,000 rows per call, so the details job asks
-- for its work list in pages, skipping the titles it already tried this run.
drop function public.titles_needing_details(smallint);

create function public.titles_needing_details(p_provider smallint, p_skip bigint[] default '{}')
returns table (id bigint, kind text, ext_id bigint, name text, year integer, cast_names text, tmdb_id integer)
language sql
stable
set search_path = ''
as $$
  select t.id, t.kind, t.ext_id, t.name, t.year, t.cast_names, t.tmdb_id
  from public.titles t
  where t.provider_id = p_provider
    and t.available
    and (t.details_at is null or (t.kind = 'series' and t.added_at > t.details_at))
    and t.id <> all (p_skip)
  order by t.added_at desc nulls last, t.id
  limit 1000
$$;

revoke execute on function public.titles_needing_details(smallint, bigint[]) from public, anon, authenticated;
