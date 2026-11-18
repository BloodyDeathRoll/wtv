/**
 * Copied from WTW src/lib/taste-scales/features.ts at 79b226d. Keep in step
 * with WTW: diff TASTE_FEATURE_VERSION, the feature order and the constants
 * (catalogueGameGenres is not copied).
 *
 * A title as the taste model sees it: 25 numbers in a fixed order. Stored in
 * WTW as `titles.taste_vec`; changing the order or any constant means bumping
 * TASTE_FEATURE_VERSION and re-finalising the catalogue.
 */
import type { GameGenre } from './brain.ts'

export const TASTE_FEATURE_VERSION = 1
export const TASTE_FEATURE_COUNT = 25

/** [1..13], sorted. */
export const FEATURE_GENRES = [
  'action', 'anim', 'anime', 'comedy', 'crime', 'doc', 'drama', 'family', 'horror', 'romance', 'scifi', 'thriller', 'war',
] as const satisfies readonly GameGenre[]
/** [14..23], sorted; `audience` is [24]. */
export const FEATURE_SCALES = [
  'commit', 'complex', 'dark', 'energy', 'fantastic', 'humor', 'indie', 'modern', 'pace', 'tone',
] as const

export type TasteScale = (typeof FEATURE_SCALES)[number] | 'audience'

/** TMDB rating mean and sd over the 980 game titles (EVIDENCE §R). */
export const RATING_MEAN = 7.6258
export const RATING_SD = 0.6436

export interface FeatureRow {
  tmdb_rating: number | null
  game_genres: GameGenre[] | null
  taste_scales: Partial<Record<TasteScale, number>> | null
}

export function tasteFeatures(row: FeatureRow): number[] {
  // Clamped: catalogue ratings go down to ~2, far outside the game set (checked in R3).
  const rating = row.tmdb_rating == null ? 0 : Math.max(-3, Math.min(3, (row.tmdb_rating - RATING_MEAN) / RATING_SD))
  const genres = row.game_genres ?? []
  const scales = row.taste_scales ?? {}
  return [
    rating,
    ...FEATURE_GENRES.map(g => (genres.includes(g) ? 1 / genres.length : 0)),
    ...FEATURE_SCALES.map(s => scales[s] ?? 0),
    scales.audience ?? 0,
  ]
}
