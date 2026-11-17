-- Second round of review fixes (#43).

-- The provider and players report an unknown duration as 0.
alter table public.progress
  drop constraint progress_duration_check,
  add constraint progress_duration_check check (duration_secs >= 0);
alter table public.episodes
  drop constraint episodes_duration_check,
  add constraint episodes_duration_check check (duration_secs >= 0);

-- RLS does not cover TRUNCATE. No policy targets anon on the user tables.
revoke truncate, references, trigger
  on public.ratings, public.watchlist, public.progress, public.channel_prefs
  from authenticated;
revoke all
  on public.ratings, public.watchlist, public.progress, public.channel_prefs
  from anon;
