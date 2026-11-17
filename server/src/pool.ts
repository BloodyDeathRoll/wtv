/** Runs `work` over `items`, at most `parallel` at a time. */
export async function pool<T>(items: T[], parallel: number, work: (item: T) => Promise<void>): Promise<void> {
  let next = 0
  await Promise.all(Array.from({ length: Math.min(parallel, items.length) }, async () => {
    while (next < items.length) await work(items[next++]!)
  }))
}
