-- The sync counts and marks rows by provider, kind, availability and last
-- sighting on every run.
create index titles_sync_idx   on public.titles   (provider_id, kind, available, last_seen_at);
create index channels_sync_idx on public.channels (provider_id, available, last_seen_at);
