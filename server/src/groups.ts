import type { Db } from './db.ts'

/**
 * Recomputes which copy of each title is its card (#56, migration
 * `title_groups`). Run after the sync and after the details job.
 * Returns the number of titles whose group fields changed.
 */
export async function refreshGroups(db: Db, providerName: string): Promise<number> {
  const [provider] = await db.select<{ id: number }>('providers', `name=eq.${encodeURIComponent(providerName)}&select=id`)
  if (!provider) throw new Error(`Unknown provider ${providerName}: run the sync first`)
  const [changed] = await db.rpc<number>('refresh_title_groups', { p_provider: provider.id })
  return changed ?? 0
}
