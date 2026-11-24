-- The sync jobs call the REST API as service_role. It had no statement timeout
-- of its own, so its calls ran under the API's 8 s. While the database is busy
-- (the sync has just rewritten every title) single statements went over and the
-- run failed, a different statement each time (#125).
-- 50 s is below the jobs' own 60 s limit per call, so a statement that is still
-- too slow fails with the database's error, not a dropped connection.
alter role service_role set statement_timeout = '50s';
-- The REST API reads role settings when its configuration loads.
notify pgrst, 'reload config';
