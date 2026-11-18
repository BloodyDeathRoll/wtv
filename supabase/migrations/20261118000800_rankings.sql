-- Each user's ranking of the catalog by WTW's formula (P4-3), written by the
-- `rank` edge function from the user's WTW taste data. One row per title
-- WTW knows (copies of a title share its score); titles WTW does not know
-- have no row and sort after the ranked ones.
create table public.rankings (
  user_id  uuid   not null references auth.users (id) on delete cascade,
  title_id bigint not null references public.titles (id) on delete cascade,
  -- WTW's composite: Φ(s / sd(s)) over the pool, in (0, 1); higher is better.
  score    real   not null,
  primary key (user_id, title_id)
);

-- When a user was last ranked, and from what.
create table public.ranking_runs (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  ranked_at  timestamptz not null,
  -- The WTW account the ranking came from.
  wtw_user_id uuid not null,
  -- How many titles were ranked, and how many ratings and picks trained it.
  titles     integer not null,
  ratings    integer not null,
  picks      integer not null
);

alter table public.rankings enable row level security;
alter table public.ranking_runs enable row level security;

-- Users read their own; only the function (as the database owner) writes.
create policy rankings_select_own on public.rankings for select to authenticated using (user_id = (select auth.uid()));
create policy ranking_runs_select_own on public.ranking_runs for select to authenticated using (user_id = (select auth.uid()));
revoke insert, update, delete on public.rankings, public.ranking_runs from anon, authenticated;

create index rankings_user_score on public.rankings (user_id, score desc);
