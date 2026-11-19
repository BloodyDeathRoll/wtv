/**
 * Fetches per-title details (P1-3) for titles never fetched and for series the
 * provider changed since:
 * - movies: the TMDB id and backdrop the provider gives, or, when it gives no
 *   id, one found by search whose name and year (or running time) agree;
 * - series: the episodes, and a TMDB id found by search. The provider gives no
 *   TMDB id for a series, only for its seasons (and most often dummies): a
 *   search hit counts when one of its seasons has one of those ids, or else
 *   when its name, years and seasons agree with the provider's.
 *
 * Resumable: results are written every chunk, and a run stops at its time budget.
 *
 * Run: node --env-file=<env file> src/details.ts
 */

import { createDb, type Db, type Row } from './db.ts'
import { refreshGroupsOrNull } from './groups.ts'
import { pool } from './pool.ts'
import { createTmdb, type Tmdb, type TmdbSeries } from './tmdb.ts'
import { createXtream, type Xtream } from './xtream.ts'

export interface Pending {
  id: number
  kind: 'movie' | 'series'
  ext_id: number
  name: string
  year: number | null
  cast_names: string | null
  tmdb_id: number | null
  /** Null when never fetched. */
  details_at: string | null
}

export interface DetailsReport {
  /** Titles in the work list, as far as this run got. */
  pending: number
  done: number
  withTmdbId: number
  episodes: number
  failed: number
  /** Stopped at the time budget with titles left. */
  outOfTime: boolean
}

/** Search hits checked per query; cast members tried; shows checked per cast member. */
const TITLE_HITS = 5
/** Minutes a movie's running time may differ from TMDB's (cuts, credits). */
const RUNTIME_SLACK_MIN = 5
const CAST_TRIED = 2
const CAST_SHOWS = 6

/** Parallel requests. The provider handled 6 without errors (measured 2026-11-17). */
const MOVIE_PARALLEL = 6
const SERIES_PARALLEL = 4
const CHUNK = 100
/** Series per request when marking dropped episodes: keeps the URL short. */
const STALE_BATCH = 100

/**
 * Provider season ids below this are dummies (seen: 1, 2). Real TMDB season
 * ids are in the tens of thousands and up.
 */
const MIN_SEASON_ID = 1000

/** This many failures in a row means the provider or TMDB is down: stop. */
const MAX_FAILURES_IN_A_ROW = 25

/**
 * The TMDB id of a series, or null. Searches each name the provider gives
 * ("המשרד ארה"ב - The Office US" is two), for the year, then for any year.
 *
 * With real provider season ids, a hit counts when one of its seasons has one,
 * and the TV credits of the first cast members are searched too (nearest year
 * first). Without them (most series), a hit counts only when its name or
 * original name is one of the provider's names, its air years cover the
 * provider's year, and every provider season exists with at least as many
 * episodes (one fewer allowed).
 */
export async function matchSeries(
  tmdb: Tmdb,
  title: { name: string; year: number | null; castNames: string | null },
  seasonIds: number[],
  episodeCounts: Record<number, number> = {},
): Promise<number | null> {
  // Any one real season id is enough: the provider may list seasons TMDB lacks (and back).
  const want = new Set(seasonIds.filter(id => id >= MIN_SEASON_ID))
  const counts = Object.entries(episodeCounts).map(([season, n]) => [Number(season), n] as const).filter(([season]) => season > 0)
  if (want.size === 0 && counts.length === 0) return null
  const names = titleNames(title.name)
  // An empty key (a name of punctuation only) must not match anything.
  const keys = new Set(names.map(nameKey).filter(Boolean))
  const tried = new Set<number>()

  function agrees(s: TmdbSeries): boolean {
    if (![s.name, s.original_name].some(n => n !== undefined && keys.has(nameKey(n)))) return false
    const first = Number(s.first_air_date?.slice(0, 4)) || null
    const last = Number(s.last_air_date?.slice(0, 4)) || first
    if (title.year !== null && first !== null && (title.year < first - 1 || title.year > (last ?? first) + 1)) return false
    const episodes = new Map(s.seasons.map(x => [x.season_number, x.episode_count ?? 0]))
    return counts.every(([season, n]) => (episodes.get(season) ?? -1) >= n - 1)
  }

  async function confirm(candidates: number[]): Promise<number | null> {
    for (const id of candidates) {
      if (tried.has(id)) continue
      tried.add(id)
      const s = await tmdb.series(id)
      if (want.size > 0 ? s.seasons.some(x => want.has(x.id)) : agrees(s)) return id
    }
    return null
  }

  for (const name of names) {
    const found =
      (title.year !== null ? await confirm(await tmdb.searchSeries(name, title.year, TITLE_HITS)) : null) ??
      (await confirm(await tmdb.searchSeries(name, null, TITLE_HITS)))
    if (found !== null) return found
  }
  if (want.size === 0) return null

  const cast = (title.castNames ?? '').split(/,|\s{2,}/).map(n => n.trim()).filter(Boolean).slice(0, CAST_TRIED)
  for (const name of cast) {
    const personId = await tmdb.searchPerson(name)
    if (personId === null) continue
    const distance = (date?: string) => (title.year === null || !date ? 9999 : Math.abs(Number(date.slice(0, 4)) - title.year))
    const shows = (await tmdb.personSeries(personId)).sort((a, b) => distance(a.first_air_date) - distance(b.first_air_date))
    const match = await confirm([...new Set(shows.map(s => s.id))].slice(0, CAST_SHOWS))
    if (match !== null) return match
  }
  return null
}

