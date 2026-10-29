-- ZENITH CUP Live Support Chat setup
-- Run this entire script once in Supabase SQL Editor.

create table if not exists public.support_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'open' check (status in ('open','closed')),
  last_message text,
  last_message_at timestamptz not null default now(),
  last_sender_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.support_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text,
  attachment_path text,
  attachment_name text,
  attachment_mime text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint support_messages_body_or_attachment check (
    nullif(trim(body), '') is not null or attachment_path is not null
  )
);

create index if not exists support_conversations_user_id_idx on public.support_conversations(user_id);
create index if not exists support_conversations_last_message_idx on public.support_conversations(last_message_at desc);
create index if not exists support_messages_conversation_created_idx on public.support_messages(conversation_id, created_at);

alter table public.support_conversations enable row level security;
alter table public.support_messages enable row level security;

drop policy if exists "support conversations read own or admin" on public.support_conversations;
create policy "support conversations read own or admin"
on public.support_conversations for select to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "support conversations create own" on public.support_conversations;
create policy "support conversations create own"
on public.support_conversations for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "support conversations admin update" on public.support_conversations;
create policy "support conversations admin update"
on public.support_conversations for update to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists "support messages read own or admin" on public.support_messages;
create policy "support messages read own or admin"
on public.support_messages for select to authenticated
using (
  public.is_admin() or exists (
    select 1 from public.support_conversations c
    where c.id = conversation_id and c.user_id = auth.uid()
  )
);

drop policy if exists "support messages send as self to own chat or admin" on public.support_messages;
create policy "support messages send as self to own chat or admin"
on public.support_messages for insert to authenticated
with check (
  sender_id = auth.uid() and (
    public.is_admin() or exists (
      select 1 from public.support_conversations c
      where c.id = conversation_id and c.user_id = auth.uid()
    )
  )
);

create or replace function public.support_message_after_insert()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  update public.support_conversations
  set last_message = case
        when new.attachment_path is not null and nullif(trim(new.body),'') is null then '📷 Image attachment'
        else left(coalesce(nullif(trim(new.body),''),'📷 Image attachment'), 180)
      end,
      last_message_at = new.created_at,
      last_sender_id = new.sender_id,
      updated_at = now()
  where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists support_message_after_insert_trigger on public.support_messages;
create trigger support_message_after_insert_trigger
after insert on public.support_messages
for each row execute function public.support_message_after_insert();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('support-attachments', 'support-attachments', false, 5242880,
        array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

drop policy if exists "support attachment read own or admin" on storage.objects;
create policy "support attachment read own or admin"
on storage.objects for select to authenticated
using (
  bucket_id = 'support-attachments'
  and exists (
    select 1 from public.support_conversations c
    where c.id::text = (storage.foldername(name))[1]
      and (c.user_id = auth.uid() or public.is_admin())
  )
);

drop policy if exists "support attachment upload own or admin" on storage.objects;
create policy "support attachment upload own or admin"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'support-attachments'
  and exists (
    select 1 from public.support_conversations c
    where c.id::text = (storage.foldername(name))[1]
      and (c.user_id = auth.uid() or public.is_admin())
  )
);

drop policy if exists "support attachment delete admin" on storage.objects;
create policy "support attachment delete admin"
on storage.objects for delete to authenticated
using (bucket_id = 'support-attachments' and public.is_admin());

do $$
begin
  alter publication supabase_realtime add table public.support_messages;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.support_conversations;
exception when duplicate_object then null;
end $$;
