/**
 * The Live TV groups, where they differ from the provider's categories:
 * its main list ("israel") is shown as General, and its sports channels,
 * which the provider keeps in that list, are also put in the Sports group.
 */
import type { Category, Channel } from './xtream.ts'

type Names = { en: string | null; he: string }

/** A live category's names: the main list is General. */
export function liveNames(names: Names): Names {
  return names.en === 'Israel' ? { en: 'General', he: 'כללי' } : names
}

/** Sports channels by name: "ספורט 5", "Sport ONE", "Eurosport 1", "ONE Doco", "UFC Fight Pass", "NBA TV". */
const SPORTS = /sport|ספורט|^ONE |WWE|UFC|fight|NBA/i

/** `channels` with the sports ones also in the Sports group (the live category named "Sports …"), when there is one. */
export function withSports(channels: Channel[], live: Category[], english: (name: string) => string | null): Channel[] {
  const sports = live.find(c => /^sports/i.test(english(c.name) ?? ''))?.extId
  if (sports === undefined) return channels
  return channels.map(c => (SPORTS.test(c.name) && !c.categoryIds.includes(sports) ? { ...c, categoryIds: [...c.categoryIds, sports] } : c))
}
