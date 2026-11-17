-- Display names in both app languages (P1-6). `name` stays as the provider
-- sends it; `name_en` and `name_he` are what the app shows.
alter table public.categories add column name_he text;
