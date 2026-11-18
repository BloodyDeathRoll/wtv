import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { Db, Row } from './db.ts'
import { matchWtw, parseVector, sameJson, sameVector, trimCrew } from './wtw-match.ts'

test('parseVector reads pgvector text and rejects anything else', () => {
  assert.deepEqual(parseVector('[-0.34307024,0.25,0]'), [-0.34307024, 0.25, 0])
  assert.equal(parseVector(null), null)
  assert.equal(parseVector('[]'), null)
  assert.equal(parseVector('[1,"x"]'), null)
  assert.equal(parseVector('not json'), null)
})

test('sameVector ignores float printing differences only', () => {
  assert.equal(sameVector([-1.5270355, 0.1 + 0.2], [-1.5270355, 0.3]), true)
  assert.equal(sameVector([-1.52704], [-1.5270355]), false)
  assert.equal(sameVector([0.25], [0.26]), false)
  assert.equal(sameVector([0.25], [0.25, 1]), false)
  assert.equal(sameVector(null, null), true)
  assert.equal(sameVector(null, [1]), false)
})

/** A Db where only `select`, `selectAll` and (for WTV) `upsert` are expected. */
function fakeDb(tables: Record<string, Row[]>) {
  const upserts: Row[][] = []
  const calls: string[] = []
  const no = async () => assert.fail('unexpected call')
  const db: Db = {
    select: async <T,>() => [{ id: 7 }] as T[],
    selectAll: async <T extends { id: number },>(table: string, columns: string, filter = '') => {
      calls.push(`${table}?${columns}&${filter}`)
      return (tables[table] ?? []) as T[]
    },
    upsert: async (_table, _onConflict, rows) => void upserts.push(rows),
    upsertOne: no,
    count: no,
    update: no,
    remove: no,
    rpc: no,
  }
  return { db, upserts, calls }
}

/** A 25-value vector as WTW sends it, and as WTV stores it. */
const vecText = (first: number) => `[${[first, ...Array(24).fill(0)].join(',')}]`
const vec = (first: number) => [first, ...Array(24).fill(0)]

/** A WTW crew snapshot with more than the ranking reads; `crew` below is it trimmed. */
const wtwCrew = {
  directors: [{ tmdb_person_id: '1', name: 'D', job: 'Director' }],
  writers: [],
  cinematographers: [{ tmdb_person_id: 2, name: 'C' }],
  cast: [1, 2, 3, 4, 5].map(i => ({ tmdb_person_id: `a${i}`, name: `A${i}`, order: i - 1, character: 'x' })),
  producers: [{ tmdb_person_id: '9', name: 'P' }],
}
const crew = {
  directors: [{ tmdb_person_id: '1', name: 'D' }],
  writers: [],
  cinematographers: [{ tmdb_person_id: '2', name: 'C' }],
  cast: [1, 2, 3].map(i => ({ tmdb_person_id: `a${i}`, name: `A${i}`, order: i - 1 })),
}
const ratings = { tmdb_rating: 7.4, omdb_rating: 0.81 }

test('trimCrew keeps what the ranking reads, in a fixed key order', () => {
  assert.deepEqual(trimCrew(wtwCrew), crew)
  assert.equal(trimCrew(null), null)
  // A cast entry without an id is dropped; the others keep their own order.
  const noId = { ...wtwCrew, cast: [{ name: 'No id', order: 0 }, ...wtwCrew.cast.slice(1)] }
  assert.deepEqual(trimCrew(noId)?.cast, [2, 3, 4].map(i => ({ tmdb_person_id: `a${i}`, name: `A${i}`, order: i - 1 })))
  assert.equal(trimCrew('x'), null)
  // jsonb returns its own key order: still the same crew.
  const reordered = { cast: crew.cast, writers: [], directors: crew.directors, cinematographers: crew.cinematographers }
  assert.ok(sameJson(reordered, crew))
  assert.ok(!sameJson({ ...crew, writers: [{ tmdb_person_id: '3', name: 'W' }] }, crew))
})

const none = { wtw_title_id: null, wtw_taste_vec: null, wtw_taste_version: null, wtw_crew: null, wtw_tmdb_rating: null, wtw_omdb_rating: null }

