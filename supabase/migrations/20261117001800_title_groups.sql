-- One card per title (#56). The provider lists some titles several times
-- (HD and 4K copies). Copies share a TMDB id; a title without one is its own
-- group. One available copy per group (the lowest id) is the card; its group
-- columns hold what the card needs from all copies. The title page lists the
-- copies (`group_id`) so Play can choose one.
alter table public.titles
  add column group_id           bigint,      -- id of the group's card
  add column group_category_ids integer[],   -- every category any copy is in
  add column group_added_at     timestamptz, -- newest copy's added_at
  add column is_primary boolean generated always as (coalesce(group_id, id) = id) stored;

create index titles_group_idx on public.titles (group_id);
create index titles_group_categories_idx on public.titles using gin (group_category_ids) where is_primary;
create index titles_primary_added_idx on public.titles (kind, group_added_at desc) where is_primary;

-- Recomputes the groups of one provider's available titles; returns rows changed.
-- Run after the sync (new titles, categories) and after the details job (TMDB ids).
create function public.refresh_title_groups(p_provider smallint)
returns integer
language sql
volatile
set search_path = ''
as $$
  with keyed as (
    select id, kind, coalesce('t' || tmdb_id::text, 'i' || id::text) as k, category_ids, added_at
    from public.titles
    where provider_id = p_provider and available
  ),
  g as (
    select kind, k, min(id) as primary_id, max(added_at) as added
    from keyed
    group by kind, k
  ),
  cats as (
    select kd.kind, kd.k, array_agg(distinct c order by c) as ids
    from keyed kd cross join lateral unnest(kd.category_ids) as c
    group by kd.kind, kd.k
  ),
  upd as (
    update public.titles t
    set group_id = g.primary_id,
        group_category_ids = coalesce(cats.ids, '{}'),
        group_added_at = g.added
    from keyed kd
    join g on g.kind = kd.kind and g.k = kd.k
    left join cats on cats.kind = kd.kind and cats.k = kd.k
    where t.id = kd.id
      and (t.group_id is distinct from g.primary_id
        or t.group_category_ids is distinct from coalesce(cats.ids, '{}')
        or t.group_added_at is distinct from g.added)
    returning 1
  )
  select count(*)::integer from upd
$$;

revoke execute on function public.refresh_title_groups(smallint) from public, anon, authenticated;
