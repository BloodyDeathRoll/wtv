package com.wtv.app.ui.components

import android.os.SystemClock
import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Info
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.tv.material3.Button
import androidx.tv.material3.Icon
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.Title
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.launch

/**
 * For a menu opened by holding OK: drops the key events of that same press
 * (its repeats and its release). On a remote, the release would otherwise
 * press the menu's focused button the moment the menu appears, and close it.
 */
@Composable
fun Modifier.ignoresOpeningPress(): Modifier {
    val openedAt = remember { SystemClock.uptimeMillis() }
    return onPreviewKeyEvent { it.nativeKeyEvent.downTime < openedAt }
}

/** Opens the long-press menu for a title card; the app frame provides it. */
val LocalTitleMenu = staticCompositionLocalOf<(Title) -> Unit> { {} }

/** A title card held down: Watchlist, Info, Play (focused), Close, each an icon with its name. Back closes. */
@Composable
fun TitleMenu(title: Title, onInfo: () -> Unit, onPlay: () -> Unit, onDismiss: () -> Unit) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val scope = rememberCoroutineScope()
    // Null until known: the Watchlist button says Add or Remove.
    var onWatchlist by remember(title.id) { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(title.id) { onWatchlist = runCatching { catalog.marks(title).onWatchlist }.getOrDefault(false) }
    val play = remember { FocusRequester() }
    // Four buttons are wider than a default dialog.
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier.ignoresOpeningPress().background(WtvColors.Surface, RoundedCornerShape(12.dp)).padding(horizontal = 32.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(title.displayName(isHebrew()), style = MaterialTheme.typography.titleLarge, color = WtvColors.TextPrimary, maxLines = 1)
            Spacer(Modifier.height(20.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                val on = onWatchlist
                MenuItem(
                    if (on == true) Icons.Outlined.Check else Icons.Outlined.Add,
                    stringResource(if (on == true) R.string.remove_from_watchlist else R.string.add_to_watchlist),
                    onClick = {
                        if (on != null) scope.launch {
                            runCatching { catalog.setWatchlist(title, !on) }
                                .onFailure { Log.w("WtvWatchlist", "Changing the watchlist failed: ${it.message}") }
                            onDismiss()
                        }
                    },
                )
                MenuItem(Icons.Outlined.Info, stringResource(R.string.more_info), onInfo)
                MenuItem(Icons.Filled.PlayArrow, stringResource(R.string.play), onPlay, Modifier.focusRequester(play))
                MenuItem(Icons.Outlined.Close, stringResource(R.string.close), onDismiss)
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { play.requestFocus() } }
}

@Composable
private fun MenuItem(icon: ImageVector, label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Button(onClick = onClick, modifier = modifier.width(132.dp)) {
        Column(Modifier.padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(28.dp))
            Spacer(Modifier.height(6.dp))
            Text(label, style = MaterialTheme.typography.labelMedium, textAlign = TextAlign.Center, maxLines = 2)
        }
    }
}
