/**
 * Copies the provider's catalog lists into the WTV database: categories,
 * movies, series and channels. Per-title details (TMDB ids, episodes) are a
 * separate job (P1-3).
 *
 * Every run writes every row. The lists are about 21,000 rows, and one full
 * pass is cheaper to trust than change detection.
 *
 * Run: node --env-file=<env file> src/sync.ts
 */

import { createDb, type Db, type Row } from './db.ts'
import { createXtream, type Category, type Channel, type Title, type Xtream } from './xtream.ts'

/**
 * A list that shrank to under this share of what the database holds is taken
 * for a broken answer, not a real removal: nothing is marked unavailable.
 */
const MIN_SHARE_TO_TRUST = 0.5

export interface SyncReport {
  categories: number
  movies: number
  series: number
  channels: number
  /** Lists that came back too short to trust; their missing rows were left as they were. */
  distrusted: string[]
}

const titleRow = (providerId: number, seenAt: string) => (t: Title): Row => ({
  provider_id: providerId,
  kind: t.kind,
  ext_id: t.extId,
  name: t.name,
  year: t.year,
  plot: t.plot,
  genres: t.genres,
  cast_names: t.castNames,
  director: t.director,
  rating: t.rating,
  poster_url: t.posterUrl,
  // Movie lists carry no backdrop; the details job fills it. Sending null would erase it.
  ...(t.kind === 'series' ? { backdrop_url: t.backdropUrl } : {}),
  trailer: t.trailer,
  runtime_min: t.runtimeMin,
  container_ext: t.containerExt,
  category_ids: t.categoryIds,
  added_at: t.addedAt?.toISOString() ?? null,
  available: true,
  last_seen_at: seenAt,
})

const channelRow = (providerId: number, seenAt: string) => (c: Channel): Row => ({
  provider_id: providerId,
  ext_id: c.extId,
  name: c.name,
  num: c.num,
  logo_url: c.logoUrl,
  epg_channel_id: c.epgChannelId,
  archive_days: c.archiveDays,
  is_radio: c.isRadio,
  category_ids: c.categoryIds,
  available: true,
  last_seen_at: seenAt,
})

const categoryRow = (providerId: number) => (c: Category): Row => ({
  provider_id: providerId,
  kind: c.kind,
  ext_id: c.extId,
  name: c.name,
  position: c.position,
})

export async function syncCatalog(xtream: Xtream, db: Db, providerName: string, now = new Date()): Promise<SyncReport> {
  await xtream.signIn()
  const provider = await db.upsertOne<{ id: number }>('providers', 'name', { name: providerName, kind: 'xtream' })
  const seenAt = now.toISOString()
  const distrusted: string[] = []

  /** Writes one list, then marks what the provider no longer lists. */
  async function replace(label: string, table: string, onConflict: string, scope: string, rows: Row[]): Promise<void> {
    const before = await db.count(table, `${scope}&available=is.true`)
    await db.upsert(table, onConflict, rows)
    if (rows.length < before * MIN_SHARE_TO_TRUST) distrusted.push(label)
    else await db.update(table, `${scope}&available=is.true&last_seen_at=lt.${encodeURIComponent(seenAt)}`, { available: false })
  }

  const byProvider = `provider_id=eq.${provider.id}`

  const categories = (await Promise.all((['movie', 'series', 'live'] as const).map(kind => xtream.categories(kind)))).flat()
  await db.upsert('categories', 'provider_id,kind,ext_id', categories.map(categoryRow(provider.id)))
  // Categories hold no user data, so stale ones are deleted. An empty list is never trusted.
  for (const kind of ['movie', 'series', 'live'] as const) {
    const kept = categories.filter(c => c.kind === kind).map(c => c.extId)
    if (kept.length > 0) await db.remove('categories', `${byProvider}&kind=eq.${kind}&ext_id=not.in.(${kept.join(',')})`)
  }

  const movies = await xtream.movies()
  await replace('movies', 'titles', 'provider_id,kind,ext_id', `${byProvider}&kind=eq.movie`, movies.map(titleRow(provider.id, seenAt)))

  const series = await xtream.series()
  await replace('series', 'titles', 'provider_id,kind,ext_id', `${byProvider}&kind=eq.series`, series.map(titleRow(provider.id, seenAt)))

  const channels = await xtream.channels()
  await replace('channels', 'channels', 'provider_id,ext_id', byProvider, channels.map(channelRow(provider.id, seenAt)))

  return { categories: categories.length, movies: movies.length, series: series.length, channels: channels.length, distrusted }
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
  const db = createDb({ url: env('SUPABASE_URL'), secretKey: env('SUPABASE_SECRET_KEY') })
  const report = await syncCatalog(xtream, db, 'prov1')
  console.log(JSON.stringify(report))
  if (report.distrusted.length > 0) process.exitCode = 1
}
