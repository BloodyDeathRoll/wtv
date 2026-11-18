-- Live TV hiding (P5-2). Single channels are hidden in channel_prefs.hidden;
-- whole groups here; the radio master switch in user_settings. Rows belong
-- to the signed-in user, as in progress and channel_prefs.

-- shortcut: groups are keyed by the live category's ext_id alone, which is
-- unique for the one provider; add provider_id with multiple accounts (P7).
create table public.live_group_prefs (
  user_id     uuid    not null default auth.uid() references auth.users (id) on delete cascade,
  category_id integer not null,
  hidden      boolean not null default false,
  primary key (user_id, category_id)
);

create table public.user_settings (
  user_id    uuid    primary key default auth.uid() references auth.users (id) on delete cascade,
  show_radio boolean not null default true
);

do $$
declare t text;
begin
  foreach t in array array['live_group_prefs', 'user_settings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)',
      t || '_own', t);
  end loop;
end $$;

revoke truncate, references, trigger on public.live_group_prefs, public.user_settings from authenticated;
revoke all on public.live_group_prefs, public.user_settings from anon;
