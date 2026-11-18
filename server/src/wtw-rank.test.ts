// Ported from WTW at 79b226d, same numbers: tests/unit/step2-formula-v2.test.ts
// (the FORMULA_V2 cases that rank; narrative, the flag, the training memo and
// rated_down_genres are not ported), external-rating-score.test.ts, the crew
// affinity cases of scoring.test.ts, title-key.test.ts (titleKey/parseTitleKey)
// and reaction-score.test.ts. WTW has no lineage-boost test; the lineage cases
// below are new.
import assert from 'node:assert/strict'
import { describe, test } from 'node:test'
import { blankDNA, type CrewAffinityEntry, type StrandA, type TitleRow, type TMDBCrewSnapshot } from '../../supabase/functions/_shared/wtw/dna.ts'
import { externalRatingScore, scoreV2 } from '../../supabase/functions/_shared/wtw/step2.ts'
import { computeCrewAffinity } from '../../supabase/functions/_shared/wtw/crew-affinity.ts'
import {
  computeBoostFromCaches, degree1Ids, getBoostEligibleIds, lineageCacheFromRows,
} from '../../supabase/functions/_shared/wtw/lineage-boost.ts'
import { parseTitleKey, titleKey } from '../../supabase/functions/_shared/wtw/title-key.ts'
import { REACTION_SCORE, clamp, confidenceDelta, lineageBoost } from '../../supabase/functions/_shared/wtw/reaction-score.ts'

/** vitest's toBeCloseTo(expected, digits). */
const close = (actual: number, expected: number, digits = 2) =>
  assert.ok(Math.abs(actual - expected) < 10 ** -digits / 2, `${actual} ≉ ${expected} (${digits} digits)`)

const emptyCrew = (): TMDBCrewSnapshot => ({ directors: [], writers: [], cinematographers: [], cast: [] })

// ── step2-formula-v2.test.ts ─────────────────────────────────────

const title = (tmdb_id: string, tmdb_rating: number): TitleRow =>
  ({ tmdb_id, type: 'movie', tmdb_rating, omdb_rating: null, crew: emptyCrew() })

const vec = (first: number) => [first, ...new Array<number>(24).fill(0)]
// A one-input model: the score is 2 × the vector's first entry.
const W = [2, ...new Array<number>(24).fill(0)]

describe('step 2 — formula v2', () => {
  test('ranks by the taste model over the crowd, with the parts stored', () => {
    // "liked" has the lower crowd score but the much higher model score.
    const vecs = new Map([['movie:liked', vec(1)], ['movie:meh', vec(-1)]])
    const out = scoreV2([title('meh', 8), title('liked', 7)], blankDNA(), W, vecs)

    assert.deepEqual(out.map(s => s.title.tmdb_id), ['liked', 'meh'])
    const [liked, meh] = out as [typeof out[0], typeof out[0]]
    assert.equal(liked.model_score, 2)
    assert.equal(meh.model_score, -2)
    close(liked.z_model, 1, 12)
    close(liked.z_crowd, -1, 12)
    assert.ok(liked.composite > 0.5)
    assert.ok(liked.composite < 1)
  })

  test('a title with no vector scores at the pool mean on the model', () => {
    const vecs = new Map([['movie:a', vec(1)], ['movie:c', vec(-1)]])
    const out = scoreV2([title('a', 7), title('b', 7), title('c', 7)], blankDNA(), W, vecs)
    const b = out.find(s => s.title.tmdb_id === 'b')!
    assert.equal(b.model_score, null)
    assert.equal(b.z_model, 0)
    close(b.composite, 0.5, 12)
  })

  test('does not match a series to a movie that shares its id', () => {
    const vecs = new Map([['tv:a', vec(1)]])
    const out = scoreV2([title('a', 7), title('b', 8)], blankDNA(), W, vecs)
    assert.equal(out.find(s => s.title.tmdb_id === 'a')?.model_score, null)
  })

  test('if the model cannot load, scores on creators and crowd and keeps the feed', () => {
    const vecs = new Map([['movie:a', vec(1)]])
    const out = scoreV2([title('a', 6), title('b', 8)], blankDNA(), null, vecs)
    assert.deepEqual(out.map(s => s.title.tmdb_id), ['b', 'a']) // the crowd decides
    assert.ok(out.every(s => s.z_model === 0))
  })

  test('an empty pool returns nothing', () => {
    assert.deepEqual(scoreV2([], blankDNA(), W, new Map()), [])
  })
})

