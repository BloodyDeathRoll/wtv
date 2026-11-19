# Session Handoff — 2026-11-19

## Goal
Get WTV's Supabase project out of the shared Free org "EinHanamer" (shared with WTW), whose 500 MB database-size quota it was pushing over, while WTV keeps talking to WTW. Then check that everything still works.

## Current State
- **WTV was moved** to a new Supabase account by the user, using a project transfer. New org id: `kkpgrytqvfdmgthtrmjg`. The old org was `tpcxqabjjbjlezsqsinj` (EinHanamer). The project ref is unchanged: `wtnddxantgcoybxyunwm`. The user confirmed the URLs stayed the same. Region `eu-central-1`, status `ACTIVE_HEALTHY` per the Management API.
- **Verified after the move (2026-11-19 ~12:30–12:35 UTC):**
  - DB reachable via `aws-0-eu-central-1.pooler.supabase.com`, with user `postgres.wtnddxantgcoybxyunwm`. Data intact: titles 21,052, auth.users 40.
  - WTV `/auth/v1/health` returned 200. `/rest/v1/` with the secret key returned 200.
  - Edge functions `rank` and `wtw-scores` answer: a POST without a user session returns `401 {"error":"Not signed in to WTV"}`.
  - WTW `/auth/v1/health` with the anon key returned 200. `wtw_scores.scored_at` max was 12:30:27 UTC, so `wtw-scores` reached WTW after the move.
  - `SUPABASE_DEPLOY_TOKEN` (in `/home/shahar/Projects/wtv/.env.local`) still reads the project via `api.supabase.com/v1/projects/<ref>`. Function deploy and `db push` rights were **not** tested; the old login may be only a Developer in the new org.
  - Emulator and streamer apps load Home. The streamer shows WTW % matches (screenshot at 12:35 UTC).
- **Catalog sync run 44524415615 FAILED.** It was triggered by hand at 12:29:54 UTC. The Sync, Details and Enrich steps failed with `57014 canceling statement due to statement timeout`; WTW match succeeded. The workflow's "Report the failure as an issue" step ran, so a GitHub issue was probably opened; this was not checked. The scheduled run before it (01:51 UTC) succeeded. No scheduled run after the move had been seen yet.
- **EinHanamer dashboard still shows Database size 426 / 500 MB** after the move. Supabase docs say this quota is the average daily size over the billing cycle, so WTV's pre-move days stay in that average. Live sizes measured: WTV 271 MB, wtw 2.0 391 MB.
- The previous session's open item was not touched: the 0.3.0 Play upload, `/home/shahar/Downloads/WhatTV-0.3.0.aab`. Whether the user uploaded it is unknown.
- No code changes this session. The worktree is on branch `release-0.3.0` at `0859964`; `handoff.md` is untracked.

## Active Files
- None changed. References used:
  - `android/app/src/main/java/com/wtv/app/data/Api.kt:66-70`: any IOException shows "No connection to the server (<path>)".
  - `android/app/src/main/java/com/wtv/app/WtvApplication.kt:17`: OkHttp `callTimeout(20, SECONDS)`.
  - `.github/workflows/sync.yml`: catalog sync, cron `17 */4 * * *`, uses secrets `SUPABASE_URL` and `SUPABASE_SECRET_KEY`.

## Changes Made This Session
1. Researched Supabase quotas. The docs conflict:
   - Pricing page: "500 MB database size per project".
   - Changelog: per active project; paused projects don't count.
   - Database size doc: summed per organization, using the average daily size over the billing period.
   The dashboard shows one org-wide figure.
2. Measured live DB sizes: WTV 271 MB, wtw 2.0 391 MB, 662 MB in total, over 500 MB.
3. Found how WTV talks to WTW: WTW's public URL and anon key, plus the user's WTW token. See `WtvApplication.kt:20`, `supabase/functions/rank/index.ts:53` and `server/src/wtw-match.ts:223`. This does not depend on which org either project is in.
4. The user could not create a second org. I proposed a new account instead: invite the old login into the new account's org as **Developer**, so the old login's 2 active free projects don't count against it, then transfer. Supabase's terms have no clause against a second account. The free-project limit counts across orgs where you are Owner or Admin. The user did the transfer.
5. Ran the post-move checks listed above.
6. Diagnosed "Could not load: No connection to the server (titles)" on the streamer. The sync I had triggered overloaded the Nano DB; the app's titles request passed its 20 s call timeout, and the app reports that as "No connection". After the sync ended, a force-stop and relaunch loaded Home fine.

## Failed Attempts
- **`aws-0-eu-central-1` pooler for WTW 2.0** fails with `tenant/user postgres.cxoivygtoncywvrkgtdr not found`. WTW 2.0 is on `aws-1-eu-central-1.pooler.supabase.com`. WTV is the opposite: only aws-0 works. WTW DB password: `SUPABASE_DB_URL` in `/home/shahar/Projects/wtw/.env.local`. Read-only use only.
- **Triggering `sync.yml` by hand right after the move** caused statement timeouts. It broke the streamer's Home load for a few minutes, and the run failed. Do not trigger the sync by hand on Nano compute while the app is in use.
- **Management API `logs.all`** returns "The logs.all endpoint has been removed. Use GET /v1/projects/{ref}/analytics/endpoints/logs instead."
- **Streamer screencap while its screensaver is on** shows a gradient, not the app. Check `dumpsys power | grep mWakefulness` first.
- **Pressing Retry with `adb shell input keyevent DPAD_CENTER`** did not clearly reload; the error was still shown 25 s later. Force-stop and relaunch worked.

## Next Step
1. Check the next scheduled catalog sync after the move:
   `gh run list --workflow sync.yml --limit 3 --json status,conclusion,createdAt,event`
   If it fails again with `57014`, investigate the DB load and statement timeout on the Nano project. Do not re-trigger it by hand without asking.
2. Check whether run 44524415615 opened a GitHub issue (`gh issue list --limit 5`). Ask the user before closing it.
3. Check that the old login can still deploy WTV edge functions and run `db push` in the new org. Test read-only first. A real deploy needs the user's go-ahead.
4. Still open from the previous session: guide the user's upload of `/home/shahar/Downloads/WhatTV-0.3.0.aab` to Play internal testing, if not done yet. Ask first. See memory `wtv-release-setup`.
