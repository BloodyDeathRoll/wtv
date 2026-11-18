-- What WTW's ranking needs per title besides the taste vector (P4-3),
-- copied from WTW's catalog by the same job, for every matched title:
--   wtw_crew         WTW's titles.crew, trimmed to what the ranking reads:
--                    directors, writers, cinematographers, first 3 of cast
--                    ({tmdb_person_id, name}, cast also {order})
--   wtw_tmdb_rating  WTW's titles.tmdb_rating (0-10)
--   wtw_omdb_rating  WTW's titles.omdb_rating (0-1)
alter table public.titles
  add column wtw_crew        jsonb,
  add column wtw_tmdb_rating double precision,
  add column wtw_omdb_rating double precision;
