package com.wtv.app.ui.search

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Button
import androidx.tv.material3.ButtonDefaults
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.CastMember
import com.wtv.app.data.Channel
import com.wtv.app.data.Kind
import com.wtv.app.data.Title
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.components.ChannelCard
import com.wtv.app.ui.components.LocalTitleMenu
import com.wtv.app.ui.components.PersonCard
import com.wtv.app.ui.components.PosterCard
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay

/** Wait this long after the last key before searching. */
private const val TYPING_PAUSE_MS = 400L

/** Suggestions under the field: a few names to pick from as you type. */
private const val SUGGESTIONS = 6

/** What a search looks in: everything (the side bar), one section's titles, or Live TV's channels. */
enum class SearchScope(val kind: Kind?, val hint: Int) {
    All(null, R.string.search_hint),
    Movies(Kind.Movie, R.string.search_hint_movies),
    Series(Kind.Series, R.string.search_hint_series),
    Live(null, R.string.search_hint_live),
}

private sealed interface Results {
    data object Idle : Results
    data object Searching : Results
    /** `query` is the one searched, which the field may have moved on from. */
    data class Found(val query: String, val titles: List<Title>, val people: List<CastMember>, val channels: List<Channel>) : Results {
        val empty get() = titles.isEmpty() && people.isEmpty() && channels.isEmpty()
    }
    data class Failed(val message: String) : Results
}

/** A suggestion under the field: what it shows, a word for its kind (actor, channel), and what picking it does. */
private class Suggestion(val text: String, val tag: String?, val pick: () -> Unit)

/**
 * Text search, in English or Hebrew. The field opens the TV's keyboard; as
 * the user types, suggestions appear under it (actors and titles, or
 * channels), then the results: actors, then title posters, or channel cards
 * on Live TV. With `grow`, the field opens out across the line when the
 * page appears (the search icon on a section).
 */
