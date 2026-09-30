# Run Doomscore on your Mac + iPhone

Replace `yourname` below with something unique to you, for example `com.suyash.doomscore`.

## 0. What you need

- A Mac on a macOS version that runs the latest Xcode (Xcode 26 or newer).
- An iPhone on iOS 18 or newer, plus a cable. Screen-broadcast extensions don't run in the Simulator.
- Your paid Apple Developer Program account.

## 1. Install the tools on the Mac

1. Install **Xcode** from the Mac App Store. Open it once and let it install the iOS platform.
2. Sign in to your developer account: Xcode → Settings → Accounts → **+** → Apple Account.
3. Install [Homebrew](https://brew.sh), then install XcodeGen:

```bash
brew install xcodegen
```

## 2. Get the code

```bash
git clone https://github.com/berlinflix/doomscore.git
```

```bash
cd doomscore
```

## 3. Find your Team ID and pick your IDs

- **Team ID**: developer.apple.com/account → Membership details (10 characters).
- **Bundle ID**: `com.yourname.doomscore`. It has to be unique across the App Store.
- **App Group**: `group.com.yourname.doomscore`.

## 4. Set up the Apple Developer portal

All of this lives at developer.apple.com/account → **Certificates, IDs & Profiles**.

1. **App Group.** Identifiers → **+** → App Groups → Continue.
   - Description `Doomscore`, identifier `group.com.yourname.doomscore` → Register.
2. **App ID for the app.** Identifiers → **+** → App IDs → App → Continue.
   - Description `Doomscore`, Explicit Bundle ID `com.yourname.doomscore`.
   - Tick these capabilities:
     - **App Groups**
     - **Associated Domains**
     - **Push Notifications**
     - **Sign In with Apple** (keep "Enable as a primary App ID")
     - **Time Sensitive Notifications**
   - Continue → Register.
   - Open the new App ID → App Groups → **Configure** → tick your group → Continue → Save.
3. **App ID for the widgets.** Same steps with bundle ID `com.yourname.doomscore.widgets`.
   - Capability: **App Groups**, configured with the same group.
4. **App ID for the reel detector.** Same steps with bundle ID `com.yourname.doomscore.broadcast`.
   - Capability: **App Groups**, configured with the same group.
5. **APNs key** (only needed for the live Dynamic Island counter with a backend).
   - Keys → **+** → name `Doomscore APNs` → tick **Apple Push Notifications service (APNs)**.
   - If asked, pick environment "Sandbox & Production" and "Team Scoped".
   - Continue → Register → **Download the .p8 file** (you can only download it once) and note the **Key ID**.
   - Never put the .p8 in the repo.

You don't need to create certificates, profiles or devices. Xcode's automatic signing handles them when you run on your iPhone.

## 5. Configure the project

1. Create your private config file:

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

2. Open `Config/Secrets.xcconfig` and set `DS_TEAM_ID`, `DS_APP_BUNDLE_ID` and `DS_APP_GROUP_ID`.
   - Leave the Supabase lines commented out for now. The app runs in local-only mode.
3. Generate the Xcode project and open it:

```bash
xcodegen generate
```

```bash
open Doomscore.xcodeproj
```

> Rule of thumb: don't edit the generated Info.plist or .entitlements files, and don't add capabilities in Xcode's UI.
> Change `project.yml` or the xcconfig instead, then run `xcodegen generate` again.

## 6. Prepare the iPhone

1. Plug it in and tap **Trust This Computer**.
2. Settings → Privacy & Security → **Developer Mode** → On → Restart → Turn On.
   - The switch only appears after Xcode has seen the phone once.

## 7. Build and run

1. In Xcode's toolbar, pick the **Doomscore** scheme and your iPhone, then press **⌘R**.
2. If you get a signing error, open each target (Doomscore, DoomscoreWidgets, DoomscoreBroadcast) → Signing & Capabilities.
   - Check the Team is yours → **Try Again**.
3. If the build fails in `App/Intents/ForegroundContinuation.swift`:
   - Add `DS_SWIFT_FLAGS =` to `Config/Secrets.xcconfig`.
   - Run `xcodegen generate` and build again.
   - The app then uses a notification instead of auto-opening.

## 8. Try it

1. Go through onboarding: set your daily cap and allow notifications.
2. Tap **arm the counter**. The system sheet shows Doomscore → **Start Broadcast**. A red pill appears at the top.
3. Open Instagram → Reels → scroll about 10 reels → switch back to Doomscore. The count should match.
4. To watch the detector's decisions live: Settings (gear) → advanced → **detector diagnostics** → open detector lab.
5. iPhone Settings → Doomscore → **Live Activities** On, plus **More Frequent Updates**.
6. Home Screen widgets: long-press the Home Screen → Edit → Add Widget → Doomscore.
7. Control Center button: swipe down → **+** → Add a Control → Doomscore **Count Reels**.

## 9. Auto-start when Instagram opens (Shortcuts)

1. Open Doomscore once first, so its actions show up in Shortcuts.
2. Shortcuts → **Automation** → **+** → **App**.
   - Choose **Instagram**, keep **Is Opened** ticked.
   - Pick **Run Immediately** and turn off **Notify When Run** → Next.
3. **New Blank Automation** → Add Action → search **Doomscore** → **Reels App Opened**.
   - Set App = Instagram → Done.
4. Optional: make a second automation with **Is Closed** → **Reels App Closed**.
5. Repeat for YouTube or TikTok if you want them counted too.

What happens next time you open Instagram with the counter off:
- **iOS 26:** the arm screen opens by itself. One tap, and you're back in Instagram.
- **iOS 18–25:** you get a "counter's off 👀" notification. Tap it to arm.

## 10. Backend (battles + live Dynamic Island), optional

Full details are in [backend/README.md](../backend/README.md). Short version:

1. On supabase.com, create a new project (region: Mumbai). Note the project ref, database password, URL and anon key.
2. Install the Supabase CLI:

```bash
brew install supabase/tap/supabase
```

```bash
supabase login
```

3. From the `backend` folder, link the project and create the database tables and security rules:

```bash
cd backend
```

```bash
supabase link --project-ref YOUR_PROJECT_REF
```

```bash
supabase db push
```

4. In the Supabase dashboard → Authentication → Sign In / Providers:
   - Turn on **Apple** and set Client IDs = `com.yourname.doomscore`.
   - Turn on **Allow anonymous sign-ins**.
5. Store your APNs key details as secrets:

```bash
supabase secrets set APNS_KEY_ID=YOUR_KEY_ID APNS_TEAM_ID=YOUR_TEAM_ID APNS_BUNDLE_ID=com.yourname.doomscore
```

```bash
supabase secrets set APNS_PRIVATE_KEY="$(cat ~/Downloads/AuthKey_YOUR_KEY_ID.p8)"
```

6. Deploy the two server functions:

```bash
supabase functions deploy ingest --no-verify-jwt
```

```bash
supabase functions deploy activity --no-verify-jwt
```

7. In `Config/Secrets.xcconfig`, uncomment `DS_SUPABASE_URL` and `DS_SUPABASE_ANON_KEY` and put in your values.
8. Run `xcodegen generate`, then run the app → Battle tab → join.

## 11. Debugging and tests

- **Reel detector:** pick the **DoomscoreBroadcast** scheme → Run → choose Doomscore when asked → start a broadcast from the app.
  - Xcode attaches to the extension.
  - Logs show up in Console.app (subsystem `app.doomscore`).
- **Unit tests:** pick any iPhone Simulator → **⌘U**.

## 12. TestFlight / App Store (later)

1. App Store Connect → Apps → **+** → New App.
   - Platform iOS, your app name, bundle ID `com.yourname.doomscore`, SKU `doomscore`.
2. In Xcode: Product → **Archive** → Distribute App → App Store Connect → Upload.
3. In the TestFlight tab, add testers.
4. Before submitting for review, add a privacy policy URL, the privacy labels and a demo video. See [APP_REVIEW.md](APP_REVIEW.md).

## Troubleshooting

| Problem | Fix |
|---|---|
| "No Account for Team" / no signing certificate | Xcode → Settings → Accounts → sign in, then pick your Team in each target |
| Profile doesn't include App Groups / Sign In with Apple / Push / Time Sensitive | Enable that capability on the App ID (step 4) → Xcode → **Try Again** |
| "Failed to register bundle identifier" | The ID is taken: change `DS_APP_BUNDLE_ID`, update the portal, run `xcodegen generate` |
| Doomscore missing from the Start Broadcast sheet | The broadcast extension didn't install: fix DoomscoreBroadcast signing, delete the app, run again |
| Count stays at 0 | Open the Detector lab; check the app is ticked under Settings → count these apps |
| Doomscore actions missing in Shortcuts | Open the app once, then force-quit and reopen Shortcuts |
