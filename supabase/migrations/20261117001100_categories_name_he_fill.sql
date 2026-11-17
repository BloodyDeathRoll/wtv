-- Rows written before `name_he` existed show the provider's name until the
-- next sync sets both display names.
update public.categories set name_he = name where name_he is null;
