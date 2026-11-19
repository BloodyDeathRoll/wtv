package com.wtv.app.ui.live

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.wtv.app.ui.components.MENU_WIDTH
import com.wtv.app.ui.components.MenuItem
import androidx.compose.ui.window.DialogProperties
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.FolderOff
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.StarBorder
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.Icons
import androidx.tv.material3.Button
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.FilterChip
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.Channel
import com.wtv.app.data.LiveCategory
import com.wtv.app.data.LiveFilters
import com.wtv.app.data.liveGroups
import com.wtv.app.player.OnNow
import com.wtv.app.player.ProviderLogin
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.components.ignoresOpeningPress
import com.wtv.app.ui.components.ChannelCard
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private sealed interface Load {
    data object Loading : Load
    data class Failed(val message: String) : Load
    data class Ready(val channels: List<Channel>, val categories: List<LiveCategory>) : Load
}

/**
 * The Live TV page: a chip per group (Favourites, then the provider's
 * categories) over a grid of channel cards. Moving onto a chip shows its
 * group. OK on a card watches the channel, with the group as the channel
 * list; holding OK opens a menu: favourite, hide the channel, hide its group.
 * Hidden things come back in Settings.
 */
@OptIn(ExperimentalTvMaterial3Api::class) // FilterChip
@Composable
fun LiveScreen(firstFocus: FocusRequester, up: FocusRequester, onWatch: (List<Channel>, Int) -> Unit) {
    val context = LocalContext.current
    val app = context.applicationContext as WtvApplication
    val catalog = app.catalog
    // For what is on now on each card; without a login the cards show the channel only.
    val providerLogin = remember { ProviderLogin.load(context)?.takeIf { it.isComplete } }
    val hebrew = isHebrew()
    val scope = rememberCoroutineScope()
    var attempt by remember { mutableIntStateOf(0) }
    val load by produceState<Load>(Load.Loading, attempt) {
        value = runCatching { Load.Ready(catalog.channels(), catalog.liveCategories()) }
            .getOrElse { Load.Failed(it.message ?: it.toString()) }
    }
    // Favourites and what is hidden load on their own: without them the page still works.
    var favorites by remember { mutableStateOf(emptySet<Long>()) }
    var filters by remember { mutableStateOf(LiveFilters()) }
    LaunchedEffect(Unit) { runCatching { catalog.favoriteChannels() }.onSuccess { favorites = it } }
    LaunchedEffect(Unit) { runCatching { catalog.liveFilters() }.onSuccess { filters = it } }
    var menu by remember { mutableStateOf<Channel?>(null) }
    // A hide chosen in the menu, run once the menu has closed (see below).
    var pendingHide by remember { mutableStateOf<(() -> Unit)?>(null) }
    var parking by remember { mutableStateOf(false) }
    val parked = remember { FocusRequester() }

    val state = load
    if (state !is Load.Ready) {
        Message(
            if (state is Load.Failed) stringResource(R.string.load_failed, state.message) else stringResource(R.string.loading),
            firstFocus,
            up,
            onRetry = if (state is Load.Failed) ({ attempt++ }) else null,
        )
        return
    }

    val favoritesLabel = stringResource(R.string.live_favorites)
    val groups = remember(state, favorites, filters, hebrew) { liveGroups(state.channels, state.categories, favorites, favoritesLabel, hebrew, filters) }
    if (groups.isEmpty()) {
        Message(stringResource(R.string.nothing_here), firstFocus, up)
        return
    }
    // The shown group, by label: it survives a favourites change that adds or drops the Favourites group.
    var shownLabel by rememberSaveable { mutableStateOf<String?>(null) }
    val shown = groups.firstOrNull { it.label == shownLabel } ?: groups.first()
    val chip = remember { FocusRequester() }
    val grid = rememberLazyGridState()
    LaunchedEffect(shown.label) { grid.scrollToItem(0) }

    val added = stringResource(R.string.live_favorite_added)
    val removed = stringResource(R.string.live_favorite_removed)
    val hiddenMessage = stringResource(R.string.live_hidden)
    fun hideChannel(c: Channel) {
        filters = filters.copy(hiddenChannels = filters.hiddenChannels + c.id)
        Toast.makeText(context, hiddenMessage, Toast.LENGTH_LONG).show()
        scope.launch {
            runCatching { catalog.setChannelHidden(c.id, true) }
                .onFailure { filters = filters.copy(hiddenChannels = filters.hiddenChannels - c.id) }
        }
    }
    fun hideGroup(category: LiveCategory) {
        filters = filters.copy(hiddenGroups = filters.hiddenGroups + category.id)
        Toast.makeText(context, hiddenMessage, Toast.LENGTH_LONG).show()
        scope.launch {
            runCatching { catalog.setGroupHidden(category.id, true) }
                .onFailure { filters = filters.copy(hiddenGroups = filters.hiddenGroups - category.id) }
        }
    }
    fun toggle(c: Channel) {
        val now = c.id !in favorites
        favorites = if (now) favorites + c.id else favorites - c.id
        Toast.makeText(context, if (now) added else removed, Toast.LENGTH_SHORT).show()
        scope.launch {
            // Put back on failure, so the star shows what is saved; unless a later press already changed it.
            runCatching { catalog.setFavorite(c.id, now) }.onFailure {
                if ((c.id in favorites) == now) favorites = if (now) favorites - c.id else favorites + c.id
            }
        }
    }

    Column(Modifier.fillMaxSize().padding(start = 88.dp, end = 48.dp, top = 96.dp)) {
        Box(Modifier.size(1.dp).focusRequester(parked).focusProperties { canFocus = parking }.focusable())
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                groups.forEach { g ->
                    FilterChip(
                        selected = g.label == shown.label,
                        onClick = { shownLabel = g.label },
                        modifier = Modifier
                            // Down from the tabs lands on the shown group's chip.
                            .then(if (g.label == shown.label) Modifier.focusRequester(chip).focusRequester(firstFocus) else Modifier)
                            .focusProperties { this.up = up }
                            .onFocusChanged { if (it.isFocused) shownLabel = g.label },
                    ) { Text("${g.label}  ${g.channels.size}") }
                }
            }
            Spacer(Modifier.padding(start = 24.dp))
            Text(stringResource(R.string.live_hint), style = MaterialTheme.typography.bodySmall, color = WtvColors.TextMuted)
        }
        Spacer(Modifier.height(20.dp))
        LazyVerticalGrid(
            state = grid,
            columns = GridCells.Fixed(COLUMNS),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            contentPadding = PaddingValues(top = 6.dp, bottom = 48.dp),
        ) {
            itemsIndexed(shown.channels, key = { _, c -> c.id }) { i, c ->
                // Asked for each card as it comes on screen; the answer is kept until the programme ends.
                // A card left on screen moves on when its programme ends.
                val onNow by produceState(OnNow.cached(c.extId, nowSecs()).second, c.extId) {
                    val login = providerLogin ?: return@produceState
                    while (true) {
                        val p = OnNow.fetch(app.http, login, c.extId, nowSecs())
                        value = p
                        // No guide, or a failed call: OnNow's own wait decides when asking again is worth it.
                        delay(((p?.end ?: (nowSecs() + 60)) - nowSecs()).coerceAtLeast(5) * 1000)
                    }
                }
                ChannelCard(
                    onNow = onNow?.title?.takeIf { it.isNotBlank() },
                    logo = c.logo,
                    name = c.name,
                    number = c.num,
                    favorite = c.id in favorites,
                    onClick = { onWatch(shown.channels, i) },
                    onLongClick = { menu = c },
                    // Up from the first row goes to the shown group's chip.
                    modifier = if (i < COLUMNS) Modifier.focusProperties { this.up = chip } else Modifier,
                )
            }
        }
    }
    // Hiding removes the focused card (or its whole group), and Android would then give the
    // focus to the first focusable item: the Home tab, which switches the section. So the focus
    // parks on a holder that is focusable only meanwhile, and then goes to the shown group's chip.
    LaunchedEffect(pendingHide) {
        val hide = pendingHide ?: return@LaunchedEffect
        try {
            withFrameNanos { } // the menu has closed
            parking = true
            withFrameNanos { } // the holder can take the focus
            runCatching { parked.requestFocus() }
            hide()
            withFrameNanos { } // the groups are redrawn: `chip` is on the shown group's chip
            withFrameNanos { }
            runCatching { chip.requestFocus() }
        } finally {
            // Also when cancelled (the last group hidden ends the page): never run twice, never stay parked.
            parking = false
            pendingHide = null
        }
    }

    menu?.let { c ->
        ChannelMenu(
            channel = c,
            favorite = c.id in favorites,
            group = shown.category,
            groupLabel = shown.label,
            onFavorite = { menu = null; toggle(c) },
            onHide = { menu = null; pendingHide = { hideChannel(c) } },
            onHideGroup = {
                menu = null
                shown.category?.let { category ->
                    // Then a neighbour group is shown, and its chip takes the focus.
                    val i = groups.indexOf(shown)
                    val next = groups.getOrNull(i + 1) ?: groups.getOrNull(i - 1)
                    pendingHide = {
                        next?.let { shownLabel = it.label }
                        hideGroup(category)
                    }
                }
            },
            onDismiss = { menu = null },
        )
    }
}

