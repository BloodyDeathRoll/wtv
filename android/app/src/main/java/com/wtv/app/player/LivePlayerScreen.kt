package com.wtv.app.player

import android.util.Log
import android.view.KeyEvent as AndroidKeyEvent
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
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
import androidx.tv.material3.ListItem
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.Channel
import com.wtv.app.data.channelByNumber
import com.wtv.app.ui.live.NumberOverlay
import com.wtv.app.ui.live.rememberNumberEntry
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

/**
 * Live TV, full screen, like a TV box: Left / Right (and the remote's channel
 * keys) change channel within `channels`, wrapping at the ends; Up and OK show
 * the banner. The banner (number, logo, name, and what is on now and next from the
 * provider's short guide) shows for a few seconds on every change; on a radio
 * channel it stays. Back leaves. Nothing is saved.
 *
 * Catch-up, on channels that keep an archive: Down opens the earlier
 * programmes; one chosen plays from its start in place of the live picture.
 * Then Left and Right (and the rewind and fast-forward keys) move 30 s, or
 * 2 minutes a step while held; OK pauses or plays; the banner shows where in
 * the programme it is, and stays while paused. Back (or a channel change)
 * returns to live.
 */
@OptIn(UnstableApi::class)
@Composable
fun LivePlayerScreen(
    channels: List<Channel>,
    start: Int,
    login: ProviderLogin,
    firstFocus: FocusRequester,
    /** Every channel the user can watch, for a number typed that is not in `channels`. */
    all: List<Channel> = channels,
) {
    require(channels.isNotEmpty()) { "A live page needs at least one channel" }
    val context = LocalContext.current
    // The channels Left and Right move through: the group watched from, or all of them after a number jump outside it.
    var list by remember { mutableStateOf(channels) }
    var index by remember { mutableIntStateOf(start.coerceIn(channels.indices)) }
    val channel = list[index]
    var error by remember { mutableStateOf<String?>(null) }
    var bannerAt by remember { mutableIntStateOf(0) } // bumped to show the banner again
    var banner by remember { mutableStateOf(true) }
    var buffering by remember { mutableStateOf(false) }
    // The channel's guide, read again each time the banner shows: what is on changes.
    var guide by remember { mutableStateOf(emptyList<Programme>()) }
    var guideFor by remember { mutableStateOf<Long?>(null) }
    // The banner's clock: ticks while the banner is up (on radio it stays), so the line and bar move on.
    var now by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    val http = (context.applicationContext as WtvApplication).http
    // The past programme playing instead of live, if any; the full-screen panel open over the picture (null: none) and its list.
    var catchup by remember { mutableStateOf<Programme?>(null) }
    var panel by remember { mutableStateOf<LivePanel?>(null) }
    var panelList by remember { mutableStateOf(emptyList<Programme>()) }
    var panelLoading by remember { mutableStateOf(false) }
    var panelFailed by remember { mutableStateOf(false) }
    // Catch-up's place in the programme, for the banner's time bar (ms), and whether it is paused.
    var position by remember { mutableLongStateOf(0L) }
    var length by remember { mutableLongStateOf(0L) }
    var paused by remember { mutableStateOf(false) }

    val player = remember {
        // Media3's own user agent, as for movies: the stream server blocks the API client's.
        val http = DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(true)
        ExoPlayer.Builder(context).setMediaSourceFactory(DefaultMediaSourceFactory(http)).build().apply { playWhenReady = true }
    }
    LaunchedEffect(channel.id, catchup) {
        error = null
        paused = false
        position = 0L
        val url = catchup?.let { timeshiftUrl(login, channel.extId, it) } ?: streamUrl(login, StreamKind.Live, channel.extId, "ts")
        player.setMediaItem(MediaItem.fromUri(url))
        player.prepare()
        player.play()
    }
    // The panel's list, read when it opens.
    val panelOpen = panel != null
    LaunchedEffect(panel, channel.id) {
        val kind = panel ?: return@LaunchedEffect
        panelList = emptyList()
        panelFailed = false
        if (kind == LivePanel.Channels) {
            panelLoading = false
            return@LaunchedEffect
        }
        panelLoading = true
        runCatching {
            when (kind) {
                LivePanel.Earlier -> archive(http, login, channel.extId, System.currentTimeMillis() / 1000)
                LivePanel.Guide -> shortEpg(http, login, channel.extId, limit = GUIDE_LIMIT)
                LivePanel.Channels -> emptyList()
            }
        }
            .onSuccess { panelList = it }
            .onFailure {
                if (it is CancellationException) throw it
                panelFailed = true
            }
        panelLoading = false
    }
    BackHandler(enabled = panelOpen) {
        panel = null
        runCatching { firstFocus.requestFocus() }
    }
    BackHandler(enabled = !panelOpen && catchup != null) {
        catchup = null
        bannerAt++
    }
    // A stream that never starts shows no error of its own: after a while it counts as failed.
    LaunchedEffect(channel.id, buffering) {
        if (buffering) {
            delay(STALL_MS)
            error = STALLED
            banner = true
        }
    }
    LaunchedEffect(channel.id, bannerAt) {
        if (guideFor != channel.id) {
            guide = emptyList()
            guideFor = channel.id
        }
        // A nicety: without a guide the banner shows the channel only.
        runCatching { shortEpg(http, login, channel.extId) }
            .onSuccess { guide = it }
            .onFailure {
                // A fetch cancelled by a newer one is not a missing guide.
                if (it is CancellationException) throw it
                Log.d("WtvGuide", "No guide for channel ${channel.extId}: ${it.message}")
            }
    }
    LaunchedEffect(banner) {
        var first = true
        while (banner) {
            now = System.currentTimeMillis() / 1000
            // The programme on air ended: read the guide again for the one after. Not on the
            // first tick: showing the banner has just started a read.
            if (!first && guide.isNotEmpty() && nowAndNext(guide, now).first == null) bannerAt++
            first = false
            delay(CLOCK_TICK_MS)
        }
    }
    // The time bar moves while it shows.
    LaunchedEffect(banner, catchup) {
        val p = catchup ?: return@LaunchedEffect
        while (banner) {
            position = player.currentPosition
            // The stream's own length once known; the guide's until then.
            length = player.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: ((p.end - p.start) * 1000)
            delay(POSITION_TICK_MS)
        }
    }
    LaunchedEffect(channel.id, bannerAt, paused) {
        banner = true
        if (!channel.isRadio && !paused) {
            delay(BANNER_MS)
            banner = false
        }
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(player, lifecycle) {
        // Live: paused in the background, and back to the live edge on return.
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> player.stop()
                // Not on the first start (the observer is told at once): nothing is set yet.
                Lifecycle.Event.ON_START -> if (player.playbackState == Player.STATE_IDLE && player.mediaItemCount > 0) player.prepare()
                else -> Unit
            }
        }
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                buffering = state == Player.STATE_BUFFERING
                // A past programme played to its end: back to live.
                if (state == Player.STATE_ENDED && catchup != null) {
                    catchup = null
                    bannerAt++
                }
                // A stall that ends: the picture is back, so the failed banner goes (after its usual few seconds).
                if (state == Player.STATE_READY && error == STALLED) {
                    error = null
                    bannerAt++
                }
            }

            // Paused follows the player, whatever paused it.
            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                paused = catchup != null && !playWhenReady
            }

            override fun onPlayerError(e: PlaybackException) {
                error = e.errorCodeName
                banner = true
            }
        }
        lifecycle.addObserver(observer)
        player.addListener(listener)
        onDispose {
            lifecycle.removeObserver(observer)
            player.removeListener(listener)
            player.release()
        }
    }
    LaunchedEffect(Unit) { runCatching { firstFocus.requestFocus() } }

    fun open(kind: LivePanel) {
        panelList = emptyList()
        panelLoading = true // from the first frame, not "nothing to show"
        panel = kind
    }

    fun move(step: Int) {
        catchup = null
        index = Math.floorMod(index + step, list.size)
    }

    // A number typed on the remote goes to that channel, from wherever the screen is.
    val numbers = rememberNumberEntry { num ->
        val found = channelByNumber(num, list, all) ?: return@rememberNumberEntry false
        panel = null
        if (found.first[found.second].id != channel.id) catchup = null // the same channel keeps its programme
        list = found.first
        index = found.second
        bannerAt++
        runCatching { firstFocus.requestFocus() }
        true
    }

    // Catch-up: back or forward, further a step while the key is held. Held keys repeat many
    // times a second: steps are spaced out, and a forward step stops short of the end (the end
    // returns to live).
    var lastStepAt by remember { mutableLongStateOf(0L) }
    fun seek(forward: Boolean, event: AndroidKeyEvent): Boolean {
        if (catchup == null) return false
        val held = event.repeatCount >= HELD_REPEATS
        if (event.repeatCount > 0 && event.eventTime - lastStepAt < HELD_STEP_GAP_MS) return true
        lastStepAt = event.eventTime
        val length = player.duration.takeIf { it != C.TIME_UNSET && it > 0 }
        val to = nextPosition(player.currentPosition, length, forward, held)
        if (to != player.currentPosition) player.seekTo(to)
        position = to
        // After a failed read the player is stopped: a skip tries again from the new place.
        if (player.playerError != null) {
            error = null
            player.prepare()
        }
        bannerAt++
        return true
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(firstFocus)
            .onKeyEvent {
                if (numbers.key(it.nativeKeyEvent)) return@onKeyEvent true
                // With the panel open, its list has the keys.
                if (it.type != KeyEventType.KeyDown || panelOpen) return@onKeyEvent false
                when (it.nativeKeyEvent.keyCode) {
                    // Left and Right change channel; in catch-up they move through the programme.
                    AndroidKeyEvent.KEYCODE_DPAD_RIGHT -> seek(forward = true, it.nativeKeyEvent) || move(1).let { true }
                    AndroidKeyEvent.KEYCODE_DPAD_LEFT -> seek(forward = false, it.nativeKeyEvent) || move(-1).let { true }
                    AndroidKeyEvent.KEYCODE_CHANNEL_UP -> move(1).let { true }
                    AndroidKeyEvent.KEYCODE_CHANNEL_DOWN -> move(-1).let { true }
                    // Up: the earlier programmes, on a channel that keeps them. Down: what is on and the channel's guide.
                    AndroidKeyEvent.KEYCODE_DPAD_UP -> {
                        if (channel.archiveDays > 0) open(LivePanel.Earlier) else bannerAt++
                        true
                    }
                    AndroidKeyEvent.KEYCODE_DPAD_DOWN -> open(LivePanel.Guide).let { true }
                    // OK: the channel list; in catch-up it pauses and plays, below.
                    AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER -> {
                        if (catchup != null) {
                            player.playWhenReady = !player.playWhenReady
                            bannerAt++
                        } else {
                            open(LivePanel.Channels)
                        }
                        true
                    }
                    AndroidKeyEvent.KEYCODE_INFO, AndroidKeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                        if (catchup != null) player.playWhenReady = !player.playWhenReady
                        bannerAt++
                        true
                    }
                    // The remote's own play and pause keys set the state rather than toggle it.
                    AndroidKeyEvent.KEYCODE_MEDIA_PLAY, AndroidKeyEvent.KEYCODE_MEDIA_PAUSE -> (catchup != null).also { c ->
                        if (c) {
                            player.playWhenReady = it.nativeKeyEvent.keyCode == AndroidKeyEvent.KEYCODE_MEDIA_PLAY
                            bannerAt++
                        }
                    }
                    AndroidKeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> seek(forward = true, it.nativeKeyEvent)
                    AndroidKeyEvent.KEYCODE_MEDIA_REWIND -> seek(forward = false, it.nativeKeyEvent)
                    else -> false
                }
            }
            .focusable(),
    ) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    this.player = player
                    useController = false
                    keepScreenOn = true
                    setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
                    // Not focusable: the keys belong to the box around it.
                    isFocusable = false
                    descendantFocusability = android.view.ViewGroup.FOCUS_BLOCK_DESCENDANTS
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
        if (banner || error != null) {
            val shown = catchup
            Banner(
                channel, error, if (shown != null) shown to null else nowAndNext(guide, now), now,
                catchup = if (shown != null) CatchupPlace(position, length, paused) else null,
            )
        }
        when (panel) {
            LivePanel.Earlier -> EarlierPanel(
                channel = channel,
                programmes = panelList,
                loading = panelLoading,
                failed = panelFailed,
                onPlay = { p ->
                    panel = null
                    catchup = p
                    bannerAt++
                    runCatching { firstFocus.requestFocus() }
                },
            )
            LivePanel.Guide -> GuidePanel(channel, panelList, playing = catchup, loading = panelLoading, failed = panelFailed)
            LivePanel.Channels -> ChannelsPanel(list, index) { i ->
                panel = null
                if (i != index) catchup = null // the same channel keeps its programme
                index = i
                bannerAt++
                runCatching { firstFocus.requestFocus() }
            }
            null -> Unit
        }
        NumberOverlay(numbers)
    }
}