@Composable
fun SearchScreen(
    field: FocusRequester,
    onOpen: (Title) -> Unit,
    onPerson: (CastMember) -> Unit,
    onWatch: (List<Channel>, Int) -> Unit,
    scope: SearchScope = SearchScope.All,
    grow: Boolean = false,
) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    var query by rememberSaveable { mutableStateOf("") }
    var results by remember { mutableStateOf<Results>(Results.Idle) }
    var fieldFocused by remember { mutableStateOf(false) }
    val firstBelow = remember { FocusRequester() }
    // Live TV searches the channel list, read once.
    var channels by remember { mutableStateOf<List<Channel>?>(null) }

    // A new query cancels the search of the previous one.
    LaunchedEffect(query, hebrew) {
        if (query.isBlank()) {
            results = Results.Idle
            return@LaunchedEffect
        }
        delay(TYPING_PAUSE_MS)
        // Earlier results stay on screen until the new ones arrive: no flicker while typing.
        if (results !is Results.Found) results = Results.Searching
        val q = query.trim()
        results = try {
            if (scope == SearchScope.Live) {
                val all = channels ?: catalog.channels().also { channels = it }
                Results.Found(q, emptyList(), emptyList(), all.filter { it.name.contains(q, ignoreCase = true) })
            } else coroutineScope {
                val titles = async { catalog.search(q, hebrew, scope.kind) }
                // Actors are a nicety: without them the titles still show.
                val people = async { runCatching { catalog.searchPeople(q, scope.kind) }.getOrDefault(emptyList()) }
                Results.Found(q, titles.await(), people.await(), emptyList())
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Results.Failed(e.message ?: e.toString())
        }
    }

    val shown = results
    val actorTag = stringResource(R.string.search_actor)
    val suggestions = remember(shown, query, hebrew) {
        val r = shown as? Results.Found
        if (r == null || r.query != query.trim()) emptyList()
        else (
            r.people.take(2).map { p -> Suggestion(p.name, actorTag, { onPerson(p) }) } +
                r.titles.map { t -> Suggestion(t.displayName(hebrew), t.year?.toString(), { onOpen(t) }) } +
                r.channels.mapIndexed { i, c -> Suggestion(c.name, null, { onWatch(r.channels, i) }) }
            ).take(SUGGESTIONS)
    }

    // The section's icon opens the field out across the line.
    var opened by remember { mutableStateOf(!grow) }
    LaunchedEffect(Unit) { opened = true }
    val fieldWidth by animateDpAsState(if (opened) 900.dp else 56.dp, label = "field")

    Column(Modifier.fillMaxSize().padding(start = 88.dp, end = 48.dp, top = 48.dp)) {
        Box(Modifier.fillMaxWidth(), contentAlignment = if (grow) Alignment.TopEnd else Alignment.TopStart) {
            BasicTextField(
                value = query,
                onValueChange = { query = it },
                singleLine = true,
                textStyle = MaterialTheme.typography.headlineMedium.copy(color = WtvColors.TextPrimary),
                cursorBrush = SolidColor(WtvColors.TextPrimary),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                // The keyboard's Search key moves on to the suggestions.
                keyboardActions = KeyboardActions(onSearch = { runCatching { firstBelow.requestFocus() } }),
                modifier = Modifier
                    .width(fieldWidth)
                    .focusRequester(field)
                    // A text field keeps Down for its cursor; on a TV Down means "to what is below".
                    .onPreviewKeyEvent {
                        if (it.type == KeyEventType.KeyDown && it.key == Key.DirectionDown) {
                            runCatching { firstBelow.requestFocus() }.getOrDefault(false)
                        } else {
                            false
                        }
                    }
                    .onFocusChanged { fieldFocused = it.isFocused }
                    .background(WtvColors.Surface, RoundedCornerShape(8.dp))
                    .border(BorderStroke(2.dp, if (fieldFocused) WtvColors.Focus else WtvColors.Surface), RoundedCornerShape(8.dp))
                    .padding(horizontal = 20.dp, vertical = 12.dp),
                decorationBox = { inner ->
                    Box {
                        if (query.isEmpty() && opened) {
                            Text(stringResource(scope.hint), style = MaterialTheme.typography.headlineMedium, color = WtvColors.TextMuted, maxLines = 1)
                        }
                        inner()
                    }
                },
            )
        }
        if (suggestions.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Column(Modifier.width(640.dp)) {
                suggestions.forEachIndexed { i, s ->
                    Button(
                        onClick = s.pick,
                        modifier = Modifier.fillMaxWidth().then(if (i == 0) Modifier.focusRequester(firstBelow) else Modifier),
                        shape = ButtonDefaults.shape(RoundedCornerShape(6.dp)),
                        colors = ButtonDefaults.colors(
                            containerColor = WtvColors.Background,
                            contentColor = WtvColors.TextSecondary,
                            focusedContainerColor = WtvColors.TextPrimary,
                            focusedContentColor = WtvColors.Background,
                        ),
                    ) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(s.text, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                            if (s.tag != null) Text(s.tag, style = MaterialTheme.typography.labelMedium)
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(20.dp))
        when (val r = shown) {
            Results.Idle -> Unit
            Results.Searching -> Note(stringResource(R.string.searching))
            is Results.Failed -> Note(stringResource(R.string.load_failed, r.message))
            is Results.Found ->
                if (r.empty) Note(stringResource(R.string.no_results, r.query))
                else Found(r, hebrew, focusFirst = suggestions.isEmpty(), firstBelow, onOpen, onPerson, onWatch)
        }
    }
}

/** The results under the suggestions: actors (named), then title posters; or channel cards. */
@Composable
private fun Found(
    r: Results.Found,
    hebrew: Boolean,
    focusFirst: Boolean,
    firstBelow: FocusRequester,
    onOpen: (Title) -> Unit,
    onPerson: (CastMember) -> Unit,
    onWatch: (List<Channel>, Int) -> Unit,
) {
    // Down from the field lands on the first suggestion, or on the first result when there are none.
    fun first(i: Int) = if (focusFirst && i == 0) Modifier.focusRequester(firstBelow) else Modifier
    if (r.channels.isNotEmpty()) {
        LazyVerticalGrid(
            columns = GridCells.Fixed(5),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            contentPadding = PaddingValues(top = 6.dp, bottom = 48.dp),
        ) {
            itemsIndexed(r.channels, key = { _, c -> c.id }) { i, c ->
                ChannelCard(logo = c.logo, name = c.name, number = c.num, favorite = false, onClick = { onWatch(r.channels, i) }, onLongClick = {}, modifier = first(i))
            }
        }
        return
    }
    Column {
        if (r.people.isNotEmpty()) {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp), contentPadding = PaddingValues(top = 6.dp, bottom = 12.dp)) {
                items(r.people, key = { it.personId }) { p ->
                    PersonCard(imageUrl = p.photo, name = p.name, onClick = { onPerson(p) }, label = p.name, modifier = first(r.people.indexOf(p)))
                }
            }
        }
        LazyVerticalGrid(
            columns = GridCells.Fixed(6),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
            contentPadding = PaddingValues(top = 6.dp, bottom = 48.dp),
        ) {
            itemsIndexed(r.titles, key = { _, t -> t.id }) { i, t ->
                PosterCard(
                    imageUrl = t.posterImage,
                    title = t.displayName(hebrew),
                    onClick = { onOpen(t) },
                    onLongClick = LocalTitleMenu.current.let { menu -> { menu(t) } },
                    modifier = if (r.people.isEmpty()) first(i) else Modifier,
                )
            }
        }
    }
}

@Composable
private fun Note(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextMuted)
}
