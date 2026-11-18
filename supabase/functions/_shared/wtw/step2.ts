/**
 * Copied from WTW src/modules/engine/pipeline/step2-composite-score.ts (the
 * FORMULA_V2 path of scoreCandidates, externalRatingScore) and
 * src/modules/engine/scoring/taste-vectors.ts (vecKey, parseVector) at 79b226d.
 * Keep in step with WTW: diff externalRatingScore, the creators line
 * (min(1, crew + lineage)), the model line (predict or null) and the final sort.
 *
 * Under v2 WTW still computes narrative/visceral/content/recency but they get
 * weight 0 (visceral and content only feed the "why" lines), so they are not
 * copied. Nor is ratedDownGenres: it is attached for the Why lines and does not
 * change the ranking.
 *
 * Candidate vectors: titles (tmdb_id, type, taste_vec) where
 * taste_version = TASTE_FEATURE_VERSION and taste_vec is not null, keyed by
 * vecKey; a title without one scores at the pool mean on the model.
 */
import type { DNA, TitleRow } from './dna.ts'
import { computeCrewAffinity } from './crew-affinity.ts'
import { computeBoostFromCaches, type LineageCache } from './lineage-boost.ts'
import { scoreFormulaV2, type V2Score } from './formula-v2.ts'
import { contributions, predict } from './taste-model.ts'

export const vecKey = (t: Pick<TitleRow, 'type' | 'tmdb_id'>) => `${t.type}:${t.tmdb_id}`

/** pgvector comes back as its text form, "[0.1,-0.2,…]". */
export function parseVector(v: unknown): number[] | null {
  if (Array.isArray(v)) return v as number[]
  if (typeof v !== 'string') return null
  try {
    const parsed = JSON.parse(v)
    return Array.isArray(parsed) ? parsed : null
  } catch {
    return null
  }
}

/**
 * Crowd score, 0–1. `tmdb_rating` is stored 0–10, `omdb_rating` 0–1.
 * With only one of the two, that one is the whole score.
 */
export function externalRatingScore(title: Pick<TitleRow, 'tmdb_rating' | 'omdb_rating'>): number {
  const { tmdb_rating: tmdb, omdb_rating: omdb } = title

  if (tmdb == null && omdb == null) return 0.5   // no data → neutral
  if (omdb == null) return tmdb! / 10
  if (tmdb == null) return omdb
  return 0.6 * (tmdb / 10) + 0.4 * omdb
}

export interface ScoredV2<T> extends V2Score {
  title: T
  /** min(1, crew affinity + lineage boost): v2's `creators`. */
  crew_affinity_score: number
  /** externalRatingScore: v2's `crowd`. */
  external_rating_score: number
}

/**
 * scoreCandidates with FORMULA_V2 on, for ranking: scores the whole pool and
 * returns it sorted by composite, best first (stable, as WTW's sort).
 * `w` null = the taste model could not load: every model z is 0 and
 * creators + crowd decide, as WTW does when loading fails.
 */
export function scoreV2<T extends TitleRow>(
  candidates: T[],
  dna: Pick<DNA, 'strand_a_creative_affinity'>,
  w: number[] | null,
  vecs: Map<string, number[]>,
  d1Cache: LineageCache = new Map(),
  d2Cache: LineageCache = new Map(),
): ScoredV2<T>[] {
  if (candidates.length === 0) return []
  const strandA = dna.strand_a_creative_affinity

  const base = candidates.map(title => {
    const crewResult    = computeCrewAffinity(title.crew, strandA)
    const lineageResult = computeBoostFromCaches(title.crew, strandA, d1Cache, d2Cache)
    return {
      title,
      crew_affinity_score:   Math.min(1.0, crewResult.score + lineageResult.boost),
      external_rating_score: externalRatingScore(title),
      vec:                   w ? vecs.get(vecKey(title)) : undefined,
    }
  })

  const v2Scores = scoreFormulaV2(base.map(s => ({
    creators: s.crew_affinity_score,
    crowd:    s.external_rating_score,
    model:    w && s.vec ? predict(w, s.vec) : null,
  })))

  const scored: ScoredV2<T>[] = base.map((s, i) => ({
    ...v2Scores[i]!,
    ...(w && s.vec ? { vec: s.vec, contributions: contributions(w, s.vec) } : {}),
    title: s.title,
    crew_affinity_score: s.crew_affinity_score,
    external_rating_score: s.external_rating_score,
  }))

  return scored.sort((a, b) => b.composite - a.composite)
}
