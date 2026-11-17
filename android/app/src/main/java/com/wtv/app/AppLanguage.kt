package com.wtv.app

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * The app's language, chosen in Settings: English (the default) or Hebrew.
 * Applied to the activity, so menus, layout direction (Hebrew is right to
 * left) and the language of titles and synopses all follow it.
 *
 * Hebrew is "iw", Android's resource code for it (`values-iw`); `isHebrew()`
 * accepts "he" too.
 */
enum class AppLanguage(val tag: String) {
    English("en"),
    Hebrew("iw"),
    ;

    companion object {
        private const val PREFS = "settings"
        private const val KEY = "language"

        /** The language for a stored tag; English for none or an unknown one. */
        internal fun fromTag(tag: String?): AppLanguage = entries.firstOrNull { it.tag == tag } ?: English

        fun current(context: Context): AppLanguage =
            fromTag(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null))

        /** Written at once: the activity is recreated right after and reads it back. */
        fun save(context: Context, language: AppLanguage) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, language.tag).commit()
        }

        /**
         * The configuration override that sets the chosen language. The default
         * locale is set too, on purpose: dates and numbers follow the app's language.
         */
        fun override(context: Context): Configuration {
            val locale = Locale.forLanguageTag(current(context).tag)
            Locale.setDefault(locale)
            return Configuration().apply {
                setLocale(locale)
                setLayoutDirection(locale)
            }
        }
    }
}
