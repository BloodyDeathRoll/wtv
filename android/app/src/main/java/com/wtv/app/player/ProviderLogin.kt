package com.wtv.app.player

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.net.URLEncoder
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The Xtream provider login, typed in Settings and kept on this device only,
 * encrypted with a key that never leaves the Android keystore (open point O5).
 */
data class ProviderLogin(val server: String, val user: String, val password: String) {
    val isComplete: Boolean get() = server.isNotBlank() && user.isNotBlank() && password.isNotBlank()

    companion object {
        private const val PREFS = "provider"
        private const val KEY = "login"
        private const val ALIAS = "wtv-provider-login"

        fun load(context: Context): ProviderLogin? {
            val stored = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return null
            val json = runCatching { JSONObject(decrypt(stored)) }.getOrNull() ?: return null
            return ProviderLogin(json.optString("server"), json.optString("user"), json.optString("password"))
        }

        /**
         * False if the keystore failed (it does on some TV boxes); nothing is stored then.
         * A key that exists but no longer works (invalidated) is replaced once: what it
         * protected is unreadable anyway.
         */
        fun save(context: Context, login: ProviderLogin): Boolean {
            val json = JSONObject().put("server", login.server.trim()).put("user", login.user.trim()).put("password", login.password).toString()
            val sealed = runCatching { encrypt(json) }.recoverCatching {
                KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(ALIAS)
                encrypt(json)
            }.getOrNull() ?: return false
            return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, sealed).commit()
        }

        private fun key(): SecretKey {
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            generator.init(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build(),
            )
            return generator.generateKey()
        }

        private fun encrypt(plain: String): String {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
            val sealed = cipher.doFinal(plain.toByteArray())
            return Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(sealed, Base64.NO_WRAP)
        }

        private fun decrypt(stored: String): String {
            val (iv, sealed) = stored.split(":").map { Base64.decode(it, Base64.NO_WRAP) }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv)) }
            return String(cipher.doFinal(sealed))
        }
    }
}

/** What to play: a movie copy, an episode, or (P5) a channel. */
enum class StreamKind(val path: String) { Movie("movie"), Episode("series"), Live("live") }

/**
 * The provider's stream URL: `<server>/<movie|series|live>/<user>/<password>/<id>.<ext>`.
 * A server without a scheme is https; user and password are path-encoded.
 */
fun streamUrl(login: ProviderLogin, kind: StreamKind, extId: Long, containerExt: String?): String {
    val server = login.server.trim().trimEnd('/').let { if (Regex("^https?://", RegexOption.IGNORE_CASE).containsMatchIn(it)) it else "https://$it" }
    val ext = containerExt?.takeIf { it.isNotBlank() } ?: if (kind == StreamKind.Live) "ts" else "mp4"
    fun seg(s: String) = URLEncoder.encode(s.trim(), "UTF-8").replace("+", "%20")
    return "$server/${kind.path}/${seg(login.user)}/${seg(login.password)}/$extId.$ext"
}
