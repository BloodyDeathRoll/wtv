package com.wtv.app

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * The app's language, chosen in Settings: English (the default) or Hebrew.
 * Applied to every activity's context, so menus, layout direction (Hebrew is
 * right to left) and the language of titles and synopses all follow it.
 */
enum class AppLanguage(val tag: String) {
    English("en"),
    Hebrew("iw"),
    ;

    companion object {
        private const val PREFS = "settings"
        private const val KEY = "language"

        fun current(context: Context): AppLanguage {
            val tag = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            return entries.firstOrNull { it.tag == tag } ?: English
        }

        fun save(context: Context, language: AppLanguage) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, language.tag).apply()
        }

        /** `base` with the chosen language. */
        fun wrap(base: Context): Context {
            val locale = Locale.forLanguageTag(current(base).tag)
            Locale.setDefault(locale)
            val config = Configuration(base.resources.configuration)
            config.setLocale(locale)
            config.setLayoutDirection(locale)
            return base.createConfigurationContext(config)
        }
    }
}
