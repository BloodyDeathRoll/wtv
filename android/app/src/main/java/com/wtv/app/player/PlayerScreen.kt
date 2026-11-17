package com.wtv.app.player

import android.view.ViewGroup
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import androidx.tv.material3.Button
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.delay

/**
 * Full-screen playback of one stream with the player's own on-screen
 * controls (play/pause, seek with the remote). Back leaves.
 *
 * Starts at `startSecs`. Reports the position (seconds, and the length when
 * known) every [SAVE_EVERY_MS] while playing, on pause, at the end, when the
 * app goes to the background, and, with `final`, when the page closes.
 */
@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(
    url: String,
    title: String,
    startSecs: Int,
    firstFocus: FocusRequester,
    onProgress: (positionSecs: Int, durationSecs: Int?, final: Boolean) -> Unit,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    var error by remember { mutableStateOf<String?>(null) }
    val report by rememberUpdatedState(onProgress)
    val player = remember(url) {
        // Media3's own user agent: the provider's stream server blocks the API client's.
        // The provider redirects to plain http on another host.
        val http = DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(true)
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(http))
            .build()
            .apply {
                setMediaItem(MediaItem.fromUri(url), startSecs * 1000L)
                prepare()
                playWhenReady = true
            }
    }
    // The app sent to the background (Home, another app): playback pauses; it is
    // released when the page closes. The stream address (it holds the login) is never logged.
    // Nothing is saved before playback has started: a stream that fails must not wipe the saved position.
    var started by remember { mutableStateOf(false) }
    fun save(final: Boolean) {
        if (!started) return
        val duration = player.duration.takeIf { it != C.TIME_UNSET && it > 0 }?.let { (it / 1000).toInt() }
        report((player.currentPosition / 1000).toInt(), duration, final)
    }
    LaunchedEffect(player) {
        while (true) {
            delay(SAVE_EVERY_MS)
            if (player.isPlaying) save(final = false)
        }
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(player, lifecycle) {
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) player.pause() }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlayerError(e: PlaybackException) {
                error = e.errorCodeName
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                // Paused, not buffering or seeking: those stop playing for a moment too.
                if (isPlaying) started = true else if (player.playbackState == Player.STATE_READY) save(final = false)
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) save(final = false)
            }
        }
        player.addListener(listener)
        onDispose {
            player.removeListener(listener)
            save(final = true)
            player.release()
        }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    this.player = player
                    keepScreenOn = true
                    setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
                }
            },
            modifier = Modifier.fillMaxSize().focusRequester(firstFocus),
        )
        val e = error
        if (e != null) {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(title, style = MaterialTheme.typography.headlineMedium, color = WtvColors.TextPrimary)
                Spacer(Modifier.height(8.dp))
                Text(stringResource(R.string.play_failed, e), style = MaterialTheme.typography.bodyLarge, color = WtvColors.TextSecondary)
                Spacer(Modifier.height(16.dp))
                val back = remember { FocusRequester() }
                Button(onClick = onClose, modifier = Modifier.focusRequester(back)) { Text(stringResource(R.string.close)) }
                LaunchedEffect(Unit) { runCatching { back.requestFocus() } }
            }
        }
    }
}

private const val SAVE_EVERY_MS = 15_000L
