import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createTmdb, TmdbError } from './tmdb.ts'

function fakeFetch(answers: Response[]) {
  const urls: URL[] = []
  const fetchFn = (async (input: URL | RequestInfo) => {
    urls.push(new URL(String(input)))
    const next = answers.shift()
    if (!next) throw new Error('no more answers')
    return next
  }) as typeof fetch
  return { fetchFn, urls }
}

const noSleep = async () => {}

test('search sends the key, the query and the year, and returns the first ids', async () => {
  const { fetchFn, urls } = fakeFetch([Response.json({ results: [{ id: 1 }, { id: 2 }, { id: 3 }] })])
  assert.deepEqual(await createTmdb('KEY', fetchFn, noSleep).searchSeries('דוקטור X', 2026, 2), [1, 2])
  const [url] = urls
  assert.equal(url?.pathname, '/3/search/tv')
  assert.deepEqual(Object.fromEntries(url!.searchParams), { api_key: 'KEY', query: 'דוקטור X', first_air_date_year: '2026' })
})

test('search without a year sends no year', async () => {
  const { fetchFn, urls } = fakeFetch([Response.json({ results: [] })])
  assert.deepEqual(await createTmdb('KEY', fetchFn, noSleep).searchSeries('x', null), [])
  assert.equal(urls[0]?.searchParams.has('first_air_date_year'), false)
})

test('429 is retried after the pause TMDB asks for', async () => {
  const pauses: number[] = []
  const { fetchFn } = fakeFetch([
    new Response(null, { status: 429, headers: { 'retry-after': '3' } }),
    new Response(null, { status: 429 }),
    Response.json({ results: [{ id: 9 }] }),
  ])
  const tmdb = createTmdb('KEY', fetchFn, async ms => void pauses.push(ms))
  assert.equal(await tmdb.searchPerson('Amy Carlson'), 9)
  assert.deepEqual(pauses, [3000, 2000])
})

test('errors never contain the key', async () => {
  const cases = [
    fakeFetch([new Response(null, { status: 401 })]).fetchFn,
    (async () => {
      throw new TypeError('fetch failed')
    }) as typeof fetch,
  ]
  for (const fetchFn of cases) {
    await assert.rejects(createTmdb('SECRET-KEY', fetchFn, noSleep).series(1), (err: unknown) => {
      assert.ok(err instanceof TmdbError)
      assert.doesNotMatch(err.message, /SECRET/)
      return true
    })
  }
})
