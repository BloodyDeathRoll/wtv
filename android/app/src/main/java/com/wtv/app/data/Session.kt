package com.wtv.app.data

import android.content.Context
import com.wtv.app.BuildConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
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
 * A signed-in session with one Supabase project. For WTV (`anonymous`) a
 * device starts as an anonymous user, created on first launch and kept, and
 * becomes the user's Google account at sign-in. For WTW there is a session
 * only after Google sign-in. The catalog is readable only with a session.
 */
class Session(
    context: Context,
    private val http: OkHttpClient,
    name: String = "session",
    private val url: String = BuildConfig.SUPABASE_URL,
    private val key: String = BuildConfig.SUPABASE_KEY,
    private val anonymous: Boolean = true,
    /** Named in the error when this build lacks the URL or key. */
    private val settingNames: String = "SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY",
) {
    private val prefs = context.getSharedPreferences(name, Context.MODE_PRIVATE)
    private val lock = Mutex()
    // Outlives the screen, so leaving Settings does not stop the server-side logout.
    private val background = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** The Google account's email, or null while not signed in with Google. */
    val email: String? get() = prefs.getString(EMAIL, null)

    /** A valid access token, refreshed or created as needed. */
    suspend fun token(): String = lock.withLock {
        requireConfigured(url, key, settingNames)
        current() ?: refresh() ?: if (anonymous) signUpAnonymously() else throw ApiException("Not signed in")
    }

    /**
     * Signs in with a Google ID token. With `link`, a device still on its
     * anonymous user becomes that Google user and keeps its data (favourites,
     * ratings, positions). When the Google account is already in use on
     * another device, this device signs in to that account instead and moves
     * its anonymous data into it.
     */
    suspend fun signInWithGoogle(idToken: String, link: Boolean) = lock.withLock {
        requireConfigured(url, key, settingNames)
        val body = { JSONObject().put("provider", "google").put("id_token", idToken) }
        val bearer = if (link && email == null) current() ?: refresh() else null
        if (bearer != null) {
            try {
                return@withLock auth("token?grant_type=id_token", body().put("link_identity", true), bearer)
            } catch (e: AuthRejected) {
                if (e.errorCode != "identity_already_exists") throw e
            }
        }
        // Switching to an account used elsewhere: the ticket carries this device's anonymous data across.
        val ticket = bearer?.let { bestEffort { rpc("create_merge_ticket", JSONObject(), it) } }
        val access = auth("token?grant_type=id_token", body())
        if (ticket != null) {
            // Best effort: a failure leaves the data on the old anonymous user, as before.
            // The move is one transaction on the server; a timed-out call may still have done it.
            bestEffort { rpc("redeem_merge_ticket", JSONObject().put("p_ticket", ticket.trim('"')), access) }
        }
        access
    }

    /** Null on failure, but a cancelled sign-in stays cancelled. */
    private inline fun <T> bestEffort(block: () -> T): T? = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }

    private suspend fun rpc(name: String, args: JSONObject, bearer: String): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("$url/rest/v1/rpc/$name")
            .header("apikey", key)
            .header("Authorization", "Bearer $bearer")
            .post(args.toString().toRequestBody(JSON))
            .build()
        http.newCall(request).execute().use {
            val text = it.body?.string().orEmpty()
            if (!it.isSuccessful) throw ApiException("$name failed (HTTP ${it.code})")
            text
        }
    }

    /**
     * Forgets the session at once (WTV starts again as a new anonymous user),
     * then ends it on the server in the background, best effort. Only this
     * device's session ends: the user stays signed in elsewhere.
     */
    suspend fun signOut() = lock.withLock {
        val stored = prefs.getString(ACCESS, null)
        val fresh = isFresh(prefs.getLong(EXPIRES_AT, 0), System.currentTimeMillis() / 1000)
        val refresh = prefs.getString(REFRESH, null)
        prefs.edit().clear().apply()
        if (stored != null) {
            background.launch {
                // The server refuses an expired access token, which would leave the session alive there.
                val token = if (fresh) stored else refresh?.let { freshToken(it) } ?: return@launch
                val request = Request.Builder()
                    .url("$url/auth/v1/logout?scope=local")
                    .header("apikey", key)
                    .header("Authorization", "Bearer $token")
                    .post(ByteArray(0).toRequestBody(JSON))
                    .build()
                runCatching { http.newCall(request).execute().close() }
            }
        }
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

    /** A new access token for `refresh`, not stored (for the logout after the device has forgotten it). */
    private fun freshToken(refresh: String): String? = runCatching {
        val request = Request.Builder()
            .url("$url/auth/v1/token?grant_type=refresh_token")
            .header("apikey", key)
            .post(JSONObject().put("refresh_token", refresh).toString().toRequestBody(JSON))
            .build()
        http.newCall(request).execute().use { JSONObject(it.body?.string().orEmpty()).optString("access_token") }
    }.getOrNull()?.takeIf { it.isNotEmpty() }

    /** Calls the auth API (as `bearer` when given), stores the new session, returns its access token. */
    private suspend fun auth(path: String, body: JSONObject, bearer: String? = null): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("$url/auth/v1/$path")
            .header("apikey", key)
            .apply { if (bearer != null) header("Authorization", "Bearer $bearer") }
            .post(body.toString().toRequestBody(JSON))
            .build()
        val (code, text) = try {
            http.newCall(request).execute().use { it.code to it.body?.string().orEmpty() }
        } catch (e: IOException) {
            throw ApiException("No connection to the server")
        }
        if (isRejection(code)) throw AuthRejected(code, runCatching { JSONObject(text).optString("error_code") }.getOrNull())
        // Anything else, 429 and 5xx included, is passing trouble: never a reason to make a new user.
        if (code !in 200..299) throw ApiException("Sign-in failed (HTTP $code)")
        val session = runCatching { JSONObject(text) }.getOrNull()
        val access = session?.optString("access_token").orEmpty()
        val refresh = session?.optString("refresh_token").orEmpty()
        val expiresAt = session?.optLong("expires_at") ?: 0
        // Anonymous users have an empty email.
        val email = session?.optJSONObject("user")?.optString("email").orEmpty()
        if (access.isEmpty() || refresh.isEmpty() || expiresAt == 0L) throw ApiException("Sign-in answer could not be read")
        prefs.edit()
            .putString(ACCESS, access)
            .putString(REFRESH, refresh)
            .putLong(EXPIRES_AT, expiresAt)
            .apply { if (email.isEmpty()) remove(EMAIL) else putString(EMAIL, email) }
            .apply()
        access
    }

    private class AuthRejected(code: Int, val errorCode: String?) : ApiException("Sign-in refused (HTTP $code)")

    private companion object {
        const val ACCESS = "access_token"
        const val REFRESH = "refresh_token"
        const val EXPIRES_AT = "expires_at"
        const val EMAIL = "email"
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
internal fun requireConfigured(url: String, key: String, names: String) {
    if (url.isBlank() || key.isBlank()) throw ApiException("This build has no database settings ($names in local.properties)")
}

open class ApiException(message: String) : Exception(message)
