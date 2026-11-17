/**
 * TMDB metadata in English and Hebrew (P1-4), for titles with a TMDB id:
 * title, synopsis, genres, certification, rating, images, cast, and per
 * episode the name, synopsis and still. Run after `details.ts`.
 *
 * A movie costs one TMDB call; a series one, plus two per season the
 * provider has (English and Hebrew episode names).
 *
 * Resumable like `details.ts`: written every chunk, stops at its time budget.
 *
 * Run: node --env-file=<env file> src/enrich.ts
 */

import { createDb, type Db, type Row } from './db.ts'
import { pool } from './pool.ts'
import { createTmdb, type Tmdb, type TmdbCastMember, type TmdbMovieFull, type TmdbSeriesFull } from './tmdb.ts'

export interface Pending {
  id: number
  kind: 'movie' | 'series'
  ext_id: number
  name: string
  tmdb_id: number
}

export interface EnrichReport {
  pending: number
  done: number
  /** Titles with a Hebrew synopsis from TMDB. */
  withHebrew: number
  episodes: number
  failed: number
  outOfTime: boolean
}

/** Cast members kept per title. */
const CAST = 15
/** Certification countries, in order of preference. */
const CERT_COUNTRIES = ['US', 'IL', 'GB']
const MOVIE_PARALLEL = 6
const SERIES_PARALLEL = 3
const CHUNK = 50
const MAX_FAILURES_IN_A_ROW = 25

const blank = (s: string | null | undefined) => (s && s.trim() !== '' ? s.trim() : null)

const notSame = (he: string | null, en: string | null) => (he !== null && he === en ? null : he)

/** TMDB's stand-in for an episode with no name ("Episode 3", "פרק 3"): the app writes its own. */
export function episodeName(name: string | null | undefined): string | null {
  const n = blank(name)
  return n === null || /^(Episode|פרק) \d+$/.test(n) ? null : n
}

/** The Hebrew title and synopsis from TMDB's translations, if any. */
function hebrew(t: TmdbMovieFull | TmdbSeriesFull): { title: string | null; overview: string | null } {
  const he = t.translations.translations.find(x => x.iso_639_1 === 'he')?.data
  return { title: blank(he?.title ?? he?.name), overview: blank(he?.overview) }
}

export function movieCertification(m: TmdbMovieFull): string | null {
  for (const country of CERT_COUNTRIES) {
    const found = m.release_dates.results.find(r => r.iso_3166_1 === country)?.release_dates.map(d => blank(d.certification)).find(Boolean)
    if (found) return found
  }
  return null
}

export function seriesCertification(s: TmdbSeriesFull): string | null {
  for (const country of CERT_COUNTRIES) {
    const found = blank(s.content_ratings.results.find(r => r.iso_3166_1 === country)?.rating)
    if (found) return found
  }
  return null
}

/** Top cast by billing order, one entry per person. */
export function topCast(cast: TmdbCastMember[]): TmdbCastMember[] {
  const seen = new Set<number>()
  return [...cast]
    .sort((a, b) => a.order - b.order)
    .filter(c => !seen.has(c.id) && seen.add(c.id))
    .slice(0, CAST)
}

const describe = (err: unknown) => (err instanceof Error ? err.message : String(err))

