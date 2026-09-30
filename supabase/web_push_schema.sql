-- Gahunda Web Push: subscriptions, reminder queue, and protected RPCs.
-- Run this complete file once in the Supabase SQL Editor.

create table if not exists public.gahunda_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (length(device_id) between 8 and 200),
  endpoint text not null check (length(endpoint) between 20 and 4096),
  p256dh text not null check (length(p256dh) between 20 and 500),
  auth_key text not null check (length(auth_key) between 8 and 500),
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique (user_id, device_id),
  unique (endpoint)
);

create table if not exists public.gahunda_push_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_key text not null check (length(source_key) between 1 and 300),
  title text not null check (length(title) between 1 and 160),
  body text not null check (length(body) between 1 and 500),
  scheduled_at_utc timestamptz not null,
  target_url text not null default './' check (length(target_url) between 1 and 500),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'delivered')),
  attempts integer not null default 0 check (attempts between 0 and 20),
  locked_at timestamptz,
  delivered_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, source_key)
);

create index if not exists gahunda_push_reminders_due_idx
  on public.gahunda_push_reminders (scheduled_at_utc)
  where status = 'pending';

create index if not exists gahunda_push_subscriptions_user_idx
  on public.gahunda_push_subscriptions (user_id);

alter table public.gahunda_push_subscriptions enable row level security;
alter table public.gahunda_push_reminders enable row level security;

revoke all on table public.gahunda_push_subscriptions from anon, authenticated;
revoke all on table public.gahunda_push_reminders from anon, authenticated;
grant select, insert, update, delete on table public.gahunda_push_subscriptions
  to service_role;
grant select, insert, update, delete on table public.gahunda_push_reminders
  to service_role;

