# WTV-public — plan

WTV-public turns WTV into a general IPTV player: the user adds their own
Xtream account or M3U link, and WTW becomes an optional layer on top. It is the
same app in the same repository. `docs/PLAN.md` describes WTV as built, with
one provider that our server syncs.

Status lives in GitHub Issues and the WTV-public project board. This file holds
the decisions and the work packages. Decided on 2026-11-23 unless a line says
otherwise.

## 1. Product

Two goals, in order:

- **Goal 1 — plain IPTV player.** It works with any Xtream account or M3U
  link. No server and no sign-in. It shows the provider's own text and images.
- **Goal 2 — the same, with WTW.** After Google sign-in the app adds TMDB text
  and images, cast, and the WTW recommendations WTV has today.

Terms and rules:

- A **playlist** is an Xtream login or an M3U link. Several can be saved; one
  is active.
- WTW is opt-in. Without it the app is the Goal 1 player.
- Today's mode, where our server syncs one provider, stays selectable in the
  app until G2-6. Current testers lose nothing in between.
- The look, the player, Live TV and sign-in stay as they are.

## 2. Architecture

| Part | Goal 1 | Goal 2 adds |
|---|---|---|
| TV app | A local database, filled straight from the user's provider. `data/Catalog.kt` is the one read path the screens use; it gets a local implementation with the same methods | TMDB data and WTW scores stored next to the local catalog |
| Server | Nothing | A match function (title names and years in, TMDB data out, shared cache) and ranking by TMDB key |
| Scheduled sync | Unchanged, for today's mode only | Retired in G2-7 |

Rules that carry over from WTV:

- Provider logins stay on the device, encrypted. The server never receives
  them.
- WTW is read-only (`docs/PLAN.md`, section 2).

Rejected: our server syncs every user's provider. It would store users'
provider passwords, and a catalog copy of about 20 MB per user.

### Known costs

- The first run of a new playlist in Goal 2 fills in TMDB details for every
  title. Estimated at 10–15 minutes for about 20,000 titles; not measured.
- Matching by name and year is less exact than a provider's TMDB id. When the
  provider gives the id, it is used.
- English category names work only for name patterns the app recognises.

## 3. Open points

| # | Point | Decide by |
|---|---|---|
| O1 | TMDB text and images in Goal 1 or Goal 2. Planned in Goal 2, so that Goal 1 needs no server. Moving them up gives the plain player English names, backdrops and cast | G1-8 |
| O2 | Programme guide for M3U playlists (XMLTV). Not in Goal 1: M3U channels have no now-and-next until it is added | G1-5 |

## 4. Work packages

Each work package is one GitHub issue, with the id in its title. A goal is a
milestone.

### Goal 1 — Plain IPTV player

| Id | Work package |
|---|---|
| G1-1 | Local database on the TV: playlists, categories, titles, episodes, channels, and the user's data. Platform SQLite, no new library |
| G1-2 | Xtream client on the TV: a Kotlin port of `server/src/xtream.ts`. Lists refresh when the app opens and every few hours; movie details and episodes load when a title opens |
| G1-3 | `Catalog` reads the local database: rows, grids, sorts, search, HD/4K copies, live groups. The screens stay as they are |
| G1-4 | User data on the device: resume, Continue watching, watchlist, favourites, hidden channels and groups, the radio switch |
| G1-5 | M3U playlists: parse, and sort entries into movies, series and channels. A link that carries an Xtream login is used as an Xtream account |
| G1-6 | First run and Settings: an "Add playlist" screen, the saved playlists, a per-category hide. The app opens with no sign-in |
| G1-7 | Remove the single-provider rules: the Hebrew category table, the Israel-specific live groups, the Turkish Series skip, the fixed `ts` live output |
| G1-8 | Hide what needs WTW or TMDB: Home picks, Recommended sort, % match, Viewers also liked, cast and person pages, genres, Love / Like / Dislike |
| G1-9 | Release on the Play internal test track |
| G1-10 | Play Store public listing for TV: store listing, TV banner, privacy policy, review (was P6-4) |

### Goal 2 — WTW on top

| Id | Work package |
|---|---|
| G2-1 | Match function on the server: title names, years and provider TMDB ids in, never logins; TMDB data out, from a shared cache |
| G2-2 | The TV applies the matches in background batches: English and Hebrew text, images, genres, cast. Cast, person pages and genres return |
| G2-3 | Ranking by TMDB key: `rank` and `wtw-scores` take keys sent by the TV, and the TV stores the scores. Recommended sort, Home picks and % match return |
| G2-4 | Viewers also liked and Watch again, by TMDB key |
| G2-5 | Ratings on the server by TMDB key, because the ranking reads them |
| G2-6 | Move current testers' data (progress, watchlist, ratings, favourites, hidden channels) to the new keys; then remove today's server-backed mode from the app |
| G2-7 | Retire the 4-hourly sync and the server's copy of the catalog; keep the TMDB cache. This deletes data: it runs only on Shahar's explicit go-ahead |

## 5. Later

Not in either goal:

- Several playlists active at the same time.
- Catch-up on M3U channels.
- Web version (`docs/PLAN.md`, section 5).
