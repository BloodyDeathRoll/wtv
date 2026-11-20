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

import { categoryNames } from './category-names.ts'
import { liveGroups, liveNames } from './live-groups.ts'
import { createDb, type Db, type Row } from './db.ts'
import { refreshGroupsOrNull } from './groups.ts'
import { createXtream, type Category, type Channel, type Title, type Xtream } from './xtream.ts'

/**
 * A list that shrank to under this share of what the database holds is taken
 * for a broken answer, not a real removal: nothing is removed or marked
 * unavailable. A real removal that big keeps failing every run until someone
 * checks it and marks the rows by hand; that is on purpose.
 */
const MIN_SHARE_TO_TRUST = 0.5

/**
 * Provider categories left out of WTV, by English name: the user does not
 * watch them, and Turkish series alone were about a fifth of all episodes.
 * Their titles are not stored, and titles already stored are deleted (their
 * episodes and progress go with them).
 */
const SKIPPED_CATEGORIES = new Set(['Turkish Series'])

export interface Distrusted {
  list: string
  stored: number
  listed: number
}

export interface SyncReport {
  categories: number
  movies: number
  series: number
  channels: number
  /** Lists that came back too short to trust; their missing rows were left as they were. */
  distrusted: Distrusted[]
  /** Category names with no English name: add them to `category-names.ts`. */
  untranslated: string[]
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

const categoryRow = (providerId: number) => (c: Category): Row => {
  const names = categoryNames(c.name)
  const { en, he } = c.kind === 'live' ? liveNames(names) : names
  return {
    provider_id: providerId,
    kind: c.kind,
    ext_id: c.extId,
    name: c.name,
    name_en: en,
    name_he: he,
    position: c.position,
  }
}

export async function syncCatalog(xtream: Xtream, db: Db, providerName: string, now = new Date()): Promise<SyncReport> {
  await xtream.signIn()
  // Everything is fetched before anything is written: a list that fails
  // leaves the database as it was.
  const kinds = ['movie', 'series', 'live'] as const
  const allCategoryLists = await Promise.all(kinds.map(kind => xtream.categories(kind)))
  const isSkipped = (c: Category) => SKIPPED_CATEGORIES.has(categoryNames(c.name).en ?? '')
  const skipped = allCategoryLists.flat().filter(isSkipped)
  const categoryLists = allCategoryLists.map(list => list.filter(c => !isSkipped(c)))
  const kept = (t: Title) => !skipped.some(c => c.kind === t.kind && t.categoryIds.includes(c.extId))
  const movies = (await xtream.movies()).filter(kept)
  const series = (await xtream.series()).filter(kept)
  // Live TV has its own groups: see live-groups.ts.
  const liveAt = kinds.indexOf('live')
  const grouped = liveGroups(categoryLists[liveAt]!, await xtream.channels(), name => categoryNames(name).en)
  categoryLists[liveAt] = grouped.categories
  const channels = grouped.channels

  const provider = await db.upsertOne<{ id: number }>('providers', 'name', { name: providerName, kind: 'xtream' })
  const byProvider = `provider_id=eq.${provider.id}`
  const seenAt = now.toISOString()
  const distrusted: Distrusted[] = []

  /** False, and noted in the report, when the list is too short to trust. */
  function trusted(list: string, stored: number, listed: number): boolean {
    if (listed >= stored * MIN_SHARE_TO_TRUST) return true
    distrusted.push({ list, stored, listed })
    return false
  }

  /**
   * Writes one list, then marks what the provider no longer lists. The rows
   * must be unique by key: one upsert cannot touch the same row twice.
   * `xtream.ts` merges the provider's repeats.
   */
  async function replace(list: string, table: string, onConflict: string, scope: string, rows: Row[]): Promise<void> {
    const stored = await db.count(table, `${scope}&available=is.true`)
    await db.upsert(table, onConflict, rows)
    if (trusted(list, stored, rows.length)) {
      await db.update(table, `${scope}&available=is.true&last_seen_at=lt.${encodeURIComponent(seenAt)}`, { available: false })
    }
  }

  // Categories hold no user data, so stale ones are deleted.
  for (const [i, kind] of kinds.entries()) {
    const list = categoryLists[i] ?? []
    const scope = `${byProvider}&kind=eq.${kind}`
    const stored = await db.count('categories', scope)
    await db.upsert('categories', 'provider_id,kind,ext_id', list.map(categoryRow(provider.id)))
    // An empty list against stored categories is reported as distrusted;
    // empty against empty has nothing to delete (and `not.in.()` is invalid).
    if (trusted(`${kind} categories`, stored, list.length) && list.length > 0) {
      await db.remove('categories', `${scope}&ext_id=not.in.(${list.map(c => c.extId).join(',')})`)
    }
  }

  // Before the lists are written, so the share check compares against what stays.
  for (const c of skipped) {
    await db.remove('titles', `${byProvider}&kind=eq.${c.kind}&category_ids=ov.{${c.extId}}`)
  }

  await replace('movies', 'titles', 'provider_id,kind,ext_id', `${byProvider}&kind=eq.movie`, movies.map(titleRow(provider.id, seenAt)))
  await replace('series', 'titles', 'provider_id,kind,ext_id', `${byProvider}&kind=eq.series`, series.map(titleRow(provider.id, seenAt)))
  await replace('channels', 'channels', 'provider_id,ext_id', byProvider, channels.map(channelRow(provider.id, seenAt)))

  const untranslated = [...new Set(categoryLists.flat().map(c => c.name).filter(name => categoryNames(name).en === null))]
  return { categories: categoryLists.flat().length, movies: movies.length, series: series.length, channels: channels.length, distrusted, untranslated }
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
  const report = await syncCatalog(xtream, db, 'prov1')
  // New titles and category changes reach the cards.
  console.log(JSON.stringify({ ...report, regrouped: await refreshGroupsOrNull(db, 'prov1') }))
  if (report.distrusted.length > 0) process.exitCode = 1
}
