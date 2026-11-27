/**
 * The few TMDB calls WTV needs. Answers are typed only as far as they are used.
 */

export class TmdbError extends Error {}

export interface TmdbSeries {
  id: number
  name?: string
  original_name?: string
  first_air_date?: string
  last_air_date?: string
  seasons: { id: number; season_number?: number; episode_count?: number }[]
  translations?: { translations: Translation[] }
}

export interface TmdbCredit {
  id: number
  first_air_date?: string
}

interface Translation {
  iso_639_1: string
  data: { title?: string; name?: string; overview?: string }
}

export interface TmdbCastMember {
  id: number
  name: string
  profile_path: string | null
  order: number
  /** Movies. */
  character?: string
  /** Series (aggregate credits). */
  roles?: { character: string }[]
}

interface Common {
  id: number
  overview: string
  genres: { id: number; name: string }[]
  vote_average: number
  original_language: string
  poster_path: string | null
  backdrop_path: string | null
  translations: { translations: Translation[] }
}

export interface TmdbMovieFull extends Common {
  title: string
  original_title?: string
  release_date?: string
  runtime: number | null
  credits: { cast: TmdbCastMember[] }
  release_dates: { results: { iso_3166_1: string; release_dates: { certification: string }[] }[] }
}

export interface TmdbSeriesFull extends Common {
  name: string
  episode_run_time: number[]
  aggregate_credits: { cast: TmdbCastMember[] }
  content_ratings: { results: { iso_3166_1: string; rating: string }[] }
}

export interface TmdbSeason {
  episodes: { episode_number: number; name: string; overview: string; still_path: string | null }[]
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
    const found = await getOrMissing<T>(path, query)
    if (found === null) throw new TmdbError(`${path}: HTTP 404`)
    return found
  }

  /** Null when TMDB answers 404. */
  async function getOrMissing<T>(path: string, query: Query = {}): Promise<T | null> {
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
      if (res.status === 404) {
        await res.body?.cancel()
        return null
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

    /** Ids of the best movie matches for a title, in any language TMDB knows. */
    async searchMovie(name: string, year: number | null, max = 5): Promise<number[]> {
      const query: Query = { query: name }
      if (year !== null) query.year = String(year)
      return ids((await get<{ results: { id: number }[] }>('search/movie', query)).results, max)
    },

    async series(id: number): Promise<TmdbSeries> {
      return get<TmdbSeries>(`tv/${id}`, { append_to_response: 'translations' })
    },

    async searchPerson(name: string): Promise<number | null> {
      return (await get<{ results: { id: number }[] }>('search/person', { query: name })).results[0]?.id ?? null
    },

    async personSeries(personId: number): Promise<TmdbCredit[]> {
      return (await get<{ cast: TmdbCredit[] }>(`person/${personId}/tv_credits`)).cast
    },

    /** English details, cast, release certifications and translations; null if TMDB has no such movie. */
    async movieFull(id: number): Promise<TmdbMovieFull | null> {
      return getOrMissing<TmdbMovieFull>(`movie/${id}`, { append_to_response: 'credits,release_dates,translations' })
    },

    async seriesFull(id: number): Promise<TmdbSeriesFull | null> {
      return getOrMissing<TmdbSeriesFull>(`tv/${id}`, { append_to_response: 'aggregate_credits,content_ratings,translations' })
    },

    /** One season's episodes in `language` (e.g. "en-US", "he-IL"); null if TMDB has no such season. */
    async season(seriesId: number, season: number, language: string): Promise<TmdbSeason | null> {
      return getOrMissing<TmdbSeason>(`tv/${seriesId}/season/${season}`, { language })
    },

    async genres(kind: 'movie' | 'tv', language: string): Promise<{ id: number; name: string }[]> {
      return (await get<{ genres: { id: number; name: string }[] }>(`genre/${kind}/list`, { language })).genres
    },
  }
}

export type Tmdb = ReturnType<typeof createTmdb>
