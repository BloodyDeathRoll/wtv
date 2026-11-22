import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createDb, DbError } from './db.ts'

interface Call {
  method: string
  url: URL
  headers: Headers
  body: unknown
}

/** A fetch that records each call and answers with `reply(call)`. */
function fakeFetch(reply: (call: Call) => Response = () => new Response(null, { status: 201 })) {
  const calls: Call[] = []
  const fetchFn = (async (input: URL | RequestInfo, init?: RequestInit) => {
    const call = {
      method: init?.method ?? 'GET',
      url: new URL(String(input)),
      headers: new Headers(init?.headers),
      body: typeof init?.body === 'string' ? JSON.parse(init.body) : undefined,
    }
    calls.push(call)
    return reply(call)
  }) as typeof fetch
  return { fetchFn, calls }
}

const config = { url: 'https://abc.supabase.co', key: 'sb_secret_x' }

test('upsert sends batches of 500 with the conflict target and the secret key', async () => {
  const { fetchFn, calls } = fakeFetch()
  const rows = Array.from({ length: 1201 }, (_, i) => ({ id: i }))
  await createDb(config, fetchFn).upsert('titles', 'provider_id,kind,ext_id', rows)

  assert.deepEqual(calls.map(c => (c.body as unknown[]).length), [500, 500, 201])
  const [first] = calls
  assert.ok(first)
  assert.equal(first.method, 'POST')
  assert.equal(first.url.pathname, '/rest/v1/titles')
  assert.equal(first.url.searchParams.get('on_conflict'), 'provider_id,kind,ext_id')
  assert.equal(first.headers.get('apikey'), 'sb_secret_x')
  assert.equal(first.headers.get('Authorization'), 'Bearer sb_secret_x')
  assert.equal(first.headers.get('Prefer'), 'resolution=merge-duplicates,return=minimal')
  assert.deepEqual((calls[2]?.body as { id: number }[])[0], { id: 1000 })
})

test('a path in the database URL is kept', async () => {
  const { fetchFn, calls } = fakeFetch()
  await createDb({ ...config, url: 'https://proxy.example/supabase' }, fetchFn).upsert('titles', 'x', [{ id: 1 }])
  assert.equal(calls[0]?.url.pathname, '/supabase/rest/v1/titles')
})

test('selectAll reads 1,000 rows at a time after the last id, until a short page', async () => {
  const rows = Array.from({ length: 2300 }, (_, i) => ({ id: i * 2 + 1 }))
  const { fetchFn, calls } = fakeFetch(call => {
    const after = Number(call.url.searchParams.get('id')?.slice(3))
    return Response.json(rows.filter(r => r.id > after).slice(0, Number(call.url.searchParams.get('limit'))))
  })
  const got = await createDb(config, fetchFn).selectAll<{ id: number }>('titles', 'id,name', 'kind=eq.movie')
  assert.equal(got.length, 2300)
  assert.deepEqual(calls.map(c => c.url.searchParams.get('id')), ['gt.-1', 'gt.1999', 'gt.3999'])
  assert.equal(calls[0]?.url.search, '?select=id,name&id=gt.-1&order=id&limit=1000&kind=eq.movie')
})

test('selectAll stops after an exactly full last page with one more call', async () => {
  const rows = Array.from({ length: 1000 }, (_, i) => ({ id: i + 1 }))
  const { fetchFn, calls } = fakeFetch(call => {
    const after = Number(call.url.searchParams.get('id')?.slice(3))
    return Response.json(rows.filter(r => r.id > after).slice(0, 1000))
  })
  assert.equal((await createDb(config, fetchFn).selectAll('titles', 'id')).length, 1000)
  assert.equal(calls.length, 2)
})

test('selectAll reads a page again once after a statement timeout, and fails on a second one', async () => {
  const timeout = () => Response.json({ code: '57014', message: 'canceling statement due to statement timeout' }, { status: 500 })
  let n = 0
  const once = fakeFetch(() => (n++ === 0 ? timeout() : Response.json([{ id: 1 }])))
  assert.deepEqual(await createDb(config, once.fetchFn).selectAll('titles', 'id'), [{ id: 1 }])
  assert.equal(once.calls.length, 2)

  const always = fakeFetch(timeout)
  await assert.rejects(createDb(config, always.fetchFn).selectAll('titles', 'id'), DbError)
  assert.equal(always.calls.length, 2)

  const other = fakeFetch(() => Response.json({ code: '42501' }, { status: 500 }))
  await assert.rejects(createDb(config, other.fetchFn).selectAll('titles', 'id'), DbError)
  assert.equal(other.calls.length, 1)
})

test('upsert of nothing makes no call', async () => {
  const { fetchFn, calls } = fakeFetch()
  await createDb(config, fetchFn).upsert('titles', 'x', [])
  assert.equal(calls.length, 0)
})

test('count reads the total from Content-Range, including zero', async () => {
  for (const [range, expected] of [['0-24/15777', 15777], ['*/0', 0]] as const) {
    const { fetchFn, calls } = fakeFetch(() => new Response(null, { status: 200, headers: { 'Content-Range': range } }))
    assert.equal(await createDb(config, fetchFn).count('titles', 'kind=eq.movie&available=is.true'), expected)
    assert.equal(calls[0]?.method, 'HEAD')
    assert.equal(calls[0]?.headers.get('Prefer'), 'count=exact')
    assert.equal(calls[0]?.url.search, '?kind=eq.movie&available=is.true')
  }
})

test('count without a total is an error', async () => {
  const { fetchFn } = fakeFetch(() => new Response(null, { status: 200 }))
  await assert.rejects(createDb(config, fetchFn).count('titles', 'x=eq.1'), DbError)
})

test('upsertOne returns the stored row', async () => {
  const { fetchFn, calls } = fakeFetch(() => Response.json([{ id: 7, name: 'prov1' }], { status: 201 }))
  assert.deepEqual(await createDb(config, fetchFn).upsertOne('providers', 'name', { name: 'prov1' }), { id: 7, name: 'prov1' })
  assert.equal(calls[0]?.headers.get('Prefer'), 'resolution=merge-duplicates,return=representation')
  assert.deepEqual(calls[0]?.body, { name: 'prov1' })
})

test('an HTTP error names the table and the reason, without the query', async () => {
  const { fetchFn } = fakeFetch(() => new Response('{"message":"duplicate key"}', { status: 409 }))
  await assert.rejects(createDb(config, fetchFn).update('titles', 'provider_id=eq.7', { available: false }), (err: unknown) => {
    assert.ok(err instanceof DbError)
    assert.equal(err.message, 'PATCH titles: HTTP 409 {"message":"duplicate key"}')
    return true
  })
})

test('rpc returns a list for a set-returning function and wraps a scalar result', async () => {
  const set = fakeFetch(() => Response.json([{ id: 1 }, { id: 2 }]))
  assert.deepEqual(await createDb(config, set.fetchFn).rpc('titles_needing_details', { p_provider: 4 }), [{ id: 1 }, { id: 2 }])
  assert.equal(set.calls[0]?.url.pathname, '/rest/v1/rpc/titles_needing_details')
  assert.deepEqual(set.calls[0]?.body, { p_provider: 4 })
  const scalar = fakeFetch(() => Response.json(21462))
  assert.deepEqual(await createDb(config, scalar.fetchFn).rpc('refresh_title_groups', { p_provider: 4 }), [21462])
})
