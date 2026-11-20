import assert from 'node:assert/strict'
import { test } from 'node:test'
import { categoryNames } from './category-names.ts'
import { liveNames, withSports } from './live-groups.ts'
import type { Category, Channel } from './xtream.ts'

const channel = (extId: number, name: string, categoryIds: number[]): Channel => ({
  extId, name, num: extId, logoUrl: null, epgChannelId: null, archiveDays: 0, isRadio: false, categoryIds,
})
const live: Category[] = [
  { kind: 'live', extId: 1, name: 'israel  - ישראל', position: 0 },
  { kind: 'live', extId: 30, name: 'Sports world - ספורט מהעולם', position: 1 },
]
const english = (name: string) => categoryNames(name).en

test('the main live list is General; other groups keep their names', () => {
  assert.deepEqual(liveNames(categoryNames('israel  - ישראל')), { en: 'General', he: 'כללי' })
  assert.deepEqual(liveNames(categoryNames('Music - מוזיקה')), { en: 'Music', he: 'מוזיקה' })
})

test('sports channels are added to the Sports group and stay in their own', () => {
  const channels = [
    channel(1, 'ספורט 5', [1]),
    channel(2, 'Sport ONE2-גיבוי', [1]),
    channel(3, 'Eurosport  2', [1]),
    channel(4, 'ONE Doco', [1]),
    channel(5, 'UFC Fight Pass', [1]),
    channel(6, 'NBA TV', [1, 30]),
    channel(7, 'ערוץ קשת 12', [1]),
    channel(8, 'Number One HD', [92]),
  ]
  assert.deepEqual(withSports(channels, live, english).map(c => c.categoryIds), [[1, 30], [1, 30], [1, 30], [1, 30], [1, 30], [1, 30], [1], [92]])
})

test('without a Sports group the channels are left as they are', () => {
  const channels = [channel(1, 'ספורט 5', [1])]
  assert.equal(withSports(channels, [live[0]!], english), channels)
})
