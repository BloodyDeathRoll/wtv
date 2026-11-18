package com.wtv.app.player

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SubtitlesTest {
    private val base = TrackSelectionParameters.Builder().build()

    @Test fun `nothing saved keeps the defaults, off disables text, a language is preferred`() {
        assertEquals(base, withSubtitles(base, null))
        assertTrue(C.TRACK_TYPE_TEXT in withSubtitles(base, Subtitles.OFF).disabledTrackTypes)
        val heb = withSubtitles(withSubtitles(base, Subtitles.OFF), "heb")
        assertFalse(C.TRACK_TYPE_TEXT in heb.disabledTrackTypes)
        assertEquals(listOf("he"), heb.preferredTextLanguages)
        assertTrue(heb.selectUndeterminedTextLanguage)
        val untagged = withSubtitles(base, Subtitles.UNTAGGED)
        assertEquals(emptyList<String>(), untagged.preferredTextLanguages)
        assertTrue(untagged.selectUndeterminedTextLanguage)
    }

    private fun text(language: String?) = Format.Builder().setSampleMimeType(MimeTypes.APPLICATION_SUBRIP).setLanguage(language).build()
    private fun group(format: Format, selected: Boolean) =
        Tracks.Group(TrackGroup(format), false, intArrayOf(C.FORMAT_HANDLED), booleanArrayOf(selected))

    @Test fun `the choice is the selected subtitle's language, untagged, or off`() {
        assertEquals(Subtitles.OFF, subtitleChoice(Tracks(listOf(group(text("he"), false)))))
        assertEquals("he", subtitleChoice(Tracks(listOf(group(text("en"), false), group(text("he"), true)))))
        assertEquals(Subtitles.UNTAGGED, subtitleChoice(Tracks(listOf(group(text(null), true)))))
        assertEquals(Subtitles.OFF, subtitleChoice(Tracks.EMPTY))
    }
}
