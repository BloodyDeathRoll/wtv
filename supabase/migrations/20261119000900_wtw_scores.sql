-- WTW's own "% match", asked of WTW per title (functions/wtw-scores), kept
-- per user for 12 hours. Replaces the match computed here (rankings.match),
-- which could not be made to agree with WTW reliably. `match` is what WTW
-- answers (0–0.97); null when WTW does not score the title.
create table public.wtw_scores (
  user_id     uuid        not null references auth.users (id) on delete cascade,
  -- The WTW account the answer is for: another account's answers are dropped.
  wtw_user_id uuid        not null,
  kind        text        not null,
  tmdb_id     integer     not null,
  match       real,
  scored_at   timestamptz not null default now(),
  primary key (user_id, kind, tmdb_id)
);

alter table public.wtw_scores enable row level security;
create policy wtw_scores_select_own on public.wtw_scores for select to authenticated using (user_id = (select auth.uid()));
revoke insert, update, delete on public.wtw_scores from anon, authenticated;

-- The match as WTW shows it, for any titles select (copies share the answer).
create or replace function public.wtw_match(t public.titles)
returns integer
language sql
stable
set search_path = ''
as $$
  select round(least(s.match, 0.97) * 100)::integer
  from public.wtw_scores s
  where s.user_id = (select auth.uid()) and s.kind = t.kind and s.tmdb_id = t.tmdb_id
    and s.scored_at > now() - interval '12 hours' and s.match > 0
$$;

alter table public.rankings drop column match;
