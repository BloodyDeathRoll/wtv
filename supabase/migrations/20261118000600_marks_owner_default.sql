-- The app saves ratings and the watchlist without naming its user, as it does
-- progress: the row is the signed-in user's. RLS (ratings_own, watchlist_own) still checks it.
alter table public.ratings alter column user_id set default auth.uid();
alter table public.watchlist alter column user_id set default auth.uid();
