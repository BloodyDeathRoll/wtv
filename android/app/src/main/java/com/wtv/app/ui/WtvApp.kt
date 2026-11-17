package com.wtv.app.ui

import androidx.activity.compose.BackHandler
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
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
import com.wtv.app.data.Category
import com.wtv.app.data.Kind
import com.wtv.app.data.Title
import com.wtv.app.ui.title.TitleScreen
import com.wtv.app.ui.browse.BrowseScreen
import com.wtv.app.ui.browse.BrowseSource
import com.wtv.app.ui.grid.GridScreen
import com.wtv.app.ui.theme.WtvColors

/** The four sections in the top tabs. */
enum class Section(@StringRes val label: Int) {
    Home(R.string.tab_home),
    Movies(R.string.tab_movies),
    Series(R.string.tab_series),
    LiveTv(R.string.tab_live),
}

/** What is on top: the section, a category's grid, a title's page, or a rail page. */
private enum class Top { Base, Grid, Title, Rail }

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
    // A category's full grid, opened from a row's More card.
    var more by remember { mutableStateOf<Category?>(null) }
    // A title's page, over the section or the grid it was opened from.
    var opened by remember { mutableStateOf<Title?>(null) }
    var tabsHaveFocus by remember { mutableStateOf(false) }
    // One per tab: Back focuses the selected tab, not the first one (which would switch section).
    val tabs = remember { Section.entries.associateWith { FocusRequester() } }
    val selectedTab = tabs.getValue(section)
    // Down from the tabs enters the page here, never the rail.
    val page = remember { FocusRequester() }
    val gridFirst = remember { FocusRequester() }
    // Each layer remembers its last focused card, to return to it.
    val baseMemory = remember { FocusMemory() }
    val gridMemory = remember { FocusMemory() }
    // Per title: a cast card of the previous title is no place to return to.
    val titleMemory = remember(opened?.id) { FocusMemory() }
    val titleFirst = remember { FocusRequester() }

    // Closing a page removes the focused item, and Android then gives the focus
    // to the first focusable item: the Home tab, which switches the section.
    // So before a page closes, the focus parks here; the layer underneath then
    // takes it back. Not focusable otherwise, so the remote never lands on it.
    var parking by remember { mutableStateOf(false) }
    val parked = remember { FocusRequester() }
    fun close(change: () -> Unit) {
        parking = true
        runCatching { parked.requestFocus() }
        change()
    }

    val top = when {
        railPage != null -> Top.Rail
        opened != null -> Top.Title
        more != null -> Top.Grid
        else -> Top.Base
    }

    // Where the focus goes when the top changes. Going back, a layer gets the
    // focus it had (the card a title was opened from); going forward, the new
    // layer's first item. The title page focuses its Play button itself.
    var shown by remember { mutableStateOf<Top?>(null) }
    LaunchedEffect(top) {
        val from = shown
        shown = top
        when (top) {
            Top.Base -> if (from == null || from == Top.Rail) selectedTab.requestFocus() else baseMemory.restore(fallback = page)
            Top.Grid -> if (from == Top.Base) gridFirst.requestFocus() else gridMemory.restore(fallback = gridFirst)
            Top.Title -> if (from == Top.Rail) titleMemory.restore(fallback = titleFirst)
            Top.Rail -> Unit
        }
        parking = false
    }

    BackHandler(enabled = top == Top.Base && !tabsHaveFocus) { selectedTab.requestFocus() }
    BackHandler(enabled = top == Top.Grid) { close { more = null } }
    BackHandler(enabled = top == Top.Title) { close { opened = null } }
    BackHandler(enabled = top == Top.Rail) { close { railPage = null } }

    Box(Modifier.fillMaxSize()) {
        Box(Modifier.size(1.dp).focusRequester(parked).focusProperties { canFocus = parking }.focusable())
        Layer(blocked = top != Top.Base, memory = baseMemory) {
            val source = when (section) {
                Section.Home -> BrowseSource.Home
                Section.Movies -> BrowseSource.Section(Kind.Movie)
                Section.Series -> BrowseSource.Section(Kind.Series)
                Section.LiveTv -> null
            }
            if (source == null) Placeholder(stringResource(section.label), page)
            else BrowseScreen(source, firstFocus = page, up = selectedTab, onMore = { more = it }, onOpen = { opened = it })
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
        more?.let { grid ->
            Layer(blocked = top != Top.Grid, memory = gridMemory, opaque = true) {
                GridScreen(grid, firstFocus = gridFirst, onOpen = { opened = it })
            }
        }
        opened?.let { title ->
            Layer(blocked = top != Top.Title, memory = titleMemory, opaque = true) {
                // TODO(P3-1): play the chosen copy or episode. TODO(P2-8): the person page.
                TitleScreen(title, play = titleFirst, onPlay = {}, onPlayEpisode = {}, onPerson = {})
            }
        }
        railPage?.let { Placeholder(stringResource(it.label), remember { FocusRequester() }) }
        SideRail(
            onSelect = {
                // The tabs' focus flag would go stale under the page.
                tabsHaveFocus = false
                railPage = it
            },
            modifier = Modifier.align(Alignment.CenterStart),
        )
    }
}

/**
 * One screen of the stack. Layers below the top stay composed (no reload,
 * same scroll) but cannot take the focus. Cards inside record themselves in
 * `memory`, so the layer can give the focus back to the last one.
 */
@Composable
private fun Layer(blocked: Boolean, memory: FocusMemory, opaque: Boolean = false, content: @Composable BoxScope.() -> Unit) {
    CompositionLocalProvider(LocalFocusMemory provides memory) {
        Box(
            Modifier
                .fillMaxSize()
                // A layer over another hides it whatever its own content draws.
                .then(if (opaque) Modifier.background(WtvColors.Background) else Modifier)
                .focusProperties { onEnter = { if (blocked) cancelFocusChange() } }
                .focusGroup(),
            content = content,
        )
    }
}

/** Stands in for a page that is not built yet. Opaque; focusable, so Down from the tabs lands somewhere; brightens when focused. */
@Composable
private fun Placeholder(title: String, focus: FocusRequester) {
    var focused by remember { mutableStateOf(false) }
    Box(
        Modifier.fillMaxSize().background(WtvColors.Background).focusRequester(focus).onFocusChanged { focused = it.isFocused }.focusable(),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, style = MaterialTheme.typography.headlineMedium, color = if (focused) WtvColors.TextPrimary else WtvColors.TextMuted)
    }
}
