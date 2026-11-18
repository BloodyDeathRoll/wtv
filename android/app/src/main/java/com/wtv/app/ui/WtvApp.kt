package com.wtv.app.ui

import android.util.Log
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.tv.material3.Button
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Tab
import androidx.tv.material3.TabDefaults
import androidx.tv.material3.TabRow
import androidx.tv.material3.TabRowDefaults
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.CastMember
import com.wtv.app.data.Category
import com.wtv.app.data.Channel
import com.wtv.app.data.Episode
import com.wtv.app.data.Kind
import com.wtv.app.data.Title
import com.wtv.app.data.episodeAfter
import com.wtv.app.player.LivePlayerScreen
import com.wtv.app.player.PlayerScreen
import com.wtv.app.player.ProviderLogin
import com.wtv.app.player.StreamKind
import com.wtv.app.player.streamUrl
import com.wtv.app.ui.browse.BrowseScreen
import com.wtv.app.ui.browse.BrowseSource
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.categories.CategoriesScreen
import com.wtv.app.ui.components.LocalTitleMenu
import com.wtv.app.ui.components.TitleMenu
import com.wtv.app.ui.components.RailItem
import com.wtv.app.ui.components.SideRail
import com.wtv.app.ui.grid.GridScreen
import com.wtv.app.ui.grid.PosterGrid
import com.wtv.app.ui.live.LiveScreen
import com.wtv.app.ui.person.PersonScreen
import com.wtv.app.ui.person.TitlesPage
import com.wtv.app.ui.search.SearchScreen
import com.wtv.app.ui.settings.SettingsScreen
import com.wtv.app.ui.theme.WtvColors
import com.wtv.app.ui.title.TitleScreen
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** The four sections in the top tabs. */
enum class Section(@StringRes val label: Int) {
    Home(R.string.tab_home),
    Movies(R.string.tab_movies),
    Series(R.string.tab_series),
    LiveTv(R.string.tab_live),
}

/** A page opened over the section: a category's grid, a title, a person. */
private sealed interface Page {
    /** Which page this is: the same person from two casts (different characters) is one page. */
    val id: String

    data class Grid(val category: Category) : Page {
        override val id get() = "grid:${category.kind}:${if (category.genre) "genre:" else ""}${category.id}"
    }

    /** Side bar → Categories: the provider's categories and the genres of a kind. */
    data class Categories(val kind: Kind) : Page {
        override val id get() = "categories"
    }

    /** "Recommended for You" in full, 50 at a time: one kind, or (null) both. */
    data class Recommendations(val kind: Kind?) : Page {
        override val id get() = "recommendations:${kind ?: "all"}"
    }

    /** `autoPlay`: opened from a card's menu with Play, so Play is pressed once the page is in. */
    data class TitlePage(val title: Title, val autoPlay: Boolean = false) : Page {
        override val id get() = "title:${title.id}"
    }

    data class Person(val person: CastMember) : Page {
        override val id get() = "person:${person.personId}"
    }

    data object Search : Page {
        override val id get() = "search"
    }

    data object Watchlist : Page {
        override val id get() = "watchlist"
    }

    /** `providerFirst`: opened from Play without a provider login, focused on the login. */
    data class Settings(val providerFirst: Boolean = false) : Page {
        override val id get() = "settings"
    }

    /** Live TV, full screen: `channels` is the group it was opened from, for channel up / down. */
    data class Live(val channels: List<Channel>, val index: Int, val login: ProviderLogin) : Page {
        override val id get() = "live"
    }

    /**
     * `titleId` is the copy played; `episodeId` set for an episode. For an
     * episode, `series` is the series' name and `episodes` its episodes in
     * order, so the next one can follow.
     */
    data class Player(
        val url: String,
        val title: String,
        val titleId: Long,
        val episodeId: Long?,
        val startSecs: Int,
        val series: String? = null,
        val episodes: List<Episode> = emptyList(),
    ) : Page {
        override val id get() = "player"
        val next: Episode? get() = episodeAfter(episodes, episodeId)
    }
}

/** A page on the stack, with the focus it should return to when it is on top again. */
private class Entry(val page: Page) {
    val memory = FocusMemory()
    /** The page's first item: where the focus goes when it opens. */
    val first = FocusRequester()
}

/**
 * The app frame: top tabs, the left rail, and the page in between.
 *
 * Remote behaviour, as in the reference:
 * - Moving focus onto a tab switches the section.
 * - Back from inside a page goes to the tabs; Back on the tabs leaves the app.
 * - A rail item opens its page over the section; Back closes it. Main menu closes every page and returns to the tabs.
 */