/** The earlier programmes of a catch-up channel, newest first, on the start side. OK plays one; Back closes. */
@Composable
private fun BoxScope.EarlierPanel(channel: Channel, programmes: List<Programme>, loading: Boolean, failed: Boolean, onPlay: (Programme) -> Unit) {
    val first = remember { FocusRequester() }
    val locale = LocalConfiguration.current.locales[0]
    val day = remember(locale) { java.time.format.DateTimeFormatter.ofPattern("EEE d.M", locale) }
    Column(Modifier.fullScreenPanel()) {
        // Title and channel apart: a Hebrew channel name inside an English line comes out in the wrong order.
        Text(stringResource(R.string.live_earlier), style = MaterialTheme.typography.headlineSmall, color = WtvColors.TextPrimary)
        Text(channel.name, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextSecondary)
        Spacer(Modifier.height(16.dp))
        when {
            failed -> Text(stringResource(R.string.live_archive_failed), color = WtvColors.TextSecondary)
            loading -> Text(stringResource(R.string.loading), color = WtvColors.TextMuted)
            programmes.isEmpty() -> Text(stringResource(R.string.live_no_archive), color = WtvColors.TextSecondary)
            else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp), contentPadding = PaddingValues(bottom = 40.dp)) {
                itemsIndexed(programmes, key = { _, p -> p.start }) { i, p ->
                    ListItem(
                        selected = false,
                        onClick = { onPlay(p) },
                        headlineContent = { Text(p.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        supportingContent = { Text("${dayOf(p.start, day)}   ${clock(p.start)}–${clock(p.end)}") },
                        modifier = if (i == 0) Modifier.focusRequester(first) else Modifier,
                    )
                }
            }
        }
    }
    LaunchedEffect(programmes.isNotEmpty()) { if (programmes.isNotEmpty()) runCatching { first.requestFocus() } }
}

