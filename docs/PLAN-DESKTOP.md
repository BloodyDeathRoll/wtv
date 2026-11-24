# WTV desktop — plan

WTV desktop is an installable desktop app: Linux first, then Mac, then Windows.
Version 1 is a copy of the TV app as built (`docs/PLAN.md`). It lives in the
same repository, in `desktop/`.

Status lives in GitHub Issues and the WTV-desktop project board; issue #167
tracks the whole plan. This file holds the decisions and the work packages.
Decided on 2026-11-24.

## 1. Product

- **A copy of the TV app.** Same catalog, same accounts, same look, English and
  Hebrew. Watchlist, progress, ratings and WTW are shared with the TV.
- **One provider.** Version 1 reads the catalog our server syncs from one
  provider, so it works with that provider only. The general version is in
  section 6.
- **Its own player.** The video plays inside the app, with our controls and the
  Live TV panels drawn over it.
- **Input** is mouse, keyboard and arrow keys. Computers only.
- **For Shahar alone, for now.** Builds get a release and a download that stay
  private until Shahar opens them.
- **Credentials are never published.** The provider login is typed in Settings
  and kept in the system keyring. It never goes into code, a build, an issue or
  a pull request. The app's own keys are inside every build and can be read out
  of it, as with the TV app's build; keeping builds private covers them too.
- **Order of work.** The Linux desktop app started first, with D1-2 on
  2026-11-24. WTV-public (`docs/PLAN-PUBLIC.md`) touches different folders and
  may run in parallel.

## 2. Architecture

| Part | Choice |
|---|---|
| App | Flutter (Dart), a new codebase in `desktop/`. It shares no code with the Kotlin TV app |
| Player | The mpv engine, through the `media_kit` library |
| Server | Unchanged: the same database and functions as the TV app |
| Sign-in | The TV's Google sign-in by a code entered on a phone, with the same client. No new Google or WTW setup |
| Provider login | The system keyring |
| Build keys | Read at build time from a git-ignored local file, as the TV build does |
| Licence | GPL-3 for `desktop/` only, because the standard mpv build is GPL. The rest of the repository has no licence file and is not changed. `desktop/` imports nothing from it. Each package carries the engine's source offer (D1-13) |
| Packages | `.deb` and AppImage with the engine included, attached to a draft GitHub release if it passes the D1-13 test (open point O3) |

### Rejected

Checked on 2026-11-24:

- **A web player in a browser.** Tested in headless Firefox 157 and Chrome
  157. Firefox did not load MKV, which is 63% of the movies. Chrome played it
  without the subtitles inside the file. Neither played AC3 sound or offered an
  audio-track choice.
- **Electron or Tauri with an engine inside.** Neither can draw our panels over
  mpv video on Linux. The Tauri mpv plugins state that window embedding does
  not work on Linux, and IPTVnator marks its embedded MPV as experimental.
- **Kotlin Compose for desktop, sharing the TV app's code.** Its way to draw
  over a native video view does not support Linux. The alternative is a library
  before version 1.0 whose Linux part is GPL-3.
- **A separate player window** (VLC or mpv opened beside the app). No Live TV
  panels over the video, and weaker resume and auto-next.

### Measured

The playback proof ran on 2026-11-24 with a throwaway app: Flutter 3.50.1,
`media_kit` 1.2.6, mpv 0.41, Ubuntu 26.04 on Wayland.

- 13 titles opened, played and seeked: MKV, MP4, AVI, an HEVC film, an MPEG-4
  film with MP3 sound, a series episode, an H.264 live channel and a 4K HEVC
  live channel with no dropped frames.
- Hebrew subtitles from inside the MKV files show.
- A film with AC3 sound decodes. Switching between two audio tracks and two
  subtitle tracks works.
- Our panel draws over the picture and takes mouse clicks. Shahar confirmed the
  picture and the sound.

Provider facts measured the same day:

- The stream server accepts the mpv and VLC identities. It rejects `okhttp` and
  ffmpeg's default identity.
- Live TV is MPEG-TS only.
- 63% of the movies are MKV; 86% of the episodes are MP4.
- The provider allows 3 streams at once.

