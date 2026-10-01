// POST   /functions/v1/activity  { token, kind: "update" | "start", env: "sandbox" | "production" }
// DELETE /functions/v1/activity  { token }
// Registers / removes ActivityKit push tokens for the device's user.
// Single-file Edge Function (paste-able into the Supabase dashboard).
import { createClient } from "npm:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const TOKEN = /^[0-9a-f]{32,400}$/;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

Deno.serve(async (req) => {
  if (req.method !== "POST" && req.method !== "DELETE") return json({ error: "method_not_allowed" }, 405);

  // Authenticate the scoped device token (only its SHA-256 is stored server-side).
  const deviceToken = req.headers.get("x-device-token") ?? "";
  if (!/^[0-9a-f]{64}$/.test(deviceToken)) return json({ error: "unauthorized" }, 401);
  const { data: userId, error: authError } = await admin.rpc("device_user", { p_token_hash: await sha256Hex(deviceToken) });
  if (authError) {
    console.error("device_user failed", authError.message);
    return json({ error: "server_error" }, 500);
  }
  if (!userId) return json({ error: "unauthorized" }, 401);

  const raw = await req.text();
  if (raw.length > 2048) return json({ error: "payload_too_large" }, 413);
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ error: "bad_json" }, 400);
  }
  if (!isRecord(body) || typeof body.token !== "string" || !TOKEN.test(body.token)) {
    return json({ error: "bad_token" }, 400);
  }

  if (req.method === "DELETE") {
    await admin.from("live_activity_tokens").delete().eq("token", body.token).eq("user_id", userId);
    return json({ ok: true });
  }

  const kind = body.kind === "start" ? "start" : body.kind === "update" ? "update" : null;
  const env = body.env === "production" ? "production" : body.env === "sandbox" ? "sandbox" : null;
  if (!kind || !env) return json({ error: "bad_request" }, 400);

  // Cap tokens per user so a leaked device token can't fill the table.
  const { count } = await admin
    .from("live_activity_tokens")
    .select("token", { count: "exact", head: true })
    .eq("user_id", userId);
  if ((count ?? 0) > 40) {
    await admin.from("live_activity_tokens").delete().eq("user_id", userId).eq("kind", kind)
      .lt("updated_at", new Date(Date.now() - 24 * 3600 * 1000).toISOString());
  }

  const { error } = await admin.from("live_activity_tokens").upsert({
    token: body.token,
    user_id: userId,
    kind,
    apns_env: env,
    updated_at: new Date().toISOString(),
  }, { onConflict: "token" });
  if (error) {
    console.error("token upsert failed", error.message);
    return json({ error: "server_error" }, 500);
  }
  return json({ ok: true });
});
