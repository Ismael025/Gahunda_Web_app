-- Run after deploying the send-gahunda-reminders Edge Function.
-- Before running, create these Vault secrets in the Supabase SQL Editor:
-- select vault.create_secret('https://YOUR_PROJECT_REF.supabase.co', 'gahunda_project_url');
-- select vault.create_secret('YOUR_LONG_RANDOM_CRON_SECRET', 'gahunda_cron_secret');

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
declare
  existing_job_id bigint;
begin
  select jobid into existing_job_id
  from cron.job
  where jobname = 'gahunda-web-push-every-minute';
  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;
end;
$$;

select cron.schedule(
  'gahunda-web-push-every-minute',
  '* * * * *',
  $$
  select net.http_post(
    url := (
      select decrypted_secret
      from vault.decrypted_secrets
      where name = 'gahunda_project_url'
    ) || '/functions/v1/send-gahunda-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-gahunda-cron-secret', (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'gahunda_cron_secret'
      )
    ),
    body := jsonb_build_object('invoked_at', now())
  ) as request_id;
  $$
);
