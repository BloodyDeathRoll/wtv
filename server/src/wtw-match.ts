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
  tmdb_id: number
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
  movie: Coverage
  series: Coverage
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
  const byKey = new Map(wtwTitles.map(t => [`${t.type}:${String(t.tmdb_id).trim()}`, t]))

  const ours = await wtv.selectAll<OurTitle>('titles', 'id,kind,ext_id,name,tmdb_id', `provider_id=eq.${provider.id}&tmdb_id=not.is.null`)
  const empty = (): Coverage => ({ withTmdbId: 0, inWtw: 0, scored: 0 })
  const report: WtwReport = { wtwTitles: wtwTitles.length, movie: empty(), series: empty() }

  const rows: Row[] = ours.map(t => {
    const match = byKey.get(`${t.kind === 'movie' ? 'movie' : 'tv'}:${t.tmdb_id}`)
    const vec = match ? parseVector(match.taste_vec) : null
    const coverage = report[t.kind]
    coverage.withTmdbId++
    if (match) coverage.inWtw++
    if (vec) coverage.scored++
    return {
      provider_id: provider.id,
      kind: t.kind,
      ext_id: t.ext_id,
      name: t.name,
      wtw_title_id: match?.id ?? null,
      wtw_taste_vec: vec,
      wtw_taste_version: vec ? match?.taste_version ?? null : null,
    }
  })
  await wtv.upsert('titles', 'provider_id,kind,ext_id', rows)
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
