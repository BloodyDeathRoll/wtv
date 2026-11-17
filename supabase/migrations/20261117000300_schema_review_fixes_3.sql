-- Third round of review fixes (#43).

-- Same as the user tables: no schema changes on catalog tables by client roles.
revoke references, trigger
  on public.providers, public.categories, public.titles, public.episodes, public.channels
  from anon, authenticated;

-- Tables created by later migrations start without Supabase's broad default
-- grants. A table that clients may use needs an explicit grant and a policy.
alter default privileges for role postgres in schema public
  revoke all on tables from anon;
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger on tables from authenticated;