/**
 * What is on (or the catch-up programme playing) with its description, then the channel's guide after it.
 * Rows take focus only so the remote can scroll the list.
 */
@Composable
private fun BoxScope.GuidePanel(channel: Channel, programmes: List<Programme>, playing: Programme?, loading: Boolean, failed: Boolean) {
    val first = remember { FocusRequester() }
    val (lead, after) = guideOf(programmes, playing, System.currentTimeMillis() / 1000)
    Column(Modifier.fullScreenPanel()) {
        Text(channel.name, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextSecondary)
        Spacer(Modifier.height(12.dp))
        if (lead != null) {
            Text(lead.title, style = MaterialTheme.typography.headlineMedium, color = WtvColors.TextPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text("${clock(lead.start)}–${clock(lead.end)}", style = MaterialTheme.typography.titleMedium, color = WtvColors.Accent)
            lead.description?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, style = MaterialTheme.typography.bodyLarge, color = WtvColors.TextSecondary, maxLines = 5, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.height(24.dp))
        }
        Text(stringResource(R.string.live_guide), style = MaterialTheme.typography.titleLarge, color = WtvColors.TextPrimary)
        Spacer(Modifier.height(8.dp))
        when {
            failed -> Text(stringResource(R.string.live_guide_failed), color = WtvColors.TextSecondary)
            loading -> Text(stringResource(R.string.loading), color = WtvColors.TextMuted)
            after.isEmpty() -> Text(stringResource(R.string.live_no_guide), color = WtvColors.TextSecondary)
            else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp), contentPadding = PaddingValues(bottom = 40.dp)) {
                itemsIndexed(after, key = { _, p -> p.start }) { i, p ->
                    ListItem(
                        selected = false,
                        onClick = {},
                        // Time and title apart: a Hebrew title in one line with the time swaps their order.
                        leadingContent = { Text(clock(p.start), style = MaterialTheme.typography.titleMedium) },
                        headlineContent = { Text(p.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        supportingContent = p.description?.let { d -> { Text(d, maxLines = 2, overflow = TextOverflow.Ellipsis) } },
                        modifier = if (i == 0) Modifier.focusRequester(first) else Modifier,
                    )
                }
            }
        }
    }
    LaunchedEffect(after.isNotEmpty()) { if (after.isNotEmpty()) runCatching { first.requestFocus() } }
}

