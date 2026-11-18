package com.wtv.app.ui.live

import android.widget.Toast
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Button
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.FilterChip
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.Channel
import com.wtv.app.data.LiveCategory
import com.wtv.app.data.liveGroups
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.components.ChannelCard
import com.wtv.app.ui.theme.WtvColors
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
 * list; holding OK adds or removes a favourite.
 */
@OptIn(ExperimentalTvMaterial3Api::class) // FilterChip
@Composable
fun LiveScreen(firstFocus: FocusRequester, up: FocusRequester, onWatch: (List<Channel>, Int) -> Unit) {
    val context = LocalContext.current
    val catalog = (context.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    val scope = rememberCoroutineScope()
    var attempt by remember { mutableIntStateOf(0) }
    val load by produceState<Load>(Load.Loading, attempt) {
        value = runCatching { Load.Ready(catalog.channels(), catalog.liveCategories()) }
            .getOrElse { Load.Failed(it.message ?: it.toString()) }
    }
    // Favourites load on their own: without them the page still works.
    var favorites by remember { mutableStateOf(emptySet<Long>()) }
    LaunchedEffect(Unit) { runCatching { catalog.favoriteChannels() }.onSuccess { favorites = it } }

    val state = load
    if (state !is Load.Ready) {
        Message(
            if (state is Load.Failed) stringResource(R.string.load_failed, state.message) else stringResource(R.string.loading),
            firstFocus,
            onRetry = if (state is Load.Failed) ({ attempt++ }) else null,
        )
        return
    }

    val favoritesLabel = stringResource(R.string.live_favorites)
    val groups = remember(state, favorites, hebrew) { liveGroups(state.channels, state.categories, favorites, favoritesLabel, hebrew) }
    if (groups.isEmpty()) {
        Message(stringResource(R.string.nothing_here), firstFocus)
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
                ChannelCard(
                    logo = c.logo,
                    name = c.name,
                    number = c.num,
                    favorite = c.id in favorites,
                    onClick = { onWatch(shown.channels, i) },
                    onLongClick = { toggle(c) },
                    // Up from the first row goes to the shown group's chip.
                    modifier = if (i < COLUMNS) Modifier.focusProperties { this.up = chip } else Modifier,
                )
            }
        }
    }
}

private const val COLUMNS = 5

/** Loading, empty or error message; with `onRetry`, a Retry button takes the focus. */
@Composable
private fun Message(text: String, focus: FocusRequester, onRetry: (() -> Unit)? = null) {
    val box = if (onRetry == null) Modifier.focusRequester(focus).focusable() else Modifier
    Box(Modifier.fillMaxSize().then(box), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(text, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextMuted)
            if (onRetry != null) {
                Spacer(Modifier.height(16.dp))
                Button(onClick = onRetry, modifier = Modifier.focusRequester(focus)) { Text(stringResource(R.string.retry)) }
            }
        }
    }
}
