-- ZENITH CUP Live Chat sender-role fix
-- Run once in Supabase SQL Editor after the original setup.
alter table public.support_messages
  add column if not exists sender_role text not null default 'user';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'support_messages_sender_role_check'
      and conrelid = 'public.support_messages'::regclass
  ) then
    alter table public.support_messages
      add constraint support_messages_sender_role_check
      check (sender_role in ('user','admin'));
  end if;
end $$;

drop policy if exists "support messages send as self to own chat or admin" on public.support_messages;
create policy "support messages send as self to own chat or admin"
on public.support_messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and (
    (sender_role = 'admin' and public.is_admin())
    or
    (sender_role = 'user' and not public.is_admin() and exists (
      select 1 from public.support_conversations c
      where c.id = conversation_id and c.user_id = auth.uid()
    ))
  )
);
