/**
 * Asking WTW itself for its "% match": WTW's GET /api/recommendations/score
 * (WTW src/app/api/recommendations/score/route.ts, score-one.ts) answers one
 * title for the signed-in user with the match WTW shows (`match`, 0–0.97).
 * The route reads WTW's Supabase session from its cookie (@supabase/ssr), so
 * the user's WTW access token is passed as that cookie. No refresh token goes
 * with it: WTW never refreshes (and so never rotates) the user's session here;
 * an access token close to expiry is refused before asking.
 */

/** @supabase/ssr's cookie for a session: `sb-<ref>-auth-token`, "base64-" + base64url(JSON), in chunks above its limit. */
export function sessionCookie(supabaseUrl: string, accessToken: string, expiresAt: number): string {
  const ref = new URL(supabaseUrl).hostname.split('.')[0]
  const name = `sb-${ref}-auth-token`
  const session = { access_token: accessToken, token_type: 'bearer', expires_at: expiresAt, expires_in: Math.max(0, expiresAt - Math.floor(Date.now() / 1000)), refresh_token: '' }
  const value = 'base64-' + base64url(JSON.stringify(session))
  if (value.length <= CHUNK) return `${name}=${value}`
  const parts: string[] = []
  for (let i = 0; i * CHUNK < value.length; i++) parts.push(`${name}.${i}=${value.slice(i * CHUNK, (i + 1) * CHUNK)}`)
  return parts.join('; ')
}

/** @supabase/ssr's MAX_CHUNK_SIZE. */
const CHUNK = 3180

function base64url(s: string): string {
  const bytes = new TextEncoder().encode(s)
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

/** A JWT's `exp` and `sub`, unverified (WTW verifies the token; this only decides whether to ask). */
export function claimsOf(jwt: string): { exp: number; sub: string } | null {
  try {
    const part = jwt.split('.')[1]!.replace(/-/g, '+').replace(/_/g, '/')
    const json = JSON.parse(atob(part + '='.repeat((4 - (part.length % 4)) % 4)))
    return typeof json.exp === 'number' && typeof json.sub === 'string' ? { exp: json.exp, sub: json.sub } : null
  } catch {
    return null
  }
}

/** What WTW answered for one title: its match (0–0.97), null when WTW scores it not at all (not in its catalogue, cold start). */
export type WtwAnswer = { match: number | null }

/** WTW's answer, or undefined when it could not be had (network, 5xx, timeout): undefined is not stored. */
export function answerOf(status: number, body: unknown): WtwAnswer | undefined {
  if (status !== 200 || typeof body !== 'object' || body === null) return undefined
  const b = body as { scored?: unknown; match?: unknown }
  if (b.scored === false) return { match: null }
  return b.scored === true && typeof b.match === 'number' ? { match: b.match } : undefined
}

/** Runs `work` over `items`, at most `limit` at a time. */
export async function eachLimited<T>(items: T[], limit: number, work: (item: T) => Promise<void>): Promise<void> {
  let next = 0
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) await work(items[next++]!)
  }))
}
