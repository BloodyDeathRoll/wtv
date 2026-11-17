-- Every table in public must have row level security on. Supabase grants
-- select, insert, update and delete on new tables to `authenticated`, so a
-- table without RLS is open to every signed-in user.
do $$
declare open_tables text;
begin
  select string_agg(relname, ', ' order by relname) into open_tables
  from pg_class
  where relnamespace = 'public'::regnamespace and relkind in ('r', 'p') and not relrowsecurity;
  if open_tables is not null then
    raise exception 'Tables without row level security: %', open_tables;
  end if;
end $$;
