/**
 * Ranks the catalog for one user by WTW's formula v2 (P4-3) and stores it in
 * `rankings`. Called by the app with the user's WTV session (Authorization)
 * and their WTW access token (body `wtw_token`). Everything WTW-side is read
 * as that user, so WTW's row level security decides what is visible; nothing
 * is written to WTW.
 *
 * Body: { wtw_token: string, force?: boolean }
 * Answer: { ranked, ratings, picks, fresh } — `fresh` when a ranking younger
 * than FRESH_MS was kept.
 */
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2.49.4'
import postgres from 'npm:postgres@3.4.5'
import { blankDNA, type DNA, type TMDBCrewSnapshot } from '../_shared/wtw/dna.ts'
import { TASTE_FEATURE_VERSION } from '../_shared/wtw/features.ts'
import { degree1Ids, getBoostEligibleIds, LINEAGE_COLUMNS, LINEAGE_TABLE, lineageCacheFromRows, type LineageCache, type LineageRecord } from '../_shared/wtw/lineage-boost.ts'
import { scoreV2, vecKey } from '../_shared/wtw/step2.ts'
import { picksFromPayloads, tasteVecsFromRows, trainingTitleIds, trainUserWeights } from '../_shared/wtw/taste-training.ts'

/** A ranking younger than this is kept unless `force`. */
const FRESH_MS = 60 * 60 * 1000
/** Even with `force`, a user is ranked at most this often (each run rewrites ~12k rows). */
const MIN_INTERVAL_MS = 2 * 60 * 1000
/** WTW reads in flight at once, per list of chunks. */
const PARALLEL = 4
/** Ids per `in (...)` filter, as WTW does, to keep request URLs short. */
const ID_CHUNK = 300
const PAGE = 1000

const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!, { prepare: false })

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

Deno.serve(async req => {
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)
  const body = await req.json().catch(() => null) as { wtw_token?: unknown; force?: unknown } | null
  const wtwToken = typeof body?.wtw_token === 'string' ? body.wtw_token : null
  if (!wtwToken) return json({ error: 'wtw_token missing' }, 400)

  // The WTV user, from the session the platform has already verified.
  // The platform provides the public key under either name, depending on the key system.
  const publicKey = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? ''
  const wtv = createClient(Deno.env.get('SUPABASE_URL')!, publicKey, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  })
  const { data: wtvUser, error: wtvError } = await wtv.auth.getUser()
  if (wtvError || !wtvUser.user) return json({ error: 'Not signed in to WTV' }, 401)
  const userId = wtvUser.user.id

  // WTW, read as the user. The token is checked before anything is answered.
  const wtw = createClient(Deno.env.get('WTW_SUPABASE_URL')!, Deno.env.get('WTW_SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: `Bearer ${wtwToken}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: wtwUser, error: wtwError } = await wtw.auth.getUser(wtwToken)
  if (wtwError || !wtwUser.user) {
    // Only a refusal means "connect WTW again"; anything else is passing trouble.
    const refused = !wtwError || [400, 401, 403].includes(wtwError.status ?? 0)
    return refused ? json({ error: 'WTW session not valid' }, 401) : json({ error: `WTW unreachable: ${wtwError.message}` }, 502)
  }
  const wtwUserId = wtwUser.user.id

  // A ranking is kept only for the same WTW account.
  const [run] = await sql`select ranked_at, wtw_user_id from public.ranking_runs where user_id = ${userId}`
  if (run && run.wtw_user_id === wtwUserId) {
    const age = Date.now() - new Date(run.ranked_at).getTime()
    if (age < MIN_INTERVAL_MS || (body?.force !== true && age < FRESH_MS)) return json({ fresh: true })
  }

  try {
    const dna = await readDna(wtw, wtwUserId)
    const picks = picksFromPayloads(await readPicks(wtw, wtwUserId))
    // No ratings and no picks: nothing personal to rank by (P4-7 shows the plain lists).
    if (dna.signals.length === 0 && picks.length === 0) {
      await sql.begin(async tx => {
        await tx`delete from public.rankings where user_id = ${userId}`
        await tx`delete from public.ranking_runs where user_id = ${userId}`
      })
      return json({ ranked: 0, ratings: 0, picks: 0 })
    }

    // As WTW: if the taste model cannot be trained, rank without it.
    let w: number[] | null = null
    try {
      const { data: state, error } = await wtw.from('play_state').select('state').eq('user_id', wtwUserId)
      if (error) throw error
      const { keys, ids } = trainingTitleIds(dna.signals, picks)
      const vecs = tasteVecsFromRows(await readWtwVectors(wtw, ids), keys)
      w = trainUserWeights({ dna, picks, playState: state?.[0]?.state ?? null, vecs })
    } catch (err) {
      console.warn('[rank] taste model unavailable, ranking without it:', err instanceof Error ? err.message : err)
    }

    const { pool, idsByKey, vecs } = await readCandidates()
    const strandA = dna.strand_a_creative_affinity
    const eligible = getBoostEligibleIds(strandA)
    let d1: LineageCache = new Map()
    let d2: LineageCache = new Map()
    if (eligible.length > 0) {
      d1 = lineageCacheFromRows(await readLineage(wtw, eligible))
      const deg1 = degree1Ids(pool, d1)
      if (deg1.length > 0) d2 = lineageCacheFromRows(await readLineage(wtw, deg1))
    }

    const scored = scoreV2(pool, dna, w, vecs, d1, d2)
    const titleIds: number[] = []
    const scores: number[] = []
    const sums: number[] = []
    for (const s of scored) {
      for (const id of idsByKey.get(vecKey(s.title)) ?? []) {
        titleIds.push(id)
        scores.push(s.composite)
        sums.push(s.s)
      }
    }
    await sql.begin(async tx => {
      await tx`delete from public.rankings where user_id = ${userId}`
      await tx`insert into public.rankings (user_id, title_id, score, s)
        select ${userId}, * from unnest(${titleIds}::bigint[], ${scores}::real[], ${sums}::float8[])`
      await tx`insert into public.ranking_runs (user_id, ranked_at, wtw_user_id, titles, ratings, picks)
        values (${userId}, now(), ${wtwUserId}, ${titleIds.length}, ${dna.signals.length}, ${picks.length})
        on conflict (user_id) do update set ranked_at = excluded.ranked_at, wtw_user_id = excluded.wtw_user_id,
          titles = excluded.titles, ratings = excluded.ratings, picks = excluded.picks`
    })
    return json({ ranked: titleIds.length, ratings: dna.signals.length, picks: picks.length })
  } catch (err) {
    console.error('[rank] failed:', err)
    return json({ error: err instanceof Error ? err.message : String(err) }, 500)
  }
})

