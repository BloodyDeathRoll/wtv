-- Text search on title names (P2-9): substring matches on the English and
-- Hebrew display names and the provider's name, for cards only.
create extension if not exists pg_trgm with schema extensions;

create index titles_search_en_idx on public.titles using gin (sort_name_en extensions.gin_trgm_ops) where is_primary;
create index titles_search_he_idx on public.titles using gin (sort_name_he extensions.gin_trgm_ops) where is_primary;
create index titles_search_name_idx on public.titles using gin (name extensions.gin_trgm_ops) where is_primary;
