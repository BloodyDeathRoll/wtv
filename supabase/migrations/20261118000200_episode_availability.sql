-- The provider re-adds a series' episodes under new ids and the old ids stop
-- playing; both stayed listed (427 series had every episode twice). The
-- details job now stamps the episodes it finds (`seen_at`) and marks the
-- series' others unavailable. They are kept: progress may point at them.
alter table public.episodes
  add column available boolean not null default true,
  add column seen_at   timestamptz;
