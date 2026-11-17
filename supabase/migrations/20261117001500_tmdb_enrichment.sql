-- TMDB metadata in English and Hebrew (P1-4). Filled by server/src/enrich.ts
-- for titles with a TMDB id; the app falls back to the provider's own fields.
-- Image columns hold TMDB paths ("/abc.jpg"): the app picks the size.

alter table public.titles
  add column title_en          text,
  add column title_he          text,
  add column overview_en       text,
  add column overview_he       text,
  add column tmdb_genre_ids    integer[],
  add column certification     text,      -- e.g. "R", "TV-14", "14"
  add column tmdb_rating       real,      -- TMDB vote average, 0-10
  add column original_language text,
  add column tmdb_poster       text,
  add column tmdb_backdrop     text,
  add column tmdb_runtime_min  integer,   -- movies: runtime; series: typical episode
  add column enriched_at       timestamptz;

alter table public.episodes
  add column name_en     text,
  add column name_he     text,
  add column overview_en text,
  add column overview_he text,
  add column tmdb_still  text;

-- TMDB genre names. Movie and TV genres are separate lists in TMDB.
create table public.genres (
  kind    text    not null check (kind in ('movie', 'series')),
  id      integer not null,
  name_en text    not null,
  name_he text,
  primary key (kind, id)
);

create table public.people (
  tmdb_id integer primary key,
  name    text not null,
  profile text           -- TMDB image path
);

create table public.title_cast (
  title_id  bigint   not null references public.titles (id) on delete cascade,
  person_id integer  not null references public.people (tmdb_id) on delete cascade,
  position  smallint not null,
  character text,
  primary key (title_id, person_id)
);

create index title_cast_person_idx on public.title_cast (person_id);

do $$
declare t text;
begin
  foreach t in array array['genres', 'people', 'title_cast'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
    execute format('revoke insert, update, delete, truncate, references, trigger on public.%I from authenticated', t);
  end loop;
end $$;

-- The enrichment job's work list: titles with a TMDB id never enriched, and
-- series whose details changed since (new episodes). 1,000 per call.
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
    and (t.enriched_at is null or (t.kind = 'series' and t.details_at > t.enriched_at))
    and t.id <> all (p_skip)
  order by t.added_at desc nulls last, t.id
  limit 1000
$$;

revoke execute on function public.titles_needing_enrichment(smallint, bigint[]) from public, anon, authenticated;
