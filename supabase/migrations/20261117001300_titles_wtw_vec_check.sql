-- WTW's taste vectors have 25 floats (taste version 1). A WTW change in size
-- fails the WTW match loudly instead of storing vectors the ranking cannot use.
alter table public.titles
  add constraint titles_wtw_taste_vec_check check (cardinality(wtw_taste_vec) = 25);
