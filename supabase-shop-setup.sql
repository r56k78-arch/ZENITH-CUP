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
create policy "Public can read Telegram setting" on public.site_settings for select to anon, authenticated using (key = 'telegram_help_url');
drop policy if exists "Admins can manage site settings" on public.site_settings;
create policy "Admins can manage site settings" on public.site_settings for all to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