test('titles are matched by kind and TMDB id; coverage is counted per kind', async () => {
  const wtw = fakeDb({
    titles: [
      { id: 1, tmdb_id: '1185344', type: 'movie', taste_vec: vecText(0.5), taste_version: 1, crew: wtwCrew, ...ratings },
      { id: 2, tmdb_id: '22', type: 'tv', taste_vec: null, taste_version: null },
      // Same TMDB id as the movie, but a series: must not match the movie.
      { id: 3, tmdb_id: '1185344', type: 'tv', taste_vec: vecText(1), taste_version: 1 },
    ],
  })
  const wtv = fakeDb({
    titles: [
      { id: 10, kind: 'movie', ext_id: 387982, name: 'החיה', tmdb_id: 1185344, ...none },
      { id: 11, kind: 'movie', ext_id: 5, name: 'unknown', tmdb_id: 999, ...none },
      { id: 12, kind: 'series', ext_id: 5829, name: 'דוקטור X', tmdb_id: 22, ...none },
    ],
  })
  const report = await matchWtw(wtv.db, wtw.db, 'prov1')
  assert.deepEqual(report, {
    wtwTitles: 3,
    wtwDuplicates: 0,
    movie: { withTmdbId: 2, inWtw: 1, scored: 1 },
    series: { withTmdbId: 1, inWtw: 1, scored: 0 },
    updated: 2,
    versions: { 1: 1 },
  })
  // The unknown movie had nothing and still has nothing: not written.
  assert.deepEqual(wtv.upserts, [[
    { provider_id: 7, kind: 'movie', ext_id: 387982, name: 'החיה', wtw_title_id: 1, wtw_taste_vec: vec(0.5), wtw_taste_version: 1, wtw_crew: crew, wtw_tmdb_rating: 7.4, wtw_omdb_rating: 0.81 },
    // No crew or ratings on the WTW row: copied as null.
    { provider_id: 7, kind: 'series', ext_id: 5829, name: 'דוקטור X', wtw_title_id: 2, wtw_taste_vec: null, wtw_taste_version: null, wtw_crew: null, wtw_tmdb_rating: null, wtw_omdb_rating: null },
  ]])
  // WTW is only read.
  assert.deepEqual(wtw.upserts, [])
  assert.deepEqual(wtv.calls, [
    'titles?id,kind,ext_id,name,tmdb_id,wtw_title_id,wtw_taste_vec,wtw_taste_version,wtw_crew,wtw_tmdb_rating,wtw_omdb_rating&provider_id=eq.7&or=(tmdb_id.not.is.null,wtw_title_id.not.is.null)',
  ])
})

test('unchanged titles are not written; a lost TMDB id clears the match', async () => {
  const wtw = fakeDb({ titles: [{ id: 1, tmdb_id: '100', type: 'movie', taste_vec: vecText(0.5), taste_version: 1, crew: wtwCrew, ...ratings }] })
  const kept = { tmdb_id: 100, wtw_title_id: 1, wtw_taste_vec: vec(0.5), wtw_taste_version: 1, wtw_crew: crew, wtw_tmdb_rating: 7.4, wtw_omdb_rating: 0.81 }
  const wtv = fakeDb({
    titles: [
      { id: 10, kind: 'movie', ext_id: 1, name: 'same', ...kept },
      { id: 12, kind: 'movie', ext_id: 3, name: 'same too', ...kept },
      { id: 11, kind: 'movie', ext_id: 2, name: 'lost id', ...kept, tmdb_id: null },
      // Only the rating changed in WTW: written.
      { id: 13, kind: 'movie', ext_id: 4, name: 'new rating', ...kept, wtw_tmdb_rating: 7.1 },
    ],
  })
  const report = await matchWtw(wtv.db, wtw.db, 'prov1')
  assert.equal(report.updated, 2)
  // The title without a TMDB id is not counted in coverage.
  assert.deepEqual(report.movie, { withTmdbId: 3, inWtw: 3, scored: 3 })
  assert.deepEqual(wtv.upserts, [[
    { provider_id: 7, kind: 'movie', ext_id: 2, name: 'lost id', ...none },
    { provider_id: 7, kind: 'movie', ext_id: 4, name: 'new rating', wtw_title_id: 1, wtw_taste_vec: vec(0.5), wtw_taste_version: 1, wtw_crew: crew, wtw_tmdb_rating: 7.4, wtw_omdb_rating: 0.81 },
  ]])
})

