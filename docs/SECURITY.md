# Security & privacy model

## Threats and controls

| Threat | Control |
|---|---|
| Screen content leaking (DMs, banking…) | Frames never retained/written/uploaded; OCR text lives in memory only; no logging of text (`Log` only emits counters). Reel identities persisted only as salted, truncated SHA-256, reset daily. Optional strict mode. |
| Stolen user session | Supabase session in the **app-private** Keychain (`AfterFirstUnlockThisDeviceOnly`, not synced). Single-flight refresh avoids refresh-token reuse. |
| Extension needing credentials | Separate **scoped device token** (256-bit random, shared Keychain group). Server stores only its SHA-256; it can only write the owner's counts and Live Activity tokens; max 5 active per user; revocable; deleted on sign-out/account deletion. |
| Reading other users' data | Postgres **Row-Level Security** on every table: profiles/stats readable by self + friends only; friendships/invites only your own; device/push/rate tables have no client access. Table privileges revoked from `anon`, minimal grants to `authenticated`. |
| Writing fake stats directly | No client write access to `daily_stats`. Only `ingest_stats` (service role) writes, after validation. |
| Leaderboard cheating | Totals are monotonic; growth capped at ~1 reel / 1.2 s since last update (+ burst); first upload capped by time elapsed that day; day window ±2 days; per-device 1.5 s rate limit; clamped rows flagged and hidden from friends. |
| Invite code guessing / spam | 10-char codes from a 31-symbol alphabet (~49 bits); accept limited to 30/hour/user; create 30/day; codes expire (14 days, 25 uses); can't friend yourself; 200-friend cap. |
| Injection | All SQL in parameterised functions with `search_path = ''`; Edge Functions validate every field (types, ranges, sizes ≤ 8 KB). |
| Push token abuse | Tokens validated (hex), capped per user, dead tokens pruned on APNs 410/BadDeviceToken. APNs key only in Edge Function secrets. |
| Man-in-the-middle | HTTPS only (ATS defaults, no exceptions). |
| Account deletion (App Store 5.1.1(v)) | `delete_account()` removes the auth user → cascades to all rows. Local data reset in Settings. CSV export available. |

## Optional hardening (phase 2)

* **App Attest** (DeviceCheck) for `register_device`: attest the key, bind the device
  token to it, require assertions on registration. Raises the bar against scripted
  cheating; not needed for privacy.
* **Captcha** (Supabase hCaptcha/Turnstile) on anonymous sign-ups if abused.
* Certificate pinning for `*.supabase.co` (trade-off: key rotation risk).
* Short JWT expiry (default 1 h is fine — the extension never uses JWTs).

## Secrets checklist

* `Config/Secrets.xcconfig` (git-ignored): team ID, Supabase URL + anon/publishable key
  (public by design — RLS protects data).
* Supabase function secrets: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`,
  `APNS_BUNDLE_ID`. Never commit the `.p8`.
* Service role key: only inside Supabase (auto-provided to Edge Functions).
