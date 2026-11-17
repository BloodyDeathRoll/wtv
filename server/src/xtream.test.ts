import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  createXtream,
  toChannel,
  toMovie,
  toMovieInfo,
  toProgrammes,
  toSeries,
  toSeriesInfo,
  XtreamError,
} from './xtream.ts'

const b64 = (s: string) => Buffer.from(s, 'utf8').toString('base64')

/** A fetch that answers each `action` from a table and records the calls. */
function fakeFetch(answers: Record<string, unknown>) {
  const calls: { url: URL; userAgent: string | null; init: RequestInit | undefined }[] = []
  const fetchFn = (async (input: URL | RequestInfo, init?: RequestInit) => {
    const url = new URL(String(input))
    calls.push({ url, userAgent: new Headers(init?.headers).get('User-Agent'), init })
    const answer = answers[url.searchParams.get('action') ?? 'sign-in']
    if (answer instanceof Response) return answer
    return Response.json(answer)
  }) as typeof fetch
  return { fetchFn, calls }
}

const config = { server: 'https://provider.example:443', user: 'u', password: 'p' }

test('movie row: provider strings become typed values', () => {
  const movie = toMovie({
    stream_id: 387982,
    name: 'החיה (2026)',
    title: 'החיה',
    year: '2026',
    rating: 5.3,
    added: '1794871453',
    plot: ' plot ',
    cast: 'A, B',
    director: 'D',
    genre: 'אקשן, מותחן',
    youtube_trailer: 'p_F6pzv20Vg',
    episode_run_time: '99',
    category_id: '118',
    category_ids: [118],
    container_extension: 'MP4',
    stream_icon: 'https://img/p.jpg',
  })
  assert.deepEqual(movie, {
    kind: 'movie',
    extId: 387982,
    name: 'החיה',
    year: 2026,
    plot: 'plot',
    genres: 'אקשן, מותחן',
    castNames: 'A, B',
    director: 'D',
    rating: 5.3,
    posterUrl: 'https://img/p.jpg',
    backdropUrl: null,
    trailer: 'p_F6pzv20Vg',
    runtimeMin: 99,
    containerExt: 'mp4',
    categoryIds: [118],
    addedAt: new Date(1794871453 * 1000),
  })
})

test('movie row: unknown values are null, whatever form the provider uses', () => {
  const movie = toMovie({
    stream_id: 1,
    name: 'Only name (1999)',
    title: null,
    year: null,
    rating: 0,
    plot: '',
    cast: null,
    youtube_trailer: '',
    episode_run_time: 0,
    category_id: '7',
    stream_icon: '',
    added: '',
  })
  assert.equal(movie?.name, 'Only name (1999)')
  for (const key of ['year', 'rating', 'plot', 'castNames', 'trailer', 'runtimeMin', 'posterUrl', 'addedAt'] as const) {
    assert.equal(movie?.[key], null, key)
  }
  // No category_ids list: falls back to the single category_id.
  assert.deepEqual(movie?.categoryIds, [7])
})

test('a rating below 1 is kept', () => {
  assert.equal(toMovie({ stream_id: 1, name: 'x', rating: '0.5' })?.rating, 0.5)
})

test('rows without an id or a name are dropped', () => {
  assert.equal(toMovie({ stream_id: 5, name: null, title: null }), null)
  assert.equal(toMovie({ name: 'x' }), null)
  assert.equal(toSeries({ series_id: 5, name: '' }), null)
  assert.equal(toChannel({ stream_id: 5 }), null)
})

test('series row: backdrop list, string rating, last_modified', () => {
  const series = toSeries({
    series_id: 5829,
    name: 'דוקטור X (2026)',
    title: 'דוקטור X',
    year: '2026',
    rating: '9',
    last_modified: '1794873137',
    cover: 'https://img/c.jpg',
    backdrop_path: ['https://img/b1.jpg', 'https://img/b2.jpg'],
    episode_run_time: '0',
    youtube_trailer: null,
    category_ids: [107],
  })
  assert.equal(series?.kind, 'series')
  assert.equal(series?.rating, 9)
  assert.equal(series?.posterUrl, 'https://img/c.jpg')
  assert.equal(series?.backdropUrl, 'https://img/b1.jpg')
  assert.equal(series?.runtimeMin, null)
  assert.equal(series?.containerExt, null)
  assert.deepEqual(series?.addedAt, new Date(1794873137 * 1000))
  assert.equal(toSeries({ series_id: 1, name: 'x', backdrop_path: [] })?.backdropUrl, null)
})

test('channel row: catch-up days, radio, missing guide id', () => {
  assert.deepEqual(
    toChannel({ stream_id: 9, name: 'Ch', num: 3, stream_type: 'live', tv_archive: 1, tv_archive_duration: 7, epg_channel_id: 'x.il', stream_icon: '', category_ids: [1] }),
    { extId: 9, name: 'Ch', num: 3, logoUrl: null, epgChannelId: 'x.il', archiveDays: 7, isRadio: false, categoryIds: [1] },
  )
  const radio = toChannel({ stream_id: 10, name: 'FM', stream_type: 'radio_streams', tv_archive: 0, tv_archive_duration: 5, epg_channel_id: null })
  assert.equal(radio?.isRadio, true)
  // A duration without the archive flag is not catch-up.
  assert.equal(radio?.archiveDays, 0)
  assert.equal(radio?.epgChannelId, null)
})