create or replace function public.upsert_gahunda_push_subscription(
  p_device_id text,
  p_endpoint text,
  p_p256dh text,
  p_auth_key text,
  p_user_agent text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'gahunda_authentication_required' using errcode = '42501';
  end if;
  if p_device_id is null or length(p_device_id) not between 8 and 200
     or p_endpoint is null or length(p_endpoint) not between 20 and 4096
     or p_p256dh is null or length(p_p256dh) not between 20 and 500
     or p_auth_key is null or length(p_auth_key) not between 8 and 500 then
    raise exception 'gahunda_invalid_push_subscription' using errcode = '22023';
  end if;

  -- A browser endpoint belongs to one current account at a time.
  delete from public.gahunda_push_subscriptions
  where endpoint = p_endpoint and user_id <> current_user_id;

  insert into public.gahunda_push_subscriptions (
    user_id, device_id, endpoint, p256dh, auth_key, user_agent,
    created_at, updated_at, last_seen_at
  ) values (
    current_user_id, p_device_id, p_endpoint, p_p256dh, p_auth_key,
    left(p_user_agent, 1000), now(), now(), now()
  )
  on conflict (user_id, device_id) do update
  set endpoint = excluded.endpoint,
      p256dh = excluded.p256dh,
      auth_key = excluded.auth_key,
      user_agent = excluded.user_agent,
      updated_at = now(),
      last_seen_at = now();
end;
$$;

revoke all on function public.upsert_gahunda_push_subscription(
  text, text, text, text, text
) from public;
grant execute on function public.upsert_gahunda_push_subscription(
  text, text, text, text, text
) to authenticated;

create or replace function public.replace_gahunda_push_reminders(
  p_reminders jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  item jsonb;
  item_source_key text;
  item_title text;
  item_body text;
  item_target_url text;
  item_scheduled_at timestamptz;
begin
  if current_user_id is null then
    raise exception 'gahunda_authentication_required' using errcode = '42501';
  end if;
  if p_reminders is null or jsonb_typeof(p_reminders) <> 'array'
     or jsonb_array_length(p_reminders) > 100 then
    raise exception 'gahunda_invalid_push_reminders' using errcode = '22023';
  end if;

  -- Replace only work that has not already been delivered.
  delete from public.gahunda_push_reminders
  where user_id = current_user_id and status in ('pending', 'processing');

  for item in select value from jsonb_array_elements(p_reminders)
  loop
    item_source_key := trim(item->>'source_key');
    item_title := trim(item->>'title');
    item_body := trim(item->>'body');
    item_target_url := coalesce(nullif(trim(item->>'target_url'), ''), './');
    begin
      item_scheduled_at := (item->>'scheduled_at_utc')::timestamptz;
    exception when others then
      raise exception 'gahunda_invalid_push_reminder_time' using errcode = '22007';
    end;

    if jsonb_typeof(item) <> 'object'
       or item_source_key is null
       or item_title is null
       or item_body is null
       or item_scheduled_at is null
       or length(item_source_key) not between 1 and 300
       or length(item_title) not between 1 and 160
       or length(item_body) not between 1 and 500
       or length(item_target_url) not between 1 and 500
       or item_scheduled_at < now() - interval '5 minutes'
       or item_scheduled_at > now() + interval '370 days' then
      raise exception 'gahunda_invalid_push_reminder' using errcode = '22023';
    end if;

    insert into public.gahunda_push_reminders (
      user_id, source_key, title, body, scheduled_at_utc, target_url,
      status, attempts, locked_at, delivered_at, last_error,
      created_at, updated_at
    ) values (
      current_user_id, item_source_key, item_title, item_body,
      item_scheduled_at, item_target_url,
      'pending', 0, null, null, null, now(), now()
    )
    on conflict (user_id, source_key) do update
    set title = excluded.title,
        body = excluded.body,
        scheduled_at_utc = excluded.scheduled_at_utc,
        target_url = excluded.target_url,
        status = case
          when gahunda_push_reminders.scheduled_at_utc is distinct from
               excluded.scheduled_at_utc then 'pending'
          else gahunda_push_reminders.status
        end,
        attempts = case
          when gahunda_push_reminders.scheduled_at_utc is distinct from
               excluded.scheduled_at_utc then 0
          else gahunda_push_reminders.attempts
        end,
        locked_at = case
          when gahunda_push_reminders.scheduled_at_utc is distinct from
               excluded.scheduled_at_utc then null
          else gahunda_push_reminders.locked_at
        end,
        delivered_at = case
          when gahunda_push_reminders.scheduled_at_utc is distinct from
               excluded.scheduled_at_utc then null
          else gahunda_push_reminders.delivered_at
        end,
        last_error = null,
        updated_at = now();
  end loop;
end;
$$;

revoke all on function public.replace_gahunda_push_reminders(jsonb)
  from public;
grant execute on function public.replace_gahunda_push_reminders(jsonb)
  to authenticated;

create or replace function public.claim_due_gahunda_push_reminders(
  p_limit integer default 50
)
returns setof public.gahunda_push_reminders
language sql
security definer
set search_path = public
as $$
  update public.gahunda_push_reminders r
  set status = 'processing',
      attempts = r.attempts + 1,
      locked_at = now(),
      updated_at = now()
  where r.id in (
    select due.id
    from public.gahunda_push_reminders due
    where due.scheduled_at_utc <= now()
      and due.attempts < 5
      and (
        due.status = 'pending'
        or (due.status = 'processing' and due.locked_at < now() - interval '5 minutes')
      )
    order by due.scheduled_at_utc
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 100))
  )
  returning r.*;
$$;

create or replace function public.complete_gahunda_push_reminder(
  p_id uuid,
  p_error text default null
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.gahunda_push_reminders
  set status = 'delivered',
      delivered_at = now(),
      locked_at = null,
      last_error = left(p_error, 1000),
      updated_at = now()
  where id = p_id and status = 'processing';
$$;

create or replace function public.fail_gahunda_push_reminder(
  p_id uuid,
  p_error text
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.gahunda_push_reminders
  set status = case when attempts >= 5 then 'delivered' else 'pending' end,
      delivered_at = case when attempts >= 5 then now() else null end,
      locked_at = null,
      last_error = left(coalesce(p_error, 'Unknown Web Push error'), 1000),
      updated_at = now()
  where id = p_id and status = 'processing';
$$;

revoke all on function public.claim_due_gahunda_push_reminders(integer)
  from public;
revoke all on function public.complete_gahunda_push_reminder(uuid, text)
  from public;
revoke all on function public.fail_gahunda_push_reminder(uuid, text)
  from public;
grant execute on function public.claim_due_gahunda_push_reminders(integer)
  to service_role;
grant execute on function public.complete_gahunda_push_reminder(uuid, text)
  to service_role;
grant execute on function public.fail_gahunda_push_reminder(uuid, text)
  to service_role;

-- Remove delivered rows after 30 days without touching future reminders.
create or replace function public.cleanup_gahunda_push_history()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.gahunda_push_reminders
  where status = 'delivered' and delivered_at < now() - interval '30 days';
$$;

revoke all on function public.cleanup_gahunda_push_history() from public;
grant execute on function public.cleanup_gahunda_push_history()
  to service_role;
