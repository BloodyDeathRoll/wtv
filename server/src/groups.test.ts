import assert from 'node:assert/strict'
import { test } from 'node:test'
import type { Db, Row } from './db.ts'
import { refreshGroups, refreshGroupsOrNull } from './groups.ts'

function fakeDb(providers: Row[], answer: unknown) {
  const calls: [string, Row][] = []
  const no = async () => assert.fail('unexpected call')
  const db = {
    select: async <T,>() => providers as T[],
    rpc: async <T,>(name: string, args: Row) => {
      calls.push([name, args])
      return answer as T[]
    },
    selectAll: no, upsert: no, upsertOne: no, count: no, update: no, remove: no,
  } satisfies Db
  return { db, calls }
}

test('calls the database function for the provider and returns the count', async () => {
  const { db, calls } = fakeDb([{ id: 4 }], [21462])
  assert.equal(await refreshGroups(db, 'prov1'), 21462)
  assert.deepEqual(calls, [['refresh_title_groups', { p_provider: 4 }]])
})

test('the command-line form logs a failure, marks the run failed and returns null', async () => {
  const { db } = fakeDb([], [0])
  const before = process.exitCode
  const errors: string[] = []
  const log = console.error
  console.error = (m: string) => void errors.push(m)
  try {
    assert.equal(await refreshGroupsOrNull(db, 'nope'), null)
    assert.equal(process.exitCode, 1)
    assert.deepEqual(errors, ['Regrouping failed: Unknown provider nope: run the sync first'])
  } finally {
    console.error = log
    process.exitCode = before
  }
})

test('an unknown provider is an error', async () => {
  const { db } = fakeDb([], [0])
  await assert.rejects(refreshGroups(db, 'nope'), /Unknown provider nope/)
})