export async function enrich(tmdb: Tmdb, db: Db, providerName: string, budgetMs: number, now: () => number = Date.now): Promise<EnrichReport> {
  const deadline = now() + budgetMs
  const [provider] = await db.select<{ id: number }>('providers', `name=eq.${encodeURIComponent(providerName)}&select=id`)
  if (!provider) throw new Error(`Unknown provider ${providerName}: run the sync first`)
  const providerId = provider.id

  // Genre names change rarely; four calls a run keep them current.
  const genreRows: Row[] = []
  for (const [kind, tmdbKind] of [['movie', 'movie'], ['series', 'tv']] as const) {
    const [en, he] = await Promise.all([tmdb.genres(tmdbKind, 'en-US'), tmdb.genres(tmdbKind, 'he-IL')])
    for (const g of en) genreRows.push({ kind, id: g.id, name_en: g.name, name_he: he.find(h => h.id === g.id)?.name ?? null })
  }
  await db.upsert('genres', 'kind,id', genreRows)

  const report: EnrichReport = { pending: 0, done: 0, withHebrew: 0, episodes: 0, failed: 0, outOfTime: false }
  let failuresInARow = 0
  let lastError = ''
  const tried: number[] = []
  const outOfTime = () => {
    if (now() < deadline) return false
    report.outOfTime = true
    return true
  }
  const halted = () => failuresInARow >= MAX_FAILURES_IN_A_ROW

  async function runChunk(titles: Pending[], kind: 'movie' | 'series'): Promise<void> {
    const enrichedAt = new Date(now()).toISOString()
    const titleRows: Row[] = []
    const people = new Map<number, Row>()
    const castRows: Row[] = []
    const episodeRows: Row[] = []

    // The provider's episodes of these series, to attach TMDB's to.
    const stored = kind === 'series'
      ? await db.selectAll<{ id: number; title_id: number; ext_id: number; season: number; episode: number }>(
          'episodes',
          'id,title_id,ext_id,season,episode',
          `title_id=in.(${titles.map(t => t.id).join(',')})`,
        )
      : []

    await pool(titles, kind === 'movie' ? MOVIE_PARALLEL : SERIES_PARALLEL, async t => {
      if (halted() || outOfTime()) return
      try {
        const full = kind === 'movie' ? await tmdb.movieFull(t.tmdb_id) : await tmdb.seriesFull(t.tmdb_id)
        const base = { provider_id: providerId, kind: t.kind, ext_id: t.ext_id, name: t.name, enriched_tmdb_id: t.tmdb_id }
        if (full === null) {
          // TMDB has no such id: done with empty fields, until the TMDB id changes.
          titleRows.push({ ...base, ...emptyEnrichment, enriched_at: enrichedAt })
          failuresInARow = 0
          return
        }
        const he = hebrew(full)
        const movie = kind === 'movie' ? (full as TmdbMovieFull) : null
        const series = kind === 'series' ? (full as TmdbSeriesFull) : null
        const seasonEpisodes: Row[] = []
        if (series) {
          const mine = stored.filter(e => e.title_id === t.id)
          for (const number of [...new Set(mine.map(e => e.season))]) {
            // A long series stops between seasons at the deadline; it is not
            // written, not counted as failed, and is done whole next run.
            if (outOfTime()) return
            const [en, heSeason] = await Promise.all([tmdb.season(t.tmdb_id, number, 'en-US'), tmdb.season(t.tmdb_id, number, 'he-IL')])
            for (const e of mine.filter(x => x.season === number)) {
              const enEp = en?.episodes.find(x => x.episode_number === e.episode)
              const heEp = heSeason?.episodes.find(x => x.episode_number === e.episode)
              if (!enEp && !heEp) continue
              const nameEn = episodeName(enEp?.name)
              const overviewEn = blank(enEp?.overview)
              seasonEpisodes.push({
                title_id: t.id,
                ext_id: e.ext_id,
                season: e.season,
                episode: e.episode,
                name_en: nameEn,
                overview_en: overviewEn,
                // TMDB may answer he-IL with the English text; the app falls back to English anyway.
                name_he: notSame(episodeName(heEp?.name), nameEn),
                overview_he: notSame(blank(heEp?.overview), overviewEn),
                tmdb_still: enEp?.still_path ?? heEp?.still_path ?? null,
              })
            }
          }
        }
        titleRows.push({
          ...base,
          title_en: blank(movie ? movie.title : series!.name),
          title_he: he.title,
          overview_en: blank(full.overview),
          overview_he: he.overview,
          tmdb_genre_ids: full.genres.map(g => g.id),
          certification: movie ? movieCertification(movie) : seriesCertification(series!),
          tmdb_rating: full.vote_average > 0 ? full.vote_average : null,
          original_language: blank(full.original_language),
          tmdb_poster: full.poster_path,
          tmdb_backdrop: full.backdrop_path,
          tmdb_runtime_min: (movie ? movie.runtime : series!.episode_run_time[0]) || null,
          enriched_at: enrichedAt,
        })
        topCast(movie ? movie.credits.cast : series!.aggregate_credits.cast).forEach((c, position) => {
          people.set(c.id, { tmdb_id: c.id, name: c.name, profile: c.profile_path })
          castRows.push({ title_id: t.id, person_id: c.id, position, character: blank(c.character) ?? blank(c.roles?.[0]?.character) })
        })
        episodeRows.push(...seasonEpisodes)
        failuresInARow = 0
      } catch (err) {
        report.failed++
        failuresInARow++
        lastError = describe(err)
      }
    })

    const doneIds = titles.filter(t => titleRows.some(r => r.ext_id === t.ext_id)).map(t => t.id)
    // People before cast (foreign key); cast replaced whole; titles last, so a
    // title is marked enriched only once everything else is stored.
    await db.upsert('people', 'tmdb_id', [...people.values()])
    if (doneIds.length > 0) await db.remove('title_cast', `title_id=in.(${doneIds.join(',')})`)
    await db.upsert('title_cast', 'title_id,person_id', castRows)
    await db.upsert('episodes', 'title_id,ext_id', episodeRows)
    await db.upsert('titles', 'provider_id,kind,ext_id', titleRows)
    report.done += titleRows.length
    report.withHebrew += titleRows.filter(r => r.overview_he).length
    report.episodes += episodeRows.length
    if (halted()) throw new Error(`Stopped after ${MAX_FAILURES_IN_A_ROW} failures in a row; last: ${lastError}`)
  }

  for (;;) {
    const page = await db.rpc<Pending>('titles_needing_enrichment', { p_provider: providerId, p_skip: tried })
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

/** Every enrichment column, empty: same keys as a full row, as the bulk upsert needs. */
const emptyEnrichment = {
  title_en: null,
  title_he: null,
  overview_en: null,
  overview_he: null,
  tmdb_genre_ids: null,
  certification: null,
  tmdb_rating: null,
  original_language: null,
  tmdb_poster: null,
  tmdb_backdrop: null,
  tmdb_runtime_min: null,
}

function env(name: string): string {
  const value = process.env[name]
  if (!value) throw new Error(`Missing environment variable ${name}`)
  return value
}

if (import.meta.main) {
  const db = createDb({ url: env('SUPABASE_URL'), key: env('SUPABASE_SECRET_KEY') })
  const budgetMin = Number(process.env.ENRICH_BUDGET_MIN ?? '8')
  const report = await enrich(createTmdb(env('TMDB_API_KEY')), db, 'prov1', budgetMin * 60_000)
  console.log(JSON.stringify(report))
  if (report.failed > Math.max(10, report.done * 0.05)) process.exitCode = 1
}
