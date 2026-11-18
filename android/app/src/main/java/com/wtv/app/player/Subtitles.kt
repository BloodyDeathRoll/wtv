package com.wtv.app.player

import android.content.Context
import androidx.media3.common.C
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks

/**
 * The viewer's last subtitle choice, carried to the next video (the next
 * episode most of all). Subtitles come only from the files themselves (open
 * point O3): the provider lists none, and many tracks carry no language tag.
 *
 * Stored as [OFF], [UNTAGGED] or a language code. Nothing stored: each file's
 * own default. A file without the saved language shows its untagged track, if
 * any: most tracks here carry no tag.
 */
object Subtitles {
    const val OFF = "off"
    const val UNTAGGED = "und"
    private const val PREFS = "player"
    private const val KEY = "subtitles"

    fun load(context: Context): String? = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)

    fun save(context: Context, choice: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, choice).apply()
    }
}

/** `params` with the saved choice applied. An untagged track stands in when the language is missing. */
internal fun withSubtitles(params: TrackSelectionParameters, saved: String?): TrackSelectionParameters = when (saved) {
    null -> params
    Subtitles.OFF -> params.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true).build()
    else -> params.buildUpon()
        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
        .setPreferredTextLanguage(saved.takeIf { it != Subtitles.UNTAGGED })
        .setSelectUndeterminedTextLanguage(true)
        .build()
}

/** The parts of `params` that choose subtitles; a change in them is the viewer's choice. */
internal fun textSelection(params: TrackSelectionParameters): List<Any> = listOf(
    C.TRACK_TYPE_TEXT in params.disabledTrackTypes,
    params.overrides.filterKeys { it.type == C.TRACK_TYPE_TEXT },
    params.preferredTextLanguages,
    params.ignoredTextSelectionFlags,
)

/** The choice the playing tracks show: the selected subtitle's language, or [Subtitles.OFF]. */
internal fun subtitleChoice(tracks: Tracks): String =
    tracks.groups.firstOrNull { it.type == C.TRACK_TYPE_TEXT && it.isSelected }
        ?.let { group -> (0 until group.length).firstOrNull { group.isTrackSelected(it) }?.let { group.getTrackFormat(it).language } ?: Subtitles.UNTAGGED }
        ?: Subtitles.OFF
