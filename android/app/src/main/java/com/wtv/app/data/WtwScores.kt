package com.wtv.app.data

import android.util.Log
import androidx.compose.runtime.mutableStateMapOf
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/**
 * WTW's own "% match" for the cards on screen, asked of WTW a few at a time
 * (Catalog.wtwScores) while WTW is connected. Answers fill in as they arrive;
 * cards already answered within the server's 12 hours come with their titles
 * (`Title.match`). Call from the main thread.
 */
class WtwScores(private val catalog: Catalog, private val wtw: Session, private val scope: CoroutineScope) {
    private val known = mutableStateMapOf<Long, Int?>()
    private val asked = HashSet<Long>()
    private val calls = Semaphore(PARALLEL_CALLS)
    /** The WTW account the answers are for: another account's are dropped. */
    private var account: String? = null

    /** WTW's percent for this card once answered; null before, or when WTW does not score it. */
    operator fun get(id: Long): Int? = known[id]

    /** Asks for the cards not asked yet, in order (the first rows first). */
    fun request(ids: List<Long>) {
        val email = wtw.email ?: return
        if (email != account) {
            known.clear()
            asked.clear()
            account = email
        }
        ids.filter { asked.add(it) }.chunked(PER_CALL).forEach { chunk ->
            scope.launch {
                calls.withPermit {
                    // Answers for an account switched away from meanwhile are dropped.
                    if (account != email) return@withPermit
                    try {
                        val answers = catalog.wtwScores(wtw.token(minSeconds = TOKEN_MIN_SECONDS), chunk)
                        if (account == email) known.putAll(answers)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        // A nicety: the cards stay without a number, and are asked again next time.
                        if (account == email) asked.removeAll(chunk.toSet())
                        Log.d("WtwScores", "Not answered: ${e.message}")
                    }
                }
            }
        }
    }
}

/** Titles per server call: WTW answers them at once, within the app's 20 s call timeout. */
private const val PER_CALL = 6
private const val PARALLEL_CALLS = 2
/** The server refuses a WTW token about to expire: it must outlive the calls. */
private const val TOKEN_MIN_SECONDS = 300L
