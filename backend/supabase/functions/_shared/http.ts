// Shared helpers for Doomscore Edge Functions (Deno / Supabase Edge Runtime).
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export const admin: SupabaseClient = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Reads a JSON body with a hard size cap. */
export async function readJson(req: Request, maxBytes = 8192): Promise<unknown | Response> {
  const raw = await req.text();
  if (raw.length > maxBytes) return json({ error: "payload_too_large" }, 413);
  try {
    return JSON.parse(raw);
  } catch {
    return json({ error: "bad_json" }, 400);
  }
}

export interface DeviceAuth {
  userId: string;
  tokenHash: string;
}

/**
 * Authenticates the scoped device token sent by the app / broadcast
 * extension (header `x-device-token`, 64 hex chars). Only the SHA-256 hash is
 * ever compared or stored.
 */
export async function authenticateDevice(req: Request): Promise<DeviceAuth | Response> {
  const token = req.headers.get("x-device-token") ?? "";
  if (!/^[0-9a-f]{64}$/.test(token)) return json({ error: "unauthorized" }, 401);
  const tokenHash = await sha256Hex(token);
  const { data, error } = await admin.rpc("device_user", { p_token_hash: tokenHash });
  if (error) {
    console.error("device_user failed", error.message);
    return json({ error: "server_error" }, 500);
  }
  if (!data) return json({ error: "unauthorized" }, 401);
  return { userId: data as string, tokenHash };
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function isInt(value: unknown, min: number, max: number): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= min && value <= max;
}

// deno-lint-ignore no-explicit-any
declare const EdgeRuntime: { waitUntil(promise: Promise<any>): void } | undefined;

/** Runs work after the response is sent when the runtime supports it. */
export function background(promise: Promise<unknown>): Promise<unknown> | void {
  if (typeof EdgeRuntime !== "undefined" && EdgeRuntime?.waitUntil) {
    EdgeRuntime.waitUntil(promise);
    return;
  }
  return promise;
}
