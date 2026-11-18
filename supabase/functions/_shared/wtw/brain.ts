/**
 * Copied from WTW src/app/play/lib/brain.ts (`nevers`, the PlayState fields
 * genreLean reads) and src/app/play/lib/genres.ts (GAME_GENRES ids) at 79b226d.
 * Keep in step with WTW: diff `nevers`, the -5 threshold, and the GAME_GENRES id list.
 *
 * PlayState is WTW's play_state.state (JSON). Only the three fields the taste
 * model's genre lean reads are typed here; the rest of the save is ignored.
 */

/** The 13 genres of the taste games, in WTW's GAME_GENRES order. */
export const GAME_GENRES = [
  'comedy', 'drama', 'action', 'crime', 'thriller', 'scifi', 'horror', 'romance', 'anim', 'family', 'anime', 'doc', 'war',
] as const

export type GameGenre = (typeof GAME_GENRES)[number]

export interface PlayState {
  /** 2 love · 1 like · 0 meh · -9 never. Love/like drift with every pick. */
  gen: Record<GameGenre, number>
  /** Love + like genres chosen on the setup screen; null until setup is done. */
  sel: GameGenre[] | null
  /** The genres the player said they love at setup (the rest of `sel` are likes). `gen` drifts with picks; this doesn't. */
  loved?: GameGenre[]
}

/** Reads only `gen`, and says so in the type: the engine's cold start calls it on a partial state. */
export const nevers = (S: Pick<PlayState, 'gen'>): GameGenre[] =>
  GAME_GENRES.filter(g => S.gen[g] <= -5)
