-- The provider's plot is Hebrew, and mostly the same text as TMDB's Hebrew
-- overview. Keep it only when TMDB has no Hebrew overview: it saves about a
-- tenth of the database. The jobs keep sending the plot; this trigger drops it.
-- If TMDB's Hebrew overview is later cleared, the title's plot comes back on
-- the next list sync; an episode's comes back when its series is re-fetched.

create function public.drop_plot_when_tmdb_hebrew() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.overview_he is not null then
    new.plot := null;
  end if;
  return new;
end;
$$;

revoke execute on function public.drop_plot_when_tmdb_hebrew() from public, anon, authenticated;

create trigger titles_drop_plot before insert or update on public.titles
  for each row execute function public.drop_plot_when_tmdb_hebrew();

create trigger episodes_drop_plot before insert or update on public.episodes
  for each row execute function public.drop_plot_when_tmdb_hebrew();

update public.titles set plot = null where plot is not null and overview_he is not null;
update public.episodes set plot = null where plot is not null and overview_he is not null;
