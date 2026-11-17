/**
 * The few TMDB calls WTV needs. Answers are typed only as far as they are used.
 */

export class TmdbError extends Error {}

export interface TmdbSeries {
  id: number
  seasons: { id: number }[]
}

export interface TmdbCredit {
  id: number
  first_air_date?: string
}

type Query = Record<string, string>

const BASE = 'https://api.themoviedb.org/3/'

/** TMDB answers 429 when called too fast; it is retried after a pause. */
const RETRIES = 4
/** A 5xx or a dropped connection is retried once. */
const TRANSIENT_RETRIES = 1
/** Longest pause honoured from `retry-after`. */
const MAX_PAUSE_MS = 30_000

export function createTmdb(apiKey: string, fetchFn: typeof fetch = fetch, sleep = (ms: number) => new Promise(r => setTimeout(r, ms))) {
  async function get<T>(path: string, query: Query = {}): Promise<T> {
    const url = new URL(path, BASE)
    url.searchParams.set('api_key', apiKey)
    for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v)

    let transient = 0
    for (let attempt = 0; ; attempt++) {
      let res: Response
      try {
        res = await fetchFn(url, { signal: AbortSignal.timeout(20_000) })
      } catch (err) {
        if (transient++ < TRANSIENT_RETRIES) {
          await sleep(1000)
          continue
        }
        // The URL carries the key: it never goes into an error.
        throw new TmdbError(`${path}: request failed (${err instanceof Error ? err.name : 'unknown'})`)
      }
      if (res.status === 429 && attempt < RETRIES) {
        await res.body?.cancel()
        await sleep(Math.min(MAX_PAUSE_MS, 1000 * (Number(res.headers.get('retry-after')) || 2 ** attempt)))
        continue
      }
      if (res.status >= 500 && transient++ < TRANSIENT_RETRIES) {
        await res.body?.cancel()
        await sleep(1000)
        continue
      }
      if (!res.ok) {
        await res.body?.cancel()
        throw new TmdbError(`${path}: HTTP ${res.status}`)
      }
      return (await res.json()) as T
    }
  }

  const ids = (results: { id: number }[], max: number) => results.slice(0, max).map(r => r.id)

  return {
    /** Ids of the best TV matches for a title, in any language TMDB knows. */
    async searchSeries(name: string, year: number | null, max = 5): Promise<number[]> {
      const query: Query = { query: name }
      if (year !== null) query.first_air_date_year = String(year)
      return ids((await get<{ results: { id: number }[] }>('search/tv', query)).results, max)
    },

    async series(id: number): Promise<TmdbSeries> {
      return get<TmdbSeries>(`tv/${id}`)
    },

    async searchPerson(name: string): Promise<number | null> {
      return (await get<{ results: { id: number }[] }>('search/person', { query: name })).results[0]?.id ?? null
    },

    async personSeries(personId: number): Promise<TmdbCredit[]> {
      return (await get<{ cast: TmdbCredit[] }>(`person/${personId}/tv_credits`)).cast
    },
  }
}

export type Tmdb = ReturnType<typeof createTmdb>
