# WTV — plan

WTV is an IPTV player for Android TV, later for the web. It plays the content of
an Xtream account and uses WTW (What To Watch) to recommend from what the
provider actually has.

Status lives in GitHub Issues and the project board. This file holds the
decisions and the work packages. Decided on 2026-11-17 unless a line says
otherwise.

Version 1 is complete (2026-11-23): every work package in section 4 is done,
except P6-4, the public Play listing. P6-4 and the general multi-provider
player (M3U, several accounts) continue in `docs/PLAN-PUBLIC.md`.

## 1. Product

### Sections

Home, Movies, Series, Live TV. A side rail holds search, browse and watchlist.
The look and feel follows the current Amazon Prime Video TV app (dark, a large
header for the focused title over a backdrop image, rows of cards below).

### Movies and Series

- **Header:** the top of the screen shows the title in focus: name, year,
  genres, age rating, synopsis, backdrop.
- **Rows:** one row per provider category, the 10 leading titles each. "More"
  opens the whole category as a poster grid.
- **Sort:** WTW recommendation, date added, year, name, TMDB rating.
- **Home:** WTW recommendations out of the latest provider content, a
  "Continue watching" row and a "Watch again" row.

### Title page

- The same header, with Play, Love / Like / Dislike, add to watchlist and more
  info.
- **Series:** row 1 is seasons and episodes (the header shows the synopsis of
  the episode in focus), row 2 is "Viewers also liked", row 3 is cast.
- **Movies:** row 1 is "Viewers also liked", row 2 is cast.
- A click on a cast member lists that person's titles the provider has.

### Live TV

- **Channel list:** cards, grouped by provider category, with add / remove
  favourite and click to view.
- **Viewing:** full screen, like a classic TV box. Channel up / down, an info
  banner with what is on now and next for that channel, and playback of earlier
  programmes on channels that have catch-up. No full programme guide.
- **Hiding:** the user can hide any channel or whole group from the lists. One
  master switch turns all radio channels on or off.

### Language

- English is the default: menus, and titles and synopses from TMDB whenever
  TMDB has them.
- Hebrew is optional, menus included (right-to-left layout).
- Where TMDB has nothing, the app shows the provider's own text.

### Player (version 1)

Resume, continue watching, auto-play next episode, subtitles, audio track
choice.

### Other

- Search is text only. Voice comes with the web version.
- One profile per device.
- Distribution: sideload (APK) and Play Store as an internal test track for invited testers only, no public listing (decided 2026-11-18). One signing key for both, registered with Play as the app signing key, so either install updates the other.

## 2. Architecture

### Parts

| Part | What it does | Technology |
|---|---|---|
| TV app | Everything the user sees; plays streams straight from the provider | Kotlin, Compose for TV, Media3 (ExoPlayer) |
| WTV database | Catalog copy, TMDB metadata, ratings, watchlist, progress, favourites, hidden channels | Supabase (own project) |
| Sync job | Copies the provider catalog into the WTV database and matches it to TMDB | TypeScript, scheduled |
| Ranking function | Scores the provider's titles for one user from their WTW fingerprint | TypeScript (Supabase Edge Function) |

The server side is TypeScript because the ranking formula is copied from WTW,
which is TypeScript.

### WTW is read-only

WTW is a standalone project with other developers. WTV adds nothing to it: no
code, no endpoints, no tables, no data writes. WTV only reads.

- **Sign-in:** WTW is Google sign-in only, so WTV is too. The user signs in with
  Google once; the app holds a WTV session and a WTW session for the same Google
  account. Allowing the WTV app in WTW's sign-in settings is a settings change
  that Shahar makes when the work reaches it (work package P4-1).
- **What WTV reads from WTW**, with the user's own login: the user's fingerprint
  (`users.dna`), their ratings, and the shared catalog (`titles`, with
  `taste_vec`; `crew_members`). Titles join on `type:tmdb_id`.
- **Ranking:** WTV carries its own copy of WTW's taste-weights formula
  (`src/modules/engine/scoring/taste-weights.ts` in WTW) and scores provider
  titles against `titles.taste_vec`. If the WTW team changes the formula, the
  copy is updated by hand.
- **"Viewers also liked":** the provider titles nearest to the seed title by
  WTW's title vectors. For a title WTW has not scored: TMDB's recommendations,
  kept only where the provider has them.
- **Cast click:** WTW's own person search is a TMDB call, so WTV calls TMDB
  directly and keeps only provider titles.
- **"Watch again":** a Love / Like / Dislike in WTW means the user watched the
  title. Loved and liked ones the provider has make the row; the rating shows
  pre-filled on the title page.
- **Ratings made in WTV** are stored in the WTV database only. A sync to WTW may
  come later (section 5).

### Fallbacks

- A user with no ratings in WTW gets the plain provider list with the normal
  sorts. The default is date added.
- A title WTW has not scored gets no personal rank and sits in normal sort
  order.
- A title TMDB does not know shows the provider's metadata.

### Provider facts (measured 2026-11-17, provider 1)

- 15,964 movies, 5,700 series, 584 live channels.
- 95 channels have catch-up; 261 have programme data.
- 3 simultaneous connections; `ts` output only for live.
- Movies: the TMDB id comes only from the per-title detail call
  (`get_vod_info`), not from the list. The first match is about 15,800 detail
  calls; after that, only new titles.
- Series: the provider gives no TMDB id for the series. `get_series_info` gives
  the TMDB ids of its seasons and episodes only. A series is matched by a TMDB
  title search, and the season id confirms the match (found 2026-11-17).
