package com.wtv.app.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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
import com.wtv.app.ui.theme.WtvColors

enum class RailItem(val label: Int) {
    Search(com.wtv.app.R.string.rail_search),
    Categories(com.wtv.app.R.string.rail_categories),
    Watchlist(com.wtv.app.R.string.rail_watchlist),
    Settings(com.wtv.app.R.string.rail_settings),
}

/**
 * The narrow icon rail on the left (right in Hebrew): search, categories,
 * watchlist, settings. The arrow towards the page calls `onLeave`: nothing
 * focusable lies level with the rail, so the remote would otherwise be stuck.
 */
@Composable
fun SideRail(onSelect: (RailItem) -> Unit, onLeave: () -> Unit, modifier: Modifier = Modifier) {
    val towardsPage = if (LocalLayoutDirection.current == LayoutDirection.Rtl) Key.DirectionLeft else Key.DirectionRight
    Column(
        modifier
            .fillMaxHeight()
            .padding(start = 20.dp)
            .onPreviewKeyEvent {
                if (it.key != towardsPage) return@onPreviewKeyEvent false
                if (it.type == KeyEventType.KeyDown) onLeave()
                true
            },
        verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically),
    ) {
        listOf(
            RailItem.Search to Icons.Outlined.Search,
            RailItem.Categories to Icons.Outlined.GridView,
            RailItem.Watchlist to Icons.Outlined.BookmarkBorder,
            RailItem.Settings to Icons.Outlined.Settings,
        ).forEach { (item, icon) ->
            IconButton(
                onClick = { onSelect(item) },
                modifier = Modifier.size(40.dp),
                colors = IconButtonDefaults.colors(
                    containerColor = Color.Transparent,
                    contentColor = WtvColors.TextMuted,
                    focusedContainerColor = WtvColors.TextPrimary,
                    focusedContentColor = WtvColors.Background,
                ),
            ) {
                Icon(icon, contentDescription = stringResource(item.label), modifier = Modifier.size(22.dp))
            }
        }
    }
}
