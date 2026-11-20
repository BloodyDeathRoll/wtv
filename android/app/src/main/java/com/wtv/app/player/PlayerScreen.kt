package com.wtv.app.player

import android.view.KeyEvent as AndroidKeyEvent
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ClosedCaption
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RadioButtonChecked
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.DefaultTrackNameProvider
import androidx.media3.ui.PlayerView
import androidx.tv.material3.Button
import androidx.tv.material3.Icon
import androidx.tv.material3.IconButton
import androidx.tv.material3.IconButtonDefaults
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.ui.components.MENU_WIDTH
import com.wtv.app.ui.components.MenuItem
import com.wtv.app.ui.components.ignoresOpeningPress
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.delay

/**
 * Full-screen playback of one stream. Back leaves.
 *
 * The remote, on the picture: OK pauses or plays at once. Left and Right move
 * [SEEK_MS]; held, the steps grow the longer the key is held ([scrubTo]), and
 * the picture follows when the key is let go. Down (or Up) goes to the buttons.
 *
 * The controls look like Live TV's catch-up banner: the title, then one line of
 * play or pause, the time in, the time bar, the length, the previous and next
 * episode (`episode` only), subtitles, settings (audio track and speed). They
 * show while paused; while playing they go [HIDE_MS] after the last key
 * ([BUTTONS_HIDE_MS] with a button focused). What has the focus is in the
 * accent colour: a button, or the time bar (with a knob) when the keys are the
 * picture's. The subtitle choice is kept for the next video ([Subtitles]).
 *
 * Starts at `startSecs`. Reports the position (seconds, and the length when
 * known) every [SAVE_EVERY_MS] while playing, on pause, at the end, when the
 * app goes to the background, and, with `final`, when the page closes.
 *
 * `next` names the episode that follows, if any. When the episode ends, an
 * Up next card counts down [UP_NEXT_SECS] and then calls `onNext`; OK on it
 * plays at once, Back hides it. Not before the end: there is no way to tell
 * where the credits start, and a guess cut the story short.
 * `onPrevious` is null on a series' first episode.
 */
