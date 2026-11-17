/**
 * Fetches per-title details (P1-3) for titles never fetched and for series the
 * provider changed since:
 * - movies: the TMDB id and backdrop the provider gives;
 * - series: the episodes, and a TMDB id found by search. The provider gives no
 *   TMDB id for a series, only for its seasons; a search hit counts only when
 *   one of its seasons has one of those ids.
 *
 * Resumable: results are written every chunk, and a run stops at its time budget.
 *
 * Run: node --env-file=<env file> src/details.ts
 */

import { createDb, type Db, type Row } from './db.ts'
import { refreshGroupsOrNull } from './groups.ts'
import { pool } from './pool.ts'
import { createTmdb, type Tmdb } from './tmdb.ts'
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
 * The TMDB id of a series, or null. Tries title search for the year, then for
 * any year, then the TV credits of the first cast members (nearest year first).
 * A candidate counts only when one of its seasons has a provider season id.
 */
export async function matchSeries(
  tmdb: Tmdb,
  title: { name: string; year: number | null; castNames: string | null },
  seasonIds: number[],
): Promise<number | null> {
  // Any one real season id is enough: the provider may list seasons TMDB lacks (and back).
  const want = new Set(seasonIds.filter(id => id >= MIN_SEASON_ID))
  if (want.size === 0) return null
  const tried = new Set<number>()

  async function confirm(candidates: number[]): Promise<number | null> {
    for (const id of candidates) {
      if (tried.has(id)) continue
      tried.add(id)
      if ((await tmdb.series(id)).seasons.some(s => want.has(s.id))) return id
    }
    return null
  }

  const found =
    (title.year !== null ? await confirm(await tmdb.searchSeries(title.name, title.year, TITLE_HITS)) : null) ??
    (await confirm(await tmdb.searchSeries(title.name, null, TITLE_HITS)))
  if (found !== null) return found

  const cast = (title.castNames ?? '').split(',').map(n => n.trim()).filter(Boolean).slice(0, CAST_TRIED)
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
          titleRows.push({ ...base(t), tmdb_id: info.tmdbId, backdrop_url: info.backdropUrl, details_at: detailsAt })
          return
        }
        const info = await xtream.seriesInfo(t.ext_id)
        // Searched on the first fetch only: a series TMDB does not know is not
        // searched again on every new episode. A miss is permanent until the
        // row's `details_at` is cleared by hand.
        const tmdbId = t.details_at !== null
          ? t.tmdb_id
          : await matchSeries(tmdb, { name: t.name, year: t.year, castNames: t.cast_names }, Object.values(info.tmdbSeasonIds))
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
