// POST /functions/v1/ingest
// Called by the broadcast extension (every few seconds while counting) and by
// the app (catch-up sync). Auth: scoped device token in `x-device-token`.
// Body: { day, tzOffsetMinutes, apps: [{app, reels, watchSeconds, adsSkipped}],
//         live?: {todayCount, sessionCount, goal, armed, appName, sessionStarted},
//         clientTime, appVersion }
import { admin, authenticateDevice, background, isInt, isRecord, json, readJson } from "../_shared/http.ts";
import { apnsConfigured, isDeadToken, sendLiveActivityPush } from "../_shared/apns.ts";

const APPS = new Set(["instagram", "youtube", "tiktok", "snapchat", "other"]);

interface AppTotal {
  app: string;
  reels: number;
  watchSeconds: number;
  adsSkipped: number;
}

interface Live {
  todayCount: number;
  sessionCount: number;
  goal: number;
  armed: boolean;
  appName: string;
  sessionStarted: boolean;
}

function parse(body: unknown): { day: string; apps: AppTotal[]; live?: Live } | string {
  if (!isRecord(body)) return "bad_body";
  const day = body.day;
  if (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day) || Number.isNaN(Date.parse(day))) return "bad_day";
  if (!Array.isArray(body.apps) || body.apps.length > 8) return "bad_apps";
  const apps: AppTotal[] = [];
  for (const entry of body.apps) {
    if (!isRecord(entry) || typeof entry.app !== "string" || !APPS.has(entry.app)) return "bad_app";
    if (!isInt(entry.reels, 0, 20000) || !isInt(entry.watchSeconds, 0, 86400) || !isInt(entry.adsSkipped, 0, 20000)) {
      return "bad_numbers";
    }
    apps.push({ app: entry.app, reels: entry.reels, watchSeconds: entry.watchSeconds, adsSkipped: entry.adsSkipped });
  }
  let live: Live | undefined;
  if (body.live !== undefined && body.live !== null) {
    const l = body.live;
    if (
      !isRecord(l) || !isInt(l.todayCount, 0, 100000) || !isInt(l.sessionCount, 0, 100000) || !isInt(l.goal, 1, 5000) ||
      typeof l.armed !== "boolean" || typeof l.appName !== "string" || typeof l.sessionStarted !== "boolean"
    ) return "bad_live";
    live = {
      todayCount: l.todayCount,
      sessionCount: l.sessionCount,
      goal: l.goal,
      armed: l.armed,
      appName: l.appName.slice(0, 24),
      sessionStarted: l.sessionStarted,
    };
  }
  return { day, apps, live };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const auth = await authenticateDevice(req);
  if (auth instanceof Response) return auth;

  const body = await readJson(req);
  if (body instanceof Response) return body;
  const parsed = parse(body);
  if (typeof parsed === "string") return json({ error: parsed }, 400);

  if (parsed.apps.length > 0) {
    const { data, error } = await admin.rpc("ingest_stats", {
      p_user: auth.userId,
      p_device_hash: auth.tokenHash,
      p_day: parsed.day,
      p_rows: parsed.apps,
    });
    if (error) {
      console.error("ingest_stats failed", error.message);
      return json({ error: "server_error" }, 500);
    }
    if (isRecord(data) && data.ok === false) {
      return json(data, data.error === "rate_limited" ? 429 : 400);
    }
  }

  if (parsed.live && apnsConfigured()) {
    const work = mirrorToLiveActivity(auth.userId, parsed.live).catch((e) => console.error("apns", e));
    const pending = background(work);
    if (pending) await pending;
  }
  return json({ ok: true });
});

/** Pushes the new count to the user's Live Activity (or starts one). */
async function mirrorToLiveActivity(userId: string, live: Live) {
  const now = Math.floor(Date.now() / 1000);
  const contentState = {
    todayCount: live.todayCount,
    sessionCount: live.sessionCount,
    goal: live.goal,
    armed: live.armed,
    appName: live.appName,
    updatedAt: now,
  };

  const since = new Date(Date.now() - 8 * 3600 * 1000).toISOString();
  const { data: updateTokens } = await admin
    .from("live_activity_tokens")
    .select("token, apns_env, last_push_at, last_high_priority_at")
    .eq("user_id", userId)
    .eq("kind", "update")
    .gte("updated_at", since);

  if (updateTokens && updateTokens.length > 0) {
    for (const row of updateTokens) {
      const lastHigh = row.last_high_priority_at ? Date.parse(row.last_high_priority_at) / 1000 : 0;
      // High priority at most every ~20 s; the rest go out as low priority so
      // we stay inside Apple's Live Activity update budget.
      const priority: 5 | 10 = now - lastHigh > 20 || !live.armed ? 10 : 5;
      const result = await sendLiveActivityPush(row.token, row.apns_env, {
        aps: { timestamp: now, event: "update", "content-state": contentState, "stale-date": now + 1800 },
      }, priority);
      if (isDeadToken(result)) {
        await admin.from("live_activity_tokens").delete().eq("token", row.token);
      } else if (result.status === 200) {
        const patch: Record<string, string> = { last_push_at: new Date().toISOString() };
        if (priority === 10) patch.last_high_priority_at = patch.last_push_at;
        await admin.from("live_activity_tokens").update(patch).eq("token", row.token);
      } else {
        console.warn("apns update", result.status, result.reason);
      }
    }
    return;
  }

  // No running activity: start one remotely (iOS 17.2+ push-to-start),
  // at most once per 10 minutes, only when a scrolling session begins.
  if (!live.sessionStarted || !live.armed) return;
  const { data: startTokens } = await admin
    .from("live_activity_tokens")
    .select("token, apns_env, last_push_at")
    .eq("user_id", userId)
    .eq("kind", "start");
  for (const row of startTokens ?? []) {
    const last = row.last_push_at ? Date.parse(row.last_push_at) / 1000 : 0;
    if (now - last < 600) continue;
    const result = await sendLiveActivityPush(row.token, row.apns_env, {
      aps: {
        timestamp: now,
        event: "start",
        "content-state": contentState,
        "attributes-type": "DoomActivityAttributes",
        attributes: { sessionStartEpoch: now },
        "stale-date": now + 1800,
        alert: { title: "counting your reels 👀", body: `${live.todayCount} today · ${live.appName}` },
      },
    }, 10);
    if (isDeadToken(result)) {
      await admin.from("live_activity_tokens").delete().eq("token", row.token);
    } else if (result.status === 200) {
      await admin.from("live_activity_tokens").update({ last_push_at: new Date().toISOString() }).eq("token", row.token);
    }
  }
}
