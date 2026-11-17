-- WTV first schema (P0-2). See docs/PLAN.md.
--
-- Catalog tables hold a copy of what the provider has. Only the sync job
-- (secret key, which bypasses RLS) writes them; signed-in users read them.
-- User tables hold one user's own rows.
--
-- Columns for TMDB metadata arrive with the enrichment work (P1-4).

-- ── Catalog ──────────────────────────────────────────────────

create table public.providers (
  id         smallint generated always as identity primary key,
  name       text        not null unique,
  kind       text        not null check (kind in ('xtream', 'm3u')),
  created_at timestamptz not null default now()
);

create table public.categories (
  provider_id smallint not null references public.providers (id) on delete cascade,
  kind        text     not null check (kind in ('movie', 'series', 'live')),
  ext_id      integer  not null,           -- the provider's category_id
  name        text     not null,           -- as the provider gives it
  name_en     text,                        -- P1-6
  position    integer  not null default 0, -- the provider's order
  primary key (provider_id, kind, ext_id)
);

create table public.titles (
  id            bigint generated always as identity primary key,
  provider_id   smallint    not null references public.providers (id) on delete cascade,
  kind          text        not null check (kind in ('movie', 'series')),
  ext_id        integer     not null,      -- stream_id (movie) or series_id
  name          text        not null,
  year          integer,
  plot          text,
  genres        text,
  cast_names    text,
  director      text,
  rating        real,
  poster_url    text,
  backdrop_url  text,
  trailer       text,                      -- YouTube id
  runtime_min   integer,
  container_ext text,                      -- movies only; needed for the stream URL
  category_ids  integer[]   not null default '{}',
  added_at      timestamptz,               -- when the provider added or last changed it
  tmdb_id       integer,                   -- P1-3
  tmdb_checked_at timestamptz,             -- set even when the provider has no TMDB id
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (provider_id, kind, ext_id)
);

create index titles_added_at_idx on public.titles (kind, added_at desc);
create index titles_tmdb_idx on public.titles (kind, tmdb_id) where tmdb_id is not null;
create index titles_category_ids_idx on public.titles using gin (category_ids);

create table public.episodes (
  id            bigint generated always as identity primary key,
  title_id      bigint      not null references public.titles (id) on delete cascade,
  ext_id        integer     not null,      -- the provider's episode id
  season        integer     not null,
  episode       integer     not null,
  name          text,
  plot          text,
  duration_secs integer,
  image_url     text,
  container_ext text,
  added_at      timestamptz,
  unique (title_id, ext_id)
);

create index episodes_order_idx on public.episodes (title_id, season, episode);

create table public.channels (
  id             bigint generated always as identity primary key,
  provider_id    smallint not null references public.providers (id) on delete cascade,
  ext_id         integer  not null,        -- stream_id
  name           text     not null,
  num            integer,                  -- the provider's channel number
  logo_url       text,
  epg_channel_id text,
  archive_days   integer  not null default 0, -- catch-up window; 0 = none
  category_ids   integer[] not null default '{}',
  unique (provider_id, ext_id)
);

-- ── User data ────────────────────────────────────────────────

create table public.ratings (
  user_id    uuid        not null references auth.users (id) on delete cascade,
  title_id   bigint      not null references public.titles (id) on delete cascade,
  rating     text        not null check (rating in ('love', 'like', 'dislike')),
  updated_at timestamptz not null default now(),
  primary key (user_id, title_id)
);

create table public.watchlist (
  user_id  uuid        not null references auth.users (id) on delete cascade,
  title_id bigint      not null references public.titles (id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (user_id, title_id)
);

-- One row per movie, and one per episode watched.
create table public.progress (
  user_id       uuid        not null references auth.users (id) on delete cascade,
  title_id      bigint      not null references public.titles (id) on delete cascade,
  episode_id    bigint      references public.episodes (id) on delete cascade,
  position_secs integer     not null,
  duration_secs integer,
  updated_at    timestamptz not null default now(),
  unique nulls not distinct (user_id, title_id, episode_id)
);

create index progress_recent_idx on public.progress (user_id, updated_at desc);

create table public.channel_prefs (
  user_id    uuid    not null references auth.users (id) on delete cascade,
  channel_id bigint  not null references public.channels (id) on delete cascade,
  favorite   boolean not null default false,
  hidden     boolean not null default false,
  primary key (user_id, channel_id)
);

-- ── Row level security ───────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array['providers', 'categories', 'titles', 'episodes', 'channels'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_read', t);
  end loop;

  foreach t in array array['ratings', 'watchlist', 'progress', 'channel_prefs'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)',
      t || '_own', t);
  end loop;
end $$;
