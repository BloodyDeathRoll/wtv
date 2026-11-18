/**
 * Copied from WTW src/modules/engine/scoring/crew-affinity.ts at 79b226d. Keep
 * in step with WTW: diff ROLE_WEIGHTS, normalizeAffinity and roleRaw.
 *
 * For each role on the title, looks up the crew members in the user's
 * strand_a and takes the strongest known one; the role raws are combined by
 * ROLE_WEIGHTS. Unknown crew are not evidence — a title with no familiar
 * crew lands at 0.5 (neutral), and unknowns never dilute a known match.
 *
 * Lineage boost is computed separately (lineage-boost.ts) and added on top.
 *
 * Score arithmetic:
 *   per-person raw  = normalized entry.score × entry.confidence   → [-1.0, 1.0]
 *   per-role raw    = the strongest per-person raw (largest |raw|)
 *   weighted raw    = Σ (role_raw × role_weight)                   → [-1.0, 1.0]
 *   final score     = (weighted_raw + 1) / 2                       → [0.0, 1.0]
 */

import type { StrandA, CrewAffinityEntry, ReasonPayload, TMDBCrewSnapshot } from './dna.ts'
import { REACTION_SCORE } from './reaction-score.ts'

export interface CrewAffinityResult {
  score: number                              // 0.0 – 1.0
  crew_matches: ReasonPayload['crew_matches']
}

const ROLE_WEIGHTS = {
  director:       0.40,
  writer:         0.30,
  cinematographer: 0.15,
  actor:          0.15,
} as const

/**
 * A strand_a entry's `score` is the running average reaction level:
 * "always loved" converges on REACTION_SCORE.loved (+0.30), "always disliked"
 * on REACTION_SCORE.disliked (−0.20). Used raw, the whole component lived in
 * 0.45–0.58 and decided nothing. Map that natural range to [-1, 1] before
 * applying confidence.
 */
function normalizeAffinity(entry: CrewAffinityEntry): number {
  const ceiling = entry.score >= 0 ? REACTION_SCORE.loved : -REACTION_SCORE.disliked
  const level = Math.max(-1, Math.min(1, entry.score / ceiling))
  return level * entry.confidence
}

/** Crew affinity score for a single title. Pure function — no I/O. */
export function computeCrewAffinity(
  crew: TMDBCrewSnapshot,
  strandA: StrandA
): CrewAffinityResult {
  const crew_matches: ReasonPayload['crew_matches'] = []

  function roleRaw(
    crewList: { tmdb_person_id: string; name: string }[],
    affinityMap: Record<string, CrewAffinityEntry>,
    role: string,
    limit = crewList.length
  ): number {
    const persons = crewList.slice(0, limit)
    if (persons.length === 0) return 0

    // Strongest signal wins, not the average: averaging let one known director
    // be diluted by unknown writers so every candidate scored 0.50.
    // Unknown people are simply not evidence — no boost, no penalty, no dilution.
    let strongest = 0
    for (const person of persons) {
      const entry = affinityMap[person.tmdb_person_id]
      if (entry) {
        const raw = normalizeAffinity(entry)
        if (Math.abs(raw) > Math.abs(strongest)) strongest = raw
        crew_matches.push({ name: person.name, role, affinity_score: raw })
      }
    }
    return strongest
  }

  const dirRaw  = roleRaw(crew.directors,        strandA.directors,        'director')
  const writRaw = roleRaw(crew.writers,           strandA.writers,          'writer')
  const dpRaw   = roleRaw(crew.cinematographers,  strandA.cinematographers, 'cinematographer')
  const castRaw = roleRaw(crew.cast,              strandA.actors,           'actor', 3)

  // Weighted sum in [-1, 1]
  const weighted =
    dirRaw  * ROLE_WEIGHTS.director +
    writRaw * ROLE_WEIGHTS.writer +
    dpRaw   * ROLE_WEIGHTS.cinematographer +
    castRaw * ROLE_WEIGHTS.actor

  // Normalize to [0, 1]: 0 weighted → 0.5 (neutral), +1 → 1.0, -1 → 0.0
  const score = (weighted + 1) / 2

  return { score, crew_matches }
}