/**
 * The TMDB id of a movie the provider gives none for, or null. Searches each
 * name (for the year, then any year); a hit counts only when its title,
 * original title or Hebrew title is one of the provider's names and its
 * release year is within a year of the provider's, or, when either year is
 * unknown, its running time is within a few minutes of the provider's. A name
 * alone is not enough: remakes share names.
 */
export async function matchMovie(
  tmdb: Tmdb,
  title: { name: string; year: number | null },
  durationSecs: number | null,
): Promise<number | null> {
  const names = titleNames(title.name.replace(/\s*\(\d{4}\)\s*$/, ''))
  const keys = new Set(names.map(nameKey).filter(Boolean))
  if (keys.size === 0) return null
  const minutes = durationSecs ? durationSecs / 60 : null
  const tried = new Set<number>()
  for (const name of names) {
    for (const year of title.year !== null ? [title.year, null] : [null]) {
      for (const id of await tmdb.searchMovie(name, year, TITLE_HITS)) {
        if (tried.has(id)) continue
        tried.add(id)
        const m = await tmdb.movieFull(id)
        if (m === null) continue
        const hebrew = m.translations.translations.find(x => x.iso_639_1 === 'he')?.data.title
        if (![m.title, m.original_title, hebrew].some(n => n && keys.has(nameKey(n)))) continue
        const released = Number(m.release_date?.slice(0, 4)) || null
        if (title.year !== null && released !== null) {
          if (Math.abs(title.year - released) <= 1) return id
        } else if (minutes !== null && m.runtime && Math.abs(minutes - m.runtime) <= RUNTIME_SLACK_MIN) {
          return id
        }
      }
    }
  }
  return null
}

/** Episodes per season number. */
function episodeCounts(episodes: { season: number }[]): Record<number, number> {
  const out: Record<number, number> = {}
  for (const e of episodes) out[e.season] = (out[e.season] ?? 0) + 1
  return out
}

/** The names in a provider title: the whole, then each side of " - " ("Shtisel - שטיסל"; – — | too). */
export function titleNames(name: string): string[] {
  return [...new Set([name, ...name.split(/\s+[-–—|]\s+/)].map(n => n.trim()).filter(Boolean))]
}

