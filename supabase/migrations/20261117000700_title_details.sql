-- Per-title details (P1-3): TMDB ids, movie backdrops, series episodes.
--
-- `details_at` replaces the unused `tmdb_checked_at`: when the details job
-- last fetched the title, whether or not a TMDB id was found. A series is
-- fetched again when the provider changes it (new episodes).
alter table public.titles rename column tmdb_checked_at to details_at;

-- The details job's work list: titles never fetched, and series changed since.
-- Newest first, so recent additions get their metadata first.
create function public.titles_needing_details(p_provider smallint)
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
  order by t.added_at desc nulls last, t.id
$$;

-- For the job only (secret key).
revoke execute on function public.titles_needing_details(smallint) from public, anon, authenticated;
