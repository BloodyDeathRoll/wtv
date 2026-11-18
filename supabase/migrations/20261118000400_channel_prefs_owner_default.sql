-- The app saves channel favourites without naming its user, as it does
-- progress: the row is the signed-in user's. RLS (channel_prefs_own) still checks it.
alter table public.channel_prefs alter column user_id set default auth.uid();
