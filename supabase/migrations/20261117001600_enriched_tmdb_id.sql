-- Which TMDB id a title was enriched from. If the details job later changes a
-- title's TMDB id, the title is enriched again (also after a TMDB 404).
alter table public.titles add column enriched_tmdb_id integer;
update public.titles set enriched_tmdb_id = tmdb_id where enriched_at is not null;

drop function public.titles_needing_enrichment(smallint, bigint[]);

create function public.titles_needing_enrichment(p_provider smallint, p_skip bigint[] default '{}')
returns table (id bigint, kind text, ext_id bigint, name text, tmdb_id integer)
language sql
stable
set search_path = ''
as $$
  select t.id, t.kind, t.ext_id, t.name, t.tmdb_id
  from public.titles t
  where t.provider_id = p_provider
    and t.available
    and t.tmdb_id is not null
    and (
      t.enriched_at is null
      or t.enriched_tmdb_id is distinct from t.tmdb_id
      or (t.kind = 'series' and t.details_at > t.enriched_at)
    )
    and t.id <> all (p_skip)
  order by t.added_at desc nulls last, t.id
  limit 1000
$$;

revoke execute on function public.titles_needing_enrichment(smallint, bigint[]) from public, anon, authenticated;
