<p align="center">
  <img src="App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="128" alt="Doomscore app icon">
</p>

# Doomscore 🫠 — how cooked are you today?

An iOS reel counter with Gen-Z energy. It tracks your Instagram and TikTok scrolling all day
in the background, with no screen recording, shows your count in the Dynamic Island, and lets
you battle friends over who's the most cooked. A 30-second pace test makes the estimate
personal. An opt-in exact mode, tucked away in Settings, can count every single reel with a
screen broadcast. The app never asks for screen sharing by itself.

## Features

| | |
|---|---|
| ⏳ **Auto mode** | Screen Time tracks Instagram / TikTok minutes in the background (no recording, no taps) and turns them into reels with your scroll pace |
| ⏱️ **Pace test** | 30 seconds: scroll ~20 reels, the app times you. Your swipe speed turns minutes into reels — no screen recording |
| 🎯 **Exact mode** | Opt-in, in Settings → advanced: counts every paged swipe with a screen broadcast, skips ads and rewatches. Never offered automatically |
| 🏝️ **Dynamic Island / Lock Screen** | Live Activity with a cap ring, live count, session timer, session count and streak (the iOS version of the floating bubble) |
| ⚡️ **Instant island** | Optional Shortcuts automation: the island appears the second Instagram opens and closes when it closes |
| 🧩 **Widgets** | Small, medium and lock screen counters, a battle widget, and a Control Center "Count Reels" button |
| ⚔️ **Scroll Battle** | Friends leaderboard (today / week), "most cooked" or "touch grass" modes, invite links |
| 🧊 **Chill streaks** | Days in a row at or under your daily cap, plus your best streak |
| 📼 **Wrapped** | Story-style weekly, monthly and yearly recap: totals, time, meters scrolled, doom hour, wildest day, personality archetype, shareable card |
| 📊 **Progress** | Day, week, month and year charts, per-app split, averages, highest day |
| 🔒 **Private by design** | Auto mode never sees the screen; exact mode analyses it on-device. Only daily numbers ever sync |

## How it works (short version)

Android reel counters read Instagram's view tree with an Accessibility Service and draw an
overlay (see [docs/ANDROID_TEARDOWN.md](docs/ANDROID_TEARDOWN.md)). iOS has no equivalent:
no app can read another app's screen without a screen broadcast. So Doomscore has two modes:

1. **Auto mode: Screen Time API (FamilyControls + DeviceActivity).** After one Face ID
   approval and picking Instagram, iOS wakes a tiny monitor extension at every minute of
   Instagram use. Doomscore multiplies minutes by your pace (reels per minute) and shows the
   result with "≈". It runs all day, even when the app is closed, and never sees content.
2. **Exact mode (opt-in): Broadcast Upload Extension (ReplayKit).** The only way to count individual
   reels on iOS. Frames are shrunk to motion thumbnails and read with on-device OCR, then
   thrown away. It needs one tap in the system sheet per session and shows the red pill.
   Every exact session teaches auto mode your real pace. The app never offers it on its own.
3. **Live Activity via your backend.** Extensions can't update Live Activities, so counts go
   to your Supabase `ingest` function, which pushes start, update and end events through APNs.

The full design is in [docs/IOS_ARCHITECTURE.md](docs/IOS_ARCHITECTURE.md).

> Stated honestly: Screen Time only reports minutes, so auto mode's reels are an estimate
> (marked ≈); the pace test makes it personal. Counting individual reels, ads and rewatches
> is impossible on iOS without a screen broadcast — that's an Apple rule, not a Doomscore choice.

## Repo layout

```
project.yml                XcodeGen spec (5 targets)
Config/                    Base.xcconfig (+ your Secrets.xcconfig)
App/                       SwiftUI app: screens, services, App Intents, assets
ActivityMonitor/           Screen Time monitor extension (auto mode)
Broadcast/                 Broadcast Upload Extension (exact mode): frames, Vision OCR, recorder
Detection/                 Pure counting logic: motion, classifier, engine (unit tested)
Widgets/                   WidgetKit widgets, Live Activity UI, Control Center control
Shared/Core                Models, Screen Time estimator, App Group store, stats, sync client
Shared/UI                  Theme, Goob mascot, Live Activity attributes (app + widgets)
Tests/                     XCTest: engine, motion, classifier, Screen Time estimator, stats
backend/                   Supabase: SQL (RLS, RPCs, anti-cheat), Edge Functions (ingest, APNs)
web/                       Invite landing page, privacy policy, apple-app-site-association
docs/                      Teardown, architecture, security, App Review, detector tuning
```

## Build it (on a Mac)

The full walk-through, including the Apple Developer portal setup, is in
**[docs/SETUP_MAC.md](docs/SETUP_MAC.md)**. The short version:

1. The Apple Developer portal is set up under `com.gridcc.doomscore`, and
   `Config/Base.xcconfig` already holds the Team ID, bundle IDs and the `doomscore.gridcc.tech` domain.
2. Install XcodeGen, generate the project and open it:

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open Doomscore.xcodeproj
```

3. Run on a real iPhone (Screen Time and broadcasts don't work in the Simulator), connect
   Screen Time in onboarding, pick Instagram, and go scroll.
4. Take the 30-second pace test on Home. Optional: the "instant island" Shortcuts automation.

Tests: pick an iPhone Simulator and press ⌘U.

## Before you ship

- Request the **Family Controls (Distribution)** entitlement from Apple for the app and the
  monitor extension. Development builds work without it; TestFlight and the App Store don't.
- Tune exact mode on real devices with Settings → advanced → exact mode → detector lab
  ([docs/DETECTOR_TUNING.md](docs/DETECTOR_TUNING.md)).
- Host a privacy policy, fill in the privacy labels, and attach a demo video for review.
