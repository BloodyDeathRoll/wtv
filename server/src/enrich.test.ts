import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { Db, Row } from './db.ts'
import { enrich, episodeName, movieCertification, seriesCertification, topCast, type Pending } from './enrich.ts'
import type { Tmdb, TmdbMovieFull, TmdbSeason, TmdbSeriesFull } from './tmdb.ts'

const translations = (he?: { title?: string; name?: string; overview?: string }) => ({
  translations: he ? [{ iso_639_1: 'he', data: he }, { iso_639_1: 'fr', data: { overview: 'fr' } }] : [],
})

const movieFull = (over: Partial<TmdbMovieFull> = {}): TmdbMovieFull => ({
  id: 1185344,
  title: 'The Beast',
  overview: 'A hostile army…',
  genres: [{ id: 28, name: 'Action' }],
  vote_average: 5.1,
  original_language: 'en',
  poster_path: '/p.jpg',
  backdrop_path: '/b.jpg',
  runtime: 99,
  credits: { cast: [] },
  release_dates: { results: [] },
  translations: translations({ title: 'החיה', overview: 'כשצבא עוין…' }),
  ...over,
})

const seriesFull = (over: Partial<TmdbSeriesFull> = {}): TmdbSeriesFull => ({
  id: 1408,
  name: 'House',
  overview: 'A misanthropic doctor…',
  genres: [{ id: 18, name: 'Drama' }],
  vote_average: 8.6,
  original_language: 'en',
  poster_path: '/hp.jpg',
  backdrop_path: null,
  episode_run_time: [44],
  // An empty `character` falls through to the series role.
  aggregate_credits: { cast: [{ id: 41419, name: 'Hugh Laurie', profile_path: '/hl.jpg', order: 0, character: '', roles: [{ character: 'Gregory House' }] }] },
  content_ratings: { results: [{ iso_3166_1: 'US', rating: 'TV-14' }] },
  translations: translations({ name: 'האוס', overview: '' }),
  ...over,
})

test('episode placeholders are dropped, real names kept', () => {
  assert.equal(episodeName('Episode 3'), null)
  assert.equal(episodeName('פרק 12'), null)
  assert.equal(episodeName(' Pilot '), 'Pilot')
  assert.equal(episodeName('Episode 3: The Return'), 'Episode 3: The Return')
  assert.equal(episodeName(''), null)
})

test('certification: US first, then IL, then GB; empty ones skipped', () => {
  const m = movieFull({
    release_dates: {
      results: [
        { iso_3166_1: 'IL', release_dates: [{ certification: '14' }] },
        { iso_3166_1: 'US', release_dates: [{ certification: '' }, { certification: 'R' }] },
      ],
    },
  })
  assert.equal(movieCertification(m), 'R')
  assert.equal(movieCertification(movieFull({ release_dates: { results: [{ iso_3166_1: 'IL', release_dates: [{ certification: '14' }] }] } })), '14')
  assert.equal(movieCertification(movieFull()), null)
  assert.equal(seriesCertification(seriesFull({ content_ratings: { results: [{ iso_3166_1: 'US', rating: '' }, { iso_3166_1: 'GB', rating: '15' }] } })), '15')
})

test('cast: billing order, one entry per person, at most 15', () => {
  const cast = Array.from({ length: 20 }, (_, i) => ({ id: i, name: `p${i}`, profile_path: null, order: 19 - i, character: 'c' }))
  cast.push({ id: 19, name: 'p19 again', profile_path: null, order: 0, character: 'second role' })
  const top = topCast(cast)
  assert.equal(top.length, 15)
  assert.deepEqual(top.slice(0, 2).map(c => c.id), [19, 18])
  assert.equal(new Set(top.map(c => c.id)).size, 15)
})

/** TMDB answers keyed by id; seasons keyed by "id/season/language". */
function fakeTmdb(movies: Record<number, TmdbMovieFull | null>, series: Record<number, TmdbSeriesFull | null>, seasons: Record<string, TmdbSeason | null> = {}) {
  const seasonCalls: string[] = []
  const no = async () => assert.fail('not used by enrich')
  const tmdb: Tmdb = {
    searchSeries: no,
    series: no,
    searchPerson: no,
    personSeries: no,
    movieFull: async id => {
      if (!(id in movies)) throw new Error(`movie/${id}: HTTP 500`)
      return movies[id] ?? null
    },
    seriesFull: async id => series[id] ?? null,
    season: async (id, n, language) => {
      seasonCalls.push(`${id}/${n}/${language}`)
      return seasons[`${id}/${n}/${language}`] ?? null
    },
    genres: async (kind, language) => [{ id: kind === 'movie' ? 28 : 18, name: language === 'he-IL' ? 'עברית' : 'English' }],
  }
  return { tmdb, seasonCalls }
}

