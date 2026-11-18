-- The composite saturates near 1 for a user's best titles (Φ of several sd),
-- so many tie at the top. Rank by the weighted sum before Φ instead, and
-- keep the composite for a match %.
alter table public.rankings add column s double precision;
update public.rankings set s = score;
alter table public.rankings alter column s set not null;
drop index public.rankings_user_score;
create index rankings_user_s on public.rankings (user_id, s desc);
comment on column public.rankings.s is 'WTW formula v2 weighted sum before Φ; order by this, higher is better.';
