package com.wtv.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Constraints
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
 * `selected` shows a chosen rating. Focused, it names itself underneath, like the reference.
 */
@Composable
fun ActionIcon(
    icon: ImageVector,
    description: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
) {
    var focused by remember { mutableStateOf(false) }
    Box(modifier.padding(horizontal = 4.dp)) {
        IconButton(
            onClick = onClick,
            modifier = Modifier.onFocusChanged { focused = it.isFocused },
            colors = IconButtonDefaults.colors(
                containerColor = Color.Transparent,
                contentColor = if (selected) WtvColors.Accent else WtvColors.TextPrimary,
                focusedContainerColor = WtvColors.TextPrimary,
                focusedContentColor = WtvColors.Background,
            ),
        ) {
            Icon(icon, contentDescription = description, modifier = Modifier.size(24.dp))
        }
        if (focused) {
            Text(
                description,
                style = MaterialTheme.typography.labelMedium,
                color = WtvColors.TextPrimary,
                maxLines = 1,
                softWrap = false,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .layout { measurable, _ ->
                        // Measured at its full width but laid out as zero size: centred under the button, outside the row.
                        val label = measurable.measure(Constraints())
                        layout(0, 0) { label.place(-label.width / 2, 6.dp.roundToPx()) }
                    },
            )
        }
    }
}

/** The thin line between the title actions and the ratings. */
@Composable
fun ActionDivider() {
    Box(Modifier.padding(horizontal = 16.dp).size(width = 1.dp, height = 28.dp).background(WtvColors.TextMuted))
}
