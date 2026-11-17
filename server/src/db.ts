/**
 * The few calls the sync needs against the WTV database, over Supabase's REST
 * API with the secret key (which bypasses row level security).
 */

export interface DbConfig {
  url: string
  secretKey: string
}

export type Row = Record<string, unknown>

export class DbError extends Error {}

export function createDb(config: DbConfig, fetchFn: typeof fetch = fetch) {
  async function request(method: string, path: string, body?: unknown, prefer?: string): Promise<Response> {
    const res = await fetchFn(new URL(`/rest/v1/${path}`, config.url), {
      method,
      headers: {
        apikey: config.secretKey,
        Authorization: `Bearer ${config.secretKey}`,
        'Content-Type': 'application/json',
        ...(prefer ? { Prefer: prefer } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(60_000),
    })
    if (!res.ok) throw new DbError(`${method} ${path.split('?')[0]}: HTTP ${res.status} ${(await res.text()).slice(0, 300)}`)
    return res
  }

  return {
    /** Inserts rows, or updates the given columns where `onConflict` matches. */
    async upsert(table: string, onConflict: string, rows: Row[], batchSize = 500): Promise<void> {
      for (let i = 0; i < rows.length; i += batchSize) {
        const res = await request('POST', `${table}?on_conflict=${onConflict}`, rows.slice(i, i + batchSize), 'resolution=merge-duplicates,return=minimal')
        await res.body?.cancel()
      }
    },

    /** Like upsert for one row, and returns the stored row. */
    async upsertOne<T extends Row>(table: string, onConflict: string, row: Row): Promise<T> {
      const res = await request('POST', `${table}?on_conflict=${onConflict}`, row, 'resolution=merge-duplicates,return=representation')
      const [stored] = (await res.json()) as T[]
      if (!stored) throw new DbError(`${table}: upsert returned no row`)
      return stored
    },

    /** `filter` is a PostgREST query string, e.g. `kind=eq.movie&available=is.true`. */
    async count(table: string, filter: string): Promise<number> {
      const res = await request('HEAD', `${table}?${filter}`, undefined, 'count=exact')
      const total = Number(res.headers.get('content-range')?.split('/')[1])
      if (!Number.isInteger(total)) throw new DbError(`${table}: no row count in the answer`)
      return total
    },

    async update(table: string, filter: string, values: Row): Promise<void> {
      await (await request('PATCH', `${table}?${filter}`, values, 'return=minimal')).body?.cancel()
    },

    async remove(table: string, filter: string): Promise<void> {
      await (await request('DELETE', `${table}?${filter}`, undefined, 'return=minimal')).body?.cancel()
    },
  }
}

export type Db = ReturnType<typeof createDb>
