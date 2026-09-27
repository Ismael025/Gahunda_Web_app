-- Gahunda Task 8: authenticated, revision-safe cloud snapshots.
-- Run this complete file once in the Supabase SQL editor.

create table if not exists public.gahunda_user_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null check (revision >= 1),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  device_id text not null check (length(trim(device_id)) > 0),
  updated_at timestamptz not null default now()
);

alter table public.gahunda_user_snapshots enable row level security;

revoke all on table public.gahunda_user_snapshots from anon;
grant select, insert, update on table public.gahunda_user_snapshots
  to authenticated;

drop policy if exists "Users read their own Gahunda backup"
  on public.gahunda_user_snapshots;
create policy "Users read their own Gahunda backup"
  on public.gahunda_user_snapshots
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users create their own Gahunda backup"
  on public.gahunda_user_snapshots;
create policy "Users create their own Gahunda backup"
  on public.gahunda_user_snapshots
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users update their own Gahunda backup"
  on public.gahunda_user_snapshots;
create policy "Users update their own Gahunda backup"
  on public.gahunda_user_snapshots
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create or replace function public.save_gahunda_snapshot(
  p_expected_revision bigint,
  p_payload jsonb,
  p_device_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  saved public.gahunda_user_snapshots;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'gahunda_authentication_required' using errcode = '42501';
  end if;

  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'gahunda_invalid_revision' using errcode = '22023';
  end if;

  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object'
     or p_device_id is null
     or length(trim(p_device_id)) = 0 then
    raise exception 'gahunda_invalid_snapshot' using errcode = '22023';
  end if;

  if p_expected_revision = 0 then
    insert into public.gahunda_user_snapshots (
      user_id,
      revision,
      payload,
      device_id,
      updated_at
    ) values (
      current_user_id,
      1,
      p_payload,
      p_device_id,
      now()
    )
    on conflict (user_id) do nothing
    returning * into saved;
  else
    update public.gahunda_user_snapshots
    set revision = revision + 1,
        payload = p_payload,
        device_id = p_device_id,
        updated_at = now()
    where user_id = current_user_id
      and revision = p_expected_revision
    returning * into saved;
  end if;

  if saved.user_id is null then
    raise exception 'gahunda_revision_conflict' using errcode = '40001';
  end if;

  return jsonb_build_object(
    'revision', saved.revision,
    'payload', saved.payload,
    'device_id', saved.device_id,
    'updated_at', saved.updated_at
  );
end;
$$;

revoke all on function public.save_gahunda_snapshot(bigint, jsonb, text)
  from public;
grant execute on function public.save_gahunda_snapshot(bigint, jsonb, text)
  to authenticated;