/** Held OK on a channel: favourite, hide it, hide the group it is shown in (not Favourites), or close; a list like the title menu. Back closes. */
@Composable
private fun ChannelMenu(
    channel: Channel,
    favorite: Boolean,
    group: LiveCategory?,
    groupLabel: String,
    onFavorite: () -> Unit,
    onHide: () -> Unit,
    onHideGroup: () -> Unit,
    onDismiss: () -> Unit,
) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val first = remember { FocusRequester() }
        Column(
            Modifier.ignoresOpeningPress().width(MENU_WIDTH).background(WtvColors.Surface, RoundedCornerShape(12.dp)).padding(24.dp),
        ) {
            Text(channel.name, style = MaterialTheme.typography.titleLarge, color = WtvColors.TextPrimary, maxLines = 2)
            Spacer(Modifier.height(16.dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MenuItem(
                    if (favorite) Icons.Filled.Star else Icons.Outlined.StarBorder,
                    stringResource(if (favorite) R.string.live_menu_unfavorite else R.string.live_menu_favorite),
                    onFavorite,
                    Modifier.focusRequester(first),
                )
                MenuItem(Icons.Outlined.VisibilityOff, stringResource(R.string.live_menu_hide), onHide)
                if (group != null) MenuItem(Icons.Outlined.FolderOff, stringResource(R.string.live_menu_hide_group, groupLabel), onHideGroup)
                MenuItem(Icons.Outlined.Close, stringResource(R.string.close), onDismiss)
            }
        }
        LaunchedEffect(Unit) { runCatching { first.requestFocus() } }
    }
}

private const val COLUMNS = 5

private fun nowSecs() = System.currentTimeMillis() / 1000

/** Loading, empty or error message; with `onRetry`, a Retry button takes the focus. */
@Composable
private fun Message(text: String, focus: FocusRequester, up: FocusRequester, onRetry: (() -> Unit)? = null) {
    // Up goes to the selected tab, not whichever tab sits above the middle (that would switch the section).
    val toTab = Modifier.focusRequester(focus).focusProperties { this.up = up }
    val box = if (onRetry == null) toTab.focusable() else Modifier
    Box(Modifier.fillMaxSize().then(box), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextMuted)
            if (onRetry != null) {
                Spacer(Modifier.height(16.dp))
                Button(onClick = onRetry, modifier = toTab) { Text(stringResource(R.string.retry)) }
            }
        }
    }
}
