package com.wtv.app.ui.components

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Button
import androidx.tv.material3.ButtonDefaults
import androidx.tv.material3.Icon
import androidx.tv.material3.IconButton
import androidx.tv.material3.IconButtonDefaults
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.ui.theme.WtvColors

/** The main action on a title page. Light when focused, like the reference. */
@Composable
fun PlayButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    // `modifier` may carry a FocusRequester: the title page focuses Play first.
    Button(
        onClick = onClick,
        modifier = modifier,
        shape = ButtonDefaults.shape(RoundedCornerShape(8.dp)),
        colors = ButtonDefaults.colors(
            containerColor = WtvColors.Surface,
            contentColor = WtvColors.TextPrimary,
            focusedContainerColor = WtvColors.TextPrimary,
            focusedContentColor = WtvColors.Background,
        ),
    ) {
        Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(8.dp))
        Text(label, style = MaterialTheme.typography.labelLarge)
    }
}

/**
 * A round icon action next to Play: watchlist, Love, Like, Dislike, more info.
 * `selected` shows a chosen rating.
 */
@Composable
fun ActionIcon(
    icon: ImageVector,
    description: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier.padding(horizontal = 4.dp),
        colors = IconButtonDefaults.colors(
            containerColor = Color.Transparent,
            contentColor = if (selected) WtvColors.Accent else WtvColors.TextPrimary,
            focusedContainerColor = WtvColors.TextPrimary,
            focusedContentColor = WtvColors.Background,
        ),
    ) {
        Icon(icon, contentDescription = description, modifier = Modifier.size(24.dp))
    }
}
