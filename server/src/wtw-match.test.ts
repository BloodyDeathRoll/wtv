import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { Db, Row } from './db.ts'
import { matchWtw, parseVector } from './wtw-match.ts'

test('parseVector reads pgvector text and rejects anything else', () => {
  assert.deepEqual(parseVector('[-0.34307024,0.25,0]'), [-0.34307024, 0.25, 0])
  assert.equal(parseVector(null), null)
  assert.equal(parseVector('[]'), null)
  assert.equal(parseVector('[1,"x"]'), null)
  assert.equal(parseVector('not json'), null)
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

test('titles are matched by kind and TMDB id; coverage is counted per kind', async () => {
  const wtw = fakeDb({
    titles: [
      { id: 1, tmdb_id: '1185344', type: 'movie', taste_vec: '[0.5,-1]', taste_version: 1 },
      { id: 2, tmdb_id: '22', type: 'tv', taste_vec: null, taste_version: null },
      // Same TMDB id as the movie, but a series: must not match the movie.
      { id: 3, tmdb_id: '1185344', type: 'tv', taste_vec: '[1,1]', taste_version: 1 },
    ],
  })
  const wtv = fakeDb({
    titles: [
      { id: 10, kind: 'movie', ext_id: 387982, name: 'החיה', tmdb_id: 1185344 },
      { id: 11, kind: 'movie', ext_id: 5, name: 'unknown', tmdb_id: 999 },
      { id: 12, kind: 'series', ext_id: 5829, name: 'דוקטור X', tmdb_id: 22 },
    ],
  })
  const report = await matchWtw(wtv.db, wtw.db, 'prov1')
  assert.deepEqual(report, {
    wtwTitles: 3,
    movie: { withTmdbId: 2, inWtw: 1, scored: 1 },
    series: { withTmdbId: 1, inWtw: 1, scored: 0 },
  })
  assert.deepEqual(wtv.upserts, [[
    { provider_id: 7, kind: 'movie', ext_id: 387982, name: 'החיה', wtw_title_id: 1, wtw_taste_vec: [0.5, -1], wtw_taste_version: 1 },
    { provider_id: 7, kind: 'movie', ext_id: 5, name: 'unknown', wtw_title_id: null, wtw_taste_vec: null, wtw_taste_version: null },
    { provider_id: 7, kind: 'series', ext_id: 5829, name: 'דוקטור X', wtw_title_id: 2, wtw_taste_vec: null, wtw_taste_version: null },
  ]])
  // WTW is only read.
  assert.deepEqual(wtw.upserts, [])
  assert.deepEqual(wtv.calls, ['titles?id,kind,ext_id,name,tmdb_id&provider_id=eq.7&tmdb_id=not.is.null'])
})
