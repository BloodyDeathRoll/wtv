package com.wtv.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged

/**
 * The item that last had the focus in one layer of screens, so Back from a
 * title page lands on the card it was opened from.
 */
class FocusMemory {
    private var last: FocusRequester? = null

    fun remember(item: FocusRequester) {
        last = item
    }

    /**
     * Focuses the remembered item, or `fallback` if there is none, it is gone
     * (throws) or cannot take the focus now (returns false).
     */
    fun restore(fallback: FocusRequester) {
        val item = last
        if (item == null || !runCatching { item.requestFocus() }.getOrDefault(false)) runCatching { fallback.requestFocus() }
    }
}

val LocalFocusMemory = staticCompositionLocalOf<FocusMemory?> { null }

/** Makes this item one the layer can return the focus to. */
@Composable
fun Modifier.remembersFocus(): Modifier {
    val memory = LocalFocusMemory.current ?: return this
    val item = remember { FocusRequester() }
    return focusRequester(item).onFocusChanged { if (it.hasFocus) memory.remember(item) }
}
