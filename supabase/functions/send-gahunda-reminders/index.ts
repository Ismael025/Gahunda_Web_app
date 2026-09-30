import { createClient } from "npm:@supabase/supabase-js@2";
import {
  ApplicationServer,
  importVapidKeys,
  PushMessageError,
  Urgency,
} from "jsr:@negrel/webpush@0.5.0";

type Reminder = {
  id: string;
  user_id: string;
  source_key: string;
  title: string;
  body: string;
  target_url: string;
};

type Subscription = {
  id: string;
  endpoint: string;
  p256dh: string;
  auth_key: string;
};

function required(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing Edge Function secret: ${name}`);
  return value;
}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  try {
    const cronSecret = required("GAHUNDA_CRON_SECRET");
    if (request.headers.get("x-gahunda-cron-secret") !== cronSecret) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }

    const supabase = createClient(
      required("SUPABASE_URL"),
      required("SUPABASE_SERVICE_ROLE_KEY"),
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const vapidKeys = await importVapidKeys(
      JSON.parse(required("GAHUNDA_VAPID_KEYS_JSON")),
    );
    const applicationServer = await ApplicationServer.new({
      contactInformation: required("GAHUNDA_VAPID_SUBJECT"),
      vapidKeys,
    });

    const { data, error } = await supabase.rpc(
      "claim_due_gahunda_push_reminders",
      { p_limit: 50 },
    );
    if (error) throw error;

    const reminders = (data ?? []) as Reminder[];
    let delivered = 0;
    let retried = 0;
    let expiredSubscriptions = 0;

    for (const reminder of reminders) {
      const subscriptionsResult = await supabase
        .from("gahunda_push_subscriptions")
        .select("id, endpoint, p256dh, auth_key")
        .eq("user_id", reminder.user_id);

      if (subscriptionsResult.error) {
        await supabase.rpc("fail_gahunda_push_reminder", {
          p_id: reminder.id,
          p_error: subscriptionsResult.error.message,
        });
        retried += 1;
        continue;
      }

      const subscriptions = (subscriptionsResult.data ?? []) as Subscription[];
      if (subscriptions.length === 0) {
        await supabase.rpc("complete_gahunda_push_reminder", {
          p_id: reminder.id,
          p_error: "No active browser subscriptions",
        });
        continue;
      }

      let successes = 0;
      const failures: string[] = [];
      for (const subscription of subscriptions) {
        try {
          const subscriber = applicationServer.subscribe({
            endpoint: subscription.endpoint,
            keys: {
              p256dh: subscription.p256dh,
              auth: subscription.auth_key,
            },
          });
          await subscriber.pushTextMessage(
            JSON.stringify({
              title: reminder.title,
              body: reminder.body,
              tag: reminder.source_key,
              url: reminder.target_url,
            }),
            {
              ttl: 60 * 60,
              urgency: Urgency.High,
              topic: `gahunda-${reminder.id.replaceAll("-", "").slice(0, 20)}`,
            },
          );
          successes += 1;
        } catch (pushError) {
          if (pushError instanceof PushMessageError && pushError.isGone()) {
            await supabase
              .from("gahunda_push_subscriptions")
              .delete()
              .eq("id", subscription.id);
            expiredSubscriptions += 1;
          } else {
            failures.push(errorText(pushError));
          }
        }
      }

      if (successes > 0 || failures.length === 0) {
        await supabase.rpc("complete_gahunda_push_reminder", {
          p_id: reminder.id,
          p_error: failures.length === 0 ? null : failures.join(" | "),
        });
        delivered += 1;
      } else {
        await supabase.rpc("fail_gahunda_push_reminder", {
          p_id: reminder.id,
          p_error: failures.join(" | "),
        });
        retried += 1;
      }
    }

    await supabase.rpc("cleanup_gahunda_push_history");
    return Response.json({
      claimed: reminders.length,
      delivered,
      retried,
      expired_subscriptions: expiredSubscriptions,
    });
  } catch (error) {
    console.error(error);
    return Response.json({ error: errorText(error) }, { status: 500 });
  }
});
