import assert from 'node:assert/strict'
import { test } from 'node:test'
import { categoryNames } from './category-names.ts'
import { liveGroups, liveNames, MOVIES_GROUP } from './live-groups.ts'
import type { Category, Channel } from './xtream.ts'

const channel = (extId: number, name: string, categoryIds: number[]): Channel => ({
  extId, name, num: extId, logoUrl: null, epgChannelId: null, archiveDays: 0, isRadio: false, categoryIds,
})
const live: Category[] = [
  { kind: 'live', extId: 1, name: 'israel  - ישראל', position: 0 },
  { kind: 'live', extId: 30, name: 'Sports world - ספורט מהעולם', position: 1 },
  { kind: 'live', extId: 20, name: 'רדיו', position: 2 },
]
const english = (name: string) => categoryNames(name).en

test('the main live list is General, Sports world is Sports; other groups keep their names', () => {
  assert.deepEqual(liveNames(categoryNames('israel  - ישראל')), { en: 'General', he: 'כללי' })
  assert.deepEqual(liveNames(categoryNames('Sports world - ספורט מהעולם')), { en: 'Sports', he: 'ספורט' })
  assert.deepEqual(liveNames(categoryNames('Music - מוזיקה')), { en: 'Music', he: 'מוזיקה' })
})

test('channels named sport or ספורט are added to Sports and stay in their own group', () => {
  const channels = [
    channel(1, 'ספורט 5', [1]),
    channel(2, 'Sport ONE2-גיבוי', [1]),
    channel(3, 'Eurosport  2', [1]),
    channel(4, 'NBA TV', [1, 30]),
    channel(5, 'ערוץ קשת 12', [1]),
  ]
  const got = liveGroups(live, channels, english)
  assert.deepEqual(got.channels.map(c => c.categoryIds), [[1, 30], [1, 30], [1, 30], [1, 30], [1]])
  // No movie channel: no Movies group, and the categories are untouched.
  assert.equal(got.categories, live)
})

test('channels named movies get a Movies group, placed after Sports', () => {
  const channels = [channel(1, 'yes Movies Action', [1]), channel(2, 'סלקום MOVIES DRAMA', [1]), channel(3, 'HOT Cinema 1', [1])]
  const got = liveGroups(live, channels, english)
  assert.deepEqual(got.channels.map(c => c.categoryIds), [[1, MOVIES_GROUP], [1, MOVIES_GROUP], [1]])
  assert.deepEqual(got.categories.map(c => [c.extId, c.position]), [[1, 0], [30, 1], [MOVIES_GROUP, 2], [20, 3]])
  const movies = got.categories.find(c => c.extId === MOVIES_GROUP)!
  assert.deepEqual(liveNames(categoryNames(movies.name)), { en: 'Movies', he: 'סרטים' })
})

test('without a Sports group: no channel is moved, and Movies comes last', () => {
  const channels = [channel(1, 'ספורט 5', [1]), channel(2, 'FreeTV Movies Drama', [1])]
  const got = liveGroups([live[0]!], channels, english)
  assert.deepEqual(got.channels.map(c => c.categoryIds), [[1], [1, MOVIES_GROUP]])
  assert.deepEqual(got.categories.map(c => c.extId), [1, MOVIES_GROUP])
})