function fakeDb(pending: Pending[], episodes: Row[] = []) {
  const writes: { op: string; table: string; rows?: Row[]; filter?: string }[] = []
  const no = async () => assert.fail('unexpected call')
  const db: Db = {
    select: async <T,>() => [{ id: 7 }] as T[],
    selectAll: async <T extends { id: number },>(table: string) => {
      assert.equal(table, 'episodes')
      return episodes as T[]
    },
    rpc: async <T,>(name: string, args: Row) => {
      assert.equal(name, 'titles_needing_enrichment')
      const skip = new Set(args.p_skip as number[])
      return pending.filter(t => !skip.has(t.id)) as T[]
    },
    upsert: async (table, _onConflict, rows) => void writes.push({ op: 'upsert', table, rows }),
    remove: async (table, filter) => void writes.push({ op: 'remove', table, filter }),
    upsertOne: no,
    count: no,
    update: no,
  }
  const rows = (table: string) => writes.filter(w => w.op === 'upsert' && w.table === table).flatMap(w => w.rows ?? [])
  return { db, writes, rows }
}

const at = 1_794_900_000_000
const when = new Date(at).toISOString()

test('a movie gets English and Hebrew text, genres, certification, images and cast', async () => {
  const movie: Pending = { id: 10, kind: 'movie', ext_id: 387982, name: 'החיה', tmdb_id: 1185344 }
  const full = movieFull({
    credits: { cast: [{ id: 2231, name: 'Samuel L. Jackson', profile_path: '/s.jpg', order: 0, character: 'President' }] },
    release_dates: { results: [{ iso_3166_1: 'US', release_dates: [{ certification: 'R' }] }] },
  })
  const { db, writes, rows } = fakeDb([movie])
  const report = await enrich(fakeTmdb({ 1185344: full }, {}).tmdb, db, 'prov1', 60_000, () => at)
  assert.deepEqual(report, { pending: 1, done: 1, withHebrew: 1, episodes: 0, failed: 0, outOfTime: false })

  assert.deepEqual(rows('genres'), [
    { kind: 'movie', id: 28, name_en: 'English', name_he: 'עברית' },
    { kind: 'series', id: 18, name_en: 'English', name_he: 'עברית' },
  ])
  assert.deepEqual(rows('titles'), [{
    provider_id: 7, kind: 'movie', ext_id: 387982, name: 'החיה', enriched_tmdb_id: 1185344,
    title_en: 'The Beast', title_he: 'החיה', overview_en: 'A hostile army…', overview_he: 'כשצבא עוין…',
    tmdb_genre_ids: [28], certification: 'R', tmdb_rating: 5.1, original_language: 'en',
    tmdb_poster: '/p.jpg', tmdb_backdrop: '/b.jpg', tmdb_runtime_min: 99, enriched_at: when,
  }])
  assert.deepEqual(rows('people'), [{ tmdb_id: 2231, name: 'Samuel L. Jackson', profile: '/s.jpg' }])
  assert.deepEqual(rows('title_cast'), [{ title_id: 10, person_id: 2231, position: 0, character: 'President' }])
  // Old cast removed first; people before cast; titles written last.
  const order = writes.map(w => `${w.op}:${w.table}`)
  assert.ok(order.indexOf('remove:title_cast') < order.lastIndexOf('upsert:title_cast'))
  assert.ok(order.indexOf('upsert:people', 2) < order.lastIndexOf('upsert:title_cast'))
  assert.equal(order.at(-1), 'upsert:titles')
})

