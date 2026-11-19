package com.wtv.app.ui.grid

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
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.style.TextOverflow
import androidx.tv.material3.Button
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.FilterChip
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.Category
import com.wtv.app.data.Genre
import com.wtv.app.data.Kind
import com.wtv.app.data.Sort
import com.wtv.app.data.Title
import com.wtv.app.ui.browse.TitleHeader
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.components.LocalTitleMenu
import com.wtv.app.ui.components.Backdrop
import com.wtv.app.ui.components.HeaderHeight
import com.wtv.app.ui.components.HeaderTop
import com.wtv.app.ui.components.LandscapeCard
import com.wtv.app.ui.components.RowsAtTop
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.launch

private const val PAGE = 60
private const val COLUMNS = 4

/** Load the next page when the focus gets this close to the end. */
private const val PRELOAD = 2 * COLUMNS

/** A 200 dp landscape card's height. */
private val CARD_HEIGHT = 112.5.dp
private val ROW_GAP = 28.dp
private val EDGE = 12.dp

/**
 * A whole category in rows of four, with a choice of order. The focused
 * title's header and backdrop show above the rows.
 */
@Composable
fun GridScreen(category: Category, firstFocus: FocusRequester, onOpen: (Title) -> Unit) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    PosterGrid(category.label(hebrew), firstFocus, onOpen) { sort, offset, limit ->
        sort?.let { catalog.page(category, it, hebrew, offset, limit) } ?: catalog.recommendedPage(category, offset, limit)
    }
}

/**
 * Titles in rows of four under `label`, two rows on screen, loaded `pageSize`
 * at a time as the focus nears the end. With `sorts`, chips choose the order
 * (null: Recommended); without, `fetch` gets null.
 */