test('movie details: TMDB id, duration, backdrop', () => {
  assert.deepEqual(
    toMovieInfo({ info: { tmdb_id: 1185344, duration_secs: 5940, backdrop_path: ['https://img/b.jpg'] }, movie_data: {} }),
    { tmdbId: 1185344, durationSecs: 5940, backdropUrl: 'https://img/b.jpg' },
  )
  assert.deepEqual(toMovieInfo({ info: { tmdb_id: '', duration_secs: 0, backdrop_path: '' } }), { tmdbId: null, durationSecs: null, backdropUrl: null })
  // The provider answers `{"info": []}` for an unknown id.
  assert.deepEqual(toMovieInfo({ info: [] }), { tmdbId: null, durationSecs: null, backdropUrl: null })
})

test('series details: season TMDB ids and episodes, for both episode layouts', () => {
  const episode = {
    id: '369702',
    episode_num: '1',
    title: 'S01E01',
    container_extension: 'mp4',
    season: 1,
    added: '1793482517',
    info: { tmdb_id: '6301744', plot: '', duration_secs: '3974', movie_image: 'https://img/e.jpg' },
  }
  const expected = {
    extId: 369702,
    season: 1,
    episode: 1,
    name: 'S01E01',
    plot: null,
    durationSecs: 3974,
    imageUrl: 'https://img/e.jpg',
    containerExt: 'mp4',
    addedAt: new Date(1793482517 * 1000),
  }
  const seasons = [{ id: 460408, season_number: 1 }, { id: 0, season_number: 2 }]

  const keyed = toSeriesInfo({ seasons, info: {}, episodes: { '1': [episode, { id: 'bad' }] } })
  assert.deepEqual(keyed, { tmdbSeasonIds: { 1: 460408 }, episodes: [expected] })

  const repeated = toSeriesInfo({ seasons: [], episodes: { '1': [episode], '2': [{ ...episode, title: 'repeat' }] } })
  assert.deepEqual(repeated.episodes, [expected])

  const listed = toSeriesInfo({ seasons: [], episodes: [[episode]] })
  assert.deepEqual(listed, { tmdbSeasonIds: {}, episodes: [expected] })

  assert.deepEqual(toSeriesInfo({ info: [], episodes: [] }), { tmdbSeasonIds: {}, episodes: [] })
})

test('programmes: base64 text is decoded', () => {
  const body = {
    epg_listings: [
      { title: b64('חדשות'), description: b64('תיאור'), start_timestamp: '1794909600', stop_timestamp: '1794920400' },
      { title: b64('No description'), description: '', start_timestamp: 1794920400, stop_timestamp: 1794931200 },
      { title: '', start_timestamp: '1', stop_timestamp: '2' },
    ],
  }
  assert.deepEqual(toProgrammes(body), [
    { title: 'חדשות', description: 'תיאור', start: new Date(1794909600_000), end: new Date(1794920400_000) },
    { title: 'No description', description: null, start: new Date(1794920400_000), end: new Date(1794931200_000) },
  ])
  assert.deepEqual(toProgrammes({ epg_listings: [] }), [])
})

test('programmes: text that is not base64 is kept as it is', () => {
  const [programme] = toProgrammes({
    epg_listings: [{ title: 'News at 9!', description: 'חדשות', start_timestamp: 1, stop_timestamp: 2 }],
  })
  assert.equal(programme?.title, 'News at 9!')
  assert.equal(programme?.description, 'חדשות')
})

test('programmes: a short plain word made of base64 letters is not decoded to junk', () => {
  for (const title of ['News', 'Lost', 'Sport1']) {
    const [programme] = toProgrammes({ epg_listings: [{ title, start_timestamp: 1, stop_timestamp: 2 }] })
    assert.equal(programme?.title, title)
  }
})

test('ids accept plain decimals only', () => {
  assert.equal(toMovie({ stream_id: '12', name: 'x' })?.extId, 12)
  assert.equal(toMovie({ stream_id: '0x10', name: 'x' }), null)
  assert.equal(toMovie({ stream_id: '1e3', name: 'x' }), null)
})

test('lists: a title in two categories comes back once, with both', async () => {
  const { fetchFn } = fakeFetch({
    get_vod_streams: [
      { stream_id: 1, name: 'A', category_ids: [10] },
      { stream_id: 2, name: 'B', category_ids: [10] },
      { stream_id: 1, name: 'A', category_ids: [20] },
    ],
  })
  const movies = await createXtream(config, fetchFn).movies()
  assert.deepEqual(movies.map(m => [m.extId, m.categoryIds]), [[1, [10, 20]], [2, [10]]])
})

