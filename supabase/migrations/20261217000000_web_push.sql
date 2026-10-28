-- Web push: one row per browser/device that turned on alerts. Each new in-app notification is also pushed
-- to that user's devices by the send-push Edge Function (called via pg_net; secret + URL live in Vault).
create extension if not exists pg_net with schema extensions;

create table push_subscriptions (
  endpoint text primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);
alter table push_subscriptions enable row level security;
create policy push_subscriptions_own on push_subscriptions for select using (user_id = auth.uid());
create policy push_subscriptions_delete_own on push_subscriptions for delete using (user_id = auth.uid());
grant select, delete on push_subscriptions to authenticated;

create function save_push_subscription(p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_allowed'; end if;
  if p_endpoint !~ '^https://' or length(p_endpoint) > 1000 then raise exception 'invalid: bad endpoint'; end if;
  insert into push_subscriptions (endpoint, user_id, p256dh, auth) values (p_endpoint, auth.uid(), p_p256dh, p_auth)
  on conflict (endpoint) do update set user_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth, created_at = now();
end $$;
revoke all on function save_push_subscription(text, text, text) from public, anon;
grant execute on function save_push_subscription(text, text, text) to authenticated;

create function push_on_notification() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from push_subscriptions where user_id = new.user_id) then
    perform net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'push_function_url'),
      body := jsonb_build_object('user_id', new.user_id, 'title', new.title, 'body', new.body, 'path', new.action_path),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret',
        (select decrypted_secret from vault.decrypted_secrets where name = 'push_hook_secret')));
  end if;
  return new;
exception when others then
  return new; -- a push failure must never block the in-app notification
end $$;
revoke all on function push_on_notification() from public, anon, authenticated;
create trigger app_notifications_push after insert on app_notifications for each row execute function push_on_notification();
