import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { Db, Row } from './db.ts'
import { fetchDetails, matchMovie, matchSeries, nameKey, titleNames, type Pending } from './details.ts'
import type { Tmdb, TmdbCredit, TmdbMovieFull, TmdbSeries } from './tmdb.ts'
import type { Xtream } from './xtream.ts'

/** A TMDB with fixed answers; records which series were looked up. */
function fakeTmdb(data: {
  search?: Record<string, number[]>
  seasons?: Record<number, number[]>
  people?: Record<string, number>
  credits?: Record<number, TmdbCredit[]>
  /** Name, years and seasons of a series, for matching without season ids. */
  shows?: Record<number, Omit<TmdbSeries, 'id'>>
  /** Movie search answers ("name|year") and movies by id: title, original title, Hebrew title, year, minutes. */
  movieSearch?: Record<string, number[]>
  movies?: Record<number, { title: string; original?: string; hebrew?: string; year?: number; minutes?: number }>
}) {
  const looked: number[] = []
  const tmdb: Tmdb = {
    searchSeries: async (name, year) => data.search?.[`${name}|${year ?? ''}`] ?? [],
    series: async id => {
      looked.push(id)
      return data.shows?.[id] ? { id, ...data.shows[id] } : { id, seasons: (data.seasons?.[id] ?? []).map(s => ({ id: s })) }
    },
    searchPerson: async name => data.people?.[name] ?? null,
    personSeries: async id => data.credits?.[id] ?? [],
    searchMovie: async (name, year) => data.movieSearch?.[`${name}|${year ?? ''}`] ?? [],
    movieFull: async id => {
      looked.push(id)
      const m = data.movies?.[id]
      if (!m) return null
      return {
        id,
        title: m.title,
        original_title: m.original ?? m.title,
        release_date: m.year ? `${m.year}-05-01` : '',
        runtime: m.minutes ?? null,
        translations: { translations: m.hebrew ? [{ iso_639_1: 'he', data: { title: m.hebrew } }] : [] },
      } as TmdbMovieFull
    },
    seriesFull: async () => assert.fail('not used by details'),
    season: async () => assert.fail('not used by details'),
    genres: async () => assert.fail('not used by details'),
  }
  return { tmdb, looked }
}

const doctorX = { name: 'דוקטור X', year: 2026, castNames: 'Kim Ji-won, Lee Jung-eun' }

test('match: a title hit counts only when it has one of the provider season ids', async () => {
  const { tmdb } = fakeTmdb({ search: { 'דוקטור X|2026': [11, 22] }, seasons: { 11: [999], 22: [460408] } })
  assert.equal(await matchSeries(tmdb, doctorX, [460408]), 22)
})

test('match: falls back to any year, then to the cast, nearest year first', async () => {
  const anyYear = fakeTmdb({ search: { 'דוקטור X|': [33] }, seasons: { 33: [460408] } })
  assert.equal(await matchSeries(anyYear.tmdb, doctorX, [460408]), 33)

  const byCast = fakeTmdb({
    people: { 'Lee Jung-eun': 5 },
    credits: { 5: [{ id: 70, first_air_date: '2010-01-01' }, { id: 71, first_air_date: '2026-03-01' }] },
    seasons: { 70: [460408], 71: [460408] },
  })
  assert.equal(await matchSeries(byCast.tmdb, doctorX, [460408]), 71)
  // The first cast member is unknown to TMDB; the second is tried. Nearest year checked first.
  assert.deepEqual(byCast.looked, [71])
})

test('match: dummy season ids are ignored; nothing to check gives null without a lookup', async () => {
  const { tmdb, looked } = fakeTmdb({ search: { 'דוקטור X|2026': [11], 'דוקטור X|': [11] }, seasons: { 11: [1, 2] } })
  assert.equal(await matchSeries(tmdb, doctorX, [1, 2]), null)
  assert.equal(await matchSeries(tmdb, doctorX, []), null)
  assert.deepEqual(looked, [])
})

