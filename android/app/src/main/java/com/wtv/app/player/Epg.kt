package com.wtv.app.player

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.Base64

/**
 * One programme of a channel's guide; times in Unix seconds. `archived`: it
 * can be played back (catch-up); `providerStart` is its start as the provider
 * writes it, in the server's own time, which the catch-up address needs.
 */
data class Programme(
    val title: String,
    val description: String?,
    val start: Long,
    val end: Long,
    val archived: Boolean = false,
    val providerStart: String? = null,
)

/**
 * The next few programmes of a live channel from the provider's short guide
 * (`get_short_epg`). The provider's catalog API takes the client's own user
 * agent. Empty when the channel has no guide; throws when the call fails.
 */
suspend fun shortEpg(http: OkHttpClient, login: ProviderLogin, streamId: Long, limit: Int = 4): List<Programme> =
    programmes(guideCall(http, login, "get_short_epg", streamId, "limit" to limit.toString()))

/**
 * The programmes of a catch-up channel that can be played back, newest first:
 * archived and already over at `now` (Unix seconds). The full guide
 * (`get_simple_data_table`) is a few hundred rows.
 */
suspend fun archive(http: OkHttpClient, login: ProviderLogin, streamId: Long, now: Long): List<Programme> =
    programmes(guideCall(http, login, "get_simple_data_table", streamId))
        .filter { it.archived && it.end <= now && it.providerStart != null }
        .sortedByDescending { it.start }

private suspend fun guideCall(http: OkHttpClient, login: ProviderLogin, action: String, streamId: Long, vararg extra: Pair<String, String>): String =
    withContext(Dispatchers.IO) {
        val url = "${serverBase(login)}/player_api.php".toHttpUrl().newBuilder()
            .addQueryParameter("username", login.user.trim())
            .addQueryParameter("password", login.password)
            .addQueryParameter("action", action)
            .addQueryParameter("stream_id", streamId.toString())
            .apply { extra.forEach { (k, v) -> addQueryParameter(k, v) } }
            .build()
        // The URL holds the login: it never goes into an error message.
        http.newCall(Request.Builder().url(url).build()).execute().use {
            if (!it.isSuccessful) throw java.io.IOException("Guide: HTTP ${it.code}")
            it.body?.string().orEmpty()
        }
    }

/** Parses a short-guide answer. Titles and descriptions arrive base64-encoded; text that is not, is kept as it is. */
internal fun programmes(json: String): List<Programme> {
    val list = runCatching { JSONObject(json).optJSONArray("epg_listings") }.getOrNull() ?: return emptyList()
    return (0 until list.length()).mapNotNull { i ->
        val p = list.optJSONObject(i) ?: return@mapNotNull null
        val title = decode(p.optString("title")) ?: return@mapNotNull null
        val start = p.optString("start_timestamp").toLongOrNull() ?: return@mapNotNull null
        val end = p.optString("stop_timestamp").toLongOrNull() ?: return@mapNotNull null
        Programme(
            title,
            decode(p.optString("description")),
            start,
            end,
            archived = p.optString("has_archive") == "1",
            providerStart = p.optString("start").takeIf { it.isNotBlank() },
        ).takeIf { end > start }
    }.sortedBy { it.start }
}

private fun decode(s: String?): String? {
    val text = s?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    // The provider pads its base64; unpadded or invalid text was sent plain.
    if (text.length % 4 != 0) return text
    val bytes = runCatching { Base64.getDecoder().decode(text) }.getOrNull() ?: return text
    // Text that decodes to bytes that are not readable UTF-8 ("News"), or to control
    // characters ("AAAA"), was sent plain too.
    val decoded = runCatching { Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString().trim() }.getOrNull()
    return decoded?.takeIf { it.isNotEmpty() && it.none(Char::isISOControl) } ?: text
}

/** What is on at `now` (Unix seconds), and what follows it. */
fun nowAndNext(programmes: List<Programme>, now: Long): Pair<Programme?, Programme?> {
    val i = programmes.indexOfFirst { now >= it.start && now < it.end }
    return if (i >= 0) programmes[i] to programmes.getOrNull(i + 1) else null to programmes.firstOrNull { it.start > now }
}
