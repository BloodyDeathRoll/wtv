package com.wtv.app.data

import com.wtv.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONException
import java.io.IOException

/** Reads from the WTV database's REST API with the session's token. */
class Api(private val session: Session, private val http: OkHttpClient) {

    /** `path` is a PostgREST path and query, e.g. `titles?select=id&limit=10`. */
    suspend fun get(path: String): JSONArray = withContext(Dispatchers.IO) {
        val what = path.substringBefore('?')
        val token = session.token()
        var result = call(path, token, what)
        if (result.first == 401) {
            // Expired or revoked: one retry with a fresh token.
            session.invalidate(token)
            result = call(path, session.token(), what)
        }
        val (code, body) = result
        if (code !in 200..299) throw ApiException("Could not load $what (HTTP $code)")
        try {
            JSONArray(body)
        } catch (e: JSONException) {
            throw ApiException("Could not read $what")
        }
    }

    private fun call(path: String, token: String, what: String): Pair<Int, String> {
        val request = Request.Builder()
            .url("${BuildConfig.SUPABASE_URL}/rest/v1/$path")
            .header("apikey", BuildConfig.SUPABASE_KEY)
            .header("Authorization", "Bearer $token")
            .build()
        return try {
            http.newCall(request).execute().use { it.code to it.body?.string().orEmpty() }
        } catch (e: IOException) {
            throw ApiException("No connection to the server ($what)")
        }
    }
}