@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(
    url: String,
    title: String,
    startSecs: Int,
    firstFocus: FocusRequester,
    episode: Boolean,
    next: String?,
    onNext: () -> Unit,
    onPrevious: (() -> Unit)?,
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
    var paused by remember { mutableStateOf(false) }
    var tracks by remember { mutableStateOf(Tracks.EMPTY) }
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

            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                paused = !playWhenReady
            }

            override fun onTracksChanged(now: Tracks) {
                tracks = now
                if (chosen && now.groups.any { it.type == C.TRACK_TYPE_TEXT }) Subtitles.save(context, subtitleChoice(now))
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

    // The controls: shown, which part has the keys, and the menu open over them.
    var shown by remember { mutableStateOf(false) }
    var poke by remember { mutableIntStateOf(0) } // bumped by every key: the controls stay a little longer
    var onButtons by remember { mutableStateOf(false) }
    var toButtons by remember { mutableIntStateOf(0) }
    var menu by remember { mutableStateOf<PlayerMenu?>(null) }
    val playButton = remember { FocusRequester() }
    var position by remember { mutableLongStateOf(0L) }
    var length by remember { mutableLongStateOf(0L) }
    // Where held Left / Right has got to; the player goes there when the key is let go.
    var scrub by remember { mutableStateOf<Long?>(null) }
    var lastStepAt by remember { mutableLongStateOf(0L) }
    fun duration() = player.duration.takeIf { it != C.TIME_UNSET && it > 0 }
    fun toPicture() {
        runCatching { firstFocus.requestFocus() }
        onButtons = false
    }
    fun toggle() {
        shown = true
        poke++
        if (player.playWhenReady) player.pause() else {
            player.play()
            // Playing again: the keys are the picture's, so the controls go at once.
            toPicture()
        }
    }
    fun step(forward: Boolean, e: AndroidKeyEvent) {
        // A held key repeats many times a second: the steps are spaced out.
        if (e.repeatCount > 0 && e.eventTime - lastStepAt < HELD_STEP_GAP_MS) return
        lastStepAt = e.eventTime
        scrub = scrubTo(scrub ?: player.currentPosition, duration(), forward, e.eventTime - e.downTime)
        shown = true
    }
    fun commit() {
        scrub?.let {
            player.seekTo(it)
            position = it
        }
        scrub = null
    }
    // A key let go somewhere else (a menu opened, the focus moved) still lands.
    LaunchedEffect(scrub) {
        if (scrub != null) {
            delay(SCRUB_IDLE_MS)
            commit()
        }
    }
    LaunchedEffect(shown) {
        while (shown) {
            position = player.currentPosition
            length = duration() ?: 0L
            delay(POSITION_TICK_MS)
        }
    }
    LaunchedEffect(poke, paused, onButtons, menu, scrub) {
        if (paused) shown = true
        if (!shown || paused || menu != null) return@LaunchedEffect
        delay(if (onButtons) BUTTONS_HIDE_MS else HIDE_MS)
        // The buttons go with the controls: the focus leaves them first.
        toPicture()
        shown = false
    }
    LaunchedEffect(toButtons) {
        if (toButtons == 0) return@LaunchedEffect
        // The buttons are composed once the controls show.
        withFrameNanos { }
        withFrameNanos { }
        runCatching { playButton.requestFocus() }
    }
    BackHandler(enabled = onButtons) { toPicture() }

    val overlay = error != null || (upNext && next != null)
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(firstFocus)
            .onPreviewKeyEvent {
                if (it.type == KeyEventType.KeyDown && shown) poke++
                false
            }
            .onKeyEvent {
                // The error and Up next have their own button.
                if (overlay) return@onKeyEvent false
                val e = it.nativeKeyEvent
                val down = it.type == KeyEventType.KeyDown
                when (e.keyCode) {
                    AndroidKeyEvent.KEYCODE_DPAD_LEFT, AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> {
                        // On the buttons these move between them.
                        if (onButtons) return@onKeyEvent false
                        if (down) step(e.keyCode == AndroidKeyEvent.KEYCODE_DPAD_RIGHT, e) else commit()
                        true
                    }
                    AndroidKeyEvent.KEYCODE_MEDIA_FAST_FORWARD, AndroidKeyEvent.KEYCODE_MEDIA_REWIND -> {
                        if (down) step(e.keyCode == AndroidKeyEvent.KEYCODE_MEDIA_FAST_FORWARD, e) else commit()
                        true
                    }
                    AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER, AndroidKeyEvent.KEYCODE_NUMPAD_ENTER -> {
                        // On a button, OK is the button's.
                        if (onButtons) return@onKeyEvent false
                        if (down && e.repeatCount == 0) toggle()
                        true
                    }
                    AndroidKeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                        if (down && e.repeatCount == 0) toggle()
                        true
                    }
                    // The remote's own play and pause keys set the state rather than toggle it.
                    AndroidKeyEvent.KEYCODE_MEDIA_PLAY, AndroidKeyEvent.KEYCODE_MEDIA_PAUSE -> {
                        if (down && player.playWhenReady != (e.keyCode == AndroidKeyEvent.KEYCODE_MEDIA_PLAY)) toggle()
                        true
                    }
                    AndroidKeyEvent.KEYCODE_MEDIA_NEXT -> {
                        if (down && e.repeatCount == 0 && next != null) onNext()
                        true
                    }
                    AndroidKeyEvent.KEYCODE_MEDIA_PREVIOUS -> {
                        if (down && e.repeatCount == 0) onPrevious?.invoke()
                        true
                    }
                    AndroidKeyEvent.KEYCODE_DPAD_DOWN, AndroidKeyEvent.KEYCODE_DPAD_UP -> {
                        if (down && !onButtons) {
                            shown = true
                            poke++
                            toButtons++
                        } else if (down && e.keyCode == AndroidKeyEvent.KEYCODE_DPAD_UP) {
                            toPicture()
                        }
                        true
                    }
                    else -> false
                }
            }
            .focusable(),
    ) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    this.player = player
                    useController = false
                    keepScreenOn = true
                    setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
                    // Not focusable: the keys belong to the box around it.
                    isFocusable = false
                    descendantFocusability = ViewGroup.FOCUS_BLOCK_DESCENDANTS
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
        if (shown && !overlay) {
            Controls(
                title = title,
                paused = paused,
                position = scrub ?: position,
                length = length,
                barFocused = !onButtons,
                playButton = playButton,
                onFocus = { onButtons = it },
                onToggle = ::toggle,
                episode = episode,
                onPrevious = onPrevious,
                onNext = onNext.takeIf { next != null },
                onSubtitles = ({ menu = PlayerMenu.Subtitles }).takeIf { tracks.groups.any { it.type == C.TRACK_TYPE_TEXT } },
                onSettings = { menu = PlayerMenu.Settings },
            )
        }
        val names = remember { DefaultTrackNameProvider(context.resources) }
        fun choices(type: Int) = tracks.groups.filter { it.type == type }.flatMap { g ->
            (0 until g.length).filter { g.isTrackSupported(it) }.map { i ->
                Choice(names.getTrackName(g.getTrackFormat(i)), g.isTrackSelected(i)) {
                    player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                        .setTrackTypeDisabled(type, false)
                        .setOverrideForType(TrackSelectionOverride(g.mediaTrackGroup, i))
                        .build()
                }
            }
        }
        when (menu) {
            PlayerMenu.Subtitles -> {
                val text = choices(C.TRACK_TYPE_TEXT)
                val off = Choice(stringResource(R.string.player_subtitles_off), text.none { it.selected }) {
                    player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                        .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                        .build()
                }
                ChoiceMenu(listOf(stringResource(R.string.player_subtitles) to listOf(off) + text)) { menu = null }
            }
            PlayerMenu.Settings -> {
                val speed = player.playbackParameters.speed
                ChoiceMenu(
                    listOf(
                        stringResource(R.string.player_audio) to choices(C.TRACK_TYPE_AUDIO),
                        stringResource(R.string.player_speed) to SPEEDS.map { s -> Choice("$s×", s == speed) { player.setPlaybackSpeed(s) } },
                    ).filter { it.second.isNotEmpty() },
                ) { menu = null }
            }
            null -> Unit
        }
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
                runCatching { firstFocus.requestFocus() }
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