test('requests carry the credentials, the action and the player user agent', async () => {
  const { fetchFn, calls } = fakeFetch({ get_vod_info: { info: {} }, get_short_epg: { epg_listings: [] } })
  const xtream = createXtream(config, fetchFn)
  await xtream.movieInfo(42)
  await xtream.programmes(7, 2)
  const [first, second] = calls
  assert.ok(first && second)
  assert.equal(first.url.origin + first.url.pathname, 'https://provider.example/player_api.php')
  assert.deepEqual(Object.fromEntries(first.url.searchParams), { username: 'u', password: 'p', action: 'get_vod_info', vod_id: '42' })
  assert.equal(first.userAgent, 'okhttp/4.12.0')
  // Credentials are in the URL: no redirect is followed, and every request has a time limit.
  assert.equal(first.init?.redirect, 'error')
  assert.ok(first.init?.signal instanceof AbortSignal)
  assert.deepEqual(Object.fromEntries(second.url.searchParams), { username: 'u', password: 'p', action: 'get_short_epg', stream_id: '7', limit: '2' })
})

test('a server given without a scheme is called over https', async () => {
  const { fetchFn, calls } = fakeFetch({ get_vod_info: { info: {} } })
  await createXtream({ ...config, server: 'provider.example:8443' }, fetchFn).movieInfo(1)
  assert.equal(calls[0]?.url.origin, 'https://provider.example:8443')
})

test('a path in the server is kept', async () => {
  const { fetchFn, calls } = fakeFetch({ get_vod_info: { info: {} } })
  for (const server of ['https://provider.example/panel', 'https://provider.example/panel/', 'https://provider.example/panel?x=1#y', 'https://a:b@provider.example']) {
    await createXtream({ ...config, server }, fetchFn).movieInfo(1)
  }
  assert.deepEqual(calls.map(c => c.url.pathname), ['/panel/player_api.php', '/panel/player_api.php', '/panel/player_api.php', '/player_api.php'])
  assert.equal(calls[2]?.url.searchParams.get('x'), null)
  assert.equal(`${calls[3]?.url.username}${calls[3]?.url.password}`, '')
})

test('categories keep the provider order', async () => {
  const { fetchFn } = fakeFetch({
    get_live_categories: [
      { category_id: '1', category_name: 'israel  - ישראל', parent_id: 0 },
      { category_id: '', category_name: 'broken' },
      { category_id: '4', category_name: 'רדיו', parent_id: 0 },
    ],
  })
  assert.deepEqual(await createXtream(config, fetchFn).categories('live'), [
    { kind: 'live', extId: 1, name: 'israel  - ישראל', position: 0 },
    { kind: 'live', extId: 4, name: 'רדיו', position: 2 },
  ])
})

test('sign-in: active account passes, anything else throws', async () => {
  const active = fakeFetch({ 'sign-in': { user_info: { status: 'Active', max_connections: '3', exp_date: '1810063028' } } })
  assert.deepEqual(await createXtream(config, active.fetchFn).signIn(), { maxConnections: 3, expiresAt: new Date(1810063028_000) })

  const expired = fakeFetch({ 'sign-in': { user_info: { status: 'Expired' } } })
  await assert.rejects(createXtream(config, expired.fetchFn).signIn(), XtreamError)
})

test('errors never contain the credentials', async () => {
  const secret = { server: 'https://provider.example', user: 'USER-SECRET', password: 'PASS-SECRET' }
  const cases: Record<string, typeof fetch> = {
    blocked: fakeFetch({ get_vod_streams: new Response('<html>blocked</html>', { status: 403 }) }).fetchFn,
    'not json': fakeFetch({ get_vod_streams: new Response('<html>ok</html>', { status: 200 }) }).fetchFn,
    'not a list': fakeFetch({ get_vod_streams: { error: 'x' } }).fetchFn,
    network: (async (input: URL | RequestInfo) => {
      // Like undici: the real reason sits in `cause`, and may name the URL.
      throw new TypeError('fetch failed', { cause: Object.assign(new Error(`connect failed ${String(input)}`), { code: 'ECONNRESET' }) })
    }) as typeof fetch,
    timeout: (async () => {
      throw new DOMException('The operation was aborted due to timeout', 'TimeoutError')
    }) as typeof fetch,
  }
  const expected: Record<string, string> = {
    blocked: 'get_vod_streams: HTTP 403',
    'not json': 'get_vod_streams: the answer is not JSON',
    'not a list': 'movies: expected a list',
    network: 'get_vod_streams: request failed (ECONNRESET)',
    timeout: 'get_vod_streams: request failed (TimeoutError)',
  }
  for (const [name, fetchFn] of Object.entries(cases)) {
    await assert.rejects(createXtream(secret, fetchFn).movies(), (err: unknown) => {
      assert.ok(err instanceof XtreamError, name)
      assert.equal(err.message, expected[name], name)
      // Nothing attached that a logger could print the URL from.
      assert.equal(err.cause, undefined, name)
      assert.doesNotMatch(JSON.stringify(err, Object.getOwnPropertyNames(err)), /SECRET/, name)
      return true
    })
  }
})
