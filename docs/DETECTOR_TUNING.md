# Tuning the reel detector (precise mode)

This is about **precise mode** (the optional screen broadcast). Auto mode uses Screen
Time minutes and needs no tuning beyond the pace, which precise mode calibrates.

The detector ships with sensible defaults, but it reads other apps' UI — expect to tune
it on real devices, and again whenever Instagram / YouTube / TikTok redesign.

How it avoids the classic over-count: subtitles and meme text burned into videos change
every second and used to look like a new creator/caption. Only the app's own overlay
text counts now — small (`zones.maxOverlayTextHeight`) and left-aligned
(`zones.overlayMaxMinX`). A reel change without a detected swipe also needs a real
picture cut plus `implicitConfirmations` agreeing readings.

## 1. Detector lab

Settings → advanced → **detector diagnostics** → *open detector lab*. The extension
writes (numbers only) every 1.5 s:

* frames analysed, fps, OCR runs + last OCR ms, free memory,
* context (`shortVideo` / `comments` / `other`) + app, layout score,
* swipes ↑/↓, last decision (`counted (swipe)`, `rewatch (swipe)`, `ad (swipe)`,
  `forward (no ocr)`, `resume same reel`…), recent events.

Debug the extension itself: run the **DoomscoreBroadcast** scheme, pick Doomscore as the
host app, start the broadcast, then use Xcode's debugger / Console (subsystem
`app.doomscore`, category `detector`).

## 2. Test protocol (per app, per iOS version)

1. Scroll 50 reels at normal speed → expect 50 ± 1.
2. 20 fast flicks (< 1 s each) → expect 20.
3. Swipe back 3, forward 3 → expect +0.
4. Leave a reel looping for 60 s → expect +0.
5. Open comments, scroll them, close → expect +0.
6. Count sponsored reels seen → "ads dodged" should match.
7. Scroll the home feed / Explore grid for a minute → expect +0.
8. Switch to another app and back → expect +0 (resume).

## 3. What to tweak (DetectorConfig)

| symptom | knob |
|---|---|
| swipes missed | lower `motion.minImprovement` (0.38 → 0.3), raise `processFPS` |
| feed scrolls counted | raise `shortVideoScoreThreshold`, add words to `keywords.feedNegative` |
| ads counted | add the label/CTA text you see to `keywords.adLabels` / `ctaPhrases` |
| comment scrolling counted | add the sheet's placeholder text to `keywords.comments` |
| double counts on one reel | raise `implicitConfirmations` (2 → 3) or `implicitChangeCooldown`, check identity in lab |
| big captions still read as identity | lower `zones.maxOverlayTextHeight` (0.034 → 0.028) |
| username/caption not read at all | raise `zones.maxOverlayTextHeight` or `zones.overlayMaxMinX` |
| memory warnings | raise `ocr.downscale` to 3 or `ocr.intervalInReels` |

Ship fixes without an app update: host a partial JSON at `DS_REMOTE_CONFIG_URL`
(e.g. Supabase Storage public file). It is deep-merged over defaults:

```json
{
  "version": 2,
  "keywords": { "adLabels": ["sponsored", "ad", "promoted"] },
  "motion": { "minImprovement": 0.33 }
}
```

## 4. Upgrade path: a tiny Core ML screen classifier

The rule-based classifier can be complemented by an on-device image classifier
(Create ML → Image Classification, MobileNet-sized, ~1–3 MB) with labels
`ig_reel`, `ig_ad`, `yt_short`, `tiktok`, `feed`, `other`. Collect training screenshots
on your own devices (Side + Volume Up), label by folder, train in Create ML, and run it on
the 224×224 downscaled frame at ~2 Hz in the extension (Neural Engine, low memory). Blend
its confidence into `ScreenClassifier`'s score. Keep the rules as the fallback.
