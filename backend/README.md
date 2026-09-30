# Doomscore backend (your own Supabase project)

Everything here is new and yours — nothing talks to BrainPal's servers.

## 1. Create the project

1. Create a project at supabase.com (pick a region near your users, e.g. Mumbai).
2. Install the CLI (`brew install supabase/tap/supabase`) and log in.
3. From `backend/`:

```bash
supabase link --project-ref YOUR_PROJECT_REF
```

```bash
supabase db push
```

## 2. Auth

Dashboard → Authentication → Sign In / Providers:

* **Apple**: enable, add your app's bundle ID (`com.yourcompany.doomscore`) as a
  client ID (native Sign in with Apple uses the ID token; no service ID/secret needed
  for iOS-only).
* **Anonymous sign-ins**: enable (powers "quick start"). Consider enabling captcha later.

## 3. Edge Functions

```bash
supabase secrets set APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=ABCDE12345 APNS_BUNDLE_ID=com.yourcompany.doomscore
```

```bash
supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
```

```bash
supabase functions deploy ingest --no-verify-jwt
```

```bash
supabase functions deploy activity --no-verify-jwt
```

(`--no-verify-jwt` because these functions authenticate the scoped device token
themselves — see `config.toml`.)

APNs key: developer.apple.com → Keys → + → Apple Push Notifications service.

## 4. Point the app at it

`Config/Secrets.xcconfig`:

```
DS_SUPABASE_URL = https:/$()/YOUR_PROJECT_REF.supabase.co
DS_SUPABASE_ANON_KEY = <anon or publishable key>
```

## 5. What's inside

* `migrations/…_doomscore_init.sql` — tables, RLS, RPCs (`get_leaderboard`,
  `create_invite`, `accept_invite`, `remove_friend`, `register_device`,
  `delete_account`), server-only `ingest_stats` + `device_user`.
* `functions/ingest` — validates totals, stores them, mirrors the count to the user's
  Live Activity via APNs (update or push-to-start).
* `functions/activity` — registers/removes Live Activity push tokens.

## 6. Invite links (optional)

Host `web/` on your domain (Vercel/Netlify/Cloudflare Pages):

* `/.well-known/apple-app-site-association` — replace `ABCDE12345.com.yourcompany.doomscore`
  with your Team ID + bundle ID; serve as `application/json`, no redirect.
* `/i/*` → `web/i/index.html` (rewrite rule), set your App Store ID.

Set `DS_ASSOCIATED_DOMAIN` / `DS_INVITE_BASE_URL` in the xcconfig. Without a domain the
app falls back to `doomscore://invite/CODE` links.

## Costs

Free tier comfortably covers early users: ingest is ~1 small request per 4 s per active
scroller, leaderboard reads every 30 s while the battle tab is open.
