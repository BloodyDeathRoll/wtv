package com.wtv.app.ui.live

import android.view.KeyEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.delay

/**
 * A channel number typed on the remote's number keys, as on a TV box: the
 * digits show at the top right, and the number is taken 1.5 s after the last
 * one (at once at four digits). `missing` is a number with no channel, shown briefly.
 */
class NumberEntry {
    var digits by mutableStateOf("")
    var missing by mutableStateOf<Int?>(null)

    /** Takes a number key (top row or keypad); true when it was one. */
    fun key(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return false
        val digit = when (event.keyCode) {
            in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> event.keyCode - KeyEvent.KEYCODE_0
            in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9 -> event.keyCode - KeyEvent.KEYCODE_NUMPAD_0
            else -> return false
        }
        if (event.repeatCount > 0) return true // a held key adds its digit once
        if (digits.length < MAX_DIGITS) digits += digit
        missing = null
        return true
    }
}

/** `onNumber` gets each number typed; it answers whether a channel has it. */
@Composable
fun rememberNumberEntry(onNumber: (Int) -> Boolean): NumberEntry {
    val entry = remember { NumberEntry() }
    val take by rememberUpdatedState(onNumber)
    LaunchedEffect(entry.digits) {
        val typed = entry.digits.takeIf { it.isNotEmpty() } ?: return@LaunchedEffect
        if (typed.length < MAX_DIGITS) delay(WAIT_MS)
        entry.digits = ""
        val number = typed.toInt()
        if (!take(number)) entry.missing = number
    }
    LaunchedEffect(entry.missing) {
        if (entry.missing != null) {
            delay(MISSING_MS)
            entry.missing = null
        }
    }
    return entry
}

/** The digits being typed, or "No channel 57", big at the top right (in Hebrew too, like a TV's). */
@Composable
fun BoxScope.NumberOverlay(entry: NumberEntry) {
    val text = entry.digits.ifEmpty { null } ?: entry.missing?.let { stringResource(R.string.live_no_channel, it) } ?: return
    Text(
        text,
        style = if (entry.digits.isNotEmpty()) MaterialTheme.typography.displayMedium else MaterialTheme.typography.titleLarge,
        color = WtvColors.TextPrimary,
        modifier = Modifier
            .align(AbsoluteAlignment.TopRight)
            .padding(top = 40.dp, end = 56.dp)
            .background(Color(0xCC000000), RoundedCornerShape(8.dp))
            .padding(horizontal = 20.dp, vertical = 8.dp),
    )
}

private const val MAX_DIGITS = 4
private const val WAIT_MS = 1_500L
private const val MISSING_MS = 2_000L
