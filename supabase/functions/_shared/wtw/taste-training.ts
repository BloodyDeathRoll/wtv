/**
 * Copied from WTW src/modules/dna/load-taste-training.ts and
 * src/modules/engine/scoring/taste-weights.ts at 79b226d, with the reads taken
 * out: the caller reads, these functions shape and train. Keep in step with
 * WTW: diff the play_events / play_state / titles filters and the payload checks.
 *
 * What the caller reads from WTW, for one user:
 *   1. users.dna (jsonb) where id = user_id → DNA (null → blankDNA()).
 *   2. play_state.state where user_id = user_id (one row, or none) → PlayState.
 *   3. play_events.payload where user_id = user_id and kind = 'duel'
 *      and payload->>'chosen' is not null, all pages (WTW orders by id) → picksFromPayloads.
 *   4. titles (tmdb_id, type, taste_vec) where tmdb_id in trainingTitleIds(...).ids
 *      and taste_version = TASTE_FEATURE_VERSION (features.ts) and taste_vec is not null
 *      (WTW chunks the ids 300 per `in`) → tasteVecsFromRows(rows, keys).
 * Then trainUserWeights(...) gives w. WTW reads 2–4 in parallel and trains
 * once per generation; any failed read means no model (step 2 then scores with
 * w = null, see step2.ts).
 */
import type { DNA, DNASignal } from './dna.ts'
import type { PlayState } from './brain.ts'
import { parseTitleKey, titleKey, type MediaType } from './title-key.ts'
import { buildTraining, genreLean, trainTasteModel, type DuelPick } from './taste-model.ts'

/** play_events payloads → picks; a payload without string a, b and chosen is skipped. */
export function picksFromPayloads(payloads: unknown[]): DuelPick[] {
  const picks: DuelPick[] = []
  for (const payload of payloads) {
    const p = (payload ?? {}) as Partial<DuelPick>
    if (typeof p.a === 'string' && typeof p.b === 'string' && typeof p.chosen === 'string') picks.push({ a: p.a, b: p.b, chosen: p.chosen })
  }
  return picks
}

/**
 * The title keys training needs a vector for, and the bare tmdb_ids to query
 * `titles` with. A bare id (no `movie:`/`tv:`) can't be matched to one title,
 * so it is left out of the query.
 */
export function trainingTitleIds(signals: DNASignal[], picks: DuelPick[]): { keys: Set<string>; ids: string[] } {
  const keys = new Set<string>(signals.map(s => titleKey(s.type, s.tmdb_id)))
  for (const p of picks) { keys.add(p.a); keys.add(p.b) }
  const ids = [...new Set([...keys].map(parseTitleKey).filter(k => k.type).map(k => k.tmdb_id))]
  return { keys, ids }
}

/** `titles` rows → vectors by title key, keeping only the keys asked for (a movie and a series can share a tmdb_id). */
export function tasteVecsFromRows(rows: { tmdb_id: string; type: string; taste_vec: unknown }[], keys: Set<string>): Map<string, number[]> {
  const vecs = new Map<string, number[]>()
  for (const r of rows) {
    const key = titleKey(r.type as MediaType, r.tmdb_id)
    if (!keys.has(key)) continue
    // pgvector comes back as its text form, "[0.1,-0.2,…]".
    vecs.set(key, typeof r.taste_vec === 'string' ? JSON.parse(r.taste_vec) : r.taste_vec as number[])
  }
  return vecs
}

/** loadTasteTraining + trainTasteModel: the user's taste weights w. */
export function trainUserWeights(input: {
  dna: Pick<DNA, 'signals'>
  picks: DuelPick[]
  playState: Pick<PlayState, 'sel' | 'loved' | 'gen'> | null | undefined
  vecs: Map<string, number[]>
  now?: number
}): number[] {
  const { rows, pairs } = buildTraining(input.dna.signals, input.picks, input.vecs, input.now ?? Date.now())
  return trainTasteModel(rows, pairs, genreLean(input.playState))
}
