-- Sort by name as the app shows it (P2-5): TMDB's title in the app's
-- language, else the provider's. The REST API sorts by columns only.
alter table public.titles
  add column sort_name_en text generated always as (lower(coalesce(title_en, name))) stored,
  add column sort_name_he text generated always as (lower(coalesce(title_he, name))) stored;
