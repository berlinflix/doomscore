// POST   /functions/v1/activity  { token, kind: "update" | "start", env: "sandbox" | "production" }
// DELETE /functions/v1/activity  { token }
// Registers / removes ActivityKit push tokens for the device's user.
import { admin, authenticateDevice, isRecord, json, readJson } from "../_shared/http.ts";

const TOKEN = /^[0-9a-f]{32,400}$/;

Deno.serve(async (req) => {
  if (req.method !== "POST" && req.method !== "DELETE") return json({ error: "method_not_allowed" }, 405);

  const auth = await authenticateDevice(req);
  if (auth instanceof Response) return auth;

  const body = await readJson(req, 2048);
  if (body instanceof Response) return body;
  if (!isRecord(body) || typeof body.token !== "string" || !TOKEN.test(body.token)) {
    return json({ error: "bad_token" }, 400);
  }

  if (req.method === "DELETE") {
    await admin.from("live_activity_tokens").delete().eq("token", body.token).eq("user_id", auth.userId);
    return json({ ok: true });
  }

  const kind = body.kind === "start" ? "start" : body.kind === "update" ? "update" : null;
  const env = body.env === "production" ? "production" : body.env === "sandbox" ? "sandbox" : null;
  if (!kind || !env) return json({ error: "bad_request" }, 400);

  // Cap tokens per user so a compromised device token can't fill the table.
  const { count } = await admin
    .from("live_activity_tokens")
    .select("token", { count: "exact", head: true })
    .eq("user_id", auth.userId);
  if ((count ?? 0) > 40) {
    await admin.from("live_activity_tokens").delete().eq("user_id", auth.userId).eq("kind", kind)
      .lt("updated_at", new Date(Date.now() - 24 * 3600 * 1000).toISOString());
  }

  const { error } = await admin.from("live_activity_tokens").upsert({
    token: body.token,
    user_id: auth.userId,
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
