package com.wtv.app.data

import com.wtv.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONException
import java.io.IOException

/** Reads from and writes to the WTV database's REST API with the session's token. */
class Api(private val session: Session, private val http: OkHttpClient) {

    /** `path` is a PostgREST path and query, e.g. `titles?select=id&limit=10`. */
    suspend fun get(path: String): JSONArray {
        val body = send(path, post = null, prefer = null, verb = "load")
        return try {
            JSONArray(body)
        } catch (e: JSONException) {
            throw ApiException("Could not read ${path.substringBefore('?')}")
        }
    }

    /** POSTs a JSON `body` to `path`; `prefer` is PostgREST's Prefer header (upserts). */
    suspend fun post(path: String, body: String, prefer: String) {
        send(path, post = body, prefer = prefer, verb = "save")
    }

    private suspend fun send(path: String, post: String?, prefer: String?, verb: String): String = withContext(Dispatchers.IO) {
        val what = path.substringBefore('?')
        val token = session.token()
        var result = call(path, token, what, post, prefer)
        if (result.first == 401) {
            // Expired or revoked: one retry with a fresh token.
            session.invalidate(token)
            result = call(path, session.token(), what, post, prefer)
        }
        val (code, body) = result
        if (code !in 200..299) throw ApiException("Could not $verb $what (HTTP $code)")
        body
    }

    private fun call(path: String, token: String, what: String, post: String?, prefer: String?): Pair<Int, String> {
        val request = Request.Builder()
            .url("${BuildConfig.SUPABASE_URL}/rest/v1/$path")
            .header("apikey", BuildConfig.SUPABASE_KEY)
            .header("Authorization", "Bearer $token")
            .apply {
                if (post != null) post(post.toRequestBody(JSON))
                if (prefer != null) header("Prefer", prefer)
            }
            .build()
        return try {
            http.newCall(request).execute().use { it.code to it.body?.string().orEmpty() }
        } catch (e: IOException) {
            throw ApiException("No connection to the server ($what)")
        }
    }

    private companion object {
        val JSON = "application/json".toMediaType()
    }
}
