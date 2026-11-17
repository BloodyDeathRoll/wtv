-- `real` values come back from the REST API with 6 significant digits
-- (-1.5270355 is read as -1.52704). WTW's vectors carry up to 8, so the copy
-- is stored in double precision to read back what WTW has.
alter table public.titles alter column wtw_taste_vec type double precision[];
