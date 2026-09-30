# How BrainPal (Android) works — teardown

Source: `BrainPal.apk` (package `com.brainrot.android`, v14.14.549, minSdk 32, target 36).
Analysed statically (manifest, resources and dex string tables); no code was run and
**none of its servers or assets are used by Doomscore** — this is only to understand
the mechanism we have to re-create on iOS.

## 1. Counting: an Accessibility Service

`services.ReelsAccessibilityService` (`BIND_ACCESSIBILITY_SERVICE`), configured in
`res/xml/accessibility_service_config.xml`:

| setting | value | meaning |
|---|---|---|
| `accessibilityEventTypes` | `0x401820` | WINDOW_STATE_CHANGED, WINDOW_CONTENT_CHANGED, VIEW_SCROLLED, WINDOWS_CHANGED |
| `accessibilityFlags` | `0x53` | report view IDs, include non-important views, retrieve interactive windows |
| `canRetrieveWindowContent` | true | can read other apps' view trees |
| `canPerformGestures` | true | can press "back"/swipe (used by Block Reels) |
| `notificationTimeout` | 500 ms | event debounce |

It reads **Instagram's own view IDs** from the live UI tree:

```
com.instagram.android:id/clips_viewer_view_pager    ← the Reels pager (context)
com.instagram.android:id/clips_video_container
com.instagram.android:id/clips_media_component
com.instagram.android:id/clips_caption_component
com.instagram.android:id/layout_comment_thread_edittext   ← comments open → ignore
com.instagram.android:id/igds_snackbar
com.google.android.youtube:id/reel_recycler, reel_player_page_content   ← Shorts
com.google.android.youtube:id/app_engagement_panel, design_bottom_sheet ← panels open
com.snapchat.android:id/spotlight_container                            ← Spotlight
```

Log strings reveal the logic:

* **Ads** — content description starting with `"Sponsored Reel by "` → not counted.
* **Rewatches** — a `dedupeKey` per reel; logs `"… as the first reel in"` and
  `"… as the same reel resumed"`; `reverseScrolling`, `scrollDelta`, `scrollPosition`
  → scrolling back / resuming the same reel isn't counted.
* **Dwell time** — `updateReelViewDuration`, `viewDurationMillis` per reel event.
* Robustness — `"Accessibility snapshot changed during detection; retry on next event"`.

Events go to a Room DB: `reels_events(eventTimestamp, appId, viewDurationMillis)` →
rolled up into `hourly_reels_split` and `daily_reels_app_split(reelCount, viewDurationMs,
lastSyncedReelCount)`.

## 2. Fallback counter (no Accessibility)

`feature_fallback_counter.FallbackReelsCounterService` — manifest subtype string:
*"Estimates reels from watch time when Accessibility is unavailable"*; logs
*"Fallback tier active: usage-stats + audio-player counting"*. Uses
`PACKAGE_USAGE_STATS` (which app is in front) + `AudioManager.AudioPlaybackCallback`
(each reel starts a new player) to **estimate**.

## 3. "Opens automatically when Instagram opens"

It doesn't launch the app — the Accessibility Service is always running and sees
`WINDOW_STATE_CHANGED` for Instagram, then starts
`floating_bubble.ReelsCounterFloatingService` (`SYSTEM_ALERT_WINDOW`): *"Floating bubble
overlay to show reels counter while using other apps"*. `BlockReelsOverlayActivity`
draws the "limit reached" screen on top of Instagram.

## 4. Everything else

* **Sync** — WorkManager `ReelsSyncWorker` → their REST API (`/stats/api/v1/user/scroll/update`),
  friends/duels endpoints, FCM push.
* **Widgets** — Glance (`ReelsCounterWidgetReceiver`, expanded + "buddy" widget).
* **Extras** — weekly story share card, NFC "physical lock" + step challenges to unlock
  reels (Pro), RevenueCat/Razorpay paywall, Firebase analytics/remote config, Facebook SDK.

## 5. Why none of this ports to iOS directly

| Android mechanism | iOS reality |
|---|---|
| Accessibility Service reading other apps' views | ❌ No API reads another app's UI |
| Always-on service reacting to app launches | ❌ Apps can't run or launch in reaction to other apps |
| `SYSTEM_ALERT_WINDOW` overlay | ❌ No drawing over other apps |
| UsageStats foreground app | ⚠️ Screen Time API gives time only, sandboxed, no content |

→ See [IOS_ARCHITECTURE.md](IOS_ARCHITECTURE.md) for how Doomscore gets the same result.
