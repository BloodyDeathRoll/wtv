package com.wtv.app.ui.theme

import androidx.compose.ui.graphics.Color

/** Colour tokens, taken from the Prime Video TV reference photos. */
object WtvColors {
    /** Page background: near-black with a blue cast. */
    val Background = Color(0xFF0F171E)
    val Surface = Color(0xFF1A242F)
    val TextPrimary = Color(0xFFFFFFFF)
    val TextSecondary = Color(0xFFC7CBD1)
    val TextMuted = Color(0xFF8197A4)

    /** Highlight line under the title (awards, "New episode"). */
    val Accent = Color(0xFF1BC4BD)

    /** Focus ring on cards and buttons. */
    val Focus = Color(0xFFFFFFFF)

    /** What has the focus in the player's controls: bright, to find it over any picture. */
    val PlayerFocus = Color(0xFFFFE100)

    /** An unselected chip: a little lighter than [Surface]. */
    val Chip = Color(0xFF253241)

    /** A selected chip: darker than an unselected one. */
    val ChipSelected = Color(0xFF131B23)

    /** Rating badges ("TV-14", "16+"). */
    val Badge = Color(0xFF33373D)

    /** Tags on the title line ("TRENDING", "NEW"). */
    val Tag = Color(0xFFE6E6E6)
    val OnTag = Color(0xFF0F171E)
}