test('match: no confirmed hit gives null; a candidate is looked up once', async () => {
  const { tmdb, looked } = fakeTmdb({ search: { 'דוקטור X|2026': [11], 'דוקטור X|': [11] }, seasons: { 11: [1] } })
  assert.equal(await matchSeries(tmdb, doctorX, [460408]), null)
  assert.deepEqual(looked, [11])
})

const office = { name: 'המשרד ארה"ב - The Office US', year: 2013, castNames: null }
const officeShow = (name: string, first: string, last: string, episodes: number[]) => ({
  name,
  original_name: name,
  first_air_date: first,
  last_air_date: last,
  seasons: [{ id: 1, season_number: 0, episode_count: 3 }, ...episodes.map((n, i) => ({ id: 100 + i, season_number: i + 1, episode_count: n }))],
})

test('match without season ids: each name is searched; name, years and seasons must agree', async () => {
  const { tmdb } = fakeTmdb({
    search: { 'The Office US|': [8, 9, 2316] },
    shows: {
      8: officeShow('The Office', '2001-07-09', '2003-12-27', [6, 6]), // years do not cover 2013
      9: officeShow('The Officer', '2005-03-24', '2013-05-16', [6, 22]), // another name
      2316: officeShow('The Office', '2005-03-24', '2013-05-16', [6, 22]),
    },
  })
  assert.equal(await matchSeries(tmdb, office, [1, 2], { 1: 6, 2: 22 }), 2316)
})

test('match without season ids: a provider season TMDB lacks, or with more episodes, rejects the hit', async () => {
  const show = { 2316: officeShow('The Office', '2005-03-24', '2013-05-16', [6, 22]) }
  const { tmdb } = fakeTmdb({ search: { 'The Office US|': [2316] }, shows: show })
  assert.equal(await matchSeries(tmdb, office, [], { 1: 6, 3: 10 }), null)
  const more = fakeTmdb({ search: { 'The Office US|': [2316] }, shows: show })
  assert.equal(await matchSeries(more.tmdb, office, [], { 1: 6, 2: 24 }), null)
  // One episode more than TMDB lists is allowed (a special, a double episode).
  const one = fakeTmdb({ search: { 'The Office US|': [2316] }, shows: show })
  assert.equal(await matchSeries(one.tmdb, office, [], { 1: 6, 2: 23 }), 2316)
})

test('match without season ids: the Hebrew name can match the original name', async () => {
  const { tmdb } = fakeTmdb({
    search: { 'שטיסל|2013': [56017] },
    shows: { 56017: { ...officeShow('Shtisel', '2013-06-29', '2021-03-25', [12, 12, 9]), original_name: 'שטיסל' } },
  })
  assert.equal(await matchSeries(tmdb, { name: 'שטיסל', year: 2013, castNames: null }, [], { 1: 12, 2: 12, 3: 9 }), 56017)
})

test('series names: each side of a dash; keys ignore case, punctuation, "the" and country tags', () => {
  assert.deepEqual(titleNames('Shtisel - שטיסל'), ['Shtisel - שטיסל', 'Shtisel', 'שטיסל'])
  assert.deepEqual(titleNames('לוחם  – Warrior'), ['לוחם  – Warrior', 'לוחם', 'Warrior'])
  assert.deepEqual(titleNames('Spider-Man'), ['Spider-Man'])
  assert.deepEqual(titleNames('עיר של מרגלים (2020)'), ['עיר של מרגלים'])
  assert.deepEqual(titleNames('Shtisel - שטיסל (2013)'), ['Shtisel - שטיסל', 'Shtisel', 'שטיסל'])
  assert.equal(nameKey('The Office US'), nameKey('The Office'))
  assert.equal(nameKey('המשרד ארה"ב'), 'המשרד')
  assert.equal(nameKey('Theodore'), 'theodore')
  assert.equal(nameKey('US'), '')
})

test('match without season ids: a trailing year in the provider name is left out of the search', async () => {
  const { tmdb } = fakeTmdb({
    search: { 'עיר של מרגלים|2020': [113828] },
    shows: { 113828: { ...officeShow('עיר של מרגלים', '2020-12-03', '2020-12-03', [6]), original_name: 'Spy City' } },
  })
  assert.equal(await matchSeries(tmdb, { name: 'עיר של מרגלים (2020)', year: 2020, castNames: null }, [], { 1: 6 }), 113828)
})

