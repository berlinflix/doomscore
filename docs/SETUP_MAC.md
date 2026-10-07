# Run Doomscore on your Mac + iPhone

## Already done for you

- **Apple Developer portal** (team `5862BR3S2S`). Your GridCC identifiers weren't touched.
  - App Group `group.com.gridcc.doomscore`.
  - App ID `com.gridcc.doomscore` with App Groups, Associated Domains, Push Notifications,
    Sign In with Apple, Time Sensitive Notifications and Family Controls (Development).
  - App ID `com.gridcc.doomscore.activitymonitor` ("Doomscore Screen Time") with App Groups
    and Family Controls (Development).
  - App IDs `com.gridcc.doomscore.widgets` and `com.gridcc.doomscore.broadcast`, with App Groups.
  - All four App IDs are linked to the App Group.
- **`Config/Base.xcconfig`** already holds the Team ID, bundle IDs, App Group and the
  `doomscore.gridcc.tech` domain. There's nothing to edit before your first build.

Adding Family Controls invalidated the old development profiles; Xcode's automatic signing
makes new ones on the next ⌘R (press **Try Again** if it asks). TestFlight/App Store builds also
need Apple's distribution approval of Family Controls (see [APP_REVIEW.md](APP_REVIEW.md)).

## 1. Set up the Mac (once)

