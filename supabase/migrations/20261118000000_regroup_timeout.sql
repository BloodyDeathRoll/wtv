-- The REST API runs each call under an 8 s statement timeout. Right after
-- the sync has rewritten every title, the regroup reads cold pages and took
-- 6.8 s (0.35 s warm); under load it went over and the run failed (#65).
-- PostgREST applies a function's own statement_timeout to its call.
alter function public.refresh_title_groups(smallint) set statement_timeout = '120s';
