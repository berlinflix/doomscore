# Doomscore backend (your own Supabase project)

Everything here is new and yours — nothing talks to BrainPal's servers.

**Live project:** `doomscore` · ref `aybvdsufopdgyegdinpx` · region Mumbai (ap-south-1) ·
`https://aybvdsufopdgyegdinpx.supabase.co`. The migration, auth providers, both Edge Functions
and the APNs secrets (except `APNS_PRIVATE_KEY`) are already applied. The steps below are for
rebuilding it or setting up another environment.

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

* **Apple**: enable, add the app's bundle ID (`com.gridcc.doomscore`) as a
  client ID (native Sign in with Apple uses the ID token; no service ID/secret needed
  for iOS-only).
* **Anonymous sign-ins**: enable (powers "quick start"). Consider enabling captcha later.

## 3. Edge Functions

Each function is a single self-contained `index.ts`, so you can deploy it with the CLI or paste it
into the Supabase dashboard (Edge Functions → Deploy a new function → Via Editor, with
"Verify JWT" turned off).

```bash
supabase secrets set APNS_KEY_ID=ZL4A5C2JP8 APNS_TEAM_ID=5862BR3S2S APNS_BUNDLE_ID=com.gridcc.doomscore
```

```bash
supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_ZL4A5C2JP8.p8)"
```

```bash
supabase functions deploy ingest --no-verify-jwt
```

```bash
supabase functions deploy activity --no-verify-jwt
```

(`--no-verify-jwt` because these functions authenticate the scoped device token
themselves — see `config.toml`.)

APNs key: the team already has a team-scoped key, **Gridcc FCM APNs Key** (`ZL4A5C2JP8`,
Sandbox & Production). It works for every app in the team, so reuse its .p8 if you still
have it. Otherwise create a new one: developer.apple.com → Keys → + → Apple Push Notifications
service, and use its Key ID above.

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

## 6. Invite links + privacy page (doomscore.gridcc.tech)

`web/` is a static site: invite landing page (`/i/CODE`, plus `404.html` for GitHub Pages),
`apple-app-site-association` (set to `5862BR3S2S.com.gridcc.doomscore`), a home page and
`/privacy/`. It's published with GitHub Pages from `berlinflix/doomscore-site`; see
[docs/SETUP_MAC.md](../docs/SETUP_MAC.md) step 7.

## Costs

Free tier comfortably covers early users: ingest is ~1 small request per 4 s per active
scroller, leaderboard reads every 30 s while the battle tab is open.
