# Session Handoff — 2026-11-19

## Goal
Android TV UI work in WTV:
- The "More" page uses the browse header over rows of 4, with 2 rows on screen.
- Every page fits 2 rows under its header.
- The Watchlist has an All / Movies / Series filter.
- All chips share one style.
- Tab switches no longer show Loading.

The work then shipped as 0.4.0 to Play internal testing.

## Current State
- **Merged to main** (squash), all on 2026-11-19: #126, #127, #128, #129.
  - main = `8dbf6fd Version 0.4.0 (code 4) ... (#129)`.
  - `versionCode = 4`, `versionName = "0.4.0"` in `android/app/build.gradle.kts`.
- **Play:** the user said "v4 uploaded" (2026-11-19). The bundle is `/home/shahar/Downloads/WhatTV-0.4.0.aab`. Its signature SHA256 was checked and matches `~/.config/wtv/wtv-release.jks`. The next upload needs `versionCode` 5.
- **Streamer** (192.168.1.253, adb port was 42899): it runs the debug build of `94edf99`. That has the same code as main minus the version bump, signed with the release key.
- **Verified on the TV emulator** (`emulator-5554`, 960×540 dp), in English and Hebrew:
  - Home and Movies show two full rows under a 3-line synopsis.
  - On the More page each Down moves one row, and Up reaches the sort chips.
  - The Watchlist filter shows All 3, Movies 1, Series 2 (emulator test data).
  - Chips sit across from the page name and flip in Hebrew.
  - A revisited tab, and Home back from Live TV, show at 0.3 s.
- **Not verified:**
  - A filter that hides every title (empty state plus D-pad).
  - Chip contrast on the real TV.
  - Behaviour after a playback, or after a new WTW ranking, on a WTW-connected device.
- **Emulator test data left behind:** the emulator's watchlist holds "The Law of Beasts", "Win the Mall" and "Guarding Stars". The emulator's language was set back to English.
- **Open items from the previous handoff (2026-11-19 Supabase move):** none were checked this session.
  - The next scheduled catalog sync after the move.
  - The GitHub issue from failed sync run 44524415615.
  - Deploy and `db push` rights for the old login in the new org.

## Active Files
- `android/app/src/main/java/com/wtv/app/ui/grid/GridScreen.kt`: the More page (`PosterGrid`). Name and sort chips at the top, then `TitleHeader`, then a `LazyVerticalGrid` with 4 columns of `LandscapeCard`. It is fixed at 2 rows high and wrapped in `RowsAtTop(EDGE)`.
- `android/app/src/main/java/com/wtv/app/ui/browse/BrowseScreen.kt`:
  - `TitleHeader` is the shared header.
  - The row cache: `shown`, `Shown`, `rankings`, `lastWatching`, `ROWS_FRESH_MS`.
- `android/app/src/main/java/com/wtv/app/ui/components/Hero.kt`: `HeaderTop = 60.dp`, `HeaderHeight = 148.dp`; HeroText spacers changed from 10 to 8.
- `android/app/src/main/java/com/wtv/app/ui/theme/Type.kt`: smaller type scale (displayMedium 36sp, bodyLarge 15sp, titleMedium 16sp, …).
- `android/app/src/main/java/com/wtv/app/ui/components/Chips.kt` (new): `ChoiceChip`, the one chip style. It replaces every `FilterChip`.
- `android/app/src/main/java/com/wtv/app/ui/theme/Color.kt`: `Chip` 0xFF253241 (unselected) and `ChipSelected` 0xFF131B23.
- `android/app/src/main/java/com/wtv/app/ui/person/PersonScreen.kt`: `TitlesPage(kinds = true)` adds the All / Movies / Series chips.
- `android/app/src/main/java/com/wtv/app/ui/title/TitleScreen.kt`: header uses `HeaderTop` and `HeaderHeight + 92.dp`; row spacing 16.
- `android/app/src/main/java/com/wtv/app/ui/WtvApp.kt`: the Watchlist passes `kinds = true`.
- `LiveScreen.kt`, `CategoriesScreen.kt`, `SettingsScreen.kt`: switched to `ChoiceChip`.
- `res/values{,-iw}/strings.xml`: `filter_all` ("All" / "הכל").

