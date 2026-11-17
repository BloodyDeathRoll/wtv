-- What WTW knows about each title (P1-5), copied from WTW's catalog by
-- tmdb id. WTW is read only for WTV; this copy is refreshed by the job.
--   wtw_title_id       WTW's titles.id, null when WTW does not have the title
--   wtw_taste_vec      WTW's titles.taste_vec (25 floats), null when unscored
--   wtw_taste_version  WTW's titles.taste_version the vector was built with
alter table public.titles
  add column wtw_title_id      integer,
  add column wtw_taste_vec     real[],
  add column wtw_taste_version smallint;