test('match without season ids: a name with no letters matches nothing', async () => {
  const { tmdb } = fakeTmdb({ search: { '!!!|': [7] }, shows: { 7: officeShow('?', '2005-01-01', '2006-01-01', [6]) } })
  assert.equal(await matchSeries(tmdb, { name: '!!!', year: null, castNames: null }, [], { 1: 6 }), null)
})

test('movie match: the name must agree, and the year within one', async () => {
  const { tmdb } = fakeTmdb({
    movieSearch: { 'Encanto|2021': [1, 2, 3] },
    movies: { 1: { title: 'Encantado', year: 2021 }, 2: { title: 'Encanto', year: 2015 }, 3: { title: 'Encanto', year: 2022 } },
  })
  assert.equal(await matchMovie(tmdb, { name: 'Encanto - אנקאנטו (2021)', year: 2021 }, null), 3)
})

test('movie match: the Hebrew title counts; without a year the running time decides', async () => {
  const { tmdb } = fakeTmdb({
    movieSearch: { 'יוסי שריד|': [7, 8] },
    movies: { 7: { title: 'Yossi', hebrew: 'יוסי שריד', minutes: 120 }, 8: { title: 'Yossi Sarid', hebrew: 'יוסי שריד', year: 2023, minutes: 70 } },
  })
  assert.equal(await matchMovie(tmdb, { name: 'יוסי שריד', year: null }, 72 * 60), 8)
})

test('movie match: a name alone is not enough', async () => {
  const { tmdb } = fakeTmdb({ movieSearch: { 'Ami and Tami|': [9] }, movies: { 9: { title: 'Ami and Tami', year: 2018 } } })
  assert.equal(await matchMovie(tmdb, { name: 'Ami and Tami', year: null }, null), null)
})

const movie = (ext_id: number): Pending => ({ id: ext_id, kind: 'movie', ext_id, name: `m${ext_id}`, year: 2020, cast_names: null, tmdb_id: null, details_at: null })
const series = (ext_id: number, tmdb_id: number | null = null, details_at: string | null = null): Pending => ({
  id: 1000 + ext_id,
  kind: 'series',
  ext_id,
  name: 'דוקטור X',
  year: 2026,
  cast_names: null,
  tmdb_id,
  details_at,
})

function fakeXtream(failing: number[] = [], onCall: () => void = () => {}): Xtream {
  const fail = (id: number) => {
    onCall()
    if (failing.includes(id)) throw new Error(`get info ${id}: HTTP 503`)
  }
  return {
    signIn: async () => assert.fail(),
    categories: async () => assert.fail(),
    movies: async () => assert.fail(),
    series: async () => assert.fail(),
    channels: async () => assert.fail(),
    programmes: async () => assert.fail(),
    movieInfo: async id => {
      fail(id)
      return { tmdbId: id === 2 ? null : 500 + id, durationSecs: 60, backdropUrl: `https://img/${id}.jpg` }
    },
    seriesInfo: async id => {
      fail(id)
      return {
        tmdbSeasonIds: { 1: 460408 },
        episodes: [{ extId: 369702, season: 1, episode: 1, name: 'S01E01', plot: null, durationSecs: 3974, imageUrl: null, containerExt: 'mp4', addedAt: new Date('2026-10-10T00:00:00Z') }],
      }
    },
  }
}

