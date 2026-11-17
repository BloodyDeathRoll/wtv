import assert from 'node:assert/strict'
import { test } from 'node:test'
import { categoryNames } from './category-names.ts'

test('"English - עברית" is split, extra spaces and lower-case first letters tidied', () => {
  assert.deepEqual(categoryNames('Netflix - נטפליקס'), { en: 'Netflix', he: 'נטפליקס' })
  assert.deepEqual(categoryNames('israel  - ישראל'), { en: 'Israel', he: 'ישראל' })
  assert.deepEqual(categoryNames('Sports world - ספורט מהעולם'), { en: 'Sports world', he: 'ספורט מהעולם' })
})

test('Latin-only names are used for both languages', () => {
  assert.deepEqual(categoryNames('Apple TV+'), { en: 'Apple TV+', he: 'Apple TV+' })
  assert.deepEqual(categoryNames('HBO Max'), { en: 'HBO Max', he: 'HBO Max' })
})

test('Hebrew-only names come from the table, including ones with a dash', () => {
  assert.deepEqual(categoryNames('סדרות טורקיות'), { en: 'Turkish Series', he: 'סדרות טורקיות' })
  assert.deepEqual(categoryNames('מותחן - מסתורין'), { en: 'Thriller & Mystery', he: 'מותחן - מסתורין' })
  assert.deepEqual(categoryNames('סרטים - טבע, תיעודי, דוקו'), { en: 'Nature & Documentaries', he: 'סרטים - טבע, תיעודי, דוקו' })
})

test('an unknown Hebrew name has no English name', () => {
  assert.deepEqual(categoryNames('קטגוריה חדשה'), { en: null, he: 'קטגוריה חדשה' })
  // Mixed script without the " - " separator: not guessed.
  assert.deepEqual(categoryNames('4K סרטים'), { en: null, he: '4K סרטים' })
})