1. Install **Xcode** from the Mac App Store. Open it once and let it install the iOS platform.
2. Xcode → Settings → Accounts → **+** → sign in with the Apple ID that owns the developer account.
3. Install [Homebrew](https://brew.sh), then XcodeGen:

```bash
brew install xcodegen
```

## 2. Get the code and open it

```bash
git clone https://github.com/berlinflix/doomscore.git
```

```bash
cd doomscore
```

```bash
xcodegen generate
```

```bash
open Doomscore.xcodeproj
```

> Don't edit the generated Info.plist or .entitlements files, and don't add capabilities in
> Xcode's UI. Change `project.yml` or `Config/*.xcconfig`, then run `xcodegen generate` again.

## 3. Prepare the iPhone (iOS 18+)

1. Plug it into the Mac and tap **Trust This Computer**.
2. Settings → Privacy & Security → **Developer Mode** → On → Restart → Turn On.
   The switch only appears after Xcode has seen the phone once.

## 4. Run

1. In Xcode's toolbar, pick the **Doomscore** scheme and your iPhone, then press **⌘R**.
   Screen Time and screen broadcasts don't run in the Simulator, so use the phone.
2. If you get a signing error, open each target (Doomscore, DoomscoreWidgets,
   DoomscoreBroadcast, DoomscoreActivityMonitor) → Signing & Capabilities → check the Team is
   "Suyash Singh" → **Try Again**.
3. If the build fails in `App/Intents/ForegroundContinuation.swift`:
   - Create `Config/Secrets.xcconfig` containing `DS_SWIFT_FLAGS =`.
   - Run `xcodegen generate` again.
   - The app then uses a notification instead of opening by itself.
4. For any other build error, paste it to Claude.

## 5. Try it

1. Onboarding → **connect Screen Time** (Face ID) → pick **Instagram** in the picker →
   pick your scroll style → set your daily cap → allow notifications.
2. iPhone Settings → Doomscore → Live Activities On → **More Frequent Updates** On.
3. Scroll Instagram for 2–3 minutes. Each minute, the count in Doomscore, the widget and the
   Dynamic Island goes up (≈ = estimate). The island appears after the first minute; it
   needs a battle profile (device token) for live updates.
4. Widgets: long-press the Home Screen → Edit → Add Widget → Doomscore.
   Control Center: swipe down → **+** → Add a Control → **Count Reels** (precise mode).
5. Optional **precise mode** (exact count, skips ads + rewatches): Home → precise mode →
   **Start Broadcast**. A red pill shows up. Each session also teaches auto mode your pace.
6. If precise counts look off: Settings (gear) → advanced → detector diagnostics → open detector lab.

## 6. Optional: instant island when Instagram opens

Auto mode already counts without this. The automation makes the Dynamic Island appear the
second you open Instagram (instead of after a minute) and close when you leave.

1. Open Doomscore once first, so its actions show up in Shortcuts.
2. Shortcuts → **Automation** → **+** → **App** → pick **Instagram**, keep **Is Opened** →
   **Run Immediately** → turn off **Notify When Run** → Next.
3. **New Blank Automation** → Add Action → search **Doomscore** → **Reels App Opened** → App = Instagram → Done.
4. Recommended: a second automation with **Is Closed** → **Reels App Closed**.
5. Repeat for TikTok if you track it.

## 7. Website: doomscore.gridcc.tech (invite links + privacy policy)

Hosted on **GitHub Pages** from the public repo `berlinflix/doomscore-site`, which holds only the
contents of `web/`. Your app code stays private.

- DNS (Namecheap → gridcc.tech → Advanced DNS): `CNAME` record, host `doomscore`, value `berlinflix.github.io.`
  Your GitHub Pages records for `gridcc.tech` itself are untouched.
- To update the site after editing `web/` in this repo:

```bash
git subtree split --prefix web -b site-deploy
```

```bash
git push --force https://github.com/berlinflix/doomscore-site.git site-deploy:main
```

- Check it: `https://doomscore.gridcc.tech/.well-known/apple-app-site-association` should show JSON,
  and `https://doomscore.gridcc.tech/privacy/` should show the policy. HTTPS is enforced.
- On a network that blocks `.tech` sites (e.g. college Wi-Fi), check Apple's copy instead:
  `https://app-site-association.cdn-apple.com/a/v1/doomscore.gridcc.tech`. If it shows the same JSON,
  Apple can reach your site and invite links will open the app.

## 8. Backend (battles + live Dynamic Island) — already live

Supabase project **doomscore** (`aybvdsufopdgyegdinpx`, Mumbai) is set up:

- Database: tables, Row-Level Security, invites, leaderboard and anti-cheat functions.
- Auth: Sign in with Apple (client `com.gridcc.doomscore`, users without email allowed) and anonymous sign-ins.
- Edge Functions `ingest` and `activity`, with "Verify JWT" off because they check the app's device token themselves.
- Secrets `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_KEY_ID` (`VD2P5T3639`, the dedicated "Doomscore APNs" key) and `APNS_PRIVATE_KEY`.
- `Config/Base.xcconfig` already points at it.

Live Dynamic Island updates are fully configured. Keep the downloaded `AuthKey_VD2P5T3639.p8` safe
and never commit it. If you ever lose it, create a new APNs key and replace both `APNS_KEY_ID` and
`APNS_PRIVATE_KEY` in Supabase → Edge Functions → Secrets.

## 9. Debugging and tests

- **Screen Time monitor:** pick the **DoomscoreActivityMonitor** scheme → Run → choose Doomscore,
  then use Instagram. Logs are in Console.app (subsystem `app.doomscore`, category `screen-time`).
- **Reel detector (precise mode):** pick the **DoomscoreBroadcast** scheme → Run → choose Doomscore →
  start a broadcast. Logs are in Console.app (subsystem `app.doomscore`).
- **Unit tests:** pick any iPhone Simulator → **⌘U**.

## 10. TestFlight / App Store (later)

1. App Store Connect → Apps → **+** → New App → iOS, bundle ID `com.gridcc.doomscore`,
   SKU `doomscore`. The name has to be unique on the App Store.
2. Xcode → Product → **Archive** → Distribute App → App Store Connect → Upload → add testers in TestFlight.
3. Before review, add the privacy policy URL `https://doomscore.gridcc.tech/privacy/`, fill in the
   privacy labels, and attach a demo video. See [APP_REVIEW.md](APP_REVIEW.md).

## Troubleshooting

| Problem | Fix |
|---|---|
| "No Account for Team" | Xcode → Settings → Accounts → sign in, then pick the team in each target |
| Profile missing an entitlement | Developer portal → Identifiers → the App ID → enable that capability → Xcode **Try Again** |
| Doomscore missing from the Start Broadcast sheet | Fix DoomscoreBroadcast signing, delete the app from the phone, run again |
| Count stays at 0 (auto mode) | Settings → auto mode: Screen Time connected, Instagram picked, "track automatically" on. Use Instagram for a full minute |
| Count stays at 0 (precise mode) | Detector lab; also Settings → "precise mode counts these apps" |
| Dynamic Island doesn't update by itself | Join battles once (creates the device token), and turn on More Frequent Updates |
| Doomscore actions missing in Shortcuts | Open the app once, then force-quit and reopen Shortcuts |
| Invite links open Safari instead of the app | Check Apple's CDN URL from step 7 shows the JSON, then reinstall the app (iOS fetches the file at install time) |
