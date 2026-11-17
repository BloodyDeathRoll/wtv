-- The provider marks radio stations in the channel list (`stream_type`).
-- The app's master switch for radio reads this.
alter table public.channels add column is_radio boolean not null default false;
