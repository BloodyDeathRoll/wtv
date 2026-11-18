package com.wtv.app.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Border
import androidx.tv.material3.Card
import androidx.tv.material3.CardDefaults
import androidx.tv.material3.Icon
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import com.wtv.app.ui.remembersFocus
import com.wtv.app.ui.theme.WtvColors

private val CardShape = RoundedCornerShape(8.dp)

/**
 * A focusable image card. Focus gives a white ring and a slight lift.
 * `label` is drawn on the image (episode cards: "Episode 2"); `onFocused`
 * lets the page header follow the focus; `progress` (0–1) draws a watched
 * bar along the bottom.
 */
@Composable
fun ImageCard(
    imageUrl: String?,
    title: String,
    onClick: () -> Unit,
    width: Dp,
    aspectRatio: Float,
    modifier: Modifier = Modifier,
    label: String? = null,
    onFocused: () -> Unit = {},
    progress: Float? = null,
    onLongClick: (() -> Unit)? = null,
) {
    Card(
        onClick = onClick,
        onLongClick = onLongClick,
        modifier = modifier
            .remembersFocus()
            .width(width)
            .aspectRatio(aspectRatio)
            .onFocusChanged { if (it.hasFocus) onFocused() },
        shape = CardDefaults.shape(CardShape),
        scale = CardDefaults.scale(focusedScale = 1.04f),
        border = CardDefaults.border(
            focusedBorder = Border(BorderStroke(3.dp, WtvColors.Focus), shape = CardShape),
        ),
        colors = CardDefaults.colors(containerColor = WtvColors.Surface),
    ) {
        Box(Modifier.fillMaxSize()) {
            // No image, or one that fails to load: the title on a plain card.
            var failed by remember(imageUrl) { mutableStateOf(false) }
            if (imageUrl != null && !failed) {
                AsyncImage(
                    model = imageUrl,
                    contentDescription = title,
                    contentScale = ContentScale.Crop,
                    onError = { failed = true },
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Text(
                    title,
                    style = MaterialTheme.typography.labelLarge,
                    color = WtvColors.TextSecondary,
                    modifier = Modifier.align(Alignment.Center).padding(12.dp),
                )
            }
            if (label != null) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(Brush.verticalGradient(0.55f to Color.Transparent, 1f to Color(0xCC000000))),
                )
                Text(
                    label,
                    style = MaterialTheme.typography.labelLarge,
                    color = WtvColors.TextPrimary,
                    // Two lines at most: a cast card is narrow.
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.align(Alignment.BottomStart).padding(10.dp),
                )
            }
            if (progress != null) {
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(4.dp).background(Color(0x66000000))) {
                    Box(Modifier.fillMaxWidth(progress).height(4.dp).background(WtvColors.Accent))
                }
            }
        }
    }
}

/** 16:9 card for rows of titles and episodes. */
@Composable
fun LandscapeCard(
    imageUrl: String?,
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    onFocused: () -> Unit = {},
    progress: Float? = null,
    onLongClick: (() -> Unit)? = null,
) = ImageCard(imageUrl, title, onClick, width = 200.dp, aspectRatio = 16f / 9f, modifier, label, onFocused, progress, onLongClick)

/** 2:3 card for the full category grid and posters. */
@Composable
fun PosterCard(
    imageUrl: String?,
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onFocused: () -> Unit = {},
    onLongClick: (() -> Unit)? = null,
) = ImageCard(imageUrl, title, onClick, width = 120.dp, aspectRatio = 2f / 3f, modifier, onFocused = onFocused, onLongClick = onLongClick)

/** Portrait card for a cast member. */
@Composable
fun PersonCard(
    imageUrl: String?,
    name: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onFocused: () -> Unit = {},
    label: String? = null,
) = ImageCard(imageUrl, name, onClick, width = 96.dp, aspectRatio = 3f / 4f, modifier, label = label, onFocused = onFocused)

/**
 * A live channel: its logo (or its name, when there is none) on a plain
 * card, the provider's number in the corner, a star when it is a favourite.
 * Holding OK calls `onLongClick`.
 */
@Composable
fun ChannelCard(
    logo: String?,
    name: String,
    number: Int?,
    favorite: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        onClick = onClick,
        onLongClick = onLongClick,
        modifier = modifier.remembersFocus().aspectRatio(16f / 9f),
        shape = CardDefaults.shape(CardShape),
        scale = CardDefaults.scale(focusedScale = 1.04f),
        border = CardDefaults.border(
            focusedBorder = Border(BorderStroke(3.dp, WtvColors.Focus), shape = CardShape),
        ),
        colors = CardDefaults.colors(containerColor = WtvColors.Surface),
    ) {
        Box(Modifier.fillMaxSize()) {
            var failed by remember(logo) { mutableStateOf(false) }
            if (logo != null && !failed) {
                AsyncImage(
                    model = logo,
                    contentDescription = name,
                    contentScale = ContentScale.Fit,
                    onError = { failed = true },
                    modifier = Modifier.fillMaxSize().padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 30.dp),
                )
                Text(
                    name,
                    style = MaterialTheme.typography.labelMedium,
                    color = WtvColors.TextSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.align(Alignment.BottomCenter).padding(horizontal = 8.dp, vertical = 6.dp),
                )
            } else {
                Text(
                    name,
                    style = MaterialTheme.typography.titleSmall,
                    color = WtvColors.TextPrimary,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.align(Alignment.Center).padding(12.dp),
                )
            }
            if (number != null) {
                Text(
                    number.toString(),
                    style = MaterialTheme.typography.labelSmall,
                    color = WtvColors.TextMuted,
                    modifier = Modifier.align(Alignment.TopStart).padding(8.dp),
                )
            }
            if (favorite) {
                Icon(
                    Icons.Filled.Star,
                    contentDescription = null,
                    tint = WtvColors.Accent,
                    modifier = Modifier.align(Alignment.TopEnd).padding(6.dp).size(18.dp),
                )
            }
        }
    }
}
