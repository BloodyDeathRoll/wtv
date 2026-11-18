package com.wtv.app.ui.person

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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Button
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.CastMember
import com.wtv.app.data.Title
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.components.Backdrop
import com.wtv.app.ui.components.LocalTitleMenu
import com.wtv.app.ui.components.PosterCard
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.CancellationException

private sealed interface Load {
    data object Loading : Load
    data class Ready(val titles: List<Title>) : Load
    data class Failed(val message: String) : Load
}

/** A cast member's page: their photo and name, then every title of theirs the provider has. */
@Composable
fun PersonScreen(person: CastMember, firstFocus: FocusRequester, onOpen: (Title) -> Unit) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    TitlesPage(person.personId, { catalog.personTitles(person.personId) }, firstFocus, onOpen) { count ->
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (person.photo != null) {
                AsyncImage(
                    model = person.photo,
                    contentDescription = person.name,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(96.dp).clip(CircleShape),
                )
                Spacer(Modifier.width(24.dp))
            }
            Column {
                Text(person.name, style = MaterialTheme.typography.displayMedium, color = WtvColors.TextPrimary)
                if (count != null) {
                    Text(
                        pluralStringResource(R.plurals.person_titles, count, count),
                        style = MaterialTheme.typography.titleSmall,
                        color = WtvColors.TextSecondary,
                    )
                }
            }
        }
    }
}

/**
 * A page of title posters under a header: a person's titles, the watchlist.
 * `load` runs again when `key` changes; `header` gets the number of titles
 * once they are in.
 */
@Composable
fun TitlesPage(
    key: Any,
    load: suspend () -> List<Title>,
    firstFocus: FocusRequester,
    onOpen: (Title) -> Unit,
    header: @Composable (count: Int?) -> Unit,
) {
    val hebrew = isHebrew()
    var attempt by remember { mutableIntStateOf(0) }
    // The loading message holds the focus until the posters arrive. They take it
    // unless the user pressed a key meanwhile (moved to the rail, say). Removing the
    // message clears the focus, so "had the focus" cannot tell; a key press can.
    var moved by remember { mutableStateOf(false) }
    val state by produceState<Load>(Load.Loading, key, attempt) {
        value = Load.Loading
        value = try {
            Load.Ready(load())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Load.Failed(e.message ?: e.toString())
        }
    }

    // Each state's first item (loading message, Retry, empty message, first
    // poster) holds `firstFocus`; replacing a state clears the focus, so it is
    // requested again on every change, unless the user pressed a key meanwhile.
    LaunchedEffect(state) { if (!moved) runCatching { firstFocus.requestFocus() } }
    // The focused poster's name under the header, as on a category's page.
    var focused by remember(key) { mutableStateOf<Title?>(null) }

    Box(Modifier.fillMaxSize()) {
        Backdrop(focused?.heroImage)
        Column(Modifier.fillMaxSize().padding(start = 88.dp, end = 48.dp, top = 48.dp)) {
            header((state as? Load.Ready)?.titles?.size)
            Spacer(Modifier.height(8.dp))
            Text(
                focused?.let { t -> listOfNotNull(t.displayName(hebrew), t.year?.toString(), t.certification).joinToString("   ") } ?: " ",
                style = MaterialTheme.typography.titleSmall,
                color = WtvColors.TextSecondary,
                maxLines = 1,
            )
            Spacer(Modifier.height(16.dp))
            when (val s = state) {
                Load.Loading -> Message(stringResource(R.string.loading), firstFocus, onKey = { moved = true })
                is Load.Failed -> Message(stringResource(R.string.load_failed, s.message), firstFocus, onKey = { moved = true }, onRetry = { moved = false; attempt++ })
                is Load.Ready ->
                    if (s.titles.isEmpty()) Message(stringResource(R.string.nothing_here), firstFocus, onKey = { moved = true })
                    else {
                        LazyVerticalGrid(
                            columns = GridCells.Fixed(6),
                            horizontalArrangement = Arrangement.spacedBy(16.dp),
                            verticalArrangement = Arrangement.spacedBy(18.dp),
                            contentPadding = PaddingValues(top = 6.dp, bottom = 48.dp),
                        ) {
                            itemsIndexed(s.titles, key = { _, t -> t.id }) { i, t ->
                                PosterCard(
                                    imageUrl = t.posterImage,
                                    title = t.displayName(hebrew),
                                    onClick = { onOpen(t) },
                                    onLongClick = LocalTitleMenu.current.let { menu -> { menu(t) } },
                                    onFocused = { focused = t },
                                    modifier = if (i == 0) Modifier.focusRequester(firstFocus) else Modifier,
                                )
                            }
                        }
                    }
            }
        }
    }
}

/** Loading, empty or error message; with `onRetry`, a Retry button holds the focus. */
@Composable
private fun Message(text: String, focus: FocusRequester, onKey: () -> Unit, onRetry: (() -> Unit)? = null) {
    val holder = Modifier.focusRequester(focus).onPreviewKeyEvent {
        if (it.type == KeyEventType.KeyDown) onKey()
        false
    }
    Column(Modifier.fillMaxSize().then(if (onRetry == null) holder.focusable() else Modifier)) {
        Text(text, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextMuted)
        if (onRetry != null) {
            Spacer(Modifier.height(16.dp))
            Button(onClick = onRetry, modifier = holder) { Text(stringResource(R.string.retry)) }
        }
    }
}
