package com.wtv.app.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import com.wtv.app.ui.theme.WtvColors

/**
 * The page background: the focused title's backdrop on the right, fading into
 * the page colour to the left and bottom, as in the reference.
 */
@Composable
fun Backdrop(imageUrl: String?, modifier: Modifier = Modifier) {
    // The image sits at the end (right in English, left in Hebrew); the fade
    // starts from the other side. A gradient does not flip by itself.
    val stops = arrayOf(
        0.0f to WtvColors.Background,
        0.32f to WtvColors.Background,
        0.62f to WtvColors.Background.copy(alpha = 0.35f),
        1.0f to Color.Transparent,
    )
    val fromStart = LocalLayoutDirection.current == LayoutDirection.Ltr
    val fade = if (fromStart) stops else stops.map { (at, color) -> (1f - at) to color }.reversed().toTypedArray()
    // Only the image is drawn, with both fades over it alone: the window
    // background is the page colour, and full-screen layers were the frame
    // cost on the streamer's GPU (4x overdraw everywhere).
    Box(modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxWidth(ImageWidth)
                .fillMaxHeight(ImageHeight)
                .align(Alignment.TopEnd)
                .drawWithContent {
                    drawContent()
                    // The fades are laid out on the whole page; this box is its top-end part.
                    val pageWidth = size.width / ImageWidth
                    val left = if (fromStart) pageWidth - size.width else 0f
                    drawRect(Brush.horizontalGradient(*fade, startX = -left, endX = pageWidth - left))
                    drawRect(Brush.verticalGradient(0.45f / ImageHeight to Color.Transparent, 1f to WtvColors.Background))
                },
        ) {
            // A crossfade without offscreen layers: ModulateAlpha applies the
            // alpha to the image's own draw. Compose's Crossfade rendered both
            // images to buffers, the main remaining frame cost on the streamer.
            // The new image fades in over the old one at full alpha (no dip),
            // once it has loaded; the old one goes when the fade ends.
            var shown by remember { mutableStateOf(imageUrl) }
            var previous by remember { mutableStateOf<String?>(null) }
            // URLs whose image is composed and has loaded (or failed); one going from old to new keeps its entry.
            val loaded = remember { mutableStateListOf<String>() }
            val fade = remember { Animatable(1f) }
            LaunchedEffect(imageUrl) {
                if (imageUrl == shown) return@LaunchedEffect
                // Mid-fade, the half-faded image is dropped: the old one stays under.
                if (fade.value >= 0.5f || previous == null) previous = shown
                shown = imageUrl
                fade.snapTo(0f)
            }
            LaunchedEffect(shown, shown in loaded) {
                if (fade.value < 1f && (shown == null || shown in loaded)) {
                    fade.animateTo(1f, tween(FadeMillis))
                    previous = null
                }
            }
            // One call site, so an image keeps its composition (and painter) as it goes from new to old.
            for (url in listOfNotNull(previous, shown).distinct()) {
                key(url) {
                    DisposableEffect(Unit) { onDispose { loaded.remove(url) } }
                    BackdropImage(url, onLoaded = { if (url !in loaded) loaded.add(url) }) {
                        when {
                            url == shown && url != previous -> fade.value
                            shown == null -> 1f - fade.value // fading out to nothing
                            else -> 1f
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun BackdropImage(url: String, onLoaded: () -> Unit, alpha: () -> Float) {
    AsyncImage(
        model = url,
        contentDescription = null,
        contentScale = ContentScale.Crop,
        alignment = Alignment.TopEnd,
        // A failed image counts as loaded: the fade then shows the page colour.
        onSuccess = { onLoaded() },
        onError = { onLoaded() },
        modifier = Modifier.fillMaxSize().graphicsLayer {
            this.alpha = alpha()
            compositingStrategy = CompositingStrategy.ModulateAlpha
        },
    )
}

private const val FadeMillis = 300
private const val ImageWidth = 0.72f
private const val ImageHeight = 0.8f

/**
 * The header text block: title, highlight line, meta row, synopsis, and an
 * optional row of actions (title pages only). The caller sets the width.
 */
@Composable
fun HeroText(
    title: String,
    meta: @Composable () -> Unit,
    synopsis: String?,
    modifier: Modifier = Modifier,
    titleMaxLines: Int = 2,
    highlight: String? = null,
    actions: (@Composable ColumnScope.() -> Unit)? = null,
) {
    Column(modifier) {
        Text(title, style = MaterialTheme.typography.displayMedium, color = WtvColors.TextPrimary, maxLines = titleMaxLines, overflow = TextOverflow.Ellipsis)
        if (highlight != null) {
            Spacer(Modifier.height(6.dp))
            Text(highlight, style = MaterialTheme.typography.titleSmall, color = WtvColors.Accent)
        }
        Spacer(Modifier.height(10.dp))
        meta()
        if (synopsis != null) {
            Spacer(Modifier.height(10.dp))
            Text(synopsis, style = MaterialTheme.typography.bodyLarge, color = WtvColors.TextSecondary, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
        if (actions != null) {
            Spacer(Modifier.height(20.dp))
            actions()
        }
    }
}

/** "2026   Crime • Drama   [TV-MA]": plain items, then badges. */
@Composable
fun MetaRow(items: List<String>, badges: List<String> = emptyList(), tag: String? = null) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
        if (tag != null) Tag(tag)
        items.forEach { Text(it, style = MaterialTheme.typography.titleSmall, color = WtvColors.TextPrimary) }
        badges.forEach { Badge(it) }
    }
}

/** A row title above a row of cards. */
@Composable
fun RowTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.titleMedium,
        color = WtvColors.TextPrimary,
        modifier = modifier.padding(bottom = 10.dp),
    )
}
