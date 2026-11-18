package com.wtv.app.player

import android.view.View
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
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
 *
 * The controls offer subtitles and, in the settings, the audio track. The
 * subtitle choice is kept for the next video ([Subtitles]).
 *
 * `next` names the episode that follows, if any. When the episode ends, an
 * Up next card counts down [UP_NEXT_SECS] and then calls `onNext`; OK on it
 * plays at once, Back hides it. Not before the end: there is no way to tell
 * where the credits start, and a guess cut the story short.
 */
@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(
    url: String,
    title: String,
    startSecs: Int,
    firstFocus: FocusRequester,
    next: String?,
    onNext: () -> Unit,
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
                trackSelectionParameters = withSubtitles(trackSelectionParameters, Subtitles.load(context))
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
    var upNext by remember { mutableStateOf(false) }
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

            // Only a subtitle choice the viewer made is kept: not a file's own default,
            // not an audio change, and not a moment with no tracks (between files, on an error).
            var chosen = false
            var last = player.trackSelectionParameters

            override fun onTrackSelectionParametersChanged(parameters: TrackSelectionParameters) {
                if (textSelection(parameters) != textSelection(last)) chosen = true
                last = parameters
            }

            override fun onTracksChanged(tracks: Tracks) {
                if (chosen && tracks.groups.any { it.type == C.TRACK_TYPE_TEXT }) Subtitles.save(context, subtitleChoice(tracks))
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) {
                    save(final = false)
                    if (next != null) upNext = true
                }
            }
        }
        player.addListener(listener)
        onDispose {
            player.removeListener(listener)
            save(final = true)
            player.release()
        }
    }

    // The view itself must hold the Android focus: the remote's keys show its
    // controls and move between them. The Compose focus alone does not pass them in.
    var view by remember { mutableStateOf<PlayerView?>(null) }
    LaunchedEffect(view) { view?.let { if (!it.requestFocus()) it.post { it.requestFocus() } } }
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    this.player = player
                    keepScreenOn = true
                    setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
                    setShowSubtitleButton(true)
                    // Focus search does not cross the Compose wrapper: the bar and the buttons under it
                    // are linked by hand. The CC button is disabled for files with no subtitles; then Down goes to settings.
                    val subtitle = findViewById<View>(androidx.media3.ui.R.id.exo_subtitle)
                    findViewById<View>(androidx.media3.ui.R.id.exo_progress)?.setOnFocusChangeListener { bar, focused ->
                        if (focused) {
                            bar.nextFocusDownId =
                                if (subtitle?.isShown == true && subtitle.isEnabled) androidx.media3.ui.R.id.exo_subtitle else androidx.media3.ui.R.id.exo_settings
                        }
                    }
                    for (id in listOf(androidx.media3.ui.R.id.exo_subtitle, androidx.media3.ui.R.id.exo_settings)) {
                        findViewById<View>(id)?.nextFocusUpId = androidx.media3.ui.R.id.exo_progress
                    }
                    // Hidden controls take their focused button with them: the view takes the focus back.
                    setControllerVisibilityListener(PlayerView.ControllerVisibilityListener { if (it != View.VISIBLE) requestFocus() })
                    view = this
                }
            },
            modifier = Modifier.fillMaxSize().focusRequester(firstFocus),
        )
        if (upNext && next != null && error == null) {
            val button = remember { FocusRequester() }
            var left by remember { mutableIntStateOf(UP_NEXT_SECS) }
            LaunchedEffect(Unit) {
                runCatching { button.requestFocus() }
                while (left > 0) {
                    delay(1_000)
                    left--
                }
                onNext()
            }
            BackHandler {
                upNext = false
                if (view?.requestFocus() != true) runCatching { firstFocus.requestFocus() }
            }
            Column(
                Modifier.align(Alignment.BottomEnd).padding(48.dp)
                    .background(WtvColors.Surface.copy(alpha = 0.92f), RoundedCornerShape(8.dp)).padding(24.dp),
            ) {
                Text(stringResource(R.string.up_next), style = MaterialTheme.typography.labelLarge, color = WtvColors.TextSecondary)
                Spacer(Modifier.height(4.dp))
                Text(next, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextPrimary)
                Spacer(Modifier.height(16.dp))
                Button(onClick = onNext, modifier = Modifier.focusRequester(button)) { Text(stringResource(R.string.play_next_in, left)) }
            }
        }
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
private const val UP_NEXT_SECS = 10
