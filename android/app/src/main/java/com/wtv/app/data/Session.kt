package com.wtv.app.data

import android.content.Context
import com.wtv.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException

/**
 * The signed-in session with the WTV database. Until Google sign-in (P4-1)
 * this is an anonymous Supabase user, created on first launch and kept.
 * The catalog is readable only with a session.
 */
class Session(context: Context, private val http: OkHttpClient) {
    private val prefs = context.getSharedPreferences("session", Context.MODE_PRIVATE)
    private val lock = Mutex()

    /** A valid access token, refreshed or created as needed. */
    suspend fun token(): String = lock.withLock {
        requireConfigured()
        current() ?: refresh() ?: signUpAnonymously()
    }

    /**
     * The server refused `rejected`: forget it, so the next call refreshes. A
     * token another request has stored meanwhile is kept, so parallel 401s
     * cause one refresh, not one each.
     */
    suspend fun invalidate(rejected: String) = lock.withLock {
        if (prefs.getString(ACCESS, null) == rejected) prefs.edit().remove(ACCESS).apply()
    }

    private fun current(): String? {
        val token = prefs.getString(ACCESS, null) ?: return null
        return token.takeIf { isFresh(prefs.getLong(EXPIRES_AT, 0), System.currentTimeMillis() / 1000) }
    }

    /**
     * A new access token from the refresh token, or null when the server
     * rejects it (revoked, expired, user gone): only then is a new user made.
     * A network error is thrown, not treated as a rejection: signing up again
     * would leave the user's data behind on the old account.
     */
    private suspend fun refresh(): String? {
        val refresh = prefs.getString(REFRESH, null) ?: return null
        return try {
            auth("token?grant_type=refresh_token", JSONObject().put("refresh_token", refresh))
        } catch (e: AuthRejected) {
            null
        }
    }

    private suspend fun signUpAnonymously(): String = auth("signup", JSONObject())

    /** Calls the auth API, stores the new session, returns its access token. */
    private suspend fun auth(path: String, body: JSONObject): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("${BuildConfig.SUPABASE_URL}/auth/v1/$path")
            .header("apikey", BuildConfig.SUPABASE_KEY)
            .post(body.toString().toRequestBody(JSON))
            .build()
        val (code, text) = try {
            http.newCall(request).execute().use { it.code to it.body?.string().orEmpty() }
        } catch (e: IOException) {
            throw ApiException("No connection to the server")
        }
        if (isRejection(code)) throw AuthRejected(code)
        // Anything else, 429 and 5xx included, is passing trouble: never a reason to make a new user.
        if (code !in 200..299) throw ApiException("Sign-in failed (HTTP $code)")
        val session = runCatching { JSONObject(text) }.getOrNull()
        val access = session?.optString("access_token").orEmpty()
        val refresh = session?.optString("refresh_token").orEmpty()
        val expiresAt = session?.optLong("expires_at") ?: 0
        if (access.isEmpty() || refresh.isEmpty() || expiresAt == 0L) throw ApiException("Sign-in answer could not be read")
        prefs.edit()
            .putString(ACCESS, access)
            .putString(REFRESH, refresh)
            .putLong(EXPIRES_AT, expiresAt)
            .apply()
        access
    }

    private class AuthRejected(code: Int) : ApiException("Sign-in refused (HTTP $code)")

    private companion object {
        const val ACCESS = "access_token"
        const val REFRESH = "refresh_token"
        const val EXPIRES_AT = "expires_at"
        val JSON = "application/json".toMediaType()
    }
}

/**
 * The auth answers that mean "this refresh token is no good" (Supabase uses
 * 400 for an invalid one). Anything else, 429 and 5xx included, is passing
 * trouble and never a reason to make a new user.
 */
internal fun isRejection(code: Int): Boolean = code in setOf(400, 401, 403, 404, 422)

/** An access token is used until a minute before it expires. */
internal fun isFresh(expiresAtSeconds: Long, nowSeconds: Long): Boolean = nowSeconds < expiresAtSeconds - 60

/** A build without the database settings (local.properties) fails with a clear message, not a crash. */
internal fun requireConfigured() {
    if (BuildConfig.SUPABASE_URL.isBlank() || BuildConfig.SUPABASE_KEY.isBlank()) {
        throw ApiException("This build has no database settings (SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY in local.properties)")
    }
}

open class ApiException(message: String) : Exception(message)
