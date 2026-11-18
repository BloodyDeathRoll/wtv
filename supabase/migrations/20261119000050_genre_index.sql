-- Genre grids filter cards by TMDB genre: an index like the one for provider categories.
create index titles_tmdb_genre_ids_idx on public.titles using gin (tmdb_genre_ids) where is_primary;