@OptIn(ExperimentalTvMaterial3Api::class) // FilterChip
@Composable
fun PosterGrid(
    label: String,
    firstFocus: FocusRequester,
    onOpen: (Title) -> Unit,
    sorts: Boolean = true,
    pageSize: Int = PAGE,
    fetch: suspend (sort: Sort?, offset: Int, limit: Int) -> List<Title>,
) {
    val app = LocalContext.current.applicationContext as WtvApplication
    val hebrew = isHebrew()
    val scope = rememberCoroutineScope()

    // Null: Recommended, the user's WTW ranking (newest first without one).
    var sort by rememberSaveable { mutableStateOf<Sort?>(null) }
    val titles = remember(sort, hebrew) { mutableStateListOf<Title>() }
    // Rows received so far: the next offset. Not titles.size, which drops repeats.
    var fetched by remember(sort, hebrew) { mutableStateOf(0) }
    var end by remember(sort, hebrew) { mutableStateOf(false) }
    var loading by remember(sort, hebrew) { mutableStateOf(false) }
    var error by remember(sort, hebrew) { mutableStateOf<String?>(null) }
    var focused by remember(sort, hebrew) { mutableStateOf<Title?>(null) }
    val chips = remember { FocusRequester() }

    fun loadMore() {
        if (loading || end) return
        loading = true
        val before = titles.size
        scope.launch {
            runCatching { fetch(sort, fetched, pageSize) }
                .onSuccess {
                    fetched += it.size
                    // A sync between two pages shifts rows, so a title can come twice: keys must stay unique.
                    val seen = titles.mapTo(HashSet()) { t -> t.id }
                    titles.addAll(it.filter { t -> seen.add(t.id) })
                    if (it.size < pageSize) end = true
                    if (focused == null) focused = it.firstOrNull()
                    error = null
                }
                .onFailure { error = it.message ?: it.toString() }
            val addedNothing = error == null && titles.size == before
            loading = false
            // A page made only of repeats: no new card to focus, so fetch the next one now.
            if (addedNothing) loadMore()
        }
    }
    LaunchedEffect(sort, hebrew) { loadMore() }

    // The loading message held the focus; when the first page arrives, the first
    // card takes it. Only on opening: after a sort change the focus stays on the chips.
    var placed by remember { mutableStateOf(false) }
    LaunchedEffect(titles.isNotEmpty()) {
        if (titles.isNotEmpty() && !placed) {
            placed = true
            firstFocus.requestFocus()
        }
    }

    // Genre names are a nicety: without them the header's meta line just has no genres.
    val genres by produceState(emptyMap<Pair<Kind, Int>, Genre>()) { value = runCatching { app.catalog.genres() }.getOrDefault(emptyMap()) }
    // WTW's own match, asked for the two rows on screen and the one under them as the focus moves.
    val scores = app.wtwScores
    val wtw = remember { app.wtw.email != null }
    fun matchOf(t: Title): Int? = if (wtw) scores[t.id] ?: t.match else null
    LaunchedEffect(focused, titles.size) {
        val at = titles.indexOf(focused).coerceAtLeast(0) / COLUMNS * COLUMNS
        if (wtw) scores.request(titles.drop(at).take(3 * COLUMNS).filter { it.match == null }.map { it.id })
    }

    Box(Modifier.fillMaxSize()) {
        Backdrop(focused?.heroImage)
        // The name and the sort chips sit where the tabs are on the browse pages.
        Row(Modifier.padding(start = 88.dp, end = 48.dp, top = 18.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                label,
                style = MaterialTheme.typography.headlineMedium,
                color = WtvColors.TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            if (sorts) Spacer(Modifier.padding(start = 24.dp))
            // Without sorts `sort` stays null, which `fetch` gets.
            if (sorts) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // Recommended (null) is not a Sort: it is a server function, not a REST order.
                (listOf<Sort?>(null) + Sort.entries).forEachIndexed { i, s ->
                    FilterChip(
                        selected = s == sort,
                        onClick = { sort = s },
                        modifier = if (i == 0) Modifier.focusRequester(chips) else Modifier,
                    ) { Text(stringResource(s?.label ?: R.string.sort_recommended)) }
                }
            }
        }
        Column(Modifier.padding(start = 88.dp, top = HeaderTop)) {
            focused?.let { TitleHeader(it, genres, hebrew, matchOf(it)) } ?: Spacer(Modifier.height(HeaderHeight))
            when {
                titles.isEmpty() && error != null -> Message(stringResource(R.string.load_failed, error!!), firstFocus, onRetry = ::loadMore)
                titles.isEmpty() && end -> Message(stringResource(R.string.nothing_here), firstFocus)
                titles.isEmpty() -> Message(stringResource(R.string.loading), firstFocus)
                // The focused row goes to the top, so each step down shows one new row.
                else -> RowsAtTop(titleSpaceDp = EDGE) {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(COLUMNS),
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                        verticalArrangement = Arrangement.spacedBy(ROW_GAP),
                        // End: four 200 dp cards fill the row. Top and bottom: room for the focused card's lift.
                        contentPadding = PaddingValues(top = EDGE, end = 30.dp, bottom = EDGE),
                        // Two rows high: the rows under them stay hidden.
                        modifier = Modifier.height(EDGE * 2 + CARD_HEIGHT * 2 + ROW_GAP),
                    ) {
                        itemsIndexed(titles, key = { _, t -> t.id }) { i, t ->
                            LandscapeCard(
                                imageUrl = t.cardImage,
                                title = t.displayName(hebrew),
                                onClick = { onOpen(t) },
                                onLongClick = LocalTitleMenu.current.let { menu -> { menu(t) } },
                                onFocused = {
                                    focused = t
                                    if (i >= titles.size - PRELOAD) loadMore()
                                },
                                match = matchOf(t),
                                modifier = Modifier
                                    .then(if (i == 0) Modifier.focusRequester(firstFocus) else Modifier)
                                    // Up from the first row goes to the sort chips.
                                    .then(if (sorts && i < COLUMNS) Modifier.focusProperties { up = chips } else Modifier),
                            )
                        }
                        // A later page failed: a Retry under the grid, since the focus may not move again.
                        if (error != null) {
                            item(span = { GridItemSpan(maxLineSpan) }) {
                                Box(contentAlignment = Alignment.Center) {
                                    Button(onClick = ::loadMore) { Text(stringResource(R.string.retry)) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private val Sort.label: Int
    get() = when (this) {
        Sort.Added -> R.string.sort_added
        Sort.Year -> R.string.sort_year
        Sort.Name -> R.string.sort_name
        Sort.Rating -> R.string.sort_rating
    }

/** Loading, empty or error message; with `onRetry`, a Retry button takes the focus. */
@Composable
private fun Message(text: String, focus: FocusRequester, onRetry: (() -> Unit)? = null) {
    val box = if (onRetry == null) Modifier.focusRequester(focus).focusable() else Modifier
    Column(Modifier.fillMaxSize().then(box)) {
        Text(text, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextMuted)
        if (onRetry != null) {
            Spacer(Modifier.height(16.dp))
            Button(onClick = onRetry, modifier = Modifier.focusRequester(focus)) { Text(stringResource(R.string.retry)) }
        }
    }
}
