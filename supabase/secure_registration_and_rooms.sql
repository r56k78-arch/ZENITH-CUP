-- ZENITH CUP: secure tournament registration and room access
-- Run this file in Supabase SQL Editor before enabling paid registrations.
alter table public.profiles add column if not exists wallet_balance numeric(12,2) not null default 0;

create table if not exists public.match_rooms (
  tournament_id uuid primary key references public.tournaments(id) on delete cascade,
  room_id text,
  room_password text,
  updated_at timestamptz not null default now()
);

alter table public.match_rooms enable row level security;
drop policy if exists "Registered players can view room details" on public.match_rooms;
create policy "Registered players can view room details" on public.match_rooms
for select to authenticated using (
  exists (
    select 1 from public.registrations r
    where r.tournament_id = match_rooms.tournament_id
      and r.player_id = auth.uid()
      and coalesce(r.status, '') in ('registered','approved','confirmed')
  )
);
-- Admin room writes should be performed through a trusted admin tool or a separate
-- admin-only policy matching your existing profiles.role setup.

create or replace function public.register_for_tournament(p_tournament_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_fee numeric(12,2);
  v_max integer;
  v_status text;
  v_count integer;
  v_balance numeric(12,2);
begin
  if v_user is null then
    raise exception 'Please sign in first.';
  end if;

  select entry_fee, max_players, status
    into v_fee, v_max, v_status
    from public.tournaments
    where id = p_tournament_id
    for update;

  if not found or v_status <> 'published' then
    raise exception 'This tournament is not open for registration.';
  end if;

  if exists (select 1 from public.registrations where tournament_id=p_tournament_id and player_id=v_user) then
    raise exception 'You have already registered for this tournament.';
  end if;

  select count(*) into v_count
    from public.registrations
    where tournament_id=p_tournament_id
      and coalesce(status,'') in ('registered','approved','confirmed','pending');

  if v_count >= coalesce(v_max, 0) then
    raise exception 'Slots are full.';
  end if;

  select wallet_balance into v_balance from public.profiles where id=v_user for update;
  if not found then
    raise exception 'Player profile not found.';
  end if;
  v_fee := greatest(coalesce(v_fee,0),0);
  if coalesce(v_balance,0) < v_fee then
    raise exception 'Insufficient wallet balance. Please add money first.';
  end if;

  update public.profiles set wallet_balance = coalesce(wallet_balance,0) - v_fee where id=v_user;
  insert into public.registrations(tournament_id,player_id,status)
    values(p_tournament_id,v_user,'registered');

  return jsonb_build_object('success',true,'fee',v_fee,'balance',coalesce(v_balance,0)-v_fee);
end;
$$;

revoke all on function public.register_for_tournament(uuid) from public;
grant execute on function public.register_for_tournament(uuid) to authenticated;