test('a series gets episode names in both languages for the seasons the provider has', async () => {
  const series: Pending = { id: 20, kind: 'series', ext_id: 5, name: 'האוס', tmdb_id: 1408 }
  const episodes = [
    { id: 1, title_id: 20, ext_id: 501, season: 1, episode: 1 },
    { id: 2, title_id: 20, ext_id: 502, season: 1, episode: 2 },
    { id: 3, title_id: 20, ext_id: 503, season: 1, episode: 3 },
  ]
  const { tmdb, seasonCalls } = fakeTmdb({}, { 1408: seriesFull() }, {
    '1408/1/en-US': { episodes: [{ episode_number: 1, name: 'Pilot', overview: 'A teacher collapses.', still_path: '/s1.jpg' }, { episode_number: 2, name: 'Episode 2', overview: '', still_path: null }, { episode_number: 3, name: '2112', overview: 'Same text.', still_path: null }] },
    '1408/1/he-IL': { episodes: [{ episode_number: 1, name: 'פיילוט', overview: 'מורה מתמוטטת.', still_path: '/s1.jpg' }, { episode_number: 3, name: '2112', overview: 'Same text.', still_path: null }] },
  })
  const { db, rows } = fakeDb([series], episodes)
  const report = await enrich(tmdb, db, 'prov1', 60_000, () => at)
  assert.deepEqual(seasonCalls, ['1408/1/en-US', '1408/1/he-IL'])
  assert.equal(report.episodes, 3)
  assert.equal(report.withHebrew, 0) // Hebrew name but an empty Hebrew synopsis
  assert.deepEqual(rows('episodes'), [
    { title_id: 20, ext_id: 501, season: 1, episode: 1, name_en: 'Pilot', overview_en: 'A teacher collapses.', name_he: 'פיילוט', overview_he: 'מורה מתמוטטת.', tmdb_still: '/s1.jpg' },
    { title_id: 20, ext_id: 502, season: 1, episode: 2, name_en: null, overview_en: null, name_he: null, overview_he: null, tmdb_still: null },
    // The Hebrew answer repeats the English text: stored once, in English.
    { title_id: 20, ext_id: 503, season: 1, episode: 3, name_en: '2112', overview_en: 'Same text.', name_he: null, overview_he: null, tmdb_still: null },
  ])
  const title = rows('titles')[0]
  assert.equal(title?.title_he, 'האוס')
  assert.equal(title?.certification, 'TV-14')
  assert.equal(title?.tmdb_runtime_min, 44)
  assert.deepEqual(rows('title_cast'), [{ title_id: 20, person_id: 41419, position: 0, character: 'Gregory House' }])
})

test('a TMDB id TMDB no longer has is marked done with empty fields; a failing one is left', async () => {
  const gone: Pending = { id: 30, kind: 'movie', ext_id: 1, name: 'gone', tmdb_id: 111 }
  const failing: Pending = { id: 31, kind: 'movie', ext_id: 2, name: 'failing', tmdb_id: 222 }
  const { db, rows, writes } = fakeDb([gone, failing])
  const report = await enrich(fakeTmdb({ 111: null }, {}).tmdb, db, 'prov1', 60_000, () => at)
  assert.equal(report.failed, 1)
  assert.deepEqual(rows('titles').map(r => [r.ext_id, r.title_en, r.enriched_tmdb_id, r.enriched_at]), [[1, null, 111, when]])
  // Its old cast is removed; the failing title's is not touched.
  assert.deepEqual(writes.filter(w => w.op === 'remove').map(w => w.filter), ['title_id=in.(30)'])
})

test('many failures in a row stop the run', async () => {
  const pending = Array.from({ length: 40 }, (_, i): Pending => ({ id: i, kind: 'movie', ext_id: i, name: 'x', tmdb_id: 1000 + i }))
  const { db } = fakeDb(pending)
  await assert.rejects(enrich(fakeTmdb({}, {}).tmdb, db, 'prov1', 60_000, () => at), /Stopped after 25 failures in a row; last: movie\/\d+: HTTP 500/)
})

test('a long series stops between seasons at the deadline, unwritten and not failed', async () => {
  const series: Pending = { id: 20, kind: 'series', ext_id: 5, name: 'x', tmdb_id: 1408 }
  const episodes = [1, 2, 3].map(season => ({ id: season, title_id: 20, ext_id: 500 + season, season, episode: 1 }))
  const { tmdb, seasonCalls } = fakeTmdb({}, { 1408: seriesFull() })
  const { db, rows } = fakeDb([series], episodes)
  let t = 0
  // Budget 10: deadline read, chunk check, enrichedAt, then the title check and season 1 pass; season 2 does not.
  const clock = () => (t++ < 5 ? 0 : 100)
  const report = await enrich(tmdb, db, 'prov1', 10, clock)
  assert.equal(report.outOfTime, true)
  assert.equal(report.failed, 0)
  assert.deepEqual(seasonCalls, ['1408/1/en-US', '1408/1/he-IL'])
  assert.deepEqual(rows('titles'), [])
})

test('stops at the time budget', async () => {
  const pending = Array.from({ length: 3 }, (_, i): Pending => ({ id: i, kind: 'movie', ext_id: i, name: 'x', tmdb_id: i + 1 }))
  const { db } = fakeDb(pending)
  let t = 0
  const report = await enrich(fakeTmdb({ 1: movieFull(), 2: movieFull(), 3: movieFull() }, {}).tmdb, db, 'prov1', 0, () => t++)
  assert.equal(report.outOfTime, true)
  assert.equal(report.done, 0)
})
