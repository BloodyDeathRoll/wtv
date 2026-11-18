-- Issue #79: a device signing in to a Google account that is already in use
-- elsewhere switches users, which left its anonymous data behind. The device
-- now takes a ticket while still anonymous, then redeems it as the account;
-- the ticket proves it owned the anonymous user without passing its token.

create table public.merge_tickets (
  ticket     uuid        primary key default gen_random_uuid(),
  user_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
-- Reached only through the two functions below.
alter table public.merge_tickets enable row level security;
revoke all on public.merge_tickets from anon, authenticated;

create function public.create_merge_ticket() returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  t uuid;
begin
  if auth.uid() is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true then
    raise exception 'only an anonymous user can hand over its data' using errcode = '42501';
  end if;
  insert into public.merge_tickets (user_id) values (auth.uid()) returning ticket into t;
  return t;
end $$;

-- Moves the ticket owner's rows to the caller. On a clash the newer progress
-- and rating win, watchlist entries and favourite/hidden flags are combined,
-- and the account's own settings stay. Rankings are rebuilt, so they are left.
create function public.redeem_merge_ticket(p_ticket uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  src uuid;
  dst uuid := auth.uid();
begin
  if dst is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  delete from public.merge_tickets
   where ticket = p_ticket and created_at > now() - interval '10 minutes'
  returning user_id into src;
  if src is null or src = dst then
    return;
  end if;
  -- The source must still be anonymous: a ticket never moves a real account's data.
  if not exists (select 1 from auth.users where id = src and is_anonymous) then
    return;
  end if;

  insert into public.progress (user_id, title_id, episode_id, position_secs, duration_secs, updated_at)
  select dst, title_id, episode_id, position_secs, duration_secs, updated_at from public.progress where user_id = src
  on conflict (user_id, title_id, episode_id) do update
    set position_secs = excluded.position_secs, duration_secs = excluded.duration_secs, updated_at = excluded.updated_at
    where excluded.updated_at > public.progress.updated_at;

  insert into public.ratings (user_id, title_id, rating, updated_at)
  select dst, title_id, rating, updated_at from public.ratings where user_id = src
  on conflict (user_id, title_id) do update
    set rating = excluded.rating, updated_at = excluded.updated_at
    where excluded.updated_at > public.ratings.updated_at;

  insert into public.watchlist (user_id, title_id, added_at)
  select dst, title_id, added_at from public.watchlist where user_id = src
  on conflict (user_id, title_id) do nothing;

  insert into public.channel_prefs (user_id, channel_id, favorite, hidden)
  select dst, channel_id, favorite, hidden from public.channel_prefs where user_id = src
  on conflict (user_id, channel_id) do update
    set favorite = public.channel_prefs.favorite or excluded.favorite,
        hidden   = public.channel_prefs.hidden or excluded.hidden;

  insert into public.live_group_prefs (user_id, category_id, hidden)
  select dst, category_id, hidden from public.live_group_prefs where user_id = src
  on conflict (user_id, category_id) do update
    set hidden = public.live_group_prefs.hidden or excluded.hidden;

  insert into public.user_settings (user_id, show_radio)
  select dst, show_radio from public.user_settings where user_id = src
  on conflict (user_id) do nothing;

  delete from public.progress         where user_id = src;
  delete from public.ratings          where user_id = src;
  delete from public.watchlist        where user_id = src;
  delete from public.channel_prefs    where user_id = src;
  delete from public.live_group_prefs where user_id = src;
  delete from public.user_settings    where user_id = src;
end $$;

revoke execute on function public.create_merge_ticket() from public, anon;
revoke execute on function public.redeem_merge_ticket(uuid) from public, anon;
grant execute on function public.create_merge_ticket() to authenticated;
grant execute on function public.redeem_merge_ticket(uuid) to authenticated;
