/**
 * Copied from WTW src/lib/title-key.ts at 79b226d. Keep in step with WTW: diff
 * titleKey / parseTitleKey / isMediaType; the history-record helpers are not copied.
 *
 * title-key — the ONE way to address a title across modules.
 *
 * TMDB movie and TV ids are separate namespaces that collide (id 105 is both
 * Back to the Future and Sex and the City; 617 such pairs in the catalog).
 * Anything keyed on a bare tmdb_id can therefore point at the wrong title.
 * Persist and compare titles by `titleKey(type, tmdb_id)`.
 */

export type MediaType = 'movie' | 'tv'

export function isMediaType(v: unknown): v is MediaType {
  return v === 'movie' || v === 'tv'
}

export function titleKey(type: MediaType, tmdb_id: string): string {
  return `${type}:${tmdb_id}`
}

/** "movie:105" → { type: 'movie', tmdb_id: '105' }; anything else → type null. */
export function parseTitleKey(key: string): { type: MediaType | null; tmdb_id: string } {
  const m = /^(movie|tv):(.+)$/.exec(key)
  if (m) return { type: m[1] as MediaType, tmdb_id: m[2] as string }
  return { type: null, tmdb_id: key }
}
