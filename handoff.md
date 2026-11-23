# Session Handoff — 2026-11-23

## Goal
Diagnose the failed scheduled "Catalog sync" GitHub Actions run (issue #125) and stop it from recurring.

## Current State
- The 2026-11-22 21:47 UTC failure is diagnosed and fixed: PR #132 merged to `main` as `824eb77`, remote branch deleted.
- **The sync failed again after the merge, for a different reason, not diagnosed:** run `45131781784` (2026-11-23 07:31 UTC, on `824eb77`). Three steps hit statement timeout `57014` on the **WTV** database within about 20 seconds:
  - Sync: `PATCH titles`
  - Details: `POST rpc/titles_needing_details` (`server/src/details.ts:293`)
  - Enrich: `POST rpc/titles_needing_enrichment` (`server/src/enrich.ts:215`)
  - WTW match: **passed**.
- Issue #125 "Catalog sync failed" is still open.
- PR #123 (session handoff 2026-11-19) is open and was not touched.
- This worktree's branch `catalog-sync-failed-diagnose-8cbffe90` is merged; its remote is gone. `handoff.md` is the only uncommitted file.

## Active Files
- `server/src/db.ts` — REST client for both databases. `DbError` now has `code`; `selectAll` retries a page once on `57014`.
- `server/src/db.test.ts` — tests for the retry (timeout then success, timeout twice, other code, non-JSON error body).
- `server/src/wtw-match.ts` — the step that failed on 2026-11-22 (line 130, WTW `titles` read). Not changed.
- `.github/workflows/sync.yml` — the workflow: Sync, Details, Enrich, WTW match, then the issue report. Not changed.

## Changes Made This Session
1. Diagnosed run `45074047800`: `WTW match` failed with `GET titles: HTTP 500 {"code":"57014",...}` reading WTW's `titles` 1,000 rows per page with the anon key. Each page is about 850 KB (`taste_vec`, `crew`).
2. Reran the same read by hand (read-only, WTW anon key from `/home/shahar/Projects/wtv/.env.local`): 35 pages, 34,973 rows, all HTTP 200, 0.9–3.2 s per page (total time including network). So the failure was transient.
3. The user chose "retry on 57014" over smaller pages. `selectAll` now reads a page once more, at once, after `57014`; a second timeout fails as before. Only `selectAll` retries (`select`, `count`, `rpc`, writes do not).
4. From the bot review: `DbError.code` is parsed from the JSON error body in `request` (the retry checks `e.code === '57014'`, not the message text); a test for a non-JSON error body; the code comment no longer claims the retry works because of a warm cache.
5. Landed with the `pr-land` skill at the user's request on 2026-11-22: three bot reviews, last one clean, CI green on `ad279fd`, squash-merged. `gh pr merge --delete-branch` merged but could not delete the branch (`'main' is already used by worktree at '/home/shahar/Projects/wtv'`); the remote branch was deleted with `git push origin --delete`.

## Failed Attempts
- `gh run view <id> --log` on **successful** sync runs returned nothing useful to grep, and `--json jobs` gave null step times: could not compare step durations of good and failed runs.
- WTW's real statement timeout for the anon role was not read (anon cannot see it). "3 s" is the Supabase default, an assumption.
- `npx tsc --noEmit` did not run locally: `server/` has no `node_modules`. The CI `server` job passed on the PR.
- Whether an immediate retry really helps against WTW is unconfirmed: only one scheduled run has happened since, and its WTW match passed without evidence that a retry fired.

## Next Step
1. Diagnose run `45131781784`: `gh run view 45131781784 --log-failed`. Three different statements on the WTV database timed out together, which points at the database being busy or locked around 07:34 UTC on 2026-11-23, not at one slow query. This is not verified. Check what ran then (another sync, a regroup, a migration, `pg_stat_activity`/locks if it recurs) — DB access is in the `wtv-dev-environment` memory.
2. Check whether later scheduled runs pass: `gh run list --workflow sync.yml --limit 5`.
3. Close issue #125 only after the cause of the second failure is known and the user asks.
4. Earlier failures with the same code exist (2026-11-19 12:29 UTC: `POST titles` upsert in `server/src/sync.ts:133`); the WTV-side timeouts may be one recurring problem.
