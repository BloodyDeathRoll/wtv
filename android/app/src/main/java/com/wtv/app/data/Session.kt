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
        current() ?: refresh() ?: signUpAnonymously()
    }

    /** Forget the access token (the server refused it); the next call refreshes. */
    fun invalidate() {
        prefs.edit().remove(ACCESS).apply()
    }

    private fun current(): String? {
        val token = prefs.getString(ACCESS, null) ?: return null
        val expiresAt = prefs.getLong(EXPIRES_AT, 0)
        return token.takeIf { System.currentTimeMillis() / 1000 < expiresAt - 60 }
    }

    private suspend fun refresh(): String? {
        val refresh = prefs.getString(REFRESH, null) ?: return null
        return runCatching { auth("token?grant_type=refresh_token", JSONObject().put("refresh_token", refresh)) }.getOrNull()
    }

    private suspend fun signUpAnonymously(): String = auth("signup", JSONObject())

    /** Calls the auth API, stores the new session, returns its access token. */
    private suspend fun auth(path: String, body: JSONObject): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("${BuildConfig.SUPABASE_URL}/auth/v1/$path")
            .header("apikey", BuildConfig.SUPABASE_KEY)
            .post(body.toString().toRequestBody(JSON))
            .build()
        http.newCall(request).execute().use { res ->
            if (!res.isSuccessful) throw ApiException("Sign-in failed (HTTP ${res.code})")
            val session = JSONObject(res.body!!.string())
            val access = session.getString("access_token")
            prefs.edit()
                .putString(ACCESS, access)
                .putString(REFRESH, session.getString("refresh_token"))
                .putLong(EXPIRES_AT, session.getLong("expires_at"))
                .apply()
            access
        }
    }

    private companion object {
        const val ACCESS = "access_token"
        const val REFRESH = "refresh_token"
        const val EXPIRES_AT = "expires_at"
        val JSON = "application/json".toMediaType()
    }
}

class ApiException(message: String) : Exception(message)