/** A panel over the whole picture, dark enough to read on but letting the programme show through. */
private fun Modifier.fullScreenPanel(): Modifier =
    fillMaxSize().background(Color(0xD9000000)).padding(horizontal = 96.dp, vertical = 48.dp)

/** The full-screen panels: earlier programmes (Up), what is on with the guide (Down), the channel list (OK). */
private enum class LivePanel { Earlier, Guide, Channels }

/** The channels Left and Right move through, the one watched focused; OK switches to one, Back closes. */
@Composable
private fun BoxScope.ChannelsPanel(channels: List<Channel>, current: Int, onPick: (Int) -> Unit) {
    val focus = remember { FocusRequester() }
    val rows = rememberLazyListState(initialFirstVisibleItemIndex = (current - 3).coerceAtLeast(0))
    Column(Modifier.fullScreenPanel()) {
        Text(stringResource(R.string.live_channels), style = MaterialTheme.typography.headlineSmall, color = WtvColors.TextPrimary)
        Spacer(Modifier.height(16.dp))
        LazyColumn(state = rows, verticalArrangement = Arrangement.spacedBy(6.dp), contentPadding = PaddingValues(bottom = 40.dp)) {
            itemsIndexed(channels, key = { _, c -> c.id }) { i, c ->
                ListItem(
                    selected = i == current,
                    onClick = { onPick(i) },
                    leadingContent = {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            Text(c.num?.toString() ?: "", style = MaterialTheme.typography.titleMedium, modifier = Modifier.width(56.dp))
                            Box(Modifier.size(width = 64.dp, height = 36.dp)) {
                                if (c.logo != null) AsyncImage(model = c.logo, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
                            }
                        }
                    },
                    headlineContent = { Text(c.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    modifier = if (i == current) Modifier.focusRequester(focus) else Modifier,
                )
            }
        }
    }
    LaunchedEffect(Unit) {
        // The focused row is composed once the list has laid out.
        delay(50)
        runCatching { focus.requestFocus() }
    }
}

private fun dayOf(unixSeconds: Long, format: java.time.format.DateTimeFormatter): String =
    java.time.Instant.ofEpochSecond(unixSeconds).atZone(java.time.ZoneId.systemDefault()).format(format)

/** The channel strip along the bottom: number, logo, name, and the error if the channel failed. */
@Composable
private fun BoxScope.Banner(channel: Channel, error: String?, onAir: Pair<Programme?, Programme?>, now: Long, catchup: CatchupPlace? = null) {
    Box(
        Modifier
            .fillMaxWidth()
            .align(Alignment.BottomStart)
            // Dark enough to read over any picture, channels' own graphics included.
            .background(Brush.verticalGradient(0f to Color.Transparent, 0.3f to Color(0xCC000000), 1f to Color(0xF2000000)))
            .padding(start = 64.dp, end = 64.dp, top = 64.dp, bottom = 40.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            channel.num?.let { Text(it.toString(), style = MaterialTheme.typography.displaySmall, color = WtvColors.TextPrimary) }
            if (channel.logo != null) {
                Box(Modifier.size(width = 120.dp, height = 68.dp).background(WtvColors.Surface, RoundedCornerShape(6.dp)).padding(8.dp)) {
                    AsyncImage(model = channel.logo, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
                }
            }
            Column {
                Text(channel.name, style = MaterialTheme.typography.headlineSmall, color = WtvColors.TextPrimary)
                if (error != null) {
                    Text(stringResource(R.string.live_failed) + " ($error)", style = MaterialTheme.typography.bodyMedium, color = WtvColors.TextSecondary)
                }
                val (onNow, next) = onAir
                if (catchup != null) {
                    Text(
                        stringResource(if (catchup.paused) R.string.live_catchup_paused else R.string.live_catchup),
                        style = MaterialTheme.typography.labelLarge,
                        color = WtvColors.Accent,
                    )
                }
                if (onNow != null) {
                    // Times and title apart: in one line, a Hebrew title turns the line right-to-left and swaps the times.
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text("${clock(onNow.start)}–${clock(onNow.end)}", style = MaterialTheme.typography.titleMedium, color = WtvColors.TextPrimary)
                        Text(onNow.title, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (catchup != null) {
                        TimeBar(catchup)
                    } else {
                        val elapsed = ((now - onNow.start).toFloat() / (onNow.end - onNow.start)).coerceIn(0f, 1f)
                        Box(Modifier.padding(vertical = 6.dp).width(420.dp).height(3.dp).background(WtvColors.Surface)) {
                            Box(Modifier.fillMaxWidth(elapsed).height(3.dp).background(WtvColors.Accent))
                        }
                    }
                }
                if (catchup != null) {
                    Text(stringResource(R.string.live_catchup_hint), style = MaterialTheme.typography.bodySmall, color = WtvColors.TextMuted)
                }
                if (catchup == null) {
                    Text(
                        stringResource(if (channel.archiveDays > 0) R.string.live_earlier_hint else R.string.live_guide_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = WtvColors.TextMuted,
                    )
                }
                if (next != null) {
                    Text(
                        stringResource(R.string.live_next, clock(next.start), next.title),
                        style = MaterialTheme.typography.bodyMedium,
                        color = WtvColors.TextSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

/** Where catch-up is in its programme (ms), and whether it is paused. */
private class CatchupPlace(val position: Long, val length: Long, val paused: Boolean)

/** Catch-up's time bar: time in, the bar, the programme's length. Left to right in Hebrew too, like a clock. */
@Composable
private fun TimeBar(place: CatchupPlace) {
    val done = if (place.length > 0) (place.position.toFloat() / place.length).coerceIn(0f, 1f) else 0f
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Row(Modifier.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(duration(place.position), style = MaterialTheme.typography.titleSmall, color = WtvColors.TextPrimary)
            Box(Modifier.width(440.dp).height(4.dp).background(WtvColors.Surface)) {
                Box(Modifier.fillMaxWidth(done).height(4.dp).background(WtvColors.Accent))
            }
            Text(duration(place.length), style = MaterialTheme.typography.titleSmall, color = WtvColors.TextSecondary)
        }
    }
}

/**
 * Where a catch-up step lands: 30 s (2 minutes held) back or forward, never before the start,
 * and forward never into the last 10 s (the end returns to live) nor backward from there.
 */
internal fun nextPosition(position: Long, length: Long?, forward: Boolean, held: Boolean): Long {
    val step = if (held) SEEK_HELD_MS else SEEK_MS
    if (!forward) return (position - step).coerceAtLeast(0L)
    val end = length?.let { (it - END_MARGIN_MS).coerceAtLeast(0L) } ?: Long.MAX_VALUE
    return maxOf(position, minOf(position + step, end))
}

/** "1:05:09" or "5:09". */
internal fun duration(ms: Long): String {
    val s = (ms / 1000).coerceAtLeast(0)
    return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
}

/** "20:00" in the device's time zone. */
private fun clock(unixSeconds: Long): String =
    java.time.Instant.ofEpochSecond(unixSeconds).atZone(java.time.ZoneId.systemDefault()).toLocalTime().format(CLOCK)

private val CLOCK = java.time.format.DateTimeFormatter.ofPattern("HH:mm")
private const val BANNER_MS = 4_000L
private const val CLOCK_TICK_MS = 30_000L
private const val STALL_MS = 20_000L
private const val STALLED = "TIMEOUT"
private const val SEEK_MS = 30_000L
/** Held for this many key repeats (about a second), a step is 2 minutes. */
private const val HELD_REPEATS = 10
private const val SEEK_HELD_MS = 120_000L
/** While a key is held, at most one step in this time. */
private const val HELD_STEP_GAP_MS = 400L
/** A forward step stops this far before the end: the end returns to live. */
private const val END_MARGIN_MS = 10_000L
private const val POSITION_TICK_MS = 500L
/** Programmes asked for the guide panel: the provider's short guide stops at what it has. */
private const val GUIDE_LIMIT = 30
