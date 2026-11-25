# Session Handoff — 2026-11-25

## Goal

Finish the desktop parity check (issue #163, D1-12) as far as code reading
allows, then start the Mac version of the WTV desktop app (issue #165, D2-1):
build it on GitHub's Mac machines and get a build with keys to a tester.

## Current State

- **Mac build: merged, built, not run.** PR #185 is squash-merged to `main`
  (`0a57bd4`). CI job `desktop-macos` passes (`WTV.app`, 95.7 MB). The
  "Desktop Mac release" workflow ran once (run 45607789849, success) and
  attached `wtv-desktop-0.1.0-macos.zip` (36 MB) to the draft release
  `desktop-v0.1.0`. **The app has never run on a Mac.**
- **Tester:** the owner said a tester (Alon) will test on his Mac. The draft
  release is visible only to people with write access, so the owner has to
  download the zip and pass it on. Whether that happened is unknown.
- **Unsigned.** No Apple Developer account. macOS blocks first open: System
  Settings → Privacy & Security → Open Anyway.
- **Parity (#163):** still open, In Progress on the board. Second-pass
  findings are in a comment on #163 (items 35 and 36, plus three areas code
  cannot settle).
- **Board:** WTV-desktop (project 6): #165 In Progress, #163 In Progress,
  #166 (Windows) Todo.
- **Repository secrets:** `SUPABASE_PUBLISHABLE_KEY`, `GOOGLE_TV_CLIENT_ID`
  and `GOOGLE_TV_CLIENT_SECRET` were added by the owner on 2026-11-25; all six
  key names the desktop build reads now exist.
- **Local:** this worktree is on branch `d2-1-mac-build`, which is merged; its
  remote branch still exists (not deleted: not asked). Working tree clean
  apart from this file.

## Active Files

- `desktop/macos/` — the Mac runner from Flutter's template; name WTV, bundle
  id `com.wtv.desktop`, window 1280 x 720.
- `desktop/macos/Runner/MainFlutterWindow.swift` — adds the `wtv/window`
  channel (`toggleFullScreen`), as the Linux runner has.
- `desktop/macos/Runner/DebugProfile.entitlements`, `Release.entitlements` —
  sandbox on, plus `com.apple.security.network.client`.
- `desktop/lib/data/keyring.dart` — one shared `FlutterSecureStorage` constant
  with `MacOsOptions(usesDataProtectionKeychain: false)`.
- `desktop/lib/data/session.dart`, `desktop/lib/data/provider_login.dart` —
  now use `keyring`.
- `desktop/pubspec.yaml`, `pubspec.lock` — add `media_kit_libs_macos_video`.
- `.github/workflows/ci.yml` — new `desktop-macos` job: builds without keys,
  uploads artifact `wtv-macos-no-keys`.
- `.github/workflows/desktop-mac-release.yml` — hand-started; builds with keys
  from secrets and uploads the zip to a draft release.
- `desktop/README.md` — new "Mac" section.
- `docs/PLAN-DESKTOP.md` — open point O1 marked decided.

## Changes Made This Session

1. Answered from code: without a provider (Xtream) login the catalog still
   shows (it comes from WTV's database, synced from one Xtream account by
   `server/src/sync.ts`), but nothing plays. WTW gives recommendations only.
2. Parity second pass, by reading both apps' code; posted on #163:
   - 35: search field in Hebrew: TV direction follows the typed text, desktop
     follows the layout.
   - 36: provider login fields in Hebrew: desktop always left to right, TV
     follows the text.
   - Live player panel rows: same content and layout numbers in both.
   - Not settled by code: look of the TV's `tv-material` `ListItem` rows,
     which rail item Left lands on, Right at a row's end (the TV leaves both
     to Compose's focus search), the rendered look, the tab animation.
3. Mac build (PR #185):
   - Login keychain, not the data protection keychain: the latter needs an
     Apple provisioning profile, which an unsigned build lacks
     (`flutter_secure_storage` README, "Keychain Sharing requires
     provisioning").
   - Keyed builds go to a draft release, never an artifact: the repository is
     public and its artifacts can be downloaded by any signed-in person.
   - The release workflow refuses a release that is not a draft, and fails on
     an empty secret.
4. Board: #165 set to In Progress and a status comment added, after the owner
   asked why the project was not updated. Saved as memory
   `update-project-board`.

Approvals given this session (history only; ask again before repeating):
posting the parity comment on #163; "merge" for PR #185 on 2026-11-25.

## Failed Attempts

- `gh pr edit 185 --body ...` and `gh issue view 163 --comments` fail on this
  repository with "Projects (classic) is being deprecated" (GraphQL). Use
  `gh api -X PATCH repos/BloodyDeathRoll/wtv/pulls/<n> -F body=@file` and
  `gh issue view <n> --json ...`.
- The agent review could not run the diff command, so it reviewed by reading
  files. Its six suggestions were all non-blocking; no code was changed after
  it.

## Next Step

1. Get the tester's result for `wtv-desktop-0.1.0-macos.zip`. First check:
   sign in, quit, reopen, still signed in (sandbox + ad-hoc signature + login
   keychain is the main unverified risk; a keychain error such as `-34018`
   would mean dropping the sandbox or signing properly). Then film playback,
   Live TV, catch-up, full screen (View → Enter Full Screen; F11 may be taken
   by macOS).
2. Fix what the test finds; a new build is
   `gh workflow run desktop-mac-release.yml -f tag=desktop-v0.1.0`.
3. When the Mac test passes: set #165 to Done on project 6 and close it.

Follow-ups, none started:

- #163: playback on a weak computer; whether GNOME reports a minimised window
  to Flutter as hidden (item 11); the owner has not chosen what to do with
  items 35 and 36.
- The remote branch `d2-1-mac-build` is merged and still exists.
- `flutter build macos` warns that plugins without Swift Package Manager
  support "will become an error in a future version of Flutter"; `Podfile` is
  generated in CI and not committed.
