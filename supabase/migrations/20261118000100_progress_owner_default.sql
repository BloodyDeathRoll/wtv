-- The app saves playback progress without naming its user: the row is the
-- signed-in user's. RLS (progress_own) still checks it.
alter table public.progress alter column user_id set default auth.uid();