/** A name for comparing: lower case, letters and digits only, no "the", no country tag ("US", "ארה"ב"). */
export function nameKey(name: string): string {
  return name
    .toLowerCase()
    .replace(/\((?:us|uk|il)\)|\b(?:us|uk)\b|ארה"ב/g, ' ')
    .replace(/^\s*the\b/, '')
    .replace(/[^\p{L}\p{N}]+/gu, '')
}

const describe = (err: unknown) => (err instanceof Error ? err.message : String(err))

export async function fetchDetails(
  xtream: Xtream,
  tmdb: Tmdb,
  db: Db,
  providerName: string,
  budgetMs: number,
  now: () => number = Date.now,
): Promise<DetailsReport> {
  const deadline = now() + budgetMs
  const [provider] = await db.select<{ id: number }>('providers', `name=eq.${encodeURIComponent(providerName)}&select=id`)
  if (!provider) throw new Error(`Unknown provider ${providerName}: run the sync first`)

  const report: DetailsReport = { pending: 0, done: 0, withTmdbId: 0, episodes: 0, failed: 0, outOfTime: false }
  let failuresInARow = 0
  let lastError = ''
  /** Every title tried this run, done or failed: never asked for again in the same run. */
  const tried: number[] = []

  /** Runs one title; a failure leaves it for the next run. */
  async function attempt(work: () => Promise<void>): Promise<void> {
    try {
      await work()
      failuresInARow = 0
    } catch (err) {
      report.failed++
      failuresInARow++
      lastError = describe(err)
    }
  }
  const halted = () => failuresInARow >= MAX_FAILURES_IN_A_ROW
  const base = (t: Pending) => ({ provider_id: provider.id, kind: t.kind, ext_id: t.ext_id, name: t.name })

  /** Fetches and stores one chunk of titles of one kind. */
  async function runChunk(titles: Pending[], kind: 'movie' | 'series'): Promise<void> {
    const detailsAt = new Date(now()).toISOString()
    const titleRows: Row[] = []
    const episodeRows: Row[] = []
    // Titles not started by the deadline are left for the next run; the chunk's
    // finished ones are still written.
    const outOfTime = () => {
      if (now() < deadline) return false
      report.outOfTime = true
      return true
    }
    await pool(titles, kind === 'movie' ? MOVIE_PARALLEL : SERIES_PARALLEL, t =>
      halted() || outOfTime() ? Promise.resolve() : attempt(async () => {
        if (t.kind === 'movie') {
          const info = await xtream.movieInfo(t.ext_id)
          // A movie is fetched once (`details_at`): searched once when the provider has no id.
          const tmdbId = info.tmdbId ?? (await matchMovie(tmdb, { name: t.name, year: t.year }, info.durationSecs))
          titleRows.push({ ...base(t), tmdb_id: tmdbId, backdrop_url: info.backdropUrl, details_at: detailsAt })
          return
        }
        const info = await xtream.seriesInfo(t.ext_id)
        // Searched on the first fetch only: a series TMDB does not know is not
        // searched again on every new episode. A miss is permanent until the
        // row's `details_at` is cleared by hand.
        const tmdbId = t.details_at !== null
          ? t.tmdb_id
          : await matchSeries(tmdb, { name: t.name, year: t.year, castNames: t.cast_names }, Object.values(info.tmdbSeasonIds), episodeCounts(info.episodes))
        titleRows.push({ ...base(t), tmdb_id: tmdbId, details_at: detailsAt })
        for (const e of info.episodes) {
          episodeRows.push({
            title_id: t.id,
            ext_id: e.extId,
            season: e.season,
            episode: e.episode,
            name: e.name,
            plot: e.plot,
            duration_secs: e.durationSecs,
            image_url: e.imageUrl,
            container_ext: e.containerExt,
            added_at: e.addedAt?.toISOString() ?? null,
            available: true,
            seen_at: detailsAt,
          })
        }
      }))

    // Episodes first: a title is marked done only once its episodes are stored.
    // `upsert` sends batches of 500.
    await db.upsert('episodes', 'title_id,ext_id', episodeRows)
    // Episodes the provider no longer lists (re-added under new ids) are kept,
    // since progress may point at them, but marked unavailable. Only for series
    // that listed episodes now: an empty answer is not taken as "all gone".
    const listed = [...new Set(episodeRows.map(r => r.title_id as number))]
    for (let i = 0; i < listed.length; i += STALE_BATCH) {
      const ids = listed.slice(i, i + STALE_BATCH).join(',')
      await db.update('episodes', `title_id=in.(${ids})&available=is.true&or=(seen_at.is.null,seen_at.lt.${encodeURIComponent(detailsAt)})`, { available: false })
    }
    await db.upsert('titles', 'provider_id,kind,ext_id', titleRows)
    report.done += titleRows.length
    report.withTmdbId += titleRows.filter(r => r.tmdb_id !== null).length
    report.episodes += episodeRows.length
    if (halted()) throw new Error(`Stopped after ${MAX_FAILURES_IN_A_ROW} failures in a row; last: ${lastError}`)
  }

  for (;;) {
    const page = await db.rpc<Pending>('titles_needing_details', { p_provider: provider.id, p_skip: tried })
    if (page.length === 0) return report
    report.pending += page.length
    for (const kind of ['movie', 'series'] as const) {
      const titles = page.filter(t => t.kind === kind)
      for (let i = 0; i < titles.length; i += CHUNK) {
        if (report.outOfTime || now() >= deadline) {
          report.outOfTime = true
          return report
        }
        const chunk = titles.slice(i, i + CHUNK)
        tried.push(...chunk.map(t => t.id))
        await runChunk(chunk, kind)
      }
    }
  }
}

function env(name: string): string {
  const value = process.env[name]
  if (!value) throw new Error(`Missing environment variable ${name}`)
  return value
}

if (import.meta.main) {
  const xtream = createXtream({
    server: env('XTREAM_PROV1_SERVER'),
    user: env('XTREAM_PROV1_USER'),
    password: env('XTREAM_PROV1_PASSWORD'),
  })
  const db = createDb({ url: env('SUPABASE_URL'), key: env('SUPABASE_SECRET_KEY') })
  const budgetMin = Number(process.env.DETAILS_BUDGET_MIN ?? '8')
  const report = await fetchDetails(xtream, createTmdb(env('TMDB_API_KEY')), db, 'prov1', budgetMin * 60_000)
  // New TMDB ids join copies of one title into one card.
  console.log(JSON.stringify({ ...report, regrouped: await refreshGroupsOrNull(db, 'prov1') }))
  // A few unreachable titles are normal; many mean something is wrong.
  if (report.failed > Math.max(10, report.done * 0.05)) process.exitCode = 1
}