test('of two WTW rows for one title, the scored one is used and the duplicate counted', async () => {
  const wtw = fakeDb({
    titles: [
      { id: 1, tmdb_id: '100', type: 'movie', taste_vec: null, taste_version: null },
      { id: 2, tmdb_id: '100', type: 'movie', taste_vec: vecText(1), taste_version: 1 },
      { id: 3, tmdb_id: '100', type: 'movie', taste_vec: vecText(3), taste_version: 1 },
    ],
  })
  const wtv = fakeDb({ titles: [{ id: 10, kind: 'movie', ext_id: 1, name: 'x', tmdb_id: 100, ...none }] })
  const report = await matchWtw(wtv.db, wtw.db, 'prov1')
  assert.equal(report.wtwDuplicates, 2)
  assert.equal(wtv.upserts[0]?.[0]?.wtw_title_id, 2)
})

test('an empty answer from WTW clears nothing', async () => {
  const wtv = fakeDb({ titles: [{ id: 10, kind: 'movie', ext_id: 1, name: 'x', tmdb_id: 100, wtw_title_id: 1, wtw_taste_vec: [1], wtw_taste_version: 1 }] })
  await assert.rejects(matchWtw(wtv.db, fakeDb({ titles: [] }).db, 'prov1'), /WTW returned no titles/)
  assert.deepEqual(wtv.upserts, [])
})

test('a run that would clear more than half the matches writes nothing', async () => {
  const wtw = fakeDb({ titles: [{ id: 9, tmdb_id: '999', type: 'movie', taste_vec: null, taste_version: null }] })
  const matched = (ext_id: number) => ({ id: ext_id, kind: 'movie', ext_id, name: 'x', tmdb_id: ext_id, wtw_title_id: ext_id, wtw_taste_vec: null, wtw_taste_version: null })
  const wtv = fakeDb({ titles: [matched(1), matched(2), matched(3)] })
  await assert.rejects(matchWtw(wtv.db, wtw.db, 'prov1'), /would clear 3 of 3 matches \(limit: half\)/)
  assert.deepEqual(wtv.upserts, [])
})

test('a run where WTW still has the titles but most vectors are gone writes nothing', async () => {
  const wtw = fakeDb({ titles: [1, 2, 3].map(id => ({ id, tmdb_id: String(id), type: 'movie', taste_vec: null, taste_version: null })) })
  const scored = (ext_id: number) => ({ id: ext_id, kind: 'movie', ext_id, name: 'x', tmdb_id: ext_id, wtw_title_id: ext_id, wtw_taste_vec: vec(0.5), wtw_taste_version: 1 })
  const wtv = fakeDb({ titles: [scored(1), scored(2), scored(3)] })
  await assert.rejects(matchWtw(wtv.db, wtw.db, 'prov1'), /would clear 3 of 3 taste vectors/)
  assert.deepEqual(wtv.upserts, [])
})

test('a vector of the wrong size stops the run before any write', async () => {
  const wtw = fakeDb({ titles: [{ id: 1, tmdb_id: '100', type: 'movie', taste_vec: `[${Array(30).fill(0.1).join(',')}]`, taste_version: 2 }] })
  const wtv = fakeDb({ titles: [{ id: 10, kind: 'movie', ext_id: 1, name: 'x', tmdb_id: 100, ...none }] })
  await assert.rejects(matchWtw(wtv.db, wtw.db, 'prov1'), /30 values, not 25/)
  assert.deepEqual(wtv.upserts, [])
})

test('TMDB ids with leading zeros match', async () => {
  const vec = `[${Array(25).fill(0.5).join(',')}]`
  const wtw = fakeDb({ titles: [{ id: 1, tmdb_id: ' 0100 ', type: 'movie', taste_vec: vec, taste_version: 1 }] })
  const wtv = fakeDb({ titles: [{ id: 10, kind: 'movie', ext_id: 1, name: 'x', tmdb_id: 100, ...none }] })
  const report = await matchWtw(wtv.db, wtw.db, 'prov1')
  assert.deepEqual(report.movie, { withTmdbId: 1, inWtw: 1, scored: 1 })
})
