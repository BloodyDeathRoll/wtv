package com.wtv.app.player

import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import okhttp3.OkHttpClient
import java.util.concurrent.ConcurrentHashMap

/**
 * What is on now on each channel, for the channel grid: fetched for the cards
 * on screen, a few at a time, and kept until the programme ends (ten minutes
 * when the channel has no guide). Process-wide, so going back to Live TV
 * does not fetch again.
 */
object OnNow {
    private class Entry(val programme: Programme?, val validUntil: Long)

    private val cache = ConcurrentHashMap<Long, Entry>()
    // A screenful of cards is ~20: four calls at a time keeps the provider's limits.
    private val calls = Semaphore(4)

    /** The cached answer, if still valid at `now` (Unix seconds); else null, and `known` is false. */
    fun cached(streamId: Long, now: Long): Pair<Boolean, Programme?> =
        cache[streamId]?.takeIf { it.validUntil > now }?.let { true to it.programme } ?: (false to null)

    /** The programme on now, from the provider's short guide; null when there is none. Throws when the call fails. */
    suspend fun fetch(http: OkHttpClient, login: ProviderLogin, streamId: Long, now: Long): Programme? {
        cached(streamId, now).let { (known, p) -> if (known) return p }
        val programme = calls.withPermit { onAt(shortEpg(http, login, streamId, limit = 2), now) }
        cache[streamId] = Entry(programme, programme?.end ?: (now + NO_GUIDE_SECS))
        return programme
    }

    private const val NO_GUIDE_SECS = 600L
}

/** The programme running at `now`, if any. */
internal fun onAt(programmes: List<Programme>, now: Long): Programme? = programmes.firstOrNull { it.start <= now && now < it.end }
