<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="128" alt="Doomscore app icon">
</p>

# Doomscore 🫠 — how cooked are you today?

An iOS reel counter with Gen-Z energy. It counts every reel you swipe on Instagram, YouTube
Shorts, TikTok and Snapchat Spotlight, skips ads and rewatches, shows your count live in the
Dynamic Island, and lets you battle friends over who's the most cooked.

## Features

| | |
|---|---|
| 🔢 **Live reel counter** | Counts paged swipes in Reels / Shorts / TikTok / Spotlight |
| 🥷 **No ads, no rewatches** | Skips "Sponsored" and CTA reels, back-swipes and already-seen reels, loops and resumes |
| ⚡️ **Auto-start** | A Shortcuts automation fires when Instagram opens. No need to open Doomscore first |
| 🏝️ **Dynamic Island / Lock Screen** | Live Activity counter (the iOS version of the floating bubble) |
| 🧩 **Widgets** | Small, medium and lock screen counters, a battle widget, and a Control Center "Count Reels" button |
| ⚔️ **Scroll Battle** | Friends leaderboard (today / week), "most cooked" or "touch grass" modes, invite links |
| 🧊 **Chill streaks** | Days in a row at or under your daily cap, plus your best streak |
| 📼 **Wrapped** | Story-style weekly, monthly and yearly recap: totals, time, meters scrolled, doom hour, wildest day, personality archetype, shareable card |
| 📊 **Progress** | Day, week, month and year charts, per-app split, averages, highest day |
| 🔒 **Private by design** | On-device detection. Only daily numbers ever sync |

## How it works (short version)

Android reel counters read Instagram's view tree with an Accessibility Service and draw an
overlay (see [docs/ANDROID_TEARDOWN.md](docs/ANDROID_TEARDOWN.md)). iOS allows neither, so
Doomscore uses:

1. **Broadcast Upload Extension (ReplayKit).** The only sanctioned way to "see" other apps.
   Frames are shrunk to motion thumbnails and read with on-device OCR, then thrown away.
2. **Shortcuts automation + App Intents.** "When Instagram is opened → Reels App Opened"
   runs silently. It starts the Dynamic Island counter and, if the counter is off, brings up
   a one-tap arm screen (iOS 26+) or sends a nudge (iOS 18–25).
3. **Live Activity via your backend.** Extensions can't update Live Activities, so counts go
   to your Supabase `ingest` function, which pushes updates through APNs.

The full design is in [docs/IOS_ARCHITECTURE.md](docs/IOS_ARCHITECTURE.md).

> iOS limit, stated honestly: starting a screen broadcast always needs **one tap** from the
> user in the system sheet. After that, counting is automatic until you stop it or iOS ends the broadcast (usually when the phone locks).

## Repo layout

```
project.yml                XcodeGen spec (4 targets)
Config/                    Base.xcconfig (+ your Secrets.xcconfig)
App/                       SwiftUI app: screens, services, App Intents, assets
Broadcast/                 Broadcast Upload Extension: frame sampling, Vision OCR, recorder
Detection/                 Pure counting logic: motion, classifier, engine (unit tested)
Widgets/                   WidgetKit widgets, Live Activity UI, Control Center control
Shared/Core                Models, App Group store, stats/streaks, sync client (all targets)
Shared/UI                  Theme, Goob mascot, Live Activity attributes (app + widgets)
Tests/                     XCTest: engine, motion, classifier, stats
backend/                   Supabase: SQL (RLS, RPCs, anti-cheat), Edge Functions (ingest, APNs)
web/                       Invite landing page + apple-app-site-association
docs/                      Teardown, architecture, security, App Review, detector tuning
```

## Build it (on a Mac)

The full walk-through, including the Apple Developer portal setup, is in
**[docs/SETUP_MAC.md](docs/SETUP_MAC.md)**. The short version:

1. In the Apple Developer portal, register the App Group and three App IDs (app, `.widgets`,
   `.broadcast`) with the capabilities listed in the guide.
2. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and set your Team ID,
   bundle ID and App Group.
3. Install XcodeGen, generate the project and open it:

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open Doomscore.xcodeproj
```

4. Run on a real iPhone (ReplayKit broadcasts don't run in the Simulator), arm the counter
   and scroll some reels.
5. Set up the Shortcuts automation so opening Instagram starts things by itself.
6. Optional: set up the backend in [backend/README.md](backend/README.md) for battles and
   live Dynamic Island updates. Without it, the app runs in local-only mode.

Tests: pick an iPhone Simulator and press ⌘U.

## Before you ship

- Tune the detector on real devices with Settings → Detector lab
  ([docs/DETECTOR_TUNING.md](docs/DETECTOR_TUNING.md)).
- Host a privacy policy, fill in the privacy labels, and attach a demo video for review.
- Phase 2 ideas: Screen Time API estimates and blocking (needs Apple's FamilyControls
  entitlement), App Attest, a Core ML screen classifier, and a Pro tier.
