# App Store submission notes

## Capabilities (already registered on team 5862BR3S2S)

* App ID `com.gridcc.doomscore`: App Groups, Sign In with Apple, Push Notifications,
  Associated Domains, Time Sensitive Notifications (+ In-App Purchase, on by default).
* `com.gridcc.doomscore.widgets` and `com.gridcc.doomscore.broadcast`: App Groups.
* App Group `group.com.gridcc.doomscore`, linked to all three.
* APNs: the team-scoped "Gridcc FCM APNs Key" (`ZL4A5C2JP8`) also works for Doomscore.
* Privacy policy URL: `https://doomscore.gridcc.tech/privacy`.

## Review notes (paste into App Store Connect)

> Doomscore helps people understand how many short videos they scroll. It uses a
> ReplayKit Broadcast Upload Extension that the user starts explicitly (system
> "Start Broadcast" sheet; the red recording indicator is visible the whole time).
> Frames are analysed on-device only to detect vertical swipes and the "Sponsored"
> label; no video, image or text is stored or transmitted. Only daily totals sync,
> and only if the user joins the optional friends leaderboard. The Shortcuts
> automation is optional and set up by the user. Demo video attached.
> Test account: not required (quick start works without an account).

Attach a screen recording showing: onboarding → arm → Instagram reels → count rising →
widget/Live Activity → stop from the status pill.

## Guideline checklist

* **2.5.14** (recording user activity needs consent + indication) — explicit start,
  system indicator, onboarding disclosure. ✅
* **5.1.1** privacy — on-device processing, data minimisation, privacy policy link,
  account deletion in-app. ✅ (host a privacy policy and set its URL in App Store Connect)
* **5.1.2** — no tracking, no data sale. `PrivacyInfo.xcprivacy` declares User ID, Name,
  Other Usage Data (app functionality only). ✅
* **4.8** Sign in with Apple offered (and no other third-party login). ✅
* **5.2.1** trademarks — no Instagram/TikTok/YouTube logos in the icon, screenshots or UI;
  names used descriptively only. ✅ Keep metadata generic ("reels & shorts").
* **2.5.1** public APIs only — `RPSystemBroadcastPickerView` is triggered by sending
  actions to its button (widely used pattern); everything else is standard API.

## Realistic risks

* A reviewer may question "screen recording for a counter". The demo video + notes above
  address it; be ready to explain in Resolution Center.
* Detection quality varies with app UI changes — ship with remote config and the
  Detector lab so fixes don't need a new build.