### Known costs

- Two codebases: each later TV feature is built again for the desktop.
- The 3 streams are shared between the TV and the desktop.
- Software drawing stays. `media_kit` 1.2.6's graphics-card drawing path does
  not start on Flutter 3.50.1 ("EGL display or context is invalid"): D1-2
  tried Flutter's current renderer and its older one, on Wayland and on X11.
  Decoding still runs on the graphics card. With the current renderer the 4K
  HEVC live channel dropped no frames on the proof machine; weak computers are
  unproven. D1-12 tries it again if `media_kit` has a newer release by then.
- GitHub documents that draft releases are listed only for people with push
  access. It does not say whether a signed-out person with the direct file link
  can download. D1-13 tests that with a dummy file before the first real build.
- A build contains the app's keys, the same ones inside the TV app's build. It
  never contains the provider login.

## 3. Open points

| # | Point | Decide by |
|---|---|---|
| O1 | Mac: a real Mac for testing, and an Apple Developer account ($99 a year) for a build that opens without a warning. Without a Mac, Phase 2 waits | Before Phase 2 starts |
| O2 | Windows: a PC for testing, and a signing certificate or an accepted warning on first run. Without a PC, Phase 3 waits | Before Phase 3 starts |
| O3 | Where private builds live if a draft release fails the D1-13 test. Fallback: a private repository | D1-13 |

## 4. Work packages

Each work package is one GitHub issue, with the id in its title, and one pull
request. A phase is a milestone.

### Phase 1 — Linux

| Id | Work package |
|---|---|
| D1-1 | Playback proof. Done on 2026-11-24 with a throwaway app outside the repository |
| D1-2 | App shell: the Flutter project in `desktop/`, CI, theme, side menu, routes, both languages, focus by arrow keys and mouse, the GPL-3 licence file. The graphics-card drawing trial is done; its result is under Known costs |
| D1-3 | Sign-in: an anonymous start, then Google by code, as on the TV |
| D1-4 | Data layer: a Dart port of `Catalog`, `Live`, `Progress`, `Marks`, `WtwScores` and the guide calls (`Epg`, `OnNow`) |
| D1-5 | Browse: Home, Movies, Series, category pages, the More grid with its sorts and filters |
| D1-6 | Title and person pages: episodes, watchlist, Love / Like / Dislike, the title menu |
| D1-7 | Search: titles and people |
| D1-8 | Film and episode player: resume, auto-next, previous and next episode, subtitles, audio track, speed. The old stream closes before the next opens, and the provider's too-many-streams answer is shown as a message |
| D1-9 | Live TV: groups, guide, catch-up, channel numbers, favourites, hidden channels and groups, radio. The same stream rules as D1-8 |
| D1-10 | Settings: provider login, language, WTW connect, sign out |
| D1-11 | WTW: picks rows, % match, Recommended sort, Viewers also liked |
| D1-12 | Parity check: every screen compared with the TV app. Graphics-card drawing is tried again on a newer `media_kit`, if there is one. Playback is checked on a weak computer, if one is available |
| D1-13 | Packaging and private release: `.deb` and AppImage with the engine's source offer, on a draft release after the dummy-file test |

### Phase 2 — Mac

| Id | Work package |
|---|---|
| D2-1 | The same code built on GitHub's Mac machines, tested on a real Mac, and packaged |

### Phase 3 — Windows

| Id | Work package |
|---|---|
| D3-1 | The same code built on GitHub's Windows machines, tested on a PC, with an installer |

## 5. Effect on WTV-public

- G2-7 deletes the server's catalog copy. Desktop version 1 reads that copy, so
  G2-7 waits until the desktop app no longer reads it. That is the general
  desktop version (section 6), which has no work packages yet.
- G2-3 and G2-5 change the ranking and ratings calls. The desktop app moves
  with them.

## 6. Later

Not in this plan:

- The general desktop version, for any Xtream account or M3U link.
- Auto-update.
- Voice search, which `docs/PLAN.md` had planned for the web version.
- A public release.
