package com.wtv.app.ui.components

import androidx.compose.animation.Crossfade
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.text.style.TextOverflow
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
    Box(modifier.fillMaxSize().background(WtvColors.Background)) {
        Crossfade(targetState = imageUrl, modifier = Modifier.fillMaxSize(), label = "backdrop") { url ->
            Box(Modifier.fillMaxSize()) {
                if (url != null) {
                    AsyncImage(
                        model = url,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        alignment = Alignment.TopEnd,
                        modifier = Modifier.fillMaxWidth(0.72f).fillMaxHeight(0.8f).align(Alignment.TopEnd),
                    )
                }
            }
        }
        Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(*fade)))
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(0.45f to Color.Transparent, 0.8f to WtvColors.Background),
            ),
        )
    }
}

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
    highlight: String? = null,
    actions: (@Composable ColumnScope.() -> Unit)? = null,
) {
    Column(modifier) {
        Text(title, style = MaterialTheme.typography.displayMedium, color = WtvColors.TextPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
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
