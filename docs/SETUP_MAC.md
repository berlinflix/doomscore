# Run Doomscore on your Mac + iPhone

## Already done for you

- **Apple Developer portal** (team `5862BR3S2S`). Your GridCC identifiers weren't touched.
  - App Group `group.com.gridcc.doomscore`.
  - App ID `com.gridcc.doomscore` with App Groups, Associated Domains, Push Notifications,
    Sign In with Apple and Time Sensitive Notifications.
  - App IDs `com.gridcc.doomscore.widgets` and `com.gridcc.doomscore.broadcast`, with App Groups.
  - All three App IDs are linked to the App Group.
- **`Config/Base.xcconfig`** already holds the Team ID, bundle IDs, App Group and the
  `doomscore.gridcc.tech` domain. There's nothing to edit before your first build.

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
   Screen broadcasts don't run in the Simulator, so use the phone.
2. If you get a signing error, open each target (Doomscore, DoomscoreWidgets,
   DoomscoreBroadcast) → Signing & Capabilities → check the Team is "Suyash Singh" → **Try Again**.
3. If the build fails in `App/Intents/ForegroundContinuation.swift`:
   - Create `Config/Secrets.xcconfig` containing `DS_SWIFT_FLAGS =`.
   - Run `xcodegen generate` again.
   - The app then uses a notification instead of opening by itself.
4. For any other build error, paste it to Claude.

## 5. Try it

1. Onboarding → set your daily cap → allow notifications.
2. **Arm the counter** → Doomscore appears in the system sheet → **Start Broadcast**. A red pill shows up.
3. Instagram → Reels → scroll about 10 reels → back to Doomscore. The count should match.
4. iPhone Settings → Doomscore → Live Activities On → **More Frequent Updates** On.
5. Widgets: long-press the Home Screen → Edit → Add Widget → Doomscore.
   Control Center: swipe down → **+** → Add a Control → **Count Reels**.
6. If counts look off: Settings (gear) → advanced → detector diagnostics → open detector lab.

## 6. Auto-start when Instagram opens

1. Open Doomscore once first, so its actions show up in Shortcuts.
2. Shortcuts → **Automation** → **+** → **App** → pick **Instagram**, keep **Is Opened** →
   **Run Immediately** → turn off **Notify When Run** → Next.
3. **New Blank Automation** → Add Action → search **Doomscore** → **Reels App Opened** → App = Instagram → Done.
4. Optional: add a second automation with **Is Closed** → **Reels App Closed**.
5. Repeat for YouTube or TikTok if you want them counted.

## 7. Website: doomscore.gridcc.tech (invite links + privacy policy)

1. On [vercel.com](https://vercel.com), go to Add New → Project and import `berlinflix/doomscore`.
   - Set **Root Directory** to `web` and **Framework Preset** to *Other*, then Deploy.
2. Project → Settings → **Domains** → add `doomscore.gridcc.tech`.
   Vercel shows you a DNS record, usually **CNAME** `doomscore` → `cname.vercel-dns.com`.
3. Add that record wherever `gridcc.tech`'s DNS is managed. It only adds a subdomain; your
   other app's records stay as they are.
4. In `web/privacy/index.html`, replace `YOUR-CONTACT-EMAIL` with your email, then commit and push.
   Vercel redeploys by itself.
5. Check it: `https://doomscore.gridcc.tech/.well-known/apple-app-site-association` should show JSON,
   and `https://doomscore.gridcc.tech/privacy` should show the policy.

Netlify or Cloudflare Pages work too; `web/_redirects` and `web/_headers` are included for them.

## 8. Backend (battles + live Dynamic Island), optional

The full guide is [backend/README.md](../backend/README.md). The values you'll need:

| Setting | Value |
|---|---|
| Supabase → Auth → Apple → Client IDs | `com.gridcc.doomscore` |
| `APNS_TEAM_ID` | `5862BR3S2S` |
| `APNS_BUNDLE_ID` | `com.gridcc.doomscore` |
| `APNS_KEY_ID` + `.p8` | Reuse **Gridcc FCM APNs Key** `ZL4A5C2JP8` if you still have its .p8 file (it's team-wide). If you don't, create a new APNs key under Keys. |

After it's set up, put `DS_SUPABASE_URL` and `DS_SUPABASE_ANON_KEY` in `Config/Secrets.xcconfig`
and run `xcodegen generate`.

## 9. Debugging and tests

- **Reel detector:** pick the **DoomscoreBroadcast** scheme → Run → choose Doomscore → start a broadcast.
  Logs are in Console.app (subsystem `app.doomscore`).
- **Unit tests:** pick any iPhone Simulator → **⌘U**.

## 10. TestFlight / App Store (later)

1. App Store Connect → Apps → **+** → New App → iOS, bundle ID `com.gridcc.doomscore`,
   SKU `doomscore`. The name has to be unique on the App Store.
2. Xcode → Product → **Archive** → Distribute App → App Store Connect → Upload → add testers in TestFlight.
3. Before review, add the privacy policy URL `https://doomscore.gridcc.tech/privacy`, fill in the
   privacy labels, and attach a demo video. See [APP_REVIEW.md](APP_REVIEW.md).

## Troubleshooting

| Problem | Fix |
|---|---|
| "No Account for Team" | Xcode → Settings → Accounts → sign in, then pick the team in each target |
| Profile missing an entitlement | Developer portal → Identifiers → the App ID → enable that capability → Xcode **Try Again** |
| Doomscore missing from the Start Broadcast sheet | Fix DoomscoreBroadcast signing, delete the app from the phone, run again |
| Count stays at 0 | Detector lab; also Settings → "count these apps" |
| Doomscore actions missing in Shortcuts | Open the app once, then force-quit and reopen Shortcuts |
| Invite links open Safari instead of the app | Check the AASA URL from step 7 loads, then reinstall the app (iOS fetches the file at install time) |
