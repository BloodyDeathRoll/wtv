/**
 * The user's own WTW rating per title, keyed like the ranking pool
 * (`vecKey`: `movie:603`). WTW appends a signal for every new rating
 * (merge-feedback-signal.ts, update-from-session.ts), so for a title rated
 * more than once the last one wins. Old 'mixed' signals are skipped.
 */
import type { DNASignal } from './wtw/dna.ts'
import { vecKey } from './wtw/step2.ts'

export type WtwReaction = 'loved' | 'liked' | 'disliked'

/** "0603" and "603" are the same TMDB id, as in the WTW match job. */
export const normalTmdbId = (id: string | number) => String(id).trim().replace(/^0+(?=\d)/, '')

export function reactionsByKey(signals: Pick<DNASignal, 'type' | 'tmdb_id' | 'reaction'>[]): Map<string, WtwReaction> {
  const out = new Map<string, WtwReaction>()
  for (const s of signals) {
    const r = s.reaction as string
    if (r !== 'loved' && r !== 'liked' && r !== 'disliked') continue
    out.set(vecKey({ type: s.type, tmdb_id: normalTmdbId(s.tmdb_id) }), r)
  }
  return out
}
