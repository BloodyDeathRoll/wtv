import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { Db, Row } from './db.ts'
import { syncCatalog } from './sync.ts'
import type { Category, Channel, Title, Xtream } from './xtream.ts'

const title = (kind: 'movie' | 'series', extId: number): Title => ({
  kind,
  extId,
  name: `${kind} ${extId}`,
  year: 2020,
  plot: null,
  genres: null,
  castNames: null,
  director: null,
  rating: null,
  posterUrl: null,
  backdropUrl: kind === 'series' ? 'https://img/b.jpg' : null,
  trailer: null,
  runtimeMin: null,
  containerExt: kind === 'movie' ? 'mkv' : null,
  categoryIds: [1],
  addedAt: new Date('2026-01-02T03:04:05Z'),
})

const channel = (extId: number): Channel => ({
  extId,
  name: `ch ${extId}`,
  num: extId,
  logoUrl: null,
  epgChannelId: null,
  archiveDays: 0,
  isRadio: false,
  categoryIds: [3],
})

function fakeXtream(lists: { movies: Title[]; series: Title[]; channels: Channel[]; categories: Category[] }): Xtream {
  return {
    signIn: async () => ({ maxConnections: 3, expiresAt: null }),
    categories: async kind => lists.categories.filter(c => c.kind === kind),
    movies: async () => lists.movies,
    series: async () => lists.series,
    channels: async () => lists.channels,
    movieInfo: async () => assert.fail('not used by the list sync'),
    seriesInfo: async () => assert.fail('not used by the list sync'),
    programmes: async () => assert.fail('not used by the list sync'),
  }
}

/** Records every call. `available` answers the row counts, by `table + kind`. */
function fakeDb(available: Record<string, number> = {}) {
  const calls: { op: string; table: string; filter?: string; rows?: Row[]; values?: Row }[] = []
  const db: Db = {
    upsert: async (table, _onConflict, rows) => void calls.push({ op: 'upsert', table, rows }),
    upsertOne: async <T extends Row>(table: string, _onConflict: string, row: Row) => {
      calls.push({ op: 'upsertOne', table, rows: [row] })
      return { id: 7, ...row } as unknown as T
    },
    count: async (table, filter) => {
      const kind = /kind=eq\.(\w+)/.exec(filter)?.[1] ?? ''
      return available[table + kind] ?? 0
    },
    update: async (table, filter, values) => void calls.push({ op: 'update', table, filter, values }),
    remove: async (table, filter) => void calls.push({ op: 'remove', table, filter }),
  }
  return { db, calls }
}

const now = new Date('2026-11-17T12:00:00.000Z')
const lists = {
  categories: [
    { kind: 'movie', extId: 118, name: 'סרטים', position: 0 },
    { kind: 'live', extId: 1, name: 'ישראל', position: 0 },
    { kind: 'live', extId: 4, name: 'רדיו', position: 1 },
  ] satisfies Category[],
  movies: [title('movie', 1), title('movie', 2)],
  series: [title('series', 10)],
  channels: [channel(100)],
}

test('writes every list under the provider and reports the counts', async () => {
  const { db, calls } = fakeDb()
  const report = await syncCatalog(fakeXtream(lists), db, 'prov1', now)
  assert.deepEqual(report, { categories: 3, movies: 2, series: 1, channels: 1, distrusted: [] })

  assert.deepEqual(calls[0], { op: 'upsertOne', table: 'providers', rows: [{ name: 'prov1', kind: 'xtream' }] })

  const upserts = calls.filter(c => c.op === 'upsert')
  assert.deepEqual(upserts.map(c => [c.table, c.rows?.length]), [
    ['categories', 1],
    ['categories', 0],
    ['categories', 2],
    ['titles', 2],
    ['titles', 1],
    ['channels', 1],
  ])

  const movie = upserts[3]?.rows?.[0]
  assert.deepEqual(movie, {
    provider_id: 7,
    kind: 'movie',
    ext_id: 1,
    name: 'movie 1',
    year: 2020,
    plot: null,
    genres: null,
    cast_names: null,
    director: null,
    rating: null,
    poster_url: null,
    trailer: null,
    runtime_min: null,
    container_ext: 'mkv',
    category_ids: [1],
    added_at: '2026-01-02T03:04:05.000Z',
    available: true,
    last_seen_at: '2026-11-17T12:00:00.000Z',
  })
  // The movie list has no backdrop: the column is left out, so a stored one survives.
  assert.ok(!('backdrop_url' in movie))
  assert.equal(upserts[4]?.rows?.[0]?.backdrop_url, 'https://img/b.jpg')
  assert.equal(upserts[5]?.rows?.[0]?.is_radio, false)
})