// ── external-rating-score.test.ts ────────────────────────────────

describe('externalRatingScore — the crowd score', () => {
  test('TMDB only: the TMDB rating over 10, not halved', () => {
    close(externalRatingScore({ tmdb_rating: 8, omdb_rating: null }), 0.8, 10)
  })

  test('OMDB only: the OMDB rating as stored (already 0–1), not halved or divided by 10', () => {
    close(externalRatingScore({ tmdb_rating: null, omdb_rating: 0.9 }), 0.9, 10)
  })

  test('both: unchanged, 60% TMDB + 40% OMDB', () => {
    close(externalRatingScore({ tmdb_rating: 8, omdb_rating: 0.9 }), 0.6 * 0.8 + 0.4 * 0.9, 10)
  })

  test('a title with one rating scores like a title with two equal ones', () => {
    const both = externalRatingScore({ tmdb_rating: 7, omdb_rating: 0.7 })
    close(externalRatingScore({ tmdb_rating: 7, omdb_rating: null }), both, 10)
    close(externalRatingScore({ tmdb_rating: null, omdb_rating: 0.7 }), both, 10)
  })

  test('neither: neutral 0.5', () => {
    assert.equal(externalRatingScore({ tmdb_rating: null, omdb_rating: null }), 0.5)
  })

  test('a rating of 0 counts as a rating, not as missing', () => {
    assert.equal(externalRatingScore({ tmdb_rating: 0, omdb_rating: null }), 0)
    assert.equal(externalRatingScore({ tmdb_rating: null, omdb_rating: 0 }), 0)
  })
})

// ── scoring.test.ts (crew affinity) ──────────────────────────────

const person = (id: string, name = id) => ({ tmdb_person_id: id, name, order: 0 })
const crew = (o: Partial<TMDBCrewSnapshot>): TMDBCrewSnapshot => ({ ...emptyCrew(), ...o })
// score is the average reaction level: +0.30 = always loved, −0.20 = always disliked
const entry = (score: number, confidence = 1, lineage_boost: CrewAffinityEntry['lineage_boost'] = 'none'): CrewAffinityEntry =>
  ({ name: 'x', score, confidence, sample_size: 1, lineage_boost })
const strandA = (o: Partial<StrandA>): StrandA => ({ directors: {}, writers: {}, cinematographers: {}, actors: {}, ...o })

describe('crew affinity — strongest match per role', () => {
  test('is not diluted by unknown crew', () => {
    const a = strandA({ directors: { d1: entry(0.3) } })
    const alone = computeCrewAffinity(crew({ directors: [person('d1')] }), a).score
    const withUnknowns = computeCrewAffinity(
      crew({ directors: [person('d1')], writers: [person('w1'), person('w2'), person('w3')], cast: [person('c1'), person('c2')] }),
      a,
    ).score
    close(withUnknowns, alone, 6)
    assert.ok(alone > 0.5)
  })

  test('takes the strongest signal in a role, keeping its sign', () => {
    const a = strandA({ actors: { c1: entry(0.1), c2: entry(-0.2) } })
    const r = computeCrewAffinity(crew({ cast: [person('c1'), person('c2'), person('c3')] }), a)
    assert.ok(r.score < 0.5) // the always-disliked actor dominates the mildly-liked one
    assert.equal(r.crew_matches.length, 2)
  })

  test('is neutral with no known crew at all', () => {
    assert.equal(computeCrewAffinity(crew({ directors: [person('d9')] }), strandA({})).score, 0.5)
  })
})

// ── lineage boost (new) ──────────────────────────────────────────

