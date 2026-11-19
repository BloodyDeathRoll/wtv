// supabase/functions/_shared/wtw/score-api.ts: the session cookie WTW's score route reads, and its answers.
import assert from 'node:assert/strict'
import { describe, test } from 'node:test'
import { answerOf, claimsOf, eachLimited, sessionCookie } from '../../supabase/functions/_shared/wtw/score-api.ts'

const jwt = (payload: object) => `h.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.s`
const decode = (cookie: string) => JSON.parse(Buffer.from(cookie.split('=').slice(1).join('=').replace(/^base64-/, ''), 'base64url').toString())

describe('sessionCookie', () => {
  test('is @supabase/ssr\'s cookie for the project, with the access token and no refresh token', () => {
    const cookie = sessionCookie('https://abcd1234.supabase.co', 'tok', 2_000_000_000)
    assert.match(cookie, /^sb-abcd1234-auth-token=base64-/)
    const s = decode(cookie)
    assert.equal(s.access_token, 'tok')
    assert.equal(s.refresh_token, '')
    assert.equal(s.expires_at, 2_000_000_000)
  })
  test('comes in numbered chunks above the cookie size limit', () => {
    const cookie = sessionCookie('https://abcd1234.supabase.co', 'x'.repeat(5000), 2_000_000_000)
    const parts = cookie.split('; ')
    assert.deepEqual(parts.map(p => p.split('=')[0]), ['sb-abcd1234-auth-token.0', 'sb-abcd1234-auth-token.1', 'sb-abcd1234-auth-token.2'])
    assert.equal(decode(`n=${parts.map(p => p.slice(p.indexOf('=') + 1)).join('')}`).access_token, 'x'.repeat(5000))
  })
})

describe('claimsOf', () => {
  test('reads exp and sub; anything else is null', () => {
    assert.deepEqual(claimsOf(jwt({ exp: 5, sub: 'u', other: 1 })), { exp: 5, sub: 'u' })
    assert.equal(claimsOf(jwt({ sub: 'u' })), null)
    assert.equal(claimsOf('not a token'), null)
  })
})

describe('answerOf', () => {
  test('a scored title is its match; an unscored one is null; anything else is not an answer', () => {
    assert.deepEqual(answerOf(200, { scored: true, match: 0.42 }), { match: 0.42 })
    assert.deepEqual(answerOf(200, { scored: false, reason: 'not_in_catalogue' }), { match: null })
    assert.equal(answerOf(500, { error: 'x' }), undefined)
    assert.equal(answerOf(401, { error: 'Unauthorized' }), undefined)
    assert.equal(answerOf(200, { scored: true }), undefined)
  })
})

describe('eachLimited', () => {
  test('does every item, never more than the limit at once', async () => {
    let running = 0, peak = 0
    const done: number[] = []
    await eachLimited([1, 2, 3, 4, 5, 6, 7], 3, async n => {
      peak = Math.max(peak, ++running)
      await new Promise(r => setTimeout(r, 5))
      done.push(n)
      running--
    })
    assert.equal(peak, 3)
    assert.deepEqual(done.sort(), [1, 2, 3, 4, 5, 6, 7])
  })
})
