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

export interface WtwReport {
  wtwTitles: number
  /** WTW rows sharing a kind and TMDB id with another; the scored one is used. */
  wtwDuplicates: number
  movie: Coverage
  series: Coverage
  /** Titles whose WTW fields changed and were written. */
  updated: number
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
  const byKey = new Map<string, WtwTitle>()
  let wtwDuplicates = 0
  for (const t of wtwTitles) {
    const key = `${t.type}:${String(t.tmdb_id).trim()}`
    const seen = byKey.get(key)
    if (seen) wtwDuplicates++
    // A scored row wins over an unscored one; otherwise the first (lowest id) stays.
    if (!seen || (!parseVector(seen.taste_vec) && parseVector(t.taste_vec))) byKey.set(key, t)
  }

  // Titles with a TMDB id, and titles that still carry WTW fields (a TMDB id
  // that went away must not leave a stale match behind).
  const ours = await wtv.selectAll<OurTitle>(
    'titles',
    'id,kind,ext_id,name,tmdb_id,wtw_title_id,wtw_taste_vec,wtw_taste_version',
    `provider_id=eq.${provider.id}&or=(tmdb_id.not.is.null,wtw_title_id.not.is.null)`,
  )
  const empty = (): Coverage => ({ withTmdbId: 0, inWtw: 0, scored: 0 })
  const report: WtwReport = { wtwTitles: wtwTitles.length, wtwDuplicates, movie: empty(), series: empty(), updated: 0 }

  const rows: Row[] = []
  for (const t of ours) {
    const match = t.tmdb_id === null ? undefined : byKey.get(`${t.kind === 'movie' ? 'movie' : 'tv'}:${t.tmdb_id}`)
    const vec = match ? parseVector(match.taste_vec) : null
    const next = {
      wtw_title_id: match?.id ?? null,
      wtw_taste_vec: vec,
      wtw_taste_version: vec ? match?.taste_version ?? null : null,
    }
    if (t.tmdb_id !== null) {
      const coverage = report[t.kind]
      coverage.withTmdbId++
      if (match) coverage.inWtw++
      if (vec) coverage.scored++
    }
    // Unchanged rows are not written: every write moves `updated_at`.
    const same =
      t.wtw_title_id === next.wtw_title_id &&
      t.wtw_taste_version === next.wtw_taste_version &&
      sameVector(t.wtw_taste_vec, next.wtw_taste_vec)
    if (!same) rows.push({ provider_id: provider.id, kind: t.kind, ext_id: t.ext_id, name: t.name, ...next })
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
