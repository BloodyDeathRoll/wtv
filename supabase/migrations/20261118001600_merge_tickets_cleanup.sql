-- Review of #90: tickets that were never redeemed (the Google sign-in failed,
-- say) were kept forever, and an anonymous user could pile them up. A new
-- ticket now replaces the user's older ones and clears expired tickets.
create or replace function public.create_merge_ticket() returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  t uuid;
begin
  if auth.uid() is null or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) is not true then
    raise exception 'only an anonymous user can hand over its data' using errcode = '42501';
  end if;
  delete from public.merge_tickets where user_id = auth.uid() or created_at < now() - interval '10 minutes';
  insert into public.merge_tickets (user_id) values (auth.uid()) returning ticket into t;
  return t;
end $$;