async function readDna(wtw: SupabaseClient, wtwUserId: string): Promise<DNA> {
  const { data, error } = await wtw.from('users').select('dna').eq('id', wtwUserId)
  if (error) throw new Error(`WTW users: ${error.message}`)
  const dna = data?.[0]?.dna as Partial<DNA> | null | undefined
  const blank = blankDNA()
  return {
    ...blank,
    ...dna,
    signals: Array.isArray(dna?.signals) ? dna.signals : blank.signals,
    strand_a_creative_affinity: dna?.strand_a_creative_affinity ?? blank.strand_a_creative_affinity,
  } as DNA
}

/** The user's this-or-that answers: `duel` events with a choice, every page, as WTW reads them. */
async function readPicks(wtw: SupabaseClient, wtwUserId: string): Promise<unknown[]> {
  const out: unknown[] = []
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await wtw.from('play_events').select('payload')
      .eq('user_id', wtwUserId).eq('kind', 'duel').not('payload->>chosen', 'is', null)
      .order('id').range(from, from + PAGE - 1)
    if (error) throw new Error(`WTW play_events: ${error.message}`)
    for (const r of data ?? []) out.push(r.payload)
    if (!data || data.length < PAGE) return out
  }
}

/** WTW taste vectors of the titles the training needs (rated or picked), current version only. */
async function readWtwVectors(wtw: SupabaseClient, ids: string[]) {
  const results = await inChunks(ids, chunk => wtw.from('titles').select('tmdb_id, type, taste_vec')
    .in('tmdb_id', chunk).eq('taste_version', TASTE_FEATURE_VERSION).not('taste_vec', 'is', null))
  return results.flatMap(({ data, error }) => {
    if (error) throw new Error(`WTW titles: ${error.message}`)
    return data ?? []
  })
}

async function readLineage(wtw: SupabaseClient, personIds: string[]): Promise<LineageRecord[]> {
  const results = await inChunks(personIds, chunk => wtw.from(LINEAGE_TABLE).select(LINEAGE_COLUMNS).in('tmdb_person_id', chunk))
  return results.flatMap(({ data, error }) => {
    if (error) throw new Error(`WTW ${LINEAGE_TABLE}: ${error.message}`)
    return (data ?? []) as unknown as LineageRecord[]
  })
}

/** Runs `read` over `ids` in chunks of ID_CHUNK, PARALLEL at a time, keeping the order. */
async function inChunks<T>(ids: string[], read: (chunk: string[]) => PromiseLike<T>): Promise<T[]> {
  const chunks: string[][] = []
  for (let i = 0; i < ids.length; i += ID_CHUNK) chunks.push(ids.slice(i, i + ID_CHUNK))
  const out: T[] = []
  for (let i = 0; i < chunks.length; i += PARALLEL) out.push(...await Promise.all(chunks.slice(i, i + PARALLEL).map(read)))
  return out
}

interface Candidate {
  tmdb_id: string
  type: 'movie' | 'tv'
  tmdb_rating: number | null
  omdb_rating: number | null
  crew: TMDBCrewSnapshot
}

/**
 * The pool: every available title WTW knows, once per WTW title (the copies
 * of a title share one row in the pool and one score), with the vectors of
 * the current taste version.
 */
async function readCandidates() {
  const rows = await sql`
    select id, kind, tmdb_id, wtw_crew, wtw_tmdb_rating, wtw_omdb_rating, wtw_taste_vec, wtw_taste_version
    from public.titles where available and wtw_title_id is not null and tmdb_id is not null`
  const pool: Candidate[] = []
  const idsByKey = new Map<string, number[]>()
  const vecs = new Map<string, number[]>()
  const emptyCrew: TMDBCrewSnapshot = { directors: [], writers: [], cinematographers: [], cast: [] }
  for (const r of rows) {
    const t: Candidate = {
      tmdb_id: String(r.tmdb_id),
      type: r.kind === 'movie' ? 'movie' : 'tv',
      tmdb_rating: r.wtw_tmdb_rating,
      omdb_rating: r.wtw_omdb_rating,
      crew: r.wtw_crew ?? emptyCrew,
    }
    const key = vecKey(t)
    const ids = idsByKey.get(key)
    if (ids) {
      ids.push(Number(r.id))
      continue
    }
    idsByKey.set(key, [Number(r.id)])
    pool.push(t)
    // A null version is unusable, not version 1 (from the review of #50).
    if (r.wtw_taste_vec && r.wtw_taste_version === TASTE_FEATURE_VERSION) vecs.set(key, r.wtw_taste_vec)
  }
  return { pool, idsByKey, vecs }
}