@Composable
fun WtvApp() {
    var section by rememberSaveable { mutableStateOf(Section.Home) }
    // Pages opened over the section (grid, title, person), in order; Back pops one.
    val stack = remember { mutableStateListOf<Entry>() }
    var tabsHaveFocus by remember { mutableStateOf(false) }
    // Whether the focus was on the tabs (rather than the page) before it went to the rail: the arrow back returns there.
    var lastOnTabs by remember { mutableStateOf(false) }
    // One per tab: Back focuses the selected tab, not the first one (which would switch section).
    val tabs = remember { Section.entries.associateWith { FocusRequester() } }
    val selectedTab = tabs.getValue(section)
    // Down from the tabs enters the page here, never the rail.
    val page = remember { FocusRequester() }
    // The section remembers its last focused card, to return to it.
    val baseMemory = remember { FocusMemory() }

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

    // Opening a page already on the stack goes back to it, rather than stacking a
    // second copy (person → title → the same person …).
    fun open(page: Page) {
        val existing = stack.indexOfFirst { it.page.id == page.id }
        if (existing < 0) stack += Entry(page)
        else if (existing < stack.lastIndex) close { stack.removeRange(existing + 1, stack.size) }
    }

    val context = LocalContext.current
    val hebrew = isHebrew()
    val seasonEpisode = stringResource(R.string.season_episode)
    val noLogin = stringResource(R.string.provider_missing)
    // Play: the stream needs the provider login; without one, Settings opens on it.
    fun play(
        kind: StreamKind, titleId: Long, episodeId: Long?, extId: Long, containerExt: String?, title: String, startSecs: Int,
        series: String? = null, episodes: List<Episode> = emptyList(),
    ) {
        val login = ProviderLogin.load(context)
        if (login == null || !login.isComplete) {
            Toast.makeText(context, noLogin, Toast.LENGTH_LONG).show()
            open(Page.Settings(providerFirst = true))
        } else {
            open(Page.Player(streamUrl(login, kind, extId, containerExt), title, titleId, episodeId, startSecs, series, episodes))
        }
    }
    fun watch(channels: List<Channel>, index: Int) {
        val login = ProviderLogin.load(context)?.takeIf { it.isComplete }
        if (login == null) {
            Toast.makeText(context, noLogin, Toast.LENGTH_LONG).show()
            open(Page.Settings(providerFirst = true))
        } else {
            open(Page.Live(channels, index, login))
        }
    }
    fun episodeTitle(series: String, e: Episode) = "$series · ${seasonEpisode.format(e.season, e.number)}"
    // The next episode replaces the player on top: Back still returns to the series page.
    fun playNext(p: Page.Player) {
        val e = p.next ?: return
        val login = ProviderLogin.load(context)?.takeIf { it.isComplete }
        if (login == null) {
            Toast.makeText(context, noLogin, Toast.LENGTH_LONG).show()
            stack[stack.lastIndex] = Entry(Page.Settings(providerFirst = true))
            return
        }
        val url = streamUrl(login, StreamKind.Episode, e.extId, e.containerExt)
        stack[stack.lastIndex] = Entry(p.copy(url = url, title = episodeTitle(p.series.orEmpty(), e), episodeId = e.id, startSecs = 0))
    }

    // Saved positions. One save at a time; reports that arrive meanwhile collapse
    // into the latest, which carries the whole position (a held seek key sends many).
    // The pages showing positions reload when the player's last save is in.
    val catalog = (context.applicationContext as WtvApplication).catalog
    val scope = rememberCoroutineScope()
    val saving = remember { Mutex() }
    var latest by remember { mutableStateOf<(suspend () -> Unit)?>(null) }
    var progressVersion by remember { mutableIntStateOf(0) }
    fun saveProgress(p: Page.Player, positionSecs: Int, durationSecs: Int?, final: Boolean) {
        latest = {
            // shortcut: a failed save is dropped; the next one (every 15 s) carries the position.
            runCatching { catalog.saveProgress(p.titleId, p.episodeId, positionSecs, durationSecs) }
                .onFailure { Log.w("WtvProgress", "Saving the position failed: ${it.message}") }
            if (final) progressVersion++
        }
        scope.launch {
            saving.withLock {
                val save = latest ?: return@withLock
                latest = null
                save()
            }
        }
    }

    // Where the focus goes when the stack or the rail page changes. Going back,
    // the page now on top gets the focus it had (the card a title was opened
    // from); going forward, the new page's first item.
    val depth = stack.size
    var shown by remember { mutableStateOf<Int?>(null) }
    // Main menu: the tabs take the focus once the pages are closed.
    var toTabs by remember { mutableStateOf(false) }
    // The top entry too: the next episode replaces the player at the same depth.
    LaunchedEffect(depth, stack.lastOrNull()) {
        val fromDepth = shown ?: -1
        shown = depth
        val top = stack.lastOrNull()
        when {
            top == null && (fromDepth < 0 || toTabs) -> selectedTab.requestFocus()
            top == null -> baseMemory.restore(fallback = page)
            depth > fromDepth -> runCatching { top.first.requestFocus() }
            else -> top.memory.restore(fallback = top.first)
        }
        toTabs = false
        parking = false
    }

    BackHandler(enabled = stack.isEmpty() && !tabsHaveFocus) { selectedTab.requestFocus() }
    // Back on the tabs asks before leaving.
    var askExit by remember { mutableStateOf(false) }
    BackHandler(enabled = stack.isEmpty() && tabsHaveFocus) { askExit = true }
    val activity = LocalActivity.current
    if (askExit) ExitDialog(onYes = { activity?.finish() }, onNo = { askExit = false })
    BackHandler(enabled = stack.isNotEmpty()) { close { stack.removeAt(stack.lastIndex) } }

    // A card held down opens its menu, over whatever page it is on.
    var menuFor by remember { mutableStateOf<Title?>(null) }
    menuFor?.let { t ->
        TitleMenu(
            t,
            onInfo = { menuFor = null; open(Page.TitlePage(t)) },
            onPlay = { menuFor = null; open(Page.TitlePage(t, autoPlay = true)) },
            onDismiss = { menuFor = null },
        )
    }

    CompositionLocalProvider(LocalTitleMenu provides { menuFor = it }) {
        Box(Modifier.fillMaxSize()) {
            Box(Modifier.size(1.dp).focusRequester(parked).focusProperties { canFocus = parking }.focusable())
            Layer(blocked = stack.isNotEmpty(), hidden = stack.isNotEmpty(), memory = baseMemory) {
                val source = when (section) {
                    Section.Home -> BrowseSource.Home
                    Section.Movies -> BrowseSource.Section(Kind.Movie)
                    Section.Series -> BrowseSource.Section(Kind.Series)
                    Section.LiveTv -> null
                }
                Box(Modifier.onFocusChanged { if (it.hasFocus) lastOnTabs = false }) {
                    if (source == null) LiveScreen(firstFocus = page, up = selectedTab, onWatch = ::watch)
                    else BrowseScreen(
                        source,
                        firstFocus = page,
                        up = selectedTab,
                        progressVersion = progressVersion,
                        tabsFocused = tabsHaveFocus,
                        onMore = { open(Page.Grid(it)) },
                        onOpen = { open(Page.TitlePage(it)) },
                        onForYou = { open(Page.Recommendations(it)) },
                    )
                }
                TabRow(
                    selectedTabIndex = section.ordinal,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(start = 88.dp, top = 18.dp)
                        .onFocusChanged {
                            tabsHaveFocus = it.hasFocus
                            if (it.hasFocus) lastOnTabs = true
                        },
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
            stack.forEachIndexed { i, entry ->
                // Keyed by the entry, so a page keeps its state while pages open over it.
                key(entry) {
                    Layer(blocked = i != stack.lastIndex, hidden = i != stack.lastIndex, memory = entry.memory) {
                        when (val p = entry.page) {
                            is Page.Recommendations -> PosterGrid(
                                stringResource(R.string.row_recommended),
                                firstFocus = entry.first,
                                onOpen = { open(Page.TitlePage(it)) },
                                sorts = false,
                                pageSize = RECOMMENDATIONS_PAGE,
                            ) { _, offset, limit -> catalog.topPicksPage(p.kind, offset, limit) }
                            is Page.Grid -> GridScreen(p.category, firstFocus = entry.first, onOpen = { open(Page.TitlePage(it)) })
                            is Page.TitlePage -> TitleScreen(
                                p.title,
                                autoPlay = p.autoPlay,
                                play = entry.first,
                                progressVersion = progressVersion,
                                onPlay = { copy, start -> play(StreamKind.Movie, copy.id, null, copy.extId, copy.containerExt, p.title.displayName(hebrew), start) },
                                onPlayEpisode = { e, start, episodes ->
                                    val series = p.title.displayName(hebrew)
                                    play(StreamKind.Episode, p.title.id, e.id, e.extId, e.containerExt, episodeTitle(series, e), start, series, episodes)
                                },
                                onPerson = { open(Page.Person(it)) },
                                onOpen = { open(Page.TitlePage(it)) },
                                onProgressCleared = { progressVersion++ },
                            )
                            is Page.Categories -> CategoriesScreen(p.kind, firstFocus = entry.first, onOpen = { open(Page.Grid(it)) })
                            is Page.Person -> PersonScreen(p.person, firstFocus = entry.first, onOpen = { open(Page.TitlePage(it)) })
                            Page.Search -> SearchScreen(field = entry.first, onOpen = { open(Page.TitlePage(it)) })
                            // Read again after a watchlist change (a title removed from its page, say).
                            Page.Watchlist -> TitlesPage(catalog.watchlistVersion, { catalog.watchlist() }, entry.first, onOpen = { open(Page.TitlePage(it)) }) {
                                Text(stringResource(R.string.rail_watchlist), style = MaterialTheme.typography.displayMedium, color = WtvColors.TextPrimary)
                            }
                            is Page.Settings -> SettingsScreen(firstFocus = entry.first, providerFirst = p.providerFirst)
                            is Page.Live -> LivePlayerScreen(p.channels, p.index, p.login, firstFocus = entry.first)
                            is Page.Player -> PlayerScreen(
                                p.url,
                                p.title,
                                startSecs = p.startSecs,
                                firstFocus = entry.first,
                                next = p.next?.let { e -> listOfNotNull(seasonEpisode.format(e.season, e.number), e.displayName(hebrew)).joinToString(" · ") },
                                onNext = { playNext(p) },
                                onProgress = { position, duration, final -> saveProgress(p, position, duration, final) },
                                onClose = { close { stack.removeAt(stack.lastIndex) } },
                            )
                        }
                    }
                }
            }
            // Not over the video: the player is the whole screen.
            if (stack.lastOrNull()?.page.let { it !is Page.Player && it !is Page.Live }) SideRail(
                onSelect = {
                    // The tabs' focus flag would go stale under the page.
                    tabsHaveFocus = false
                    // Search and Settings are pages like the others: Back returns from them.
                    when (it) {
                        RailItem.Search -> open(Page.Search)
                        RailItem.Categories -> open(Page.Categories(if (section == Section.Series) Kind.Series else Kind.Movie))
                        RailItem.MainMenu ->
                            if (stack.isEmpty()) selectedTab.requestFocus()
                            else {
                                toTabs = true
                                close { stack.clear() }
                            }
                        RailItem.Watchlist -> open(Page.Watchlist)
                        RailItem.Settings -> open(Page.Settings())
                    }
                },
                onLeave = {
                    val top = stack.lastOrNull()
                    when {
                        top != null -> top.memory.restore(fallback = top.first)
                        lastOnTabs -> runCatching { selectedTab.requestFocus() }
                        else -> baseMemory.restore(fallback = page)
                    }
                },
                modifier = Modifier.align(Alignment.CenterStart),
                // Categories lists movie or series tags: not on Home or Live TV.
                showCategories = section == Section.Movies || section == Section.Series,
            )
        }
    }
}

/**
 * One screen of the stack. Layers below the top stay composed (no reload,
 * same scroll) but cannot take the focus and are not drawn (the window
 * background shows through the top one, which covers them anyway). Cards inside record themselves in
 * `memory`, so the layer can give the focus back to the last one.
 */
@Composable
private fun Layer(blocked: Boolean, hidden: Boolean, memory: FocusMemory, content: @Composable BoxScope.() -> Unit) {
    CompositionLocalProvider(LocalFocusMemory provides memory) {
        Box(
            Modifier
                .fillMaxSize()
                // Drawing a covered layer cost a whole extra screen per frame.
                .then(if (hidden) Modifier.drawWithContent {} else Modifier)
                .focusProperties { onEnter = { if (blocked) cancelFocusChange() } }
                .focusGroup(),
            content = content,
        )
    }
}

/** "Exit the app?" with Yes (focused) and No; Back answers No. */
@Composable
private fun ExitDialog(onYes: () -> Unit, onNo: () -> Unit) {
    val yes = remember { FocusRequester() }
    Dialog(onDismissRequest = onNo) {
        Column(
            Modifier.background(WtvColors.Surface, RoundedCornerShape(12.dp)).padding(horizontal = 40.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(stringResource(R.string.exit_question), style = MaterialTheme.typography.headlineSmall, color = WtvColors.TextPrimary)
            Spacer(Modifier.height(24.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Button(onClick = onYes, modifier = Modifier.focusRequester(yes)) { Text(stringResource(R.string.yes)) }
                Button(onClick = onNo) { Text(stringResource(R.string.no)) }
            }
        }
    }
    LaunchedEffect(Unit) { runCatching { yes.requestFocus() } }
}
