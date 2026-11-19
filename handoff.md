# Session Handoff — 2026-11-19

## Goal
Build WTV ("What to Watch"), an Android TV IPTV player for one Xtream provider in a Prime Video style, with optional WTW recommendations. WTW is read-only: never write to the WTW project. This session went from the plan through to an internal Play test, then worked through the user's UI and data feedback.

## Current State
- Repo: https://github.com/BloodyDeathRoll/wtv (public). Board: https://github.com/users/BloodyDeathRoll/projects/2. `main` is at `b2c289c`, with **0 open PRs**.
- Working: browse (Home, Movies, Series, Live TV), title pages, cast, search, playback with resume and auto-next, subtitles, Live TV (catch-up, guide panels, channel jump by number, OK channel list), Google sign-in, WTW connect, WTW rows, the WTW % match badge, the long-press menus and the exit dialog.
- The streamer (`192.168.1.253`, adb port `42899` last time; it changes on reboot) runs a **debug build of main as of #117+#119+#120**. #121 and #122 are server-only, so they need no app reinstall.
- Play internal track has **0.2.0** (versionCode 2). Everything after it (#90–#122) is not on Play. Testers get it only after a new `.aab` upload.
- Data: series without a TMDB id went from 841 to 605, and movies from 2,012 to 1,520. Most of the rest are titles TMDB has no Hebrew name for.
- Untested:
  - The WTW % match badges are untested on the TV by eye.
  - A held number key on a real remote is untested.
  - The real-remote check of long-press menus closing on release (#103) is still unconfirmed by the user.

## Active Files
- `server/src/details.ts`: provider details. `matchSeries` and `matchMovie` confirm TMDB hits. `titleNames` and `nameKey` handle name parts and comparison keys.
- `server/src/tmdb.ts`: TMDB client. This session added `searchMovie`, plus the `TmdbSeries`/`TmdbMovieFull` name, date and season fields.
- `server/src/details.test.ts`: matcher tests (168 server tests pass).
- `supabase/functions/wtw-scores/index.ts` and `server/src/wtw-scores.test.ts`: ask WTW's own `/api/recommendations/score` per title and cache the answer 12 h in `wtw_scores`.
- `supabase/migrations/20261119000600..001000_*`: `wtw_match` computed column (97% cap, below 0.5% shows null, anon gets null). `rankings.match` was dropped.
- `android/.../data/WtwScores.kt`: client batching of match requests (first 3 rows, then the focused row and the next), with an account-switch guard.
- `android/.../ui/live/ChannelNumber.kt`: `NumberEntry` for typed channel numbers (1.5 s wait, 4 digits max, held keys ignored).
- `android/.../player/LivePlayerScreen.kt`: Live player. Up opens earlier programmes, Down opens the guide, OK opens the channel list; Left/Right change channel (they seek in catch-up).
- `android/.../data/Live.kt`: `channelByNumber` and `allShown`.
- `android/.../ui/browse/BrowseScreen.kt`: rows. Series gets TMDB genre rows after the provider rows; the row key is `g<id>`/`c<id>`.
- `android/.../data/Catalog.kt`: `rows(kind, perRow, extra)` and `latest(..., genre)`.

## Changes Made This Session (late part, in order)
1. #114–#116: catch-up seeking and time bar; Live keys remapped; full-screen semi-opaque Earlier/Guide panels, as the user asked.
2. #115: new "What to Watch" icon and banner. The TV launcher caches banners, so restart the right launcher to see a change.
3. #117 WTW match badge, which changed three times:
   - Own computation against the whole catalogue gave ~100% for many titles. The cause was z-scoring against the wrong pool.
   - Then a port of WTW's pool. The user rejected it: "I completely DO NOT trust your calculations. I want WTW numbers."
   - Final: per-title calls to WTW's own score endpoint (the user chose option 1), using the user's WTW session. WTW stays read-only from our side; its server may cache values.
4. #118: the top-right search icon was removed at the user's request. The side-bar Search now searches the section on screen.
5. #119: channel jump by number keys and OK channel list (the user chose options 1+3).
6. #120: Series main page gets TMDB genre rows, since the provider files series by service only.
7. #121: series matching. 94% of unmatched series had only dummy provider season ids, so no hit could be confirmed. Now a hit is accepted when the name, air years (±1) and season/episode counts agree. The live re-run matched 236, including The Office US → TMDB 2316.
8. #122: movies with `tmdb_id: 0` are searched. A match needs the name (title, original or Hebrew), plus the year ±1, or the runtime ±5 min if a year is missing. A name alone is rejected. The live re-run matched 492, and 132 copies were regrouped.

## Failed Attempts
- **Computing WTW's % match ourselves:** first against the full catalogue, then against a ported WTW pool. Both disagreed with WTW, and the user explicitly distrusts our numbers. Do not reintroduce a local computation; use the `wtw-scores` function.
- **`served_titles` only** (WTW's saved scores) covers ~470 titles. Not enough alone.
- **Movie search by Hebrew name:** TMDB has no Hebrew title for most remaining movies (Viridiana, Mr. Hulot's Holiday, Maria Braun), so search returns nothing. Transliteration isn't feasible.
- **Emulator live playback** fails today (`Source error`) on both main and branches. The provider serves valid TS to curl. Use the streamer for live playback checks.
- **`git cherry-pick -q`** is not a valid option.
- **Docker `-v` mounts of the scratchpad** fail. Pipe SQL via stdin through the `/tmp/wtvq.sh` helper (psql in Docker, `--network host`, `PGPASSWORD=$SUPABASE_DB_PASS`).
- **Supabase CLI deploys** need `SUPABASE_ACCESS_TOKEN=$SUPABASE_DEPLOY_TOKEN` (from `.env.local`) plus `--yes`. Without `--yes` the run stops in agent mode and asks for confirmation.

## Approvals (history, not standing permission — re-ask)
- 2026-11-19: the user chose option 1 for WTW numbers (WTW endpoint per title).
- 2026-11-19: the user asked for channel jump options 1+3, Series genre rows, and the movie matching ("yes I do").
- Deploying to the WTV Supabase project with the deploy key was done this session. Ask again before each new hosted mutation.

## Next Step
1. Ask the user whether to upload a new Play build. Bump `versionCode`/`versionName` in `android/app/build.gradle.kts` (0.2.0 → 0.3.0), build a signed `.aab` with `./gradlew :app:bundleRelease` (key at `~/.config/wtv/wtv-release.jks`, password in `.env.local`), and guide the user one screen at a time.
2. Open issues:
   - #103: confirm long-press release with the user on the real remote.
   - #100: the user was asked whether sorting should be on the Movies and Series main screens; no answer yet.
3. Optional matcher follow-ups:
   - Use a `(2021)` year in a movie name when the year field is empty.
   - Skip the whole-name search when a name splits into parts.
   - Re-search unmatched titles by clearing `details_at` if TMDB adds Hebrew titles later.
