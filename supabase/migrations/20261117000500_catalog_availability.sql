-- The sync stamps every row it finds in the provider's lists. A row the
-- provider no longer lists is kept (ratings and progress point at it) and
-- marked unavailable.
alter table public.titles
  add column available    boolean     not null default true,
  add column last_seen_at timestamptz not null default now();
alter table public.channels
  add column available    boolean     not null default true,
  add column last_seen_at timestamptz not null default now();
