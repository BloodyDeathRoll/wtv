/**
 * Copies what WTW knows about the provider's titles into WTV (P1-5): WTW's
 * title id and taste vector, matched by TMDB id. Reads WTW's catalog with its
 * public key; nothing is written to WTW.
 *
 * Run: node --env-file=<env file> src/wtw-match.ts
 */

import { createDb, type Db, type Row } from './db.ts'

interface WtwTitle {
  id: number
  tmdb_id: string
  type: 'movie' | 'tv'
  /** pgvector text, e.g. "[0.1,-0.2,...]". */
  taste_vec: string | null
  taste_version: number | null
}

interface OurTitle {
  id: number
  kind: 'movie' | 'series'
  ext_id: number
  name: string
  tmdb_id: number | null
  wtw_title_id: number | null
  wtw_taste_vec: number[] | null
  wtw_taste_version: number | null
}

export interface Coverage {
  /** Titles with a TMDB id. */
  withTmdbId: number
  /** Of those, titles WTW has. */
  inWtw: number
  /** Of those, titles WTW has a taste vector for: WTW can rank them. */
  scored: number
}

/** Floats in a WTW taste vector (taste version 1); the column checks it too. */
const VECTOR_SIZE = 25

/**
 * A run that would clear more than this share of the current matches, or of
 * the current vectors, is taken for a bad read of WTW, not a real change, and
 * writes nothing.
 */
const MAX_CLEARED_SHARE = 0.5

export interface WtwReport {
  wtwTitles: number
  /** WTW rows sharing a kind and TMDB id with another; the scored one is used. */
  wtwDuplicates: number
  movie: Coverage
  series: Coverage
  /** Titles whose WTW fields changed and were written. */
  updated: number
  /** Scored titles per WTW taste version. Vectors of different versions do not compare. */
  versions: Record<string, number>
}

/** Same vector as stored, give or take float printing in the last digits. */
export function sameVector(stored: number[] | null, next: number[] | null): boolean {
  if (stored === null || next === null) return stored === next
  return stored.length === next.length && stored.every((x, i) => Math.abs(x - next[i]!) <= 1e-9 * Math.max(1, Math.abs(x)))
}

/** "[0.1,-0.2]" → [0.1, -0.2]; anything else → null. */
export function parseVector(v: string | null): number[] | null {
  if (v === null) return null
  try {
    const parsed: unknown = JSON.parse(v)
    return Array.isArray(parsed) && parsed.length > 0 && parsed.every(x => typeof x === 'number' && Number.isFinite(x)) ? parsed : null
  } catch {
    return null
  }
}

export async function matchWtw(wtv: Db, wtw: Db, providerName: string): Promise<WtwReport> {
  const [provider] = await wtv.select<{ id: number }>('providers', `name=eq.${encodeURIComponent(providerName)}&select=id`)
  if (!provider) throw new Error(`Unknown provider ${providerName}: run the sync first`)

  const wtwTitles = await wtw.selectAll<WtwTitle>('titles', 'id,tmdb_id,type,taste_vec,taste_version')
  // Row level security or a wrong key answers with no rows, not an error.
  if (wtwTitles.length === 0) throw new Error('WTW returned no titles: nothing is cleared')

  /** "0123" and "123" are the same TMDB id. */
  const key = (type: string, tmdbId: string | number) => `${type}:${String(tmdbId).trim().replace(/^0+(?=\d)/, '')}`
  const byKey = new Map<string, WtwTitle>()
  let wtwDuplicates = 0
  for (const t of wtwTitles) {
    const k = key(t.type, t.tmdb_id)
    const seen = byKey.get(k)
    if (seen) wtwDuplicates++
    // A scored row wins over an unscored one; otherwise the first (lowest id) stays.
    if (!seen || (!parseVector(seen.taste_vec) && parseVector(t.taste_vec))) byKey.set(k, t)
  }

  // Titles with a TMDB id, and titles that still carry WTW fields (a TMDB id
  // that went away must not leave a stale match behind).
  const ours = await wtv.selectAll<OurTitle>(
    'titles',
    'id,kind,ext_id,name,tmdb_id,wtw_title_id,wtw_taste_vec,wtw_taste_version',
    `provider_id=eq.${provider.id}&or=(tmdb_id.not.is.null,wtw_title_id.not.is.null)`,
  )
  const empty = (): Coverage => ({ withTmdbId: 0, inWtw: 0, scored: 0 })
  const report: WtwReport = { wtwTitles: wtwTitles.length, wtwDuplicates, movie: empty(), series: empty(), updated: 0, versions: {} }

  const rows: Row[] = []
  let matchedBefore = 0
  let cleared = 0
  let vectorsBefore = 0
  let vectorsLost = 0
  for (const t of ours) {
    const match = t.tmdb_id === null ? undefined : byKey.get(key(t.kind === 'movie' ? 'movie' : 'tv', t.tmdb_id))
    const vec = match ? parseVector(match.taste_vec) : null
    if (vec && vec.length !== VECTOR_SIZE) {
      throw new Error(`WTW title ${match?.id} has a taste vector of ${vec.length} values, not ${VECTOR_SIZE}: nothing is written`)
    }
    if (t.wtw_title_id !== null) {
      matchedBefore++
      if (!match) cleared++
    }
    if (t.wtw_taste_vec !== null) {
      vectorsBefore++
      if (!vec) vectorsLost++
    }
    const next = {
      wtw_title_id: match?.id ?? null,
      wtw_taste_vec: vec,
      wtw_taste_version: vec ? match?.taste_version ?? null : null,
    }
    if (t.tmdb_id !== null) {
      const coverage = report[t.kind]
      coverage.withTmdbId++
      if (match) coverage.inWtw++
      if (vec) {
        coverage.scored++
        const version = String(next.wtw_taste_version)
        report.versions[version] = (report.versions[version] ?? 0) + 1
      }
    }
    // Unchanged rows are not written: every write moves `updated_at`.
    const same =
      t.wtw_title_id === next.wtw_title_id &&
      t.wtw_taste_version === next.wtw_taste_version &&
      sameVector(t.wtw_taste_vec, next.wtw_taste_vec)
    if (!same) rows.push({ provider_id: provider.id, kind: t.kind, ext_id: t.ext_id, name: t.name, ...next })
  }
  const tooMany = (lost: number, before: number) => before > 0 && lost > before * MAX_CLEARED_SHARE
  if (tooMany(cleared, matchedBefore)) {
    throw new Error(`WTW match would clear ${cleared} of ${matchedBefore} matches (limit: half): nothing is written`)
  }
  if (tooMany(vectorsLost, vectorsBefore)) {
    throw new Error(`WTW match would clear ${vectorsLost} of ${vectorsBefore} taste vectors (limit: half): nothing is written`)
  }
  await wtv.upsert('titles', 'provider_id,kind,ext_id', rows)
  report.updated = rows.length
  return report
}

function env(name: string): string {
  const value = process.env[name]
  if (!value) throw new Error(`Missing environment variable ${name}`)
  return value
}

if (import.meta.main) {
  const wtv = createDb({ url: env('SUPABASE_URL'), key: env('SUPABASE_SECRET_KEY') })
  const wtw = createDb({ url: env('WTW_SUPABASE_URL'), key: env('WTW_SUPABASE_ANON_KEY') })
  console.log(JSON.stringify(await matchWtw(wtv, wtw, 'prov1')))
}
