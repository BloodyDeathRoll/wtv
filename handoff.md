# Session Handoff — 2026-11-21

## Goal
Apply the user's "corrections session" to the WTV Android TV app: fix resume, rebuild the
movie/series player controls, and reshape the Live TV groups (General, Sports, Movies).
Then ship it: merge, and build a Play bundle.

## Current State
- PR #130 (corrections) merged to `main` as `ebf10d3`. PR #131 (version 0.5.0, code 5) merged as `2334209`.
- Play bundle built and signed: `/home/shahar/Downloads/WhatTV-0.5.0.aab` (0.5.0, code 5).
  **Not uploaded to Play** — the user uploads it to the internal testing track by hand.
- The bundle was built from branch `version-0.5.0` (commit `cc5c5f2`) before #131 was squash-merged;
  same tree as `main` at that time.
- Streamer (192.168.1.253) has a debug build of commit `cbab4a5` (all corrections), still named 0.4.0.
- Sync workflow ran on schedule twice on `ebf10d3` after the merge (both success). Whether the
  General / Sports / Movies groups now show correctly in the app was **not checked**.
- Tested on the TV emulator `WTV_TV` with a local test video only (the emulator's provider account
  no longer plays): resume, OK pause, seek, two-line controls, focus colour, Up/Down between lines.
- Not tested: holding Left/Right on a device (only the step maths, unit test), subtitles menu with a
  real subtitle track, the player on the real streamer by me (the user used it).
- Seen once, not reproduced in two reruns: right after playback started, a button stayed highlighted
  while the keys were moving the time bar.
- Local `./gradlew :app:lintDebug` reports 4 errors (SettingsScreen.kt:215, :224, Subtitles.kt:44,
  `app_name` not translated in `iw`). CI does not run lint. Not introduced by the last commit; origin not traced.

## Active Files
- `android/app/src/main/java/com/wtv/app/player/PlayerScreen.kt` — movie/series player: keys, controls, menus.
- `android/app/src/main/java/com/wtv/app/ui/theme/Color.kt` — `WtvColors.Accent`, now `#FFA900`.
- `android/app/src/main/java/com/wtv/app/ui/title/TitleScreen.kt` — Play button handler (resume fix).
- `android/app/src/main/res/values/strings.xml`, `values-iw/strings.xml` — labels; Live TV tab is `טלויזיה`.
- `android/app/src/test/java/com/wtv/app/player/DurationTest.kt`, `data/ProgressTest.kt` — unit tests.
- `server/src/live-groups.ts` (+ `live-groups.test.ts`) — group names and added groups; used by `server/src/sync.ts`.
- `android/app/build.gradle.kts` — versionCode 5, versionName 0.5.0.
- `docs/PLAN.md` — updated with the above.

## Changes Made This Session
1. **Resume from the beginning** — root cause: the Play button held a stale `::pressPlay` function
   reference captured before the saved position loaded (function references compare equal across
   recompositions). Now a lambda.
2. **Player controls** (own controls, `useController = false`):
   - OK pauses/plays at once. Left/Right move 10 s; held, the step grows with hold time (`scrubTo`),
     seek commits on key up.
   - Controls hide `HIDE_MS` (0.8 s) after the last key while playing; `BUTTONS_HIDE_MS` (5 s) with a
     button focused, so there is time to choose.
   - Layout went: one line → restyled like Live TV's catch-up banner → **two lines** (user: one line
     was not clear). Line 1: time in, bar, length. Line 2: play/pause, previous, next (series only),
     CC, settings. Down goes to the buttons, Up back to the bar.
   - Focus colour went yellow → Live TV green → **app icon orange yellow `#FFA900`**, applied app-wide
     by changing `WtvColors.Accent` (user: "replace all the greens").
3. **Live TV groups** (`server/src/live-groups.ts`, applied at sync):
   - Provider's "Israel" shown as General; "Sports world" shown as Sports.
   - Sports also takes every channel whose name matches `/sport|ספורט/i`.
   - New Movies group (id `-1`), after Sports, for names matching `/movies/i`. Channels stay in their own groups too.
   - "Hide the group" removed from the menu for the main group only; other groups still offer it.
4. "Customers also liked" → "Viewers also liked".
5. Version bump to 0.5.0 (code 5): code 4 was already on Play (user said so on 2026-11-21).

History of approvals (not standing permission): the user asked for the merge of #130 and of #131,
each by its own message on 2026-11-21. Both are done.

## Failed Attempts
- Emulator's saved provider account no longer plays any stream. Worked around with a temporary,
  uncommitted override of the media URL to `http://10.0.2.2:8123/t.mp4` plus a local Range-capable
  server (scratchpad, session-only). Do not commit such an override.
- `adb install` on the emulator failed with `INSTALL_FAILED_UPDATE_INCOMPATIBLE` when the build ran
  without the project key. Source `/home/shahar/Projects/wtv/.env.local` before `./gradlew` so debug
  builds use the release key (needed for the streamer too).
- `gh pr edit --body-file` fails with a "Projects (classic)" GraphQL error. Use
  `gh api -X PATCH repos/BloodyDeathRoll/wtv/pulls/<n> -F body=@file`.
- First Play bundle was built as 0.4.0 (code 4), which was already on Play; deleted and rebuilt as 0.5.0.
- No `android/local.properties`: gradle needs `export ANDROID_HOME=~/Android/Sdk`; `adb` is not on PATH
  (`~/Android/Sdk/platform-tools/adb`).

## Next Step
1. User uploads `/home/shahar/Downloads/WhatTV-0.5.0.aab` to Play Console → internal testing.
2. Check in the app (or the DB) that Live TV shows General, Sports (all sport channels) and Movies after the sync.
3. Optional follow-ups, none requested: the 4 local lint errors; the once-seen focus highlight glitch at
   playback start (`PlayerScreen.kt`, `toPicture()` / `onButtons`); test hold-to-seek on the streamer.
4. The worktree is on branch `version-0.5.0` (merged); the remote branches of #130 and #131 were not deleted.