function fakeDb(pending: Pending[], pageSize = 1000) {
  const upserts: { table: string; rows: Row[] }[] = []
  const updates: { table: string; filter: string; values: Row }[] = []
  const rpcCalls: number[][] = []
  const db: Db = {
    select: async <T,>() => [{ id: 7 }] as T[],
    // Like the database function: pages of `pageSize`, skipping the ids given.
    selectAll: async () => assert.fail('not used'),
    rpc: async <T,>(name: string, args: Row) => {
      assert.equal(name, 'titles_needing_details')
      assert.equal(args.p_provider, 7)
      rpcCalls.push([...(args.p_skip as number[])])
      const skip = new Set(args.p_skip as number[])
      return pending.filter(t => !skip.has(t.id)).slice(0, pageSize) as T[]
    },
    upsert: async (table, _onConflict, rows) => void upserts.push({ table, rows }),
    upsertOne: async () => assert.fail(),
    count: async () => assert.fail(),
    update: async (table, filter, values) => void updates.push({ table, filter, values }),
    remove: async () => assert.fail(),
  }
  return { db, upserts, updates, rpcCalls }
}

/** A clock that moves one tick per provider call. */
function ticking() {
  let t = 0
  return { now: () => t, tick: () => void t++ }
}

test('details: movies get their TMDB id and backdrop; series their episodes and a matched id', async () => {
  const { db, upserts, updates } = fakeDb([movie(1), movie(2), series(5)])
  const { tmdb } = fakeTmdb({ search: { 'דוקטור X|2026': [22] }, seasons: { 22: [460408] } })
  const report = await fetchDetails(fakeXtream(), tmdb, db, 'prov1', 60_000, () => 1_794_900_000_000)
  assert.deepEqual(report, { pending: 3, done: 3, withTmdbId: 2, episodes: 1, failed: 0, outOfTime: false })

  const titles = upserts.filter(u => u.table === 'titles').flatMap(u => u.rows)
  const at = new Date(1_794_900_000_000).toISOString()
  assert.deepEqual(titles, [
    { provider_id: 7, kind: 'movie', ext_id: 1, name: 'm1', tmdb_id: 501, backdrop_url: 'https://img/1.jpg', details_at: at },
    { provider_id: 7, kind: 'movie', ext_id: 2, name: 'm2', tmdb_id: null, backdrop_url: 'https://img/2.jpg', details_at: at },
    { provider_id: 7, kind: 'series', ext_id: 5, name: 'דוקטור X', tmdb_id: 22, details_at: at },
  ])
  const episodes = upserts.filter(u => u.table === 'episodes').flatMap(u => u.rows)
  assert.deepEqual(episodes, [
    { title_id: 1005, ext_id: 369702, season: 1, episode: 1, name: 'S01E01', plot: null, duration_secs: 3974, image_url: null, container_ext: 'mp4', added_at: '2026-10-10T00:00:00.000Z', available: true, seen_at: at },
  ])
  // Episodes are written before the series is marked done.
  assert.ok(upserts.findIndex(u => u.table === 'episodes' && u.rows.length > 0) < upserts.findLastIndex(u => u.table === 'titles'))
  // The series' episodes not seen now (the provider re-added them under new ids) are marked unavailable.
  assert.deepEqual(updates, [
    { table: 'episodes', filter: `title_id=in.(1005)&available=is.true&or=(seen_at.is.null,seen_at.lt.${encodeURIComponent(at)})`, values: { available: false } },
  ])
})

test('details: a movie with no provider id gets one by search; one with an id is not searched', async () => {
  const { db, upserts } = fakeDb([movie(1), movie(2)])
  const { tmdb, looked } = fakeTmdb({
    movieSearch: { 'm1|2020': [99], 'm2|2020': [42] },
    movies: { 99: { title: 'm1', year: 2020 }, 42: { title: 'm2', year: 2020 } },
  })
  await fetchDetails(fakeXtream(), tmdb, db, 'prov1', 60_000, () => 1_794_900_000_000)
  const ids = upserts.filter(u => u.table === 'titles').flatMap(u => u.rows).map(r => [r.ext_id, r.tmdb_id])
  assert.deepEqual(ids, [[1, 501], [2, 42]])
  assert.deepEqual(looked, [42])
})

