-- ZENITH CUP shop and Telegram support settings
-- Run this entire script in Supabase Dashboard > SQL Editor > New query > Run.
create table if not exists public.shop_items (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  price text not null default 'Contact for price',
  image_url text,
  order_url text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.site_settings (
  key text primary key,
  value text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.shop_items enable row level security;
alter table public.site_settings enable row level security;
drop policy if exists "Public can read active shop items" on public.shop_items;
create policy "Public can read active shop items" on public.shop_items for select to anon, authenticated using (active = true);
drop policy if exists "Admins can manage shop items" on public.shop_items;
create policy "Admins can manage shop items" on public.shop_items for all to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
drop policy if exists "Public can read Telegram setting" on public.site_settings;
drop policy if exists "Public can read public wallet settings" on public.site_settings;
create policy "Public can read public wallet settings" on public.site_settings for select to anon, authenticated using (key in ('telegram_help_url', 'payment_bkash_number', 'payment_nagad_number'));

-- Default values ensure the Wallet settings table is ready on first setup.
insert into public.site_settings (key, value) values
  ('telegram_help_url', 'https://t.me/'),
  ('payment_bkash_number', '01751949571'),
  ('payment_nagad_number', '01751949571')
on conflict (key) do nothing;
drop policy if exists "Admins can manage site settings" on public.site_settings;
create policy "Admins can manage site settings" on public.site_settings for all to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

-- Payment request workflow for admin review
create table if not exists public.payment_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('deposit','withdrawal')),
  amount numeric(12,2) not null check (amount > 0),
  method text not null check (method in ('bKash','Nagad')),
  transaction_id text,
  account_number text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id)
);
alter table public.payment_requests enable row level security;
drop policy if exists "Users can create own payment requests" on public.payment_requests;
create policy "Users can create own payment requests" on public.payment_requests for insert to authenticated
with check (user_id = auth.uid() and status = 'pending' and reviewed_by is null and reviewed_at is null);
drop policy if exists "Users can read own payment requests" on public.payment_requests;
create policy "Users can read own payment requests" on public.payment_requests for select to authenticated
using (user_id = auth.uid() or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
drop policy if exists "Admins can review payment requests" on public.payment_requests;
create policy "Admins can review payment requests" on public.payment_requests for update to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));


-- Top banner + video link support (safe to run on an existing shop_items table)
alter table public.shop_items add column if not exists video_url text;
alter table public.shop_items add column if not exists is_top_banner boolean not null default false;

-- Public image storage bucket for banner images uploaded from the admin phone Gallery.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('zenith-banners', 'zenith-banners', true, 5242880, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

drop policy if exists "Admins upload Zenith banners" on storage.objects;
create policy "Admins upload Zenith banners" on storage.objects for insert to authenticated
with check (bucket_id = 'zenith-banners' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
drop policy if exists "Admins update Zenith banners" on storage.objects;
create policy "Admins update Zenith banners" on storage.objects for update to authenticated
using (bucket_id = 'zenith-banners' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (bucket_id = 'zenith-banners' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
drop policy if exists "Admins delete Zenith banners" on storage.objects;
create policy "Admins delete Zenith banners" on storage.objects for delete to authenticated
using (bucket_id = 'zenith-banners' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
drop policy if exists "Public can view Zenith banners" on storage.objects;
create policy "Public can view Zenith banners" on storage.objects for select to public
using (bucket_id = 'zenith-banners');
