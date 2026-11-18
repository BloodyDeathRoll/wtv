/**
 * Copied from WTW src/types/dna.ts, src/lib/tmdb.ts (TMDBCrewSnapshot) and
 * src/modules/engine/types.ts (TitleRow) at 79b226d, cut to the fields the
 * formula v2 ranking reads. Keep in step with WTW: diff CrewAffinityEntry,
 * StrandA, DNASignal, TMDBCrewSnapshot and the TitleRow fields listed here.
 *
 * DNA is WTW's `users.dna` jsonb (DNASchema, row `id = user_id`); only
 * `strand_a_creative_affinity` and `signals` are read. A null `users.dna` is
 * WTW's blank DNA: use blankDNA().
 */

export type LineageBoost = 'none' | 'low' | 'medium' | 'high'

export interface CrewAffinityEntry {
  name: string
  score: number          // -1.0 to 1.0
  confidence: number     // 0.0 to 1.0
  sample_size: number
  lineage_boost: LineageBoost
}

export interface StrandA {
  directors: Record<string, CrewAffinityEntry>      // keyed by TMDB person ID
  writers: Record<string, CrewAffinityEntry>
  cinematographers: Record<string, CrewAffinityEntry>
  actors: Record<string, CrewAffinityEntry>
}

export type Reaction = 'loved' | 'liked' | 'disliked'
export type SignalSource = 'onboarding' | `session_${number}` | 'recommendation_accepted' | 'manual'

/** The fields of a WTW DNASignal that taste training reads (the rest of the signal may be present). */
export interface DNASignal {
  tmdb_id: string
  type: 'movie' | 'tv'
  reaction: Reaction
  source: SignalSource
  watched_at: string | null         // ISO-8601
}

/** The part of WTW's DNASchema formula v2 reads. */
export interface DNA {
  strand_a_creative_affinity: StrandA
  signals: DNASignal[]
}

/** WTW createBlankDNA (src/modules/dna/blank-dna.ts), the fields read here. */
export const blankDNA = (): DNA => ({
  strand_a_creative_affinity: { directors: {}, writers: {}, cinematographers: {}, actors: {} },
  signals: [],
})

export interface ReasonPayload {
  crew_matches: { name: string; role: string; affinity_score: number }[]
  lineage_connections: { from: string; to: string; relationship: string }[]
}

/** WTW `titles.crew` (jsonb). */
export interface TMDBCrewSnapshot {
  directors: { tmdb_person_id: string; name: string }[]
  writers: { tmdb_person_id: string; name: string }[]
  cinematographers: { tmdb_person_id: string; name: string }[]
  cast: { tmdb_person_id: string; name: string; order: number }[]
}

/** The WTW `titles` columns formula v2 reads for a candidate. */
export interface TitleRow {
  tmdb_id: string
  type: 'movie' | 'tv'
  tmdb_rating: number | null   // 0–10
  omdb_rating: number | null   // 0–1
  crew: TMDBCrewSnapshot
}
