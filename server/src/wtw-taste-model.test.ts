// Ported from WTW at 79b226d, same numbers: tests/unit/taste-model.test.ts,
// tests/unit/taste-model-genre-lean.test.ts and the pure parts of
// tests/unit/load-taste-training.test.ts (paging and chunking are the caller's
// reads here, so those cases are not ported).
import assert from 'node:assert/strict'
import { describe, test } from 'node:test'
import type { DNASignal } from '../../supabase/functions/_shared/wtw/dna.ts'
import { blankDNA } from '../../supabase/functions/_shared/wtw/dna.ts'
import { GAME_GENRES, type GameGenre, type PlayState } from '../../supabase/functions/_shared/wtw/brain.ts'
import { FEATURE_GENRES, FEATURE_SCALES, tasteFeatures } from '../../supabase/functions/_shared/wtw/features.ts'
import {
  buildTraining, contributions, GENRE_LEAN, genreLean, predict, trainTasteModel, type TastePair, type TasteRow,
} from '../../supabase/functions/_shared/wtw/taste-model.ts'
import { picksFromPayloads, tasteVecsFromRows, trainingTitleIds, trainUserWeights } from '../../supabase/functions/_shared/wtw/taste-training.ts'
import { scoreV2 } from '../../supabase/functions/_shared/wtw/step2.ts'

/** vitest's toBeCloseTo(expected, digits). */
const close = (actual: number, expected: number, digits = 2) =>
  assert.ok(Math.abs(actual - expected) < 10 ** -digits / 2, `${actual} ≉ ${expected} (${digits} digits)`)

/** MINSTD: the same draws in JS and Python. */
function generator(seed: number) {
  const M = 2147483647
  let x = seed
  return () => { x = (48271 * x) % M; return x / M }
}

// ── taste-model.test.ts ──────────────────────────────────────────

/**
 * Reference fixture: 40 titles from a MINSTD generator, 30 rated (every 5th
 * weighted 0.5), 10 picks. Expected weights from numpy (the script is in WTW's
 * tests/unit/taste-model.test.ts).
 */
const EXPECTED = [0.23710913838722575, -0.03617272317238878, -0.03412908800798539, -0.1131998060864687, -0.04544291394589758, -0.023515812806560853, 0.12430031961745878, 0.3793936459755021, -0.1753750096923113, 0.010728759892774437, 0.07919256447652062, 0.18767615925580222, -0.10500857208401478, -0.13725827932761528, 0.017223187863216242, 0.1462781969065317, -0.2456201741917539, 0.06481232112127877, -0.05164979645608253, 0.17625489900556318, 0.4926129871401926, 0.1478133638304314, 0.1564064546140105, 0.29036284782969796, -0.14686007231655898]

function refFixture() {
  const u = generator(42)
  const V = Array.from({ length: 40 }, () => { const first = u() * 6 - 3; return [first, ...Array.from({ length: 24 }, () => u() * 2 - 1)] })
  const rows: TasteRow[] = Array.from({ length: 30 }, (_, i) => ({ vec: V[i]!, level: (1 + Math.floor(u() * 3)) as 1 | 2 | 3, weight: i % 5 === 0 ? 0.5 : 1 }))
  const pairs: TastePair[] = Array.from({ length: 10 }, (_, k) => ({ chosen: V[30 + k]!, other: V[(7 * k) % 40]! }))
  return { rows, pairs }
}

const sig = (tmdb_id: string, reaction: DNASignal['reaction'], extra: Partial<DNASignal> = {}): DNASignal => ({
  tmdb_id, type: 'movie', reaction, source: 'manual', watched_at: null, ...extra,
})

describe('trainTasteModel', () => {
  test('matches the numpy reference recipe to 1e-6', () => {
    const { rows, pairs } = refFixture()
    const w = trainTasteModel(rows, pairs)
    assert.equal(w.length, 25)
    w.forEach((v, k) => assert.ok(Math.abs(v - EXPECTED[k]!) < 1e-6, `w[${k}]`))
  })

  test('returns zeros with no data', () => {
    assert.deepEqual(trainTasteModel([], []), new Array(25).fill(0))
  })
})

describe('predict / contributions', () => {
  test('contributions sum to the prediction', () => {
    const { rows, pairs } = refFixture()
    const w = trainTasteModel(rows, pairs)
    const c = contributions(w, rows[0]!.vec)
    close(c.reduce((s, v) => s + v, 0), predict(w, rows[0]!.vec), 12)
  })
})

