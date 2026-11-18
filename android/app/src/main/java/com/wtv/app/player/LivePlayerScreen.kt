package com.wtv.app.player

import android.util.Log
import android.view.KeyEvent as AndroidKeyEvent
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.Channel
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

/**
 * Live TV, full screen, like a TV box: Up / Down (and the remote's channel
 * keys) change channel within `channels`, wrapping at the ends; OK shows the
 * banner. The banner (number, logo, name, and what is on now and next from the
 * provider's short guide) shows for a few seconds on every change; on a radio
 * channel it stays. Back leaves. Nothing is saved.
 */
@OptIn(UnstableApi::class)
@Composable
fun LivePlayerScreen(channels: List<Channel>, start: Int, login: ProviderLogin, firstFocus: FocusRequester) {
    require(channels.isNotEmpty()) { "A live page needs at least one channel" }
    val context = LocalContext.current
    var index by remember { mutableIntStateOf(start.coerceIn(channels.indices)) }
    val channel = channels[index]
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

    val player = remember {
        // Media3's own user agent, as for movies: the stream server blocks the API client's.
        val http = DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(true)
        ExoPlayer.Builder(context).setMediaSourceFactory(DefaultMediaSourceFactory(http)).build().apply { playWhenReady = true }
    }
    LaunchedEffect(channel.id) {
        error = null
        player.setMediaItem(MediaItem.fromUri(streamUrl(login, StreamKind.Live, channel.extId, "ts")))
        player.prepare()
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
    LaunchedEffect(channel.id, bannerAt) {
        banner = true
        if (!channel.isRadio) {
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
                // A stall that ends: the picture is back, so the failed banner goes (after its usual few seconds).
                if (state == Player.STATE_READY && error == STALLED) {
                    error = null
                    bannerAt++
                }
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

    fun move(step: Int) {
        index = Math.floorMod(index + step, channels.size)
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(firstFocus)
            .onKeyEvent {
                if (it.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (it.nativeKeyEvent.keyCode) {
                    AndroidKeyEvent.KEYCODE_DPAD_UP, AndroidKeyEvent.KEYCODE_CHANNEL_UP -> move(1).let { true }
                    AndroidKeyEvent.KEYCODE_DPAD_DOWN, AndroidKeyEvent.KEYCODE_CHANNEL_DOWN -> move(-1).let { true }
                    AndroidKeyEvent.KEYCODE_DPAD_CENTER, AndroidKeyEvent.KEYCODE_ENTER, AndroidKeyEvent.KEYCODE_INFO -> bannerAt++.let { true }
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
        if (banner || error != null) Banner(channel, error, nowAndNext(guide, now), now)
    }
}

/** The channel strip along the bottom: number, logo, name, and the error if the channel failed. */
@Composable
private fun BoxScope.Banner(channel: Channel, error: String?, onAir: Pair<Programme?, Programme?>, now: Long) {
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
                if (onNow != null) {
                    // Times and title apart: in one line, a Hebrew title turns the line right-to-left and swaps the times.
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text("${clock(onNow.start)}–${clock(onNow.end)}", style = MaterialTheme.typography.titleMedium, color = WtvColors.TextPrimary)
                        Text(onNow.title, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    val elapsed = ((now - onNow.start).toFloat() / (onNow.end - onNow.start)).coerceIn(0f, 1f)
                    Box(Modifier.padding(vertical = 6.dp).width(420.dp).height(3.dp).background(WtvColors.Surface)) {
                        Box(Modifier.fillMaxWidth(elapsed).height(3.dp).background(WtvColors.Accent))
                    }
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

/** "20:00" in the device's time zone. */
private fun clock(unixSeconds: Long): String =
    java.time.Instant.ofEpochSecond(unixSeconds).atZone(java.time.ZoneId.systemDefault()).toLocalTime().format(CLOCK)

private val CLOCK = java.time.format.DateTimeFormatter.ofPattern("HH:mm")
private const val BANNER_MS = 4_000L
private const val CLOCK_TICK_MS = 30_000L
private const val STALL_MS = 20_000L
private const val STALLED = "TIMEOUT"
