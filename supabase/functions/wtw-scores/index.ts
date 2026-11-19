/**
 * WTW's own "% match" for the given titles, for the signed-in WTV user, asked
 * of WTW itself (_shared/wtw/score-api.ts) and kept in `wtw_scores` for KEEP_HOURS. The app
 * sends the cards it shows; titles already kept answer at once.
 *
 * Body: { wtw_token: string, title_ids: number[] } (at most MAX_TITLES)
 * Answer: { scores: { [title_id]: number | null } } — the percent WTW shows
 * (0–97), null when WTW does not score the title. Titles WTW could not be
 * asked about this time are left out.
 */
import { createClient } from 'npm:@supabase/supabase-js@2.49.4'
import postgres from 'npm:postgres@3.4.5'
import { answerOf, claimsOf, eachLimited, sessionCookie, type WtwAnswer } from '../_shared/wtw/score-api.ts'

const WTW_SITE = Deno.env.get('WTW_SITE_URL') ?? 'https://wtw-wine.vercel.app'
const MAX_TITLES = 40
/** Calls to WTW at once, per request: WTW's own server, so kept small. */
const PARALLEL = 6
const CALL_TIMEOUT_MS = 20_000
/** How long a WTW answer is kept (the migration's wtw_match reads the same window). */
const KEEP_HOURS = 12
/** The token must outlive the calls with room to spare: below WTW's own refresh margin it would try to refresh. */
const MIN_TOKEN_SECONDS = 150

const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!, { prepare: false })
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

Deno.serve(async req => {
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405)
  const body = await req.json().catch(() => null) as { wtw_token?: unknown; title_ids?: unknown } | null
  const wtwToken = typeof body?.wtw_token === 'string' ? body.wtw_token : null
  const ids = Array.isArray(body?.title_ids) ? [...new Set(body.title_ids.filter((x): x is number => Number.isSafeInteger(x)))] : null
  if (!wtwToken || !ids) return json({ error: 'wtw_token and title_ids required' }, 400)
  if (ids.length > MAX_TITLES) return json({ error: `At most ${MAX_TITLES} titles` }, 400)

  const publicKey = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ?? ''
  const wtv = createClient(Deno.env.get('SUPABASE_URL')!, publicKey, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } })
  const { data: wtvUser, error: wtvError } = await wtv.auth.getUser()
  if (wtvError || !wtvUser.user) return json({ error: 'Not signed in to WTV' }, 401)
  const userId = wtvUser.user.id

  const claims = claimsOf(wtwToken)
  if (!claims) return json({ error: 'WTW session not valid' }, 401)
  if (claims.exp - Date.now() / 1000 < MIN_TOKEN_SECONDS) return json({ error: 'WTW session about to expire' }, 409)

  // Another WTW account than last time: what was kept is not this account's.
  await sql`delete from public.wtw_scores where user_id = ${userId} and wtw_user_id <> ${claims.sub}`

  const titles = ids.length === 0 ? [] : await sql<{ id: number; kind: string; tmdb_id: number }[]>`
    select id, kind, tmdb_id from public.titles where id = any(${ids}::bigint[]) and tmdb_id is not null`
  const kept = new Map<string, number | null>()
  if (titles.length > 0) {
    const rows = await sql<{ kind: string; tmdb_id: number; match: number | null }[]>`
      select kind, tmdb_id, match from public.wtw_scores
      where user_id = ${userId} and scored_at > now() - make_interval(hours => ${KEEP_HOURS})
        and (kind, tmdb_id) in (select * from unnest(${titles.map(t => t.kind)}::text[], ${titles.map(t => t.tmdb_id)}::int[]))`
    for (const r of rows) kept.set(`${r.kind}:${r.tmdb_id}`, r.match)
  }

  const missing = [...new Map(titles.filter(t => !kept.has(`${t.kind}:${t.tmdb_id}`)).map(t => [`${t.kind}:${t.tmdb_id}`, t])).values()]
  const cookie = sessionCookie(Deno.env.get('WTW_SUPABASE_URL')!, wtwToken, claims.exp)
  const asked: { kind: string; tmdb_id: number; answer: WtwAnswer }[] = []
  await eachLimited(missing, PARALLEL, async t => {
    const type = t.kind === 'movie' ? 'movie' : 'tv'
    try {
      const res = await fetch(`${WTW_SITE}/api/recommendations/score?type=${type}&tmdb_id=${t.tmdb_id}`, {
        headers: { cookie }, signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
      })
      const answer = answerOf(res.status, await res.json().catch(() => null))
      if (res.status === 401) console.warn('[wtw-scores] WTW refused the session')
      if (answer) asked.push({ kind: t.kind, tmdb_id: t.tmdb_id, answer })
    } catch (err) {
      console.warn(`[wtw-scores] ${type}:${t.tmdb_id} not asked:`, err instanceof Error ? err.message : err)
    }
  })
  if (asked.length > 0) {
    await sql`insert into public.wtw_scores (user_id, wtw_user_id, kind, tmdb_id, match, scored_at)
      select ${userId}, ${claims.sub}, * , now() from unnest(${asked.map(a => a.kind)}::text[], ${asked.map(a => a.tmdb_id)}::int[], ${asked.map(a => a.answer.match)}::real[])
      on conflict (user_id, kind, tmdb_id) do update set wtw_user_id = excluded.wtw_user_id, match = excluded.match, scored_at = excluded.scored_at`
    for (const a of asked) kept.set(`${a.kind}:${a.tmdb_id}`, a.answer.match)
  }

  const scores: Record<string, number | null> = {}
  for (const t of titles) {
    const k = `${t.kind}:${t.tmdb_id}`
    if (!kept.has(k)) continue
    const m = kept.get(k)
    // Below half a percent shows as no claim, not "0% match".
    scores[String(t.id)] = m != null && m >= 0.005 ? Math.round(Math.min(m, 0.97) * 100) : null
  }
  return json({ scores })
})