describe('buildTraining', () => {
  const vec = (n: number) => new Array<number>(25).fill(n)
  const vecs = new Map([['movie:1', vec(1)], ['movie:2', vec(2)], ['movie:3', vec(3)], ['tv:1', vec(9)]])
  const now = Date.parse('2026-11-11T00:00:00Z')

  test('maps reactions to levels, halves old ratings, drops chat-named and vector-less titles', () => {
    const { rows } = buildTraining([
      sig('1', 'loved'),
      sig('2', 'disliked', { watched_at: '2024-01-01T00:00:00Z' }),
      sig('3', 'liked', { source: 'session_4' }),
      sig('4', 'liked'),
    ], [], vecs, now)
    assert.deepEqual(rows, [{ vec: vec(1), level: 3, weight: 1 }, { vec: vec(2), level: 1, weight: 0.5 }])
  })

  test('skips a legacy "mixed" reaction instead of training on NaN', () => {
    const { rows } = buildTraining([sig('1', 'mixed' as DNASignal['reaction']), sig('2', 'liked')], [], vecs, now)
    assert.deepEqual(rows.map(r => r.level), [2])
    assert.ok(trainTasteModel(rows, []).every(Number.isFinite))
  })

  test('treats a rating exactly 18 months old as recent, and a null watched_at as recent', () => {
    const edge = new Date(now - 18 * 30 * 24 * 60 * 60 * 1000).toISOString()
    const { rows } = buildTraining([sig('1', 'liked', { watched_at: edge }), sig('2', 'liked')], [], vecs, now)
    assert.deepEqual(rows.map(r => r.weight), [1, 1])
  })

  test('keys by media type, so a series never borrows a movie\'s vector', () => {
    const { rows } = buildTraining([sig('1', 'liked', { type: 'tv' })], [], vecs, now)
    assert.deepEqual(rows[0]!.vec, vec(9))
  })

  test('turns picks into chosen/other pairs, skipping ones without both vectors', () => {
    const { pairs } = buildTraining([], [
      { a: 'movie:1', b: 'movie:2', chosen: 'movie:2' },
      { a: 'movie:1', b: 'movie:9', chosen: 'movie:1' },
      { a: 'movie:1', b: 'movie:2', chosen: 'movie:3' },
      { a: 'movie:1', b: 'movie:1', chosen: 'movie:1' },
    ], vecs, now)
    assert.deepEqual(pairs, [{ chosen: vec(2), other: vec(1) }])
  })

  test('drops picks touching a held-out title (evaluation)', () => {
    const picks = [{ a: 'movie:1', b: 'movie:2', chosen: 'movie:2' }, { a: 'movie:1', b: 'movie:3', chosen: 'movie:3' }]
    assert.deepEqual(buildTraining([], picks, vecs, now, new Set(['movie:2'])).pairs, [{ chosen: vec(3), other: vec(1) }])
  })
})

// ── load-taste-training.test.ts (pure parts) ─────────────────────

describe('taste training inputs', () => {
  test('skips malformed picks and bare ids, and never mixes a movie with a same-id series', () => {
    const vec = (n: number) => JSON.stringify(new Array(25).fill(n))
    const dna = blankDNA()
    dna.signals.push(sig('1', 'loved', { type: 'tv' }))
    const picks = picksFromPayloads([
      ...Array.from({ length: 1000 }, () => ({ a: 'movie:1', b: 'movie:2', chosen: 'movie:2' })),
      { a: 'movie:1', b: 'movie:2', chosen: 'movie:1' },
      { a: 'movie:1', chosen: 'movie:1' },          // no b
      { a: '77', b: 'movie:2', chosen: '77' },      // bare id: no vector, no pair
    ])
    const { keys, ids } = trainingTitleIds(dna.signals, picks)
    assert.ok(!ids.includes('77'))
    const titles = [
      { tmdb_id: '1', type: 'movie', taste_vec: vec(1) },
      { tmdb_id: '1', type: 'tv', taste_vec: vec(9) },
      { tmdb_id: '2', type: 'movie', taste_vec: vec(2) },
    ].filter(t => ids.includes(t.tmdb_id))
    const { rows, pairs } = buildTraining(dna.signals, picks, tasteVecsFromRows(titles, keys))
    assert.deepEqual(rows, [{ vec: new Array(25).fill(9), level: 3, weight: 1 }])
    assert.equal(pairs.length, 1001)
    assert.deepEqual(pairs[1000], { chosen: new Array(25).fill(1), other: new Array(25).fill(2) })
  })

  test('a vector the query returns for a key nobody asked for is dropped', () => {
    const vecs = tasteVecsFromRows([{ tmdb_id: '1', type: 'tv', taste_vec: [1] }], new Set(['movie:1']))
    assert.equal(vecs.size, 0)
  })
})