test('details: a series fetched before is not searched again, matched or not', async () => {
  const { db, upserts } = fakeDb([series(5, 77, '2026-11-01T00:00:00Z'), series(6, null, '2026-11-01T00:00:00Z')])
  const { tmdb, looked } = fakeTmdb({ search: { 'דוקטור X|2026': [22] }, seasons: { 22: [460408] } })
  await fetchDetails(fakeXtream(), tmdb, db, 'prov1', 60_000)
  assert.deepEqual(looked, [])
  assert.deepEqual(upserts.filter(u => u.table === 'titles').flatMap(u => u.rows.map(r => r.tmdb_id)), [77, null])
  // Its episodes are still refreshed.
  assert.equal(upserts.filter(u => u.table === 'episodes').flatMap(u => u.rows).length, 2)
})

test('details: titles not started by the deadline are left; finished ones in the chunk are written', async () => {
  const { db, upserts } = fakeDb([movie(1), movie(2), movie(3)])
  const clock = ticking()
  const report = await fetchDetails(fakeXtream([], clock.tick), fakeTmdb({}).tmdb, db, 'prov1', 2, clock.now)
  assert.equal(report.done, 2)
  assert.equal(report.outOfTime, true)
  assert.deepEqual(upserts.filter(u => u.table === 'titles').flatMap(u => u.rows.map(r => r.ext_id)), [1, 2])
})

test('details: a failing title is skipped and left for the next run', async () => {
  const { db, upserts } = fakeDb([movie(1), movie(3)])
  const report = await fetchDetails(fakeXtream([3]), fakeTmdb({}).tmdb, db, 'prov1', 60_000)
  assert.equal(report.failed, 1)
  assert.deepEqual(upserts.filter(u => u.table === 'titles').flatMap(u => u.rows.map(r => r.ext_id)), [1])
})

test('details: stops at the time budget, keeping what was written', async () => {
  const pending = Array.from({ length: 250 }, (_, i) => movie(i + 10))
  const { db, upserts } = fakeDb(pending)
  const clock = ticking()
  // 150 ticks of budget: chunk 1 (100 titles) finishes, chunk 2 stops after 50.
  const report = await fetchDetails(fakeXtream([], clock.tick), fakeTmdb({}).tmdb, db, 'prov1', 150, clock.now)
  assert.equal(report.outOfTime, true)
  assert.equal(report.done, 150)
  assert.deepEqual(upserts.filter(u => u.table === 'titles').map(u => u.rows.length), [100, 50])
})

test('details: many failures in a row stop the run', async () => {
  const pending = Array.from({ length: 40 }, (_, i) => movie(i + 100))
  const { db } = fakeDb(pending)
  await assert.rejects(
    fetchDetails(fakeXtream(pending.map(p => p.ext_id)), fakeTmdb({}).tmdb, db, 'prov1', 60_000),
    /Stopped after 25 failures in a row; last: get info \d+: HTTP 503/,
  )
})

test('details: the work list is read in pages until it is empty; failed titles are not asked for again', async () => {
  const pending = Array.from({ length: 250 }, (_, i) => movie(i + 10))
  const { db, rpcCalls } = fakeDb(pending, 120)
  const report = await fetchDetails(fakeXtream([10]), fakeTmdb({}).tmdb, db, 'prov1', 60_000)
  assert.deepEqual(report, { pending: 250, done: 249, withTmdbId: 249, episodes: 0, failed: 1, outOfTime: false })
  // 120 + 120 + 10, then an empty page. Every call skips all titles tried so far, failed ones included.
  assert.deepEqual(rpcCalls.map(skip => skip.length), [0, 120, 240, 250])
  assert.ok(rpcCalls[1]?.includes(10))
})

test('details: an unknown provider is an error', async () => {
  const { db } = fakeDb([])
  db.select = async <T,>() => [] as T[]
  await assert.rejects(fetchDetails(fakeXtream(), fakeTmdb({}).tmdb, db, 'nope', 1000), /Unknown provider nope/)
})

test('details: a series that lists no episodes keeps the ones stored', async () => {
  const { db, updates } = fakeDb([series(5)])
  const xtream = fakeXtream()
  xtream.seriesInfo = async () => ({ tmdbSeasonIds: {}, episodes: [] })
  await fetchDetails(xtream, fakeTmdb({}).tmdb, db, 'prov1', 60_000)
  assert.deepEqual(updates, [])
})
