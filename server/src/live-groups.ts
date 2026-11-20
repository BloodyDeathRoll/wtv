/**
 * The Live TV groups, where they differ from the provider's categories:
 * - its main list ("israel") is shown as General, and "Sports world" as Sports;
 * - its sports channels, which the provider keeps in the main list, are also put in Sports;
 * - a Movies group, which the provider does not have, holds the movie channels.
 * Channels are chosen by name, and stay in their own groups too.
 */
import type { Category, Channel } from './xtream.ts'

type Names = { en: string | null; he: string }

/** A live category's names. */
export function liveNames(names: Names): Names {
  if (names.en === 'Israel') return { en: 'General', he: 'כללי' }
  if (names.en === 'Sports world') return { en: 'Sports', he: 'ספורט' }
  return names
}

/** The Movies group's id: negative, so it never meets one of the provider's. */
export const MOVIES_GROUP = -1
const SPORTS = /sport|ספורט/i
const MOVIES = /movies/i

const added = (c: Channel, group: number | undefined, name: RegExp): number[] =>
  group !== undefined && name.test(c.name) && !c.categoryIds.includes(group) ? [group] : []

/**
 * The live categories and channels as the app shows them. `english` gives a category's English name.
 * Movies comes after Sports (last without one), and only when a channel belongs in it.
 */
export function liveGroups(
  live: Category[],
  channels: Channel[],
  english: (name: string) => string | null,
): { categories: Category[]; channels: Channel[] } {
  const sportsAt = live.findIndex(c => /^sports/i.test(english(c.name) ?? ''))
  const sports = live[sportsAt]?.extId
  const movies = channels.some(c => MOVIES.test(c.name)) ? MOVIES_GROUP : undefined
  const at = sportsAt < 0 ? live.length : sportsAt + 1
  const categories = movies === undefined
    ? live
    : [...live.slice(0, at), { kind: 'live' as const, extId: movies, name: 'Movies - סרטים', position: 0 }, ...live.slice(at)]
        .map((c, position) => ({ ...c, position }))
  return {
    categories,
    channels: channels.map(c => {
      const more = [...added(c, sports, SPORTS), ...added(c, movies, MOVIES)]
      return more.length ? { ...c, categoryIds: [...c.categoryIds, ...more] } : c
    }),
  }
}