// ── taste-model-genre-lean.test.ts ───────────────────────────────

/**
 * WTW applyGenreStep(null, answers) with the 16 chips already folded onto the
 * 13 (Love 2, Like 1, Never −9; to13 in WTW genre-step.ts).
 */
function answered(gen13: Partial<Record<GameGenre, number>>): PlayState {
  const gen = Object.fromEntries(GAME_GENRES.map(g => [g, gen13[g] ?? 0])) as Record<GameGenre, number>
  const loves = GAME_GENRES.filter(g => gen[g] >= 1)
  return { gen, sel: loves.length ? loves : null, loved: GAME_GENRES.filter(g => gen[g] >= 2) }
}

const at = (genre: (typeof FEATURE_GENRES)[number]) => 1 + FEATURE_GENRES.indexOf(genre)

describe('genreLean', () => {
  test('Love pulls a genre by g, Like by half, and Never or no answer not at all', () => {
    const w0 = genreLean(answered({ comedy: 2, drama: 1, horror: -9 }), 0.8)
    assert.equal(w0[at('comedy')], 0.8)
    assert.equal(w0[at('drama')], 0.4)
    assert.equal(w0[at('horror')], 0)
    assert.equal(w0.filter(v => v !== 0).length, 2)
    assert.equal(w0.length, 25)
  })

  test('where two of the 16 chips share an input, the stronger answer wins', () => {
    // { scifi: like, fantasy: never, hero: love } folds to scifi = Love.
    assert.equal(genreLean(answered({ scifi: 2 }), 1)[at('scifi')], 1)
    // { adultanim: like, anim: never } folds to anim = Like.
    assert.equal(genreLean(answered({ anim: 1 }), 1)[at('anim')], 0.5)
  })

  test('reads what was said, not the values that drift with picks', () => {
    const S = answered({ comedy: 2, drama: 1 })
    S.gen.comedy = 0.4   // picks pulled Love down
    S.gen.drama = 7      // and Like far up
    S.gen.crime = 3      // and raised a genre never answered
    const w0 = genreLean(S, 1)
    assert.deepEqual([w0[at('comedy')], w0[at('drama')], w0[at('crime')]], [1, 0.5, 0])
  })

  test('a genre that later became a Never stops leaning', () => {
    const S = answered({ comedy: 2 })
    S.gen.comedy = -9
    assert.ok(genreLean(S, 1).every(v => v === 0))
  })

  test('a save with no `gen` has no Nevers to skip: Love and Like still lean', () => {
    const w0 = genreLean({ loved: ['comedy'], sel: ['comedy', 'drama'] } as unknown as PlayState, 1)
    assert.deepEqual([w0[at('comedy')], w0[at('drama')]], [1, 0.5])
  })

  test('no saved answers: no lean', () => {
    assert.ok(genreLean(null).every(v => v === 0))
    assert.ok(genreLean(answered({})).every(v => v === 0))
  })
})

const TMDB_GENRES = ['Comedy', 'Drama', 'Action', 'Science Fiction', 'Horror', 'Thriller']
/** WTW candidateGenres(...).firm for a movie with these TMDB genres and no keywords. */
const GAME_OF: Record<string, GameGenre> = { Comedy: 'comedy', Drama: 'drama', Action: 'action', 'Science Fiction': 'scifi', Horror: 'horror', Thriller: 'thriller' }

/** 254 movies with one or two genres: 30 cards, 24 titles in 12 picks, and a pool of 200. */
function feedFixture() {
  const u = generator(7)
  const titles = Array.from({ length: 254 }, (_, i) => {
    const first = Math.floor(u() * 6), second = Math.floor(u() * 6)
    const genres = [...new Set(u() < 0.5 ? [first] : [first, second])].map(g => ({ name: TMDB_GENRES[g]! }))
    const taste_scales = Object.fromEntries([...FEATURE_SCALES, 'audience' as const].map(s => [s, u() * 2 - 1]))
    const tmdb_rating = 6 + u() * 3
    const row = {
      tmdb_id: String(i), type: 'movie' as const, genres, tmdb_rating, omdb_rating: null,
      crew: { directors: [], writers: [], cinematographers: [], cast: [] },
    }
    const game_genres = genres.map(g => GAME_OF[g.name]!)
    return { row, humor: taste_scales.humor!, vec: tasteFeatures({ tmdb_rating, game_genres, taste_scales }) }
  })
  // This person's answers follow how funny a title is, not its genre: the cards and picks say nothing for or against sci-fi.
  const rows: TasteRow[] = titles.slice(0, 30).map(t => ({ vec: t.vec, level: t.humor > 0.33 ? 3 : t.humor < -0.33 ? 1 : 2, weight: 1 }))
  const pairs: TastePair[] = Array.from({ length: 12 }, (_, k) => {
    const a = titles[30 + 2 * k]!, b = titles[31 + 2 * k]!
    return a.humor >= b.humor ? { chosen: a.vec, other: b.vec } : { chosen: b.vec, other: a.vec }
  })
  return { rows, pairs, pool: titles.slice(54) }
}

