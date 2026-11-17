/**
 * Client for an Xtream provider's `player_api.php`.
 *
 * The provider's JSON is loose: the same field is a string in one row, a
 * number in the next, and null or "" when unknown; a title in two categories
 * is listed twice. Everything returned here is cleaned and typed, in the
 * shape the WTV database stores.
 */

export interface XtreamConfig {
  /** Base URL, e.g. `https://host:443`. Without a scheme, https is used. */
  server: string
  user: string
  password: string
}

export type CategoryKind = 'movie' | 'series' | 'live'

export interface Category {
  kind: CategoryKind
  extId: number
  name: string
  /** Place in the provider's list. */
  position: number
}

export interface Title {
  kind: 'movie' | 'series'
  extId: number
  name: string
  year: number | null
  plot: string | null
  genres: string | null
  castNames: string | null
  director: string | null
  rating: number | null
  posterUrl: string | null
  backdropUrl: string | null
  /** YouTube id. */
  trailer: string | null
  runtimeMin: number | null
  /** Movies only. */
  containerExt: string | null
  categoryIds: number[]
  /**
   * Movies: when the provider added it. Series: when it last changed, which
   * also moves when an episode is added.
   */
  addedAt: Date | null
}

export interface Channel {
  extId: number
  name: string
  num: number | null
  logoUrl: string | null
  epgChannelId: string | null
  /** Catch-up window in days; 0 = none. */
  archiveDays: number
  isRadio: boolean
  categoryIds: number[]
}

export interface MovieInfo {
  tmdbId: number | null
  durationSecs: number | null
  backdropUrl: string | null
}

export interface Episode {
  extId: number
  season: number
  episode: number
  name: string | null
  plot: string | null
  durationSecs: number | null
  imageUrl: string | null
  containerExt: string | null
  addedAt: Date | null
}

export interface SeriesInfo {
  /**
   * TMDB ids of the seasons, by season number. The provider gives no TMDB id
   * for the series itself; a season id confirms a match found by title.
   */
  tmdbSeasonIds: Record<number, number>
  episodes: Episode[]
}

export interface Programme {
  title: string
  description: string | null
  start: Date
  end: Date
}

export class XtreamError extends Error {}

/** The provider rejects unknown clients. This is what Android player apps send. */
const USER_AGENT = 'okhttp/4.12.0'

type Raw = Record<string, unknown>
type Fetch = typeof fetch

// ── Cleaning helpers ───────────────────────────────────────────

const isRaw = (v: unknown): v is Raw => typeof v === 'object' && v !== null && !Array.isArray(v)

function rows(v: unknown, what: string): Raw[] {
  if (!Array.isArray(v)) throw new XtreamError(`${what}: expected a list`)
  return v.filter(isRaw)
}

/** A trimmed string, or null for null, "" and non-strings. */
function text(v: unknown): string | null {
  if (typeof v === 'number') return String(v)
  if (typeof v !== 'string') return null
  const t = v.trim()
  return t === '' ? null : t
}

/** A finite number from a number or a plain decimal string ("12", "5.3"), else null. */
function num(v: unknown): number | null {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null
  if (typeof v !== 'string' || !/^-?\d+(\.\d+)?$/.test(v.trim())) return null
  return Number(v)
}

function int(v: unknown): number | null {
  const n = num(v)
  return n === null ? null : Math.trunc(n)
}

/** A whole number above zero, else null. The provider writes "unknown" as 0. */
function positive(v: unknown): number | null {
  const n = int(v)
  return n !== null && n > 0 ? n : null
}

/** A number above zero, else null. */
function aboveZero(v: unknown): number | null {
  const n = num(v)
  return n !== null && n > 0 ? n : null
}

/** Unix seconds (number or string) to a Date. */
function unixDate(v: unknown): Date | null {
  const n = positive(v)
  return n === null ? null : new Date(n * 1000)
}

function ids(v: unknown): number[] {
  if (!Array.isArray(v)) return []
  return v.map(int).filter((n): n is number => n !== null)
}

/** `backdrop_path` is a list in the lists and sometimes a bare string. */
function firstUrl(v: unknown): string | null {
  return text(Array.isArray(v) ? v[0] : v)
}

function year(v: unknown): number | null {
  const n = int(v)
  return n !== null && n >= 1880 && n <= 2100 ? n : null
}

function categoryIds(r: Raw): number[] {
  const list = ids(r.category_ids)
  if (list.length > 0) return list
  const one = int(r.category_id)
  return one === null ? [] : [one]
}

/**
 * Keeps the first row per id and joins the category ids of its repeats.
 * Repeats differ only in category and list position (checked on the whole
 * provider-1 catalog, 2026-11-17).
 */
