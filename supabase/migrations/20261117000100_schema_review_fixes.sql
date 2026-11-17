-- Fixes from the review of the first schema (#43).

-- Provider ids: room for providers that use large ids.
alter table public.titles   alter column ext_id type bigint;
alter table public.episodes alter column ext_id type bigint;
alter table public.channels alter column ext_id type bigint;

-- Deleting a title, episode or channel cascades into the user tables by
-- these columns.
create index ratings_title_idx         on public.ratings (title_id);
create index watchlist_title_idx       on public.watchlist (title_id);
create index progress_title_idx        on public.progress (title_id);
create index progress_episode_idx      on public.progress (episode_id);
create index channel_prefs_channel_idx on public.channel_prefs (channel_id);

alter table public.progress
  add constraint progress_position_check check (position_secs >= 0),
  add constraint progress_duration_check check (duration_secs > 0);
alter table public.episodes
  add constraint episodes_duration_check check (duration_secs > 0);
alter table public.channels
  add constraint channels_archive_days_check check (archive_days >= 0);

-- updated_at follows every update; "continue watching" sorts by it.
create extension if not exists moddatetime with schema extensions;

create trigger titles_updated_at before update on public.titles
  for each row execute function extensions.moddatetime (updated_at);
create trigger ratings_updated_at before update on public.ratings
  for each row execute function extensions.moddatetime (updated_at);
create trigger progress_updated_at before update on public.progress
  for each row execute function extensions.moddatetime (updated_at);

-- The catalog is written by the sync job only. RLS already blocks other
-- writers; this removes the table privilege as well.
revoke insert, update, delete, truncate
  on public.providers, public.categories, public.titles, public.episodes, public.channels
  from anon, authenticated;