const has = (t: { genres: { name: string }[] }, genre: string) => t.genres.some(g => g.name === genre)

describe('trainTasteModel with a lean', () => {
  const { rows, pairs } = feedFixture()
  const lean = genreLean(answered({ scifi: 2, comedy: 1 }), 1)

  test('with no genre answers, w is exactly what it is without the lean', () => {
    assert.deepEqual(trainTasteModel(rows, pairs, genreLean(null)), trainTasteModel(rows, pairs))
  })

  test('no ratings and no picks: w is w0', () => {
    assert.deepEqual(trainTasteModel([], [], lean), lean)
  })

  test('solves (XᵀWX + Λ) w = XᵀWy + Λ·w0', () => {
    const w = trainTasteModel(rows, pairs, lean)
    const penalty = [0.5, ...new Array<number>(24).fill(4)]
    const mean = rows.reduce((s, r) => s + r.level, 0) / rows.length
    const data = [
      ...rows.map(r => ({ x: r.vec, y: r.level - mean })),
      ...pairs.map(p => ({ x: p.chosen.map((v, k) => v - p.other[k]!), y: 1 })),
    ]
    for (let i = 0; i < 25; i++) {
      // Row i of the equation, written out: Σ x_i·(x·w − y) + λ_i·(w_i − w0_i) = 0.
      const residual = data.reduce((s, { x, y }) => s + x[i]! * (x.reduce((d, v, k) => d + v * w[k]!, 0) - y), 0) + penalty[i]! * (w[i]! - lean[i]!)
      assert.ok(Math.abs(residual) < 1e-9, `row ${i}`)
    }
  })

  test('fades as ratings come in: 20 times the ratings leave a fraction of the lean', () => {
    const gap = (r: TasteRow[]) => Math.abs(trainTasteModel(r, pairs, lean)[at('scifi')]! - trainTasteModel(r, pairs)[at('scifi')]!)
    const many = Array.from({ length: 20 }, () => rows).flat()
    assert.ok(gap(rows) > 0.1)
    assert.ok(gap(many) < gap(rows) / 5)
  })
})

describe('the feed after onboarding (30 cards + 12 picks, formula v2)', () => {
  test('Loved sci-fi: more sci-fi in the top 20 than with no lean, and nothing from a Never genre', () => {
    const { rows, pairs, pool } = feedFixture()
    const S = answered({ scifi: 2, comedy: 1, horror: -9 })
    // Never is a rule in WTW (step 1 drops what it names before step 2 scores); for these movies it drops the Horror ones.
    const candidates = pool.filter(t => !has(t.row, 'Horror'))
    assert.ok(candidates.length < pool.length)
    const vecs = new Map(candidates.map(t => [`movie:${t.row.tmdb_id}`, t.vec]))

    const top20 = (w0: number[]) =>
      scoreV2(candidates.map(t => t.row), blankDNA(), trainTasteModel(rows, pairs, w0), vecs).slice(0, 20).map(s => s.title)
    const lean = genreLean(S)
    assert.equal(lean[at('scifi')], GENRE_LEAN)
    assert.equal(lean[at('horror')], 0)
    const without = top20(genreLean(null)), withLean = top20(lean)

    const scifi = (ts: { genres: { name: string }[] }[]) => ts.filter(t => has(t, 'Science Fiction')).length
    assert.ok(scifi(withLean) > scifi(without), `${scifi(withLean)} > ${scifi(without)}`)
    assert.deepEqual(withLean.filter(t => has(t, 'Horror')), [])
  })

  test('trainUserWeights is buildTraining + genreLean + trainTasteModel', () => {
    const vecs = new Map([['movie:1', [1, ...new Array<number>(24).fill(0)]], ['movie:2', [-1, ...new Array<number>(24).fill(0)]]])
    const dna = blankDNA()
    dna.signals.push(sig('1', 'loved'), sig('2', 'disliked'))
    const picks = [{ a: 'movie:1', b: 'movie:2', chosen: 'movie:1' }]
    const S = answered({ comedy: 2 })
    const { rows, pairs } = buildTraining(dna.signals, picks, vecs)
    assert.deepEqual(trainUserWeights({ dna, picks, playState: S, vecs }), trainTasteModel(rows, pairs, genreLean(S)))
  })
})