function mergeRepeats<T extends { extId: number; categoryIds: number[] }>(items: T[]): T[] {
  const byId = new Map<number, T>()
  for (const item of items) {
    const seen = byId.get(item.extId)
    if (!seen) byId.set(item.extId, item)
    else seen.categoryIds = [...new Set([...seen.categoryIds, ...item.categoryIds])]
  }
  return [...byId.values()]
}

// ── Row mappers (exported for tests) ───────────────────────────

export function toCategory(kind: CategoryKind, r: Raw, position: number): Category | null {
  const extId = int(r.category_id)
  const name = text(r.category_name)
  return extId === null || name === null ? null : { kind, extId, name, position }
}

export function toMovie(r: Raw): Title | null {
  const extId = int(r.stream_id)
  // `name` is "Title (Year)"; `title` is the bare title.
  const name = text(r.title) ?? text(r.name)
  if (extId === null || name === null) return null
  return {
    kind: 'movie',
    extId,
    name,
    year: year(r.year),
    plot: text(r.plot),
    genres: text(r.genre),
    castNames: text(r.cast),
    director: text(r.director),
    rating: aboveZero(r.rating),
    posterUrl: text(r.stream_icon),
    backdropUrl: null,
    trailer: text(r.youtube_trailer),
    runtimeMin: positive(r.episode_run_time),
    containerExt: text(r.container_extension)?.toLowerCase() ?? null,
    categoryIds: categoryIds(r),
    addedAt: unixDate(r.added),
  }
}

export function toSeries(r: Raw): Title | null {
  const extId = int(r.series_id)
  const name = text(r.title) ?? text(r.name)
  if (extId === null || name === null) return null
  return {
    kind: 'series',
    extId,
    name,
    year: year(r.year),
    plot: text(r.plot),
    genres: text(r.genre),
    castNames: text(r.cast),
    director: text(r.director),
    rating: aboveZero(r.rating),
    posterUrl: text(r.cover),
    backdropUrl: firstUrl(r.backdrop_path),
    trailer: text(r.youtube_trailer),
    runtimeMin: positive(r.episode_run_time),
    containerExt: null,
    categoryIds: categoryIds(r),
    addedAt: unixDate(r.last_modified),
  }
}

export function toChannel(r: Raw): Channel | null {
  const extId = int(r.stream_id)
  const name = text(r.name)
  if (extId === null || name === null) return null
  return {
    extId,
    name,
    num: int(r.num),
    logoUrl: text(r.stream_icon),
    epgChannelId: text(r.epg_channel_id),
    archiveDays: int(r.tv_archive) === 1 ? (positive(r.tv_archive_duration) ?? 0) : 0,
    isRadio: r.stream_type === 'radio_streams',
    categoryIds: categoryIds(r),
  }
}

export function toMovieInfo(body: unknown): MovieInfo {
  const info = isRaw(body) && isRaw(body.info) ? body.info : {}
  return {
    tmdbId: positive(info.tmdb_id),
    durationSecs: positive(info.duration_secs),
    backdropUrl: firstUrl(info.backdrop_path),
  }
}

export function toSeriesInfo(body: unknown): SeriesInfo {
  const out: SeriesInfo = { tmdbSeasonIds: {}, episodes: [] }
  if (!isRaw(body)) return out

  if (Array.isArray(body.seasons)) {
    for (const s of body.seasons.filter(isRaw)) {
      const number = int(s.season_number)
      const id = positive(s.id)
      if (number !== null && id !== null) out.tmdbSeasonIds[number] = id
    }
  }

  // `episodes` is an object keyed by season number, or a list of lists.
  const groups: unknown[] = isRaw(body.episodes)
    ? Object.values(body.episodes)
    : Array.isArray(body.episodes)
      ? body.episodes
      : []
  for (const group of groups) {
    if (!Array.isArray(group)) continue
    for (const e of group.filter(isRaw)) {
      const info = isRaw(e.info) ? e.info : {}
      const extId = int(e.id)
      const season = int(e.season) ?? int(info.season)
      const episode = int(e.episode_num)
      if (extId === null || season === null || episode === null) continue
      out.episodes.push({
        extId,
        season,
        episode,
        name: text(e.title),
        plot: text(info.plot),
        durationSecs: positive(info.duration_secs),
        imageUrl: text(info.movie_image),
        containerExt: text(e.container_extension)?.toLowerCase() ?? null,
        addedAt: unixDate(e.added),
      })
    }
  }
  return out
}

