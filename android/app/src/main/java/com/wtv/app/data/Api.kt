package com.wtv.app.data

import com.wtv.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray

/** Reads from the WTV database's REST API with the session's token. */
class Api(private val session: Session, private val http: OkHttpClient) {

    /** `path` is a PostgREST path and query, e.g. `titles?select=id&limit=10`. */
    suspend fun get(path: String): JSONArray = withContext(Dispatchers.IO) {
        var result = call(path, session.token())
        if (result.first == 401) {
            // Expired or revoked: one retry with a fresh token.
            session.invalidate()
            result = call(path, session.token())
        }
        val (code, body) = result
        if (code !in 200..299) throw ApiException("Could not load ${path.substringBefore('?')} (HTTP $code)")
        JSONArray(body)
    }

    private fun call(path: String, token: String): Pair<Int, String> {
        val request = Request.Builder()
            .url("${BuildConfig.SUPABASE_URL}/rest/v1/$path")
            .header("apikey", BuildConfig.SUPABASE_KEY)
            .header("Authorization", "Bearer $token")
            .build()
        return http.newCall(request).execute().use { it.code to (it.body?.string() ?: "") }
    }
}
