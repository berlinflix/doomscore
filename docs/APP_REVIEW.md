# App Store submission notes

## Capabilities (team 5862BR3S2S, all registered)

* App ID `com.gridcc.doomscore`: App Groups, Sign In with Apple, Push Notifications,
  Associated Domains, Time Sensitive Notifications, **Family Controls** (+ In-App Purchase, on by default).
* `com.gridcc.doomscore.activitymonitor` (Screen Time monitor): App Groups, **Family Controls**.
* `com.gridcc.doomscore.widgets` and `com.gridcc.doomscore.broadcast`: App Groups.
* App Group `group.com.gridcc.doomscore`, linked to all four.
* APNs: dedicated "Doomscore APNs" key `VD2P5T3639` (Sandbox & Production, team scoped).
* Privacy policy URL: `https://doomscore.gridcc.tech/privacy/`.

## Family Controls entitlement (needed before TestFlight / App Store)

Development builds can use Family Controls right away. Distribution builds need Apple's
approval of the **Family Controls (Distribution)** entitlement:

1. Account holder → https://developer.apple.com/contact/request/family-controls-distribution
2. Request it for **both** bundle IDs: `com.gridcc.doomscore` and `com.gridcc.doomscore.activitymonitor`.
3. Suggested description: *"Doomscore helps people see how much time they spend in short-video
   feeds. With the user's own authorization (individual, not parental), a DeviceActivity monitor
   extension receives threshold callbacks for the apps the user picks (e.g. Instagram) and shows
   minutes and an estimated number of short videos, plus daily-cap streaks. No app or web usage
   data leaves the device except optional daily totals for a friends leaderboard. No blocking,
   no tracking, no ads."*
4. After approval, the entitlement appears on the App IDs; regenerate the distribution profiles.

## Review notes (paste into App Store Connect)

> Doomscore helps people understand how much short-video scrolling they do.
> Default (auto) mode uses the Screen Time API with individual authorization: the user
> picks apps like Instagram, and a DeviceActivity monitor extension receives minute
> thresholds of use. Counts in this mode are estimates (shown with ≈); no screen content
> is accessed. Optional precise mode uses a ReplayKit Broadcast Upload Extension that the
> user starts explicitly (system "Start Broadcast" sheet; the red indicator is visible the
> whole time). Frames are analysed on-device only to detect swipes and the "Sponsored"
> label; no video, image or text is stored or transmitted. Only daily totals sync, and
> only if the user joins the optional friends leaderboard. Demo video attached.
> Test account: not required.

Attach a screen recording showing: onboarding → connect Screen Time → pick Instagram →
scroll → Dynamic Island count rising → widget. Then precise mode: start → count → stop
from the status pill.

## Guideline checklist

* **5.1.1 / 5.1.2** privacy — Screen Time data stays on device (only minutes for picked apps,
  as opaque tokens), data minimisation, privacy policy link, account deletion in-app. No
  tracking, no data sale. `PrivacyInfo.xcprivacy` declares User ID, Name, Other Usage Data
  (app functionality only). ✅
* **2.5.14** (recording user activity needs consent + indication) — precise mode only:
  explicit start, system indicator, onboarding disclosure. ✅
* **4.8** Sign in with Apple offered (and no other third-party login). ✅
* **5.2.1** trademarks — no Instagram/TikTok/YouTube logos in the icon, screenshots or UI;
  names used descriptively only. ✅ Keep metadata generic ("reels & shorts").
* **2.5.1** public APIs only — `RPSystemBroadcastPickerView` is triggered by sending
  actions to its button (widely used pattern); everything else is standard API.

## Realistic risks

* Family Controls approval can take days to weeks. Request it early.
* A reviewer may question "screen recording for a counter" in precise mode. It's optional,
  and the demo video and notes address it.
* Screen Time callbacks have known iOS bugs (late, duplicate or early thresholds). The
  estimator rejects impossible ones and re-arms monitoring; see `ScreenTimeEstimator`.
