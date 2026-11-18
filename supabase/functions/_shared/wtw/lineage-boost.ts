/**
 * Copied from WTW src/modules/engine/scoring/lineage-boost.ts (the batch API)
 * and the lineage pre-fetch in src/modules/engine/pipeline/step2-composite-score.ts
 * at 79b226d. Keep in step with WTW: diff getBoostEligibleIds,
 * computeBoostFromCaches, the weights, and step 2's degree-1 id collection.
 * WTW's fetchLineageCache is replaced by lineageCacheFromRows: the caller reads.
 *
 * For every crew member in the user's strand_a with lineage_boost 'medium' or
 * 'high', traverse their creative influence graph up to 2 degrees and check
 * whether any influenced person worked on this title.
 *
 *   Degree 1 (X influenced Y; Y is on the title):  × 0.50
 *   Degree 2 (X influenced Y, Y influenced Z; Z on the title): × 0.25
 *
 * Boost per connection = source_person.score × source_person.confidence × degree_weight
 * Total boost is capped at 0.4 (it's additive on top of crew_affinity_score).
 *
 * The caller reads WTW `crew_members` twice, as step 2 does:
 *   1. d1: `select tmdb_person_id, lineage_influences from crew_members
 *          where tmdb_person_id in (getBoostEligibleIds(strand_a))`
 *      — skip both reads when that list is empty (most users).
 *   2. d2: the same select `where tmdb_person_id in (degree1Ids(candidates, d1))`
 *      — skip when that list is empty.
 * Each result goes through lineageCacheFromRows.
 */

import type { StrandA, ReasonPayload, TMDBCrewSnapshot } from './dna.ts'

/** The WTW table and columns a lineage cache is read from. */
export const LINEAGE_TABLE = 'crew_members'
export const LINEAGE_COLUMNS = 'tmdb_person_id, lineage_influences'

export interface LineageEntry {
  id: string
  name: string
  relationship: string
}
export interface LineageRecord {
  tmdb_person_id: string
  /** jsonb, default '{}': either list may be missing. */
  lineage_influences: {
    influenced_by?: LineageEntry[]
    influences?:    LineageEntry[]
  }
}

export type LineageCache = Map<string, LineageRecord>

/** WTW fetchLineageCache, minus the query: rows of `crew_members (tmdb_person_id, lineage_influences)`. */
export function lineageCacheFromRows(rows: LineageRecord[] | null | undefined): LineageCache {
  return new Map((rows ?? []).map(r => [r.tmdb_person_id, r]))
}

/**
 * Collects TMDB person IDs from strand_a that have lineage_boost set.
 * Pure function — used by the pipeline to know what to pre-fetch.
 */
export function getBoostEligibleIds(strandA: StrandA): string[] {
  const ids: string[] = []
  for (const role of ['directors', 'writers', 'cinematographers'] as const) {
    for (const [id, entry] of Object.entries(strandA[role])) {
      if (entry.lineage_boost === 'medium' || entry.lineage_boost === 'high') {
        ids.push(id)
      }
    }
  }
  return ids
}

/**
 * From WTW step 2: all degree-1 influenced persons that sit on some candidate's
 * crew (directors, writers, cinematographers). These are the ids the d2 cache
 * is read for. Note it is the candidate pool that decides d2, so the same title
 * can get a different boost in a different pool.
 */
export function degree1Ids(candidates: { crew: TMDBCrewSnapshot }[], d1Cache: LineageCache): string[] {
  const ids = new Set<string>()
  for (const title of candidates) {
    const titleCrewIds = new Set([
      ...title.crew.directors.map(d => d.tmdb_person_id),
      ...title.crew.writers.map(w => w.tmdb_person_id),
      ...title.crew.cinematographers.map(dp => dp.tmdb_person_id),
    ])
    for (const [, row] of d1Cache) {
      for (const inf of (row.lineage_influences.influences ?? [])) {
        if (inf.id && titleCrewIds.has(inf.id)) ids.add(inf.id)
      }
    }
  }
  return [...ids]
}

export interface LineageBoostResult {
  boost: number                                           // 0.0 – 0.4, added to crew_affinity_score
  lineage_connections: ReasonPayload['lineage_connections']
}

const DEGREE_1_WEIGHT = 0.50
const DEGREE_2_WEIGHT = 0.25
const MAX_BOOST       = 0.40

/**
 * Compute lineage boost from pre-fetched caches. Pure function — no I/O.
 *
 * @param d1Cache  lineage of boost-eligible strand_a crew
 * @param d2Cache  lineage of degree-1 matched persons
 */
export function computeBoostFromCaches(
  crew: TMDBCrewSnapshot,
  strandA: StrandA,
  d1Cache: LineageCache,
  d2Cache: LineageCache
): LineageBoostResult {
  const titleCrewIds = new Set([
    ...crew.directors.map(d => d.tmdb_person_id),
    ...crew.writers.map(w => w.tmdb_person_id),
    ...crew.cinematographers.map(dp => dp.tmdb_person_id),
  ])

  const lineage_connections: ReasonPayload['lineage_connections'] = []
  let totalBoost = 0

  for (const [role, crewList] of [
    ['directors', crew.directors] as const,
    ['writers', crew.writers] as const,
    ['cinematographers', crew.cinematographers] as const,
  ]) {
    for (const person of crewList) {
      const entry = strandA[role][person.tmdb_person_id]
      if (!entry || (entry.lineage_boost !== 'medium' && entry.lineage_boost !== 'high')) continue

      const baseStrength = entry.score * entry.confidence
      const lineageRow = d1Cache.get(person.tmdb_person_id)
      if (!lineageRow) continue

      for (const influenced of (lineageRow.lineage_influences.influences ?? [])) {
        if (!influenced.id) continue

        if (titleCrewIds.has(influenced.id)) {
          totalBoost += baseStrength * DEGREE_1_WEIGHT
          lineage_connections.push({ from: person.name, to: influenced.name, relationship: influenced.relationship })
        }

        // Degree-2: check if influenced's influences are on the title
        const d2Row = d2Cache.get(influenced.id)
        for (const d2 of (d2Row?.lineage_influences.influences ?? [])) {
          if (d2.id && titleCrewIds.has(d2.id)) {
            totalBoost += baseStrength * DEGREE_2_WEIGHT
            lineage_connections.push({ from: influenced.name, to: d2.name, relationship: d2.relationship })
          }
        }
      }
    }
  }

  return { boost: Math.min(MAX_BOOST, totalBoost), lineage_connections }
}
