package com.wtv.app.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
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
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Icon
import androidx.tv.material3.IconButton
import androidx.tv.material3.IconButtonDefaults
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.ui.theme.WtvColors

/** The side rail's entries. Categories is shown only where it has something to list. */
enum class RailItem(val label: Int) {
    Search(com.wtv.app.R.string.rail_search),
    Categories(com.wtv.app.R.string.rail_categories),
    MainMenu(com.wtv.app.R.string.rail_main_menu),
    Watchlist(com.wtv.app.R.string.rail_watchlist),
    Settings(com.wtv.app.R.string.rail_settings),
}

/**
 * The narrow icon rail on the left (right in Hebrew): search, categories,
 * main menu, watchlist, settings. With the focus on it, it opens and names
 * each icon. The arrow towards the page calls `onLeave`: nothing focusable
 * lies level with the rail, so the remote would otherwise be stuck.
 */
@Composable
fun SideRail(onSelect: (RailItem) -> Unit, onLeave: () -> Unit, modifier: Modifier = Modifier, showCategories: Boolean = true) {
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val towardsPage = if (rtl) Key.DirectionLeft else Key.DirectionRight
    // Dark at the screen's edge, clear towards the page (a brush is not mirrored by itself).
    val shade = listOf(WtvColors.Background, WtvColors.Background, WtvColors.Background.copy(alpha = 0.9f), Color.Transparent).let { if (rtl) it.reversed() else it }
    var open by remember { mutableStateOf(false) }
    Column(
        modifier
            .fillMaxHeight()
            .onFocusChanged { open = it.hasFocus }
            // Open, it lies over the page: a shade keeps the labels readable.
            .then(if (open) Modifier.background(Brush.horizontalGradient(shade)) else Modifier)
            .padding(start = 20.dp, end = if (open) 96.dp else 0.dp)
            .onPreviewKeyEvent {
                if (it.key != towardsPage) return@onPreviewKeyEvent false
                if (it.type == KeyEventType.KeyDown) onLeave()
                true
            },
        verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        listOfNotNull(
            RailItem.Search to Icons.Outlined.Search,
            if (showCategories) RailItem.Categories to Icons.Outlined.GridView else null,
            RailItem.MainMenu to Icons.Outlined.Home,
            RailItem.Watchlist to Icons.Outlined.BookmarkBorder,
            RailItem.Settings to Icons.Outlined.Settings,
        ).forEach { (item, icon) ->
            var focused by remember { mutableStateOf(false) }
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(
                    onClick = { onSelect(item) },
                    modifier = Modifier.size(40.dp).onFocusChanged { focused = it.isFocused },
                    colors = IconButtonDefaults.colors(
                        containerColor = Color.Transparent,
                        contentColor = WtvColors.TextMuted,
                        focusedContainerColor = WtvColors.TextPrimary,
                        focusedContentColor = WtvColors.Background,
                    ),
                ) {
                    Icon(icon, contentDescription = stringResource(item.label), modifier = Modifier.size(22.dp))
                }
                AnimatedVisibility(visible = open, enter = fadeIn() + expandHorizontally(), exit = fadeOut() + shrinkHorizontally()) {
                    Row {
                        Spacer(Modifier.width(14.dp))
                        Text(
                            stringResource(item.label),
                            style = MaterialTheme.typography.titleSmall,
                            color = if (focused) WtvColors.TextPrimary else WtvColors.TextSecondary,
                        )
                    }
                }
            }
        }
    }
}
