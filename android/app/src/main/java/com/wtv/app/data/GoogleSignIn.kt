package com.wtv.app.data

import com.wtv.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException

/**
 * Google sign-in for TVs (OAuth device flow): the TV shows a code, the user
 * enters it on a phone at google.com/device, and the TV receives an ID token.
 * Only name and email are asked for.
 */
class GoogleSignIn(private val http: OkHttpClient) {
    data class Code(val userCode: String, val url: String, val deviceCode: String, val intervalSeconds: Long, val expiresAtMillis: Long)

    /** Asks Google for a code to show. */
    suspend fun start(): Code {
        if (BuildConfig.GOOGLE_TV_CLIENT_ID.isBlank()) throw ApiException("This build has no Google sign-in settings (GOOGLE_TV_CLIENT_ID in local.properties)")
        val (status, json) = post(
            "device/code",
            FormBody.Builder()
                .add("client_id", BuildConfig.GOOGLE_TV_CLIENT_ID)
                .add("scope", "openid email profile")
                .build(),
        )
        if (status !in 200..299) throw ApiException("Google sign-in could not start (HTTP $status)")
        return Code(
            userCode = json.optString("user_code"),
            url = json.optString("verification_url"),
            deviceCode = json.optString("device_code"),
            intervalSeconds = json.optLong("interval", 5).coerceAtLeast(1),
            expiresAtMillis = System.currentTimeMillis() + json.optLong("expires_in", 1800) * 1000,
        )
    }

    /** Waits until the user approves on the phone and returns the ID token. Throws when declined or expired. */
    suspend fun awaitIdToken(code: Code): String {
        var interval = code.intervalSeconds
        var offline = 0
        while (System.currentTimeMillis() < code.expiresAtMillis) {
            delay(interval * 1000)
            // The user may take minutes on the phone: a short network drop must not end the sign-in.
            val (status, json) = try {
                post(
                    "token",
                    FormBody.Builder()
                        .add("client_id", BuildConfig.GOOGLE_TV_CLIENT_ID)
                        .add("client_secret", BuildConfig.GOOGLE_TV_CLIENT_SECRET)
                        .add("device_code", code.deviceCode)
                        .add("grant_type", "urn:ietf:params:oauth:grant-type:device_code")
                        .build(),
                ).also { offline = 0 }
            } catch (e: ApiException) {
                if (++offline >= 6) throw e
                continue
            }
            when (val result = pollResult(status, json)) {
                is Poll.Token -> return result.idToken
                Poll.Pending -> Unit
                Poll.SlowDown -> interval += 5
                is Poll.Failed -> throw ApiException(result.reason)
            }
        }
        throw ApiException("The code expired")
    }

    private suspend fun post(path: String, body: FormBody): Pair<Int, JSONObject> = withContext(Dispatchers.IO) {
        val request = Request.Builder().url("https://oauth2.googleapis.com/$path").post(body).build()
        try {
            http.newCall(request).execute().use { it.code to (runCatching { JSONObject(it.body?.string().orEmpty()) }.getOrNull() ?: JSONObject()) }
        } catch (e: IOException) {
            throw ApiException("No connection to Google")
        }
    }
}

internal sealed interface Poll {
    data class Token(val idToken: String) : Poll
    data object Pending : Poll
    data object SlowDown : Poll
    data class Failed(val reason: String) : Poll
}

/** Reads one answer of Google's token endpoint while the user is on the phone. */
internal fun pollResult(status: Int, json: JSONObject): Poll {
    val idToken = json.optString("id_token")
    if (status in 200..299 && idToken.isNotEmpty()) return Poll.Token(idToken)
    return when (val error = json.optString("error")) {
        "authorization_pending" -> Poll.Pending
        "slow_down" -> Poll.SlowDown
        "access_denied" -> Poll.Failed("Sign-in was declined on the phone")
        "expired_token" -> Poll.Failed("The code expired")
        else -> Poll.Failed("Google sign-in failed (${error.ifEmpty { "HTTP $status" }})")
    }
}