- The lists repeat a title once per category. Without repeats and unnamed rows:
  15,777 movies, 5,685 series, 583 channels (53 of them radio).
- All titles, plots and genres are in Hebrew. Cast names are mixed languages.
- The provider rejects unknown user agents; requests need a player user agent.
- Programme titles arrive base64-encoded.

Credentials stay in `.env.local` (`XTREAM_PROV1_USER`, `XTREAM_PROV1_PASSWORD`,
`XTREAM_PROV1_SERVER`), which is never committed.

## 3. Open points

| # | Point | Decide by |
|---|---|---|
| O1 | How many provider titles WTW can score. Measured in P1-5. | End of phase 1 |
| O2 | ~~Where the sync job runs.~~ Decided 2026-11-17: GitHub Actions, every 4 hours (`.github/workflows/sync.yml`). | P0-3 |
| O3 | ~~Subtitle source.~~ Decided 2026-11-18: embedded tracks only. A sample of 24 files: most MKV movies carry one subtitle track (often untagged, Hebrew where tagged); MP4s carry none. An outside source would need a subtitle-service account and title matching. | P3-4 |
| O4 | Exact sign-in flow on a TV (Google on the device, or a code entered on a phone). Tested in P4-1. | P4-1 |
| O5 | How the app gets provider credentials in version 1 (typed in settings, or delivered after sign-in). | P6-1 |

## 4. Phases and work packages

Each work package is one GitHub issue, with the id in its title. A phase is a
milestone.

### Phase 0 — Foundations

| Id | Work package |
|---|---|
| P0-1 | Android TV project skeleton: Kotlin, Compose for TV, Media3, builds and runs on the TV and the streamer |
| P0-2 | WTV Supabase project and first schema: providers, titles, episodes, channels, categories, user data tables |
| P0-3 | Server skeleton: TypeScript project for the sync job and the ranking function; decide where the job runs (O2) |
| P0-4 | CI: build and test the app and the server on every pull request |

### Phase 1 — Catalog pipeline

| Id | Work package |
|---|---|
| P1-1 | Xtream client: sign-in, lists, per-title details, programme data, player user agent |
| P1-2 | Catalog sync: movies, series, channels and categories into the WTV database; later runs take only what changed |
| P1-3 | TMDB id backfill: the per-title detail calls for the whole catalog, rate-limited and resumable; then new titles only. Series are matched by TMDB title search (then by cast) and confirmed by season id |
| P1-4 | TMDB enrichment: English and Hebrew title and synopsis, genres, backdrop, age rating, cast with person ids, episodes |
| P1-5 | WTW match: mark which provider titles WTW has scored; coverage report (answers O1) |
| P1-6 | Category names: English names for the provider's Hebrew categories |

### Phase 2 — App shell and browse

| Id | Work package |
|---|---|
| P2-1 | Design system from the Prime reference photos: colours, type, cards, focus states |
| P2-2 | Navigation: top tabs, side rail, remote-control focus handling |
| P2-3 | Header component: details and backdrop of the title in focus |
| P2-4 | Movies and Series tabs: category rows, 10 titles each, "More" |
| P2-5 | Category grid with sort (date added, year, name, TMDB rating) |
| P2-6 | Movie title page |
| P2-7 | Series title page: seasons and episodes row |
| P2-8 | Cast row and person page |
| P2-9 | Text search |
| P2-10 | English and Hebrew: menus, metadata language switch, right-to-left layout |

### Phase 3 — Playback

| Id | Work package |
|---|---|
| P3-1 | Movie and episode player with on-screen controls |
| P3-2 | Resume and the "Continue watching" row |
| P3-3 | Auto-play next episode |
| P3-4 | Subtitles and audio track choice (decide O3) |

### Phase 4 — Accounts and WTW

| Id | Work package |
|---|---|
| P4-1 | Google sign-in on the TV, giving a WTV session and a WTW session; test the flow first (O4). Needs Shahar for the WTW sign-in settings |
| P4-2 | Love / Like / Dislike and watchlist, stored in WTV |
| P4-3 | Ranking function: copy of WTW's taste-weights formula, scores per user, refreshed when the fingerprint changes |
| P4-4 | "Recommended" sort and the Home tab |
| P4-5 | "Viewers also liked" row |
| P4-6 | "Watch again" row and pre-filled ratings from WTW |
| P4-7 | Fallback for users with no WTW ratings and for unscored titles |

### Phase 5 — Live TV

| Id | Work package |
|---|---|
| P5-1 | Channel cards by group, with favourites |
| P5-2 | Hide channels and groups; master switch for radio |
| P5-3 | Full-screen live player: `ts` playback, channel up / down |
| P5-4 | Now and next banner for the channel being watched |
| P5-5 | Catch-up playback on channels that have it |

### Phase 6 — Release

| Id | Work package |
|---|---|
| P6-1 | Settings screen: account, language, provider credentials (O5), hidden channels |
| P6-2 | Speed on the streamer: image caching, list performance, start-up time |
| P6-3 | Sideload release: signed APK |
| P6-4 | Play Store internal test track for TV (invited testers, no public listing) |

## 5. Later

Not in version 1:

- M3U playlists.
- Several provider accounts.
- Several profiles per device.
- Web version, with voice search. Browsers cannot play `ts` directly, so live
  TV on the web needs a conversion step.
- Sending WTV ratings to WTW, if it proves useful. This would need the WTW
  team's agreement, since WTW is read-only for this project.