/** The controls along the bottom, like Live TV's catch-up banner; the line is left to right in Hebrew too, like a clock. */
@Composable
private fun BoxScope.Controls(
    title: String,
    paused: Boolean,
    position: Long,
    length: Long,
    barFocused: Boolean,
    playButton: FocusRequester,
    onFocus: (Boolean) -> Unit,
    onToggle: () -> Unit,
    episode: Boolean,
    onPrevious: (() -> Unit)?,
    onNext: (() -> Unit)?,
    onSubtitles: (() -> Unit)?,
    onSettings: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .align(Alignment.BottomStart)
            // Dark enough to read over any picture.
            .background(Brush.verticalGradient(0f to Color.Transparent, 0.3f to Color(0xCC000000), 1f to Color(0xF2000000)))
            .padding(start = 64.dp, end = 64.dp, top = 64.dp, bottom = 40.dp),
    ) {
        Text(title, style = MaterialTheme.typography.headlineSmall, color = WtvColors.TextPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (paused) Text(stringResource(R.string.live_catchup_paused), style = MaterialTheme.typography.labelLarge, color = WtvColors.Accent)
        Spacer(Modifier.height(6.dp))
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
            Row(
                Modifier.onFocusChanged { onFocus(it.hasFocus) },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                ControlButton(
                    if (paused) Icons.Filled.PlayArrow else Icons.Filled.Pause,
                    stringResource(if (paused) R.string.play else R.string.player_pause),
                    onToggle,
                    // The row's ends: the focus stays.
                    Modifier.focusRequester(playButton).focusProperties { left = FocusRequester.Cancel },
                )
                Text(duration(position), style = MaterialTheme.typography.titleSmall, color = WtvColors.TextPrimary)
                val done = if (length > 0) (position.toFloat() / length).coerceIn(0f, 1f) else 0f
                Box(Modifier.weight(1f).height(4.dp).background(WtvColors.Surface)) {
                    Box(
                        Modifier.fillMaxWidth(done).height(4.dp).background(WtvColors.Accent)
                            // The knob: Left and Right move through the video now.
                            .drawBehind { if (barFocused) drawCircle(WtvColors.Accent, 9.dp.toPx(), Offset(size.width, size.height / 2)) },
                    )
                }
                Text(duration(length), style = MaterialTheme.typography.titleSmall, color = WtvColors.TextSecondary)
                if (episode) {
                    ControlButton(Icons.Filled.SkipPrevious, stringResource(R.string.player_previous), onPrevious)
                    ControlButton(Icons.Filled.SkipNext, stringResource(R.string.player_next), onNext)
                }
                ControlButton(Icons.Filled.ClosedCaption, stringResource(R.string.player_subtitles), onSubtitles)
                ControlButton(Icons.Filled.Settings, stringResource(R.string.rail_settings), onSettings, Modifier.focusProperties { right = FocusRequester.Cancel })
            }
        }
    }
}

