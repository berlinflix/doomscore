// Minimal APNs client for ActivityKit (Live Activity) pushes.
// Uses token-based auth (.p8 key) — set these secrets:
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (full .p8 contents), APNS_BUNDLE_ID

const KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
const BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "";

export const apnsConfigured = () => KEY_ID !== "" && TEAM_ID !== "" && PRIVATE_KEY !== "" && BUNDLE_ID !== "";

let cachedJwt: { token: string; issuedAt: number } | null = null;
let cachedKey: CryptoKey | null = null;

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  const binary = atob(body);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

/** ES256 provider token, cached for 50 minutes (Apple allows up to 60). */
async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.issuedAt < 50 * 60) return cachedJwt.token;
  if (!cachedKey) {
    cachedKey = await crypto.subtle.importKey(
      "pkcs8",
      pemToDer(PRIVATE_KEY),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
  }
  const encoder = new TextEncoder();
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: KEY_ID })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: TEAM_ID, iat: now })));
  const signingInput = `${header}.${claims}`;
  // WebCrypto returns the raw r||s (IEEE P1363) signature JWS expects.
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, cachedKey, encoder.encode(signingInput)),
  );
  const token = `${signingInput}.${base64url(signature)}`;
  cachedJwt = { token, issuedAt: now };
  return token;
}

export interface ApnsResult {
  status: number;
  reason?: string;
}

export async function sendLiveActivityPush(
  deviceToken: string,
  env: "sandbox" | "production",
  payload: Record<string, unknown>,
  priority: 5 | 10,
): Promise<ApnsResult> {
  const host = env === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken()}`,
      "apns-topic": `${BUNDLE_ID}.push-type.liveactivity`,
      "apns-push-type": "liveactivity",
      "apns-priority": String(priority),
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (response.status === 200) return { status: 200 };
  let reason: string | undefined;
  try {
    reason = (await response.json())?.reason;
  } catch {
    reason = undefined;
  }
  return { status: response.status, reason };
}

/** Tokens APNs says will never work again. */
export function isDeadToken(result: ApnsResult): boolean {
  return result.status === 410 || result.reason === "BadDeviceToken" || result.reason === "Unregistered" ||
    result.reason === "ExpiredToken";
}
