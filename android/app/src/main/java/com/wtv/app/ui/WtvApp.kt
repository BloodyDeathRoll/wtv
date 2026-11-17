package com.wtv.app.ui

import androidx.activity.compose.BackHandler
import androidx.annotation.StringRes
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Tab
import androidx.tv.material3.TabDefaults
import androidx.tv.material3.TabRow
import androidx.tv.material3.TabRowDefaults
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.ui.components.RailItem
import com.wtv.app.ui.components.SideRail
import com.wtv.app.ui.showcase.Showcase
import com.wtv.app.ui.theme.WtvColors

/** The four sections in the top tabs. */
enum class Section(@StringRes val label: Int) {
    Home(R.string.tab_home),
    Movies(R.string.tab_movies),
    Series(R.string.tab_series),
    LiveTv(R.string.tab_live),
}

/**
 * The app frame: top tabs, the left rail, and the page in between.
 *
 * Remote behaviour, as in the reference:
 * - Moving focus onto a tab switches the section.
 * - Back from inside a page goes to the tabs; Back on the tabs leaves the app.
 * - A rail item opens its page over the section; Back closes it.
 */
@Composable
fun WtvApp() {
    var section by rememberSaveable { mutableStateOf(Section.Home) }
    var railPage by rememberSaveable { mutableStateOf<RailItem?>(null) }
    var tabsHaveFocus by remember { mutableStateOf(false) }
    // One per tab: Back focuses the selected tab, not the first one (which would switch section).
    val tabs = remember { Section.entries.associateWith { FocusRequester() } }
    val selectedTab = tabs.getValue(section)
    // Down from the tabs enters the page here, never the rail.
    val page = remember { FocusRequester() }

    // On start and whenever a rail page closes, focus the selected tab. Not
    // while a rail page is open (also after the activity is recreated with one
    // open): the tabs are not composed then, and their requesters are unattached.
    LaunchedEffect(railPage) { if (railPage == null) selectedTab.requestFocus() }

    BackHandler(enabled = railPage == null && !tabsHaveFocus) { selectedTab.requestFocus() }
    BackHandler(enabled = railPage != null) { railPage = null }

    Box(Modifier.fillMaxSize()) {
        val open = railPage
        if (open != null) {
            Placeholder(stringResource(open.label), page)
        } else {
            when (section) {
                Section.Home -> Showcase(firstFocus = page, up = selectedTab)
                else -> Placeholder(stringResource(section.label), page)
            }
            TabRow(
                selectedTabIndex = section.ordinal,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 88.dp, top = 18.dp)
                    .onFocusChanged { tabsHaveFocus = it.hasFocus },
                indicator = { positions, rowHasFocus ->
                    positions.getOrNull(section.ordinal)?.let {
                        TabRowDefaults.PillIndicator(
                            currentTabPosition = it,
                            doesTabRowHaveFocus = rowHasFocus,
                            activeColor = WtvColors.TextPrimary,
                            inactiveColor = WtvColors.Surface,
                        )
                    }
                },
            ) {
                Section.entries.forEach { s ->
                    Tab(
                        selected = s == section,
                        onFocus = { section = s },
                        // Set on each tab: focus moves from the tab, not the row.
                        modifier = Modifier.focusRequester(tabs.getValue(s)).focusProperties { down = page },
                        colors = TabDefaults.pillIndicatorTabColors(
                            contentColor = WtvColors.TextSecondary,
                            selectedContentColor = WtvColors.TextPrimary,
                            focusedContentColor = WtvColors.Background,
                            focusedSelectedContentColor = WtvColors.Background,
                        ),
                    ) {
                        Text(
                            stringResource(s.label),
                            style = MaterialTheme.typography.titleSmall,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                        )
                    }
                }
            }
        }
        SideRail(
            onSelect = {
                // The tabs leave composition with the page open; their focus flag would go stale.
                tabsHaveFocus = false
                railPage = it
            },
            modifier = Modifier.align(Alignment.CenterStart),
        )
    }
}

/** Stands in for a page that is not built yet. Focusable, so Down from the tabs lands somewhere; brightens when focused. */
@Composable
private fun Placeholder(title: String, focus: FocusRequester) {
    var focused by remember { mutableStateOf(false) }
    Box(
        Modifier.fillMaxSize().focusRequester(focus).onFocusChanged { focused = it.isFocused }.focusable(),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = MaterialTheme.typography.headlineMedium, color = if (focused) WtvColors.TextPrimary else WtvColors.TextMuted)
    }
}