/** A round button of the controls, in the accent colour when focused; with no `onClick` it is greyed and skipped. */
@Composable
private fun ControlButton(icon: ImageVector, label: String, onClick: (() -> Unit)?, modifier: Modifier = Modifier) {
    IconButton(
        onClick = { onClick?.invoke() },
        // A greyed button would still take the focus.
        modifier = modifier.focusProperties { canFocus = onClick != null },
        enabled = onClick != null,
        colors = IconButtonDefaults.colors(
            containerColor = Color.Transparent,
            contentColor = WtvColors.TextPrimary,
            focusedContainerColor = WtvColors.Accent,
            focusedContentColor = Color.Black,
            pressedContainerColor = WtvColors.Accent,
            pressedContentColor = Color.Black,
            disabledContainerColor = Color.Transparent,
            disabledContentColor = WtvColors.TextMuted.copy(alpha = 0.5f),
        ),
    ) { Icon(icon, contentDescription = label) }
}

private enum class PlayerMenu { Subtitles, Settings }

/** A row of a player menu: `pick` chooses it. */
private class Choice(val label: String, val selected: Boolean, val pick: () -> Unit)

/** Lists to choose one row from, each under its heading; the chosen row is marked and has the focus. OK chooses and closes; Back closes. */
@Composable
private fun ChoiceMenu(sections: List<Pair<String, List<Choice>>>, onDismiss: () -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val first = remember { FocusRequester() }
        val focused = sections.flatMap { it.second }.let { all -> all.firstOrNull { it.selected } ?: all.firstOrNull() }
        Column(
            Modifier.ignoresOpeningPress().width(MENU_WIDTH).heightIn(max = 620.dp)
                .background(WtvColors.Surface, RoundedCornerShape(12.dp)).padding(24.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            sections.forEach { (heading, choices) ->
                Text(heading, style = MaterialTheme.typography.titleLarge, color = WtvColors.TextPrimary)
                choices.forEach { c ->
                    MenuItem(
                        if (c.selected) Icons.Filled.RadioButtonChecked else Icons.Filled.RadioButtonUnchecked,
                        c.label,
                        onClick = {
                            c.pick()
                            onDismiss()
                        },
                        if (c === focused) Modifier.focusRequester(first) else Modifier,
                    )
                }
                Spacer(Modifier.height(8.dp))
            }
        }
        LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
    }
}

/**
 * Where a Left / Right step lands: [SEEK_MS] on a press; on a held key the step doubles with each
 * second held, up to [SEEK_MAX_MS]. Never before the start, and forward never into the last
 * [END_MARGIN_MS] (the end starts the next episode) nor backward from there.
 */
internal fun scrubTo(position: Long, length: Long?, forward: Boolean, heldMs: Long): Long {
    val step = minOf(SEEK_MS shl (heldMs / 1000).coerceIn(0, 10).toInt(), SEEK_MAX_MS)
    if (!forward) return (position - step).coerceAtLeast(0L)
    val end = length?.let { (it - END_MARGIN_MS).coerceAtLeast(0L) } ?: Long.MAX_VALUE
    return maxOf(position, minOf(position + step, end))
}

private const val SAVE_EVERY_MS = 15_000L
private const val UP_NEXT_SECS = 10
/** While playing, the controls go this long after the last key. */
private const val HIDE_MS = 800L
/** With a button focused they stay longer: time to read and choose. */
private const val BUTTONS_HIDE_MS = 5_000L
private const val SEEK_MS = 10_000L
private const val SEEK_MAX_MS = 300_000L
/** While a key is held, at most one step in this time. */
private const val HELD_STEP_GAP_MS = 150L
/** No step for this long: the player goes to where the steps got to. */
private const val SCRUB_IDLE_MS = 600L
private const val END_MARGIN_MS = 5_000L
private const val POSITION_TICK_MS = 250L
private val SPEEDS = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f)