/** Programme titles and descriptions arrive base64-encoded. */
export function toProgrammes(body: unknown): Programme[] {
  if (!isRaw(body) || !Array.isArray(body.epg_listings)) return []
  const unpad = (s: string) => s.replace(/=+$/, '')
  const utf8 = new TextDecoder('utf-8', { fatal: true })
  const decode = (v: unknown) => {
    const s = text(v)
    if (s === null) return null
    // Buffer never rejects bad base64. Text that does not survive the round
    // trip, or does not decode to valid UTF-8 ("News" passes the round trip),
    // was sent plain.
    const bytes = Buffer.from(s, 'base64')
    if (unpad(bytes.toString('base64')) !== unpad(s)) return s
    try {
      return text(utf8.decode(bytes))
    } catch {
      return s
    }
  }
  const out: Programme[] = []
  for (const p of body.epg_listings.filter(isRaw)) {
    const title = decode(p.title)
    const start = unixDate(p.start_timestamp)
    const end = unixDate(p.stop_timestamp)
    if (title === null || start === null || end === null) continue
    out.push({ title, description: decode(p.description), start, end })
  }
  return out
}

// ── Client ─────────────────────────────────────────────────────

const LIST_ACTION = { movie: 'vod', series: 'series', live: 'live' } as const

/** A stalled provider must not hang the sync. The full lists are tens of MB. */
const TIMEOUT_MS = 30_000
const LIST_TIMEOUT_MS = 180_000

/** A short label such as `ECONNRESET` or `TimeoutError`; never the error itself, which may hold the URL. */
function failureCode(err: unknown): string {
  if (!(err instanceof Error)) return 'unknown'
  const code = (err.cause as { code?: unknown } | undefined)?.code
  return typeof code === 'string' ? code : err.name
}

export function createXtream(config: XtreamConfig, fetchFn: Fetch = fetch) {
  async function call(
    action?: string,
    params: Record<string, string | number> = {},
    timeoutMs = TIMEOUT_MS,
  ): Promise<unknown> {
    const url = new URL('/player_api.php', /^https?:\/\//i.test(config.server) ? config.server : `https://${config.server}`)
    url.searchParams.set('username', config.user)
    url.searchParams.set('password', config.password)
    if (action) url.searchParams.set('action', action)
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, String(v))

    // The URL carries the credentials. It never goes into an error (so no
    // `cause` either), and a redirect is refused rather than followed.
    const what = action ?? 'sign-in'
    let res: Response
    try {
      res = await fetchFn(url, {
        headers: { 'User-Agent': USER_AGENT },
        redirect: 'error',
        signal: AbortSignal.timeout(timeoutMs),
      })
    } catch (err) {
      throw new XtreamError(`${what}: request failed (${failureCode(err)})`)
    }
    if (!res.ok) {
      // Free the connection: the sync makes thousands of calls.
      await res.body?.cancel()
      throw new XtreamError(`${what}: HTTP ${res.status}`)
    }
    try {
      return await res.json()
    } catch (err) {
      // The timeout also covers reading the body.
      if (err instanceof Error && err.name === 'TimeoutError') throw new XtreamError(`${what}: request failed (TimeoutError)`)
      throw new XtreamError(`${what}: the answer is not JSON`)
    }
  }

  const keep = <T>(list: (T | null)[]) => list.filter((x): x is T => x !== null)

  return {
    /** Throws unless the account is active. */
    async signIn(): Promise<{ maxConnections: number | null; expiresAt: Date | null }> {
      const body = await call()
      const user = isRaw(body) && isRaw(body.user_info) ? body.user_info : {}
      if (user.status !== 'Active') throw new XtreamError('sign-in: the account is not active')
      return { maxConnections: int(user.max_connections), expiresAt: unixDate(user.exp_date) }
    },

    async categories(kind: CategoryKind): Promise<Category[]> {
      const list = rows(await call(`get_${LIST_ACTION[kind]}_categories`), 'categories')
      return keep(list.map((r, i) => toCategory(kind, r, i)))
    },

    async movies(): Promise<Title[]> {
      return mergeRepeats(keep(rows(await call('get_vod_streams', {}, LIST_TIMEOUT_MS), 'movies').map(toMovie)))
    },

    async series(): Promise<Title[]> {
      return mergeRepeats(keep(rows(await call('get_series', {}, LIST_TIMEOUT_MS), 'series').map(toSeries)))
    },

    async channels(): Promise<Channel[]> {
      return mergeRepeats(keep(rows(await call('get_live_streams', {}, LIST_TIMEOUT_MS), 'channels').map(toChannel)))
    },

    async movieInfo(extId: number): Promise<MovieInfo> {
      return toMovieInfo(await call('get_vod_info', { vod_id: extId }))
    },

    async seriesInfo(extId: number): Promise<SeriesInfo> {
      return toSeriesInfo(await call('get_series_info', { series_id: extId }))
    },

    /** What is on now and next on one channel. */
    async programmes(channelExtId: number, limit = 4): Promise<Programme[]> {
      return toProgrammes(await call('get_short_epg', { stream_id: channelExtId, limit }))
    },
  }
}

export type Xtream = ReturnType<typeof createXtream>
