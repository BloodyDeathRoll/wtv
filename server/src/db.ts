/**
 * The few calls the jobs need against a Supabase database, over its REST API.
 * For the WTV database the key is the secret key (which bypasses row level
 * security); for WTW it is WTW's public key, and only reads are made.
 */

export interface DbConfig {
  url: string
  key: string
}

export type Row = Record<string, unknown>

export class DbError extends Error {}

export function createDb(config: DbConfig, fetchFn: typeof fetch = fetch) {
  async function request(method: string, path: string, body?: unknown, prefer?: string): Promise<Response> {
    // Relative to the base with a trailing slash, so a path in the URL (a proxy) is kept.
    const base = config.url.endsWith('/') ? config.url : `${config.url}/`
    const res = await fetchFn(new URL(`rest/v1/${path}`, base), {
      method,
      headers: {
        apikey: config.key,
        Authorization: `Bearer ${config.key}`,
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

    /** `filter` is a PostgREST query string, e.g. `name=eq.prov1&select=id`. */
    async select<T>(table: string, filter: string): Promise<T[]> {
      return (await (await request('GET', `${table}?${filter}`)).json()) as T[]
    },

    /**
     * Every row matching `filter`, read 1,000 at a time in id order (the REST
     * API returns at most 1,000 rows per call). `columns` must include `id`.
     * `columns` and `filter` go into the URL as given: encode values in them.
     */
    async selectAll<T extends { id: number }>(table: string, columns: string, filter = ''): Promise<T[]> {
      const all: T[] = []
      for (let after = -1; ; ) {
        const page = (await (await request('GET', `${table}?select=${columns}&id=gt.${after}&order=id&limit=1000${filter ? `&${filter}` : ''}`)).json()) as T[]
        all.push(...page)
        const last = page.at(-1)
        if (page.length < 1000 || !last) return all
        after = last.id
      }
    },

    /** Calls a database function and returns its rows (a scalar result comes back as one). */
    async rpc<T>(name: string, args: Row): Promise<T[]> {
      const body: unknown = await (await request('POST', `rpc/${name}`, args)).json()
      return (Array.isArray(body) ? body : [body]) as T[]
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