describe('lineage boost', () => {
  const a = strandA({
    directors: { d1: entry(0.3, 1, 'high'), d2: entry(0.3, 1, 'low') },
    actors: { c9: entry(0.3, 1, 'high') },
  })
  const onTitle = crew({ directors: [person('d1')], writers: [person('w1')], cinematographers: [person('dp1')] })
  const other = crew({ directors: [person('x')] })
  const d1 = lineageCacheFromRows([{ tmdb_person_id: 'd1', lineage_influences: { influences: [
    { id: 'w1', name: 'W1', relationship: 'mentored' },
    { id: 'x', name: 'X', relationship: 'inspired' },
  ] } }])
  const d2 = lineageCacheFromRows([{ tmdb_person_id: 'x', lineage_influences: { influences: [{ id: 'dp1', name: 'DP1', relationship: 'inspired' }] } }])

  test('only medium/high directors, writers and cinematographers are eligible', () => {
    assert.deepEqual(getBoostEligibleIds(a), ['d1'])
  })

  test('degree-1 ids are the influenced people on some candidate\'s crew', () => {
    assert.deepEqual(degree1Ids([{ crew: onTitle }], d1), ['w1'])
    assert.deepEqual(degree1Ids([{ crew: onTitle }, { crew: other }], d1), ['w1', 'x'])
  })

  test('degree 1 adds score × confidence × 0.5, degree 2 × 0.25', () => {
    close(computeBoostFromCaches(onTitle, a, d1, new Map()).boost, 0.15, 12)
    const r = computeBoostFromCaches(onTitle, a, d1, d2)
    close(r.boost, 0.225, 12)
    assert.deepEqual(r.lineage_connections, [
      { from: 'd1', to: 'W1', relationship: 'mentored' },
      { from: 'X', to: 'DP1', relationship: 'inspired' },
    ])
  })

  test('creators = min(1, crew affinity + boost) in the v2 ranking', () => {
    const t: TitleRow = { tmdb_id: '1', type: 'movie', tmdb_rating: 7, omdb_rating: null, crew: onTitle }
    const [s] = scoreV2([t], { strand_a_creative_affinity: a }, null, new Map(), d1, d2)
    close(s!.crew_affinity_score, 0.7 + 0.225, 12) // director at full affinity: (0.4 + 1) / 2
  })

  test('the boost is capped at 0.4', () => {
    const many = lineageCacheFromRows([{ tmdb_person_id: 'd1', lineage_influences: { influences: [
      { id: 'w1', name: 'W1', relationship: 'r' }, { id: 'w1', name: 'W1', relationship: 'r' }, { id: 'dp1', name: 'DP1', relationship: 'r' },
    ] } }])
    assert.equal(computeBoostFromCaches(onTitle, a, many, new Map()).boost, 0.4)
  })
})

// ── title-key.test.ts ────────────────────────────────────────────

describe('titleKey / parseTitleKey', () => {
  test('round-trips', () => {
    assert.deepEqual(parseTitleKey(titleKey('movie', '105')), { type: 'movie', tmdb_id: '105' })
    assert.deepEqual(parseTitleKey('tv:1396'), { type: 'tv', tmdb_id: '1396' })
  })

  test('treats anything unprefixed as type-unknown, id intact', () => {
    assert.deepEqual(parseTitleKey('105'), { type: null, tmdb_id: '105' })
    assert.deepEqual(parseTitleKey('tt-aftersun'), { type: null, tmdb_id: 'tt-aftersun' })
    assert.deepEqual(parseTitleKey(''), { type: null, tmdb_id: '' })
  })
})

// ── reaction-score.test.ts ───────────────────────────────────────

describe('reaction score', () => {
  test('clamp bounds a value to [min,max]', () => {
    assert.equal(clamp(1.4, 0, 1), 1)
    assert.equal(clamp(-0.3, 0, 1), 0)
    assert.equal(clamp(0.5, 0, 1), 0.5)
  })

  test('confidenceDelta rewards a corroborating signal and penalises a contradicting one', () => {
    assert.ok(confidenceDelta(0.3, 0.15) > 0)
    assert.ok(confidenceDelta(-0.3, -0.2) > 0)
    assert.ok(confidenceDelta(0.3, -0.2) < 0)
    assert.ok(confidenceDelta(-0.3, 0.15) < 0)
  })

  test('lineageBoost maps score bands to tiers', () => {
    assert.equal(lineageBoost(0.8), 'high')
    assert.equal(lineageBoost(0.5), 'medium')
    assert.equal(lineageBoost(0.2), 'low')
    assert.equal(lineageBoost(0), 'none')
    assert.equal(lineageBoost(-0.5), 'none')
  })

  test('REACTION_SCORE orders reactions loved > liked > disliked', () => {
    assert.ok(REACTION_SCORE.loved > REACTION_SCORE.liked)
    assert.ok(REACTION_SCORE.liked > REACTION_SCORE.disliked)
  })
})