## Changes Made This Session
1. **#126.** The More page went from portrait posters to the browse header plus landscape rows of 4.
   - Two rows show at a time, and each Down brings in one new row.
   - The type scale and header shrank app-wide so two rows fit under the header on every page.
   - The grid height is set explicitly (2 rows), so a third row never peeks in.
2. **#127.**
   - Watchlist filter.
   - `ChoiceChip` everywhere: dark, borderless, unselected text white at 50% on a lighter chip, selected full white on a darker chip. Focused chips are light like the tabs; the user did not specify focus, so this was my choice.
   - When chips share a line with a page name, the name sits at the start and the chips at the end (`Arrangement.SpaceBetween`), so they flip in RTL. The More page chips use end padding 30.dp to line up with the end of the rows.
3. **Tab lag diagnosis.** Each switch re-read the whole page:
   - 27 requests on Movies (25 categories + 2) and 30 on Series (14 categories + 16 genres).
   - 6 in parallel, about 0.2 s each warm and 3.7 s cold.
4. **#128.** The rows each page last showed are kept per page while the app runs.
   - They are shown at once when the tab comes back.
   - They are re-read quietly after a rating, a playback (`progressVersion`), a new ranking (`shown.clear()` and `rankings++`), or 10 minutes.
   - `owner` = language + WTW email + WTV email. A different owner means no cache.
   - Rows read before a new ranking are not stored.
   - A failed Continue watching load is not cached.
5. **#129.** Version 0.4.0 (code 4). Bundle built, signature verified, copied to `~/Downloads`.

## Failed Attempts
- **`./gradlew` without env:** "SDK location not found". Run it like this:
  `cd android && set -a && . /home/shahar/Projects/wtv/.env.local && set +a && export ANDROID_HOME=/home/shahar/Android/Sdk`
  The `.env.local` also brings the signing key. A build without it fails to install over the existing app: `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
- **tv-material 1.1.0:** `FilterChip`'s content is `@Composable () -> Unit`, not `RowScope.() -> Unit`, which gave a compile error.
- **Squash-merging stacked PRs:** after #126 was squash-merged, #127 showed CONFLICTING against main.
  - Fix: `git rebase --onto origin/main <old parent tip> <branch>`, then `push --force-with-lease`.
  - Check the tree hash before and after, so no re-review is needed.
  - GitHub may report CONFLICTING for a few seconds after the push; re-check.
- **`gh pr edit --body-file`** fails with a Projects (classic) GraphQL error. Use `gh api -X PATCH repos/BloodyDeathRoll/wtv/pulls/<n> --input -` with `{"body": ...}`.
- **Emulator key sequences:** blind sequences drift. Back from a title page can land on the rail or the tabs. Screenshot before pressing CENTER.

## Next Step
1. Ask the user how 0.4.0 looks on the TV, especially chip contrast. The selected chip is the darker one; a reviewer flagged that it may be hard to spot.
2. Untested: on the Watchlist, choose Movies when only series are saved. Check the empty message, and D-pad down/up between the chips and the message.
3. The previous handoff's items are still open; check them read-only first:
   - `gh run list --workflow sync.yml --limit 3`
   - `gh issue list --limit 5`
   - Edge function deploy and `db push` rights.
   - Do not trigger the sync by hand.
4. Optional cleanups that reviewers raised; none were requested by the user:
   - Rename `PosterGrid` (it shows landscape cards now).
   - Move `TitleHeader` to `ui/components`.
   - Move `ChoiceChip` imports into the `com.wtv.*` block.
   - Use `remember` for the Watchlist filter list.
