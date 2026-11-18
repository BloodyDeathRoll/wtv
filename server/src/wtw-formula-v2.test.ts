// Ported from WTW tests/unit/formula-v2.test.ts at 79b226d, same numbers.
// P1-E3: s = 0.30·z(creators) + 0.20·z(crowd) + 0.50·z(model), composite = Φ(s / sd(s)).
import assert from 'node:assert/strict'
import { describe, test } from 'node:test'
import { zScores, normalCdf, scoreFormulaV2, V2_WEIGHTS } from '../../supabase/functions/_shared/wtw/formula-v2.ts'

/** vitest's toBeCloseTo(expected, digits). */
const close = (actual: number, expected: number, digits = 2, msg?: string) =>
  assert.ok(Math.abs(actual - expected) < 10 ** -digits / 2, msg ?? `${actual} ≉ ${expected} (${digits} digits)`)

const mean = (xs: number[]) => xs.reduce((s, x) => s + x, 0) / xs.length
const popSd = (xs: number[]) => Math.sqrt(mean(xs.map(x => (x - mean(xs)) ** 2)))

describe('zScores', () => {
  test('centres on 0 with population sd 1', () => {
    const z = zScores([1, 2, 3, 4, 10])
    close(mean(z), 0, 12)
    close(popSd(z), 1, 12)
  })

  test('uses the population sd, not the sample sd', () => {
    // [0, 2]: mean 1, population sd 1 → z = −1, +1 (the sample sd √2 would give ±0.707).
    assert.deepEqual(zScores([0, 2]), [-1, 1])
  })

  test('keeps the order', () => {
    const [a, b, c] = zScores([0.3, 0.9, 0.1]) as [number, number, number]
    assert.ok(b > a)
    assert.ok(a > c)
  })

  test('a part that does not vary gives everyone 0', () => {
    assert.deepEqual(zScores([0.5, 0.5, 0.5]), [0, 0, 0])
    assert.deepEqual(zScores([0.1 + 0.2, 0.3, 0.3]), [0, 0, 0]) // float noise counts as flat
  })

  test('handles one value and none', () => {
    assert.deepEqual(zScores([7]), [0])
    assert.deepEqual(zScores([]), [])
  })
})

describe('normalCdf (Φ)', () => {
  for (const [x, expected] of [
    [0, 0.5],
    [1, 0.8413447461],
    [-1, 0.1586552539],
    [1.96, 0.9750021048],
    [-1.96, 0.0249978952],
    [3, 0.9986501020],
  ] as const) {
    test(`Φ(${x}) ≈ ${expected}`, () => close(normalCdf(x), expected, 6))
  }

  test('is symmetric: Φ(−x) = 1 − Φ(x)', () => {
    for (const x of [0.1, 0.5, 1.3, 2.7]) close(normalCdf(-x), 1 - normalCdf(x), 12)
  })

  test('rises with x and stays inside (0,1) for any realistic s', () => {
    let prev = 0
    for (let x = -6; x <= 6; x += 0.25) {
      const p = normalCdf(x)
      assert.ok(p > prev)
      assert.ok(p < 1)
      prev = p
    }
  })
})

describe('scoreFormulaV2', () => {
  const pool = [
    { creators: 0.9, crowd: 0.70, model: 0.4 },
    { creators: 0.5, crowd: 0.85, model: -0.2 },
    { creators: 0.5, crowd: 0.60, model: 0.9 },
    { creators: 0.2, crowd: 0.75, model: 0.0 },
  ]

  test('is 0.30·zc + 0.20·zw + 0.50·zm, then Φ(s / sd(s))', () => {
    const zc = zScores(pool.map(p => p.creators))
    const zw = zScores(pool.map(p => p.crowd))
    const zm = zScores(pool.map(p => p.model))
    const s = pool.map((_, i) => 0.30 * zc[i]! + 0.20 * zw[i]! + 0.50 * zm[i]!)
    const out = scoreFormulaV2(pool)
    out.forEach((r, i) => {
      close(r.z_creators, zc[i]!, 12)
      close(r.z_crowd, zw[i]!, 12)
      close(r.z_model, zm[i]!, 12)
      close(r.s, s[i]!, 12)
      close(r.composite, normalCdf(s[i]! / popSd(s)), 12)
      assert.equal(r.model_score, pool[i]!.model)
    })
    assert.deepEqual(V2_WEIGHTS, { creators: 0.30, crowd: 0.20, model: 0.50 })
  })

  test('ranks by s, and every composite is inside (0,1)', () => {
    const out = scoreFormulaV2(pool)
    const byS = [...out].sort((a, b) => b.s - a.s).map(r => r.composite)
    assert.deepEqual(byS, [...byS].sort((a, b) => b - a))
    for (const r of out) {
      assert.ok(r.composite > 0)
      assert.ok(r.composite < 1)
    }
  })

  test('the taste model outweighs creators, which outweigh the crowd', () => {
    // Three titles, each best on exactly one part by the same margin.
    const [byCreators, byCrowd, byModel] = scoreFormulaV2([
      { creators: 1, crowd: 0, model: 0 },
      { creators: 0, crowd: 1, model: 0 },
      { creators: 0, crowd: 0, model: 1 },
    ]).map(r => r.composite) as [number, number, number]
    assert.ok(byModel > byCreators)
    assert.ok(byCreators > byCrowd)
  })

  test('a title with no taste vector sits at the pool mean: its model z is exactly 0', () => {
    const out = scoreFormulaV2([
      { creators: 0.5, crowd: 0.7, model: 1.0 },
      { creators: 0.5, crowd: 0.7, model: null },
      { creators: 0.5, crowd: 0.7, model: -1.0 },
    ])
    assert.equal(out[1]!.z_model, 0)
    assert.equal(out[1]!.model_score, null)
    close(out[1]!.composite, 0.5, 12)
    assert.ok(out[0]!.composite > 0.5)
    assert.ok(out[2]!.composite < 0.5)
  })

  test('no vectors at all: the model drops out and creators + crowd decide', () => {
    const out = scoreFormulaV2([
      { creators: 0.9, crowd: 0.7, model: null },
      { creators: 0.1, crowd: 0.7, model: null },
    ])
    assert.deepEqual(out.map(r => r.z_model), [0, 0])
    assert.ok(out[0]!.composite > out[1]!.composite)
  })

  test('a pool where nothing differs scores everyone 0.5', () => {
    const flat = { creators: 0.5, crowd: 0.7, model: 0.1 }
    assert.deepEqual(scoreFormulaV2([flat, flat, flat]).map(r => r.composite), [0.5, 0.5, 0.5])
    assert.deepEqual(scoreFormulaV2([flat]).map(r => r.composite), [0.5])
  })

  test('an empty pool scores nothing', () => {
    assert.deepEqual(scoreFormulaV2([]), [])
  })
})