test('rows the provider no longer lists are marked unavailable, per list', async () => {
  const { db, calls } = fakeDb({ titlesmovie: 2, titlesseries: 1, channels: 1 })
  await syncCatalog(fakeXtream(lists), db, 'prov1', now)
  const seen = encodeURIComponent('2026-11-17T12:00:00.000Z')
  assert.deepEqual(
    calls.filter(c => c.op === 'update'),
    [
      { op: 'update', table: 'titles', filter: `provider_id=eq.7&kind=eq.movie&available=is.true&last_seen_at=lt.${seen}`, values: { available: false } },
      { op: 'update', table: 'titles', filter: `provider_id=eq.7&kind=eq.series&available=is.true&last_seen_at=lt.${seen}`, values: { available: false } },
      { op: 'update', table: 'channels', filter: `provider_id=eq.7&available=is.true&last_seen_at=lt.${seen}`, values: { available: false } },
    ],
  )
})

test('a list under half its stored size is written but removes nothing', async () => {
  // 5 movies stored, 2 listed: a broken answer, not 3 removals.
  const { db, calls } = fakeDb({ titlesmovie: 5, titlesseries: 2 })
  const report = await syncCatalog(fakeXtream(lists), db, 'prov1', now)
  assert.deepEqual(report.distrusted, [{ list: 'movies', stored: 5, listed: 2 }])
  const updates = calls.filter(c => c.op === 'update').map(c => c.filter)
  assert.equal(updates.some(f => f?.includes('kind=eq.movie')), false)
  // Series: 1 listed of 2 stored is exactly half, which is still trusted.
  assert.equal(updates.some(f => f?.includes('kind=eq.series')), true)
  assert.equal(calls.filter(c => c.op === 'upsert' && c.table === 'titles')[0]?.rows?.length, 2)
})

test('stale categories are deleted, but never on an empty list', async () => {
  const { db, calls } = fakeDb()
  await syncCatalog(fakeXtream(lists), db, 'prov1', now)
  assert.deepEqual(
    calls.filter(c => c.op === 'remove').map(c => c.filter),
    ['provider_id=eq.7&kind=eq.movie&ext_id=not.in.(118)', 'provider_id=eq.7&kind=eq.live&ext_id=not.in.(1,4)'],
  )
})

test('a category list under half its stored size deletes nothing', async () => {
  // 6 live categories stored, 2 listed.
  const { db, calls } = fakeDb({ categorieslive: 6 })
  const report = await syncCatalog(fakeXtream(lists), db, 'prov1', now)
  assert.deepEqual(report.distrusted, [{ list: 'live categories', stored: 6, listed: 2 }])
  assert.deepEqual(calls.filter(c => c.op === 'remove').map(c => c.filter), ['provider_id=eq.7&kind=eq.movie&ext_id=not.in.(118)'])
})

test('a list that fails to load stops the sync before anything is written', async () => {
  const { db, calls } = fakeDb()
  const xtream = { ...fakeXtream(lists), channels: async () => Promise.reject(new Error('get_live_streams: HTTP 503')) }
  await assert.rejects(syncCatalog(xtream, db, 'prov1', now), /503/)
  assert.deepEqual(calls, [])
})

test('a failed sign-in stops the sync before anything is written', async () => {
  const { db, calls } = fakeDb()
  const xtream = { ...fakeXtream(lists), signIn: async () => Promise.reject(new Error('sign-in: the account is not active')) }
  await assert.rejects(syncCatalog(xtream, db, 'prov1', now), /not active/)
  assert.deepEqual(calls, [])
})
