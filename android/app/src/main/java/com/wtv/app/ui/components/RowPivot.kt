package com.wtv.app.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.gestures.BringIntoViewSpec
import androidx.compose.foundation.gestures.LocalBringIntoViewSpec
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Room above a focused card for its row title. */
private val RowTitleSpace = 40.dp

/**
 * A vertical list of rows in which the focused row always lands at the top,
 * with its title showing, as in the reference. `titleSpace` is the room kept
 * above a focused card (more where the title line holds chips). Rows inside
 * scroll sideways the default way: wrap each in [Sideways].
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun RowsAtTop(titleSpaceDp: Dp = RowTitleSpace, content: @Composable () -> Unit) {
    val titleSpace = with(LocalDensity.current) { titleSpaceDp.toPx() }
    val default = LocalBringIntoViewSpec.current
    val rowAtTop = remember(titleSpace) {
        object : BringIntoViewSpec {
            override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float): Float = offset - titleSpace
        }
    }
    CompositionLocalProvider(LocalBringIntoViewSpec provides rowAtTop, LocalSideways provides default) { content() }
}

/** Restores default scrolling for a sideways row inside [RowsAtTop]. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun Sideways(content: @Composable () -> Unit) {
    val default = LocalSideways.current
    if (default == null) content() else CompositionLocalProvider(LocalBringIntoViewSpec provides default) { content() }
}

@OptIn(ExperimentalFoundationApi::class)
private val LocalSideways = androidx.compose.runtime.staticCompositionLocalOf<BringIntoViewSpec?> { null }
