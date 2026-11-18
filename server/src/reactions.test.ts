import assert from 'node:assert/strict'
import { test } from 'node:test'
import { normalTmdbId, reactionsByKey } from '../../supabase/functions/_shared/reactions.ts'
import { vecKey } from '../../supabase/functions/_shared/wtw/step2.ts'

test('reactions are keyed like the pool; the last rating of a title wins; unknown reactions are skipped', () => {
  const r = reactionsByKey([
    { type: 'movie', tmdb_id: '603', reaction: 'liked' },
    { type: 'movie', tmdb_id: '0603', reaction: 'loved' },
    { type: 'tv', tmdb_id: '603', reaction: 'disliked' },
    { type: 'movie', tmdb_id: '11', reaction: 'mixed' as 'liked' },
  ])
  // The pool keys a WTV title by its numeric TMDB id.
  assert.equal(r.get(vecKey({ type: 'movie', tmdb_id: String(603) })), 'loved')
  assert.equal(r.get(vecKey({ type: 'tv', tmdb_id: '603' })), 'disliked')
  assert.equal(r.has('movie:11'), false)
  assert.equal(r.size, 2)
  assert.equal(normalTmdbId(' 007 '), '7')
})
