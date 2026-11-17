package com.wtv.app.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Border
import androidx.tv.material3.Card
import androidx.tv.material3.CardDefaults
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import com.wtv.app.ui.theme.WtvColors

private val CardShape = RoundedCornerShape(8.dp)

/**
 * A focusable image card. Focus gives a white ring and a slight lift.
 * `label` is drawn on the image (episode cards: "Episode 2"); `onFocused`
 * lets the page header follow the focus.
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
) {
    Card(
        onClick = onClick,
        modifier = modifier
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
                    modifier = Modifier.align(Alignment.BottomStart).padding(12.dp),
                )
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
) = ImageCard(imageUrl, title, onClick, width = 200.dp, aspectRatio = 16f / 9f, modifier, label, onFocused)

/** 2:3 card for the full category grid and posters. */
@Composable
fun PosterCard(
    imageUrl: String?,
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onFocused: () -> Unit = {},
) = ImageCard(imageUrl, title, onClick, width = 120.dp, aspectRatio = 2f / 3f, modifier, onFocused = onFocused)

/** Portrait card for a cast member. */
@Composable
fun PersonCard(
    imageUrl: String?,
    name: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onFocused: () -> Unit = {},
) = ImageCard(imageUrl, name, onClick, width = 96.dp, aspectRatio = 3f / 4f, modifier, onFocused = onFocused)
