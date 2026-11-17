package com.wtv.app.ui.browse

import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.foundation.layout.Spacer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Button
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.Catalog
import com.wtv.app.data.Category
import com.wtv.app.data.ContinueItem
import com.wtv.app.data.Genre
import com.wtv.app.data.Kind
import com.wtv.app.data.Title
import com.wtv.app.ui.components.Backdrop
import com.wtv.app.ui.components.HeroText
import com.wtv.app.ui.components.LandscapeCard
import com.wtv.app.ui.components.MetaRow
import com.wtv.app.ui.components.RowTitle
import com.wtv.app.ui.components.RowsAtTop
import com.wtv.app.ui.components.Sideways
import com.wtv.app.ui.theme.WtvColors

/** What a browse page shows: one section's category rows, or Home's latest rows. */
sealed interface BrowseSource {
    data object Home : BrowseSource
    data class Section(val kind: Kind) : BrowseSource
}

/**
 * A row on the page; `category` is set when the row has a "More" card.
 * `progress` (Continue watching) gives a card its watched bar and label, by title id.
 */
data class BrowseRow(
    val label: String,
    val category: Category?,
    val titles: List<Title>,
    val progress: Map<Long, Pair<Float?, String?>> = emptyMap(),
)

private sealed interface Load {
    data object Loading : Load
    data class Ready(val rows: List<BrowseRow>, val genres: Map<Pair<Kind, Int>, Genre>) : Load
    data class Failed(val message: String) : Load
}

/** True when the app runs in Hebrew: Android reports it as "iw" (the old code) or "he". */
@Composable
fun isHebrew(): Boolean = LocalConfiguration.current.locales[0].language.let { it == "he" || it == "iw" }

/**
 * Rows of titles under a header that follows the focus, as in the reference.
 * `firstFocus` is where Down from the tabs lands; `up` is where Up from the
 * first row goes. Home starts with Continue watching, reloaded when
 * `progressVersion` changes (a player closed) without reloading the rest.
 * When `tabsFocused`, the page is back at its top: Down from the tabs needs
 * the first row, which the list releases once it has scrolled away.
 */
@Composable
fun BrowseScreen(
    source: BrowseSource,
    firstFocus: FocusRequester,
    up: FocusRequester,
    progressVersion: Int,
    tabsFocused: Boolean,
    onMore: (Category) -> Unit,
    onOpen: (Title) -> Unit,
) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    val continueLabel = stringResource(R.string.row_continue)
    val seasonEpisode = stringResource(R.string.season_episode)
    // Null until loaded: Home shows its rows once this is in too, so the row does not
    // appear above the rows after the user has started moving. A nicety: when it
    // fails, Home just has no Continue watching row.
    val watching by produceState<List<ContinueItem>?>(null, progressVersion) {
        value = runCatching { catalog.continueWatching() }.getOrDefault(value.orEmpty())
    }
    val recentMovies = stringResource(R.string.row_recent_movies)
    val recentSeries = stringResource(R.string.row_recent_series)
    var attempt by remember { mutableIntStateOf(0) }
    val load by produceState<Load>(Load.Loading, source, hebrew, attempt) {
        value = Load.Loading
        value = runCatching {
            val rows = loadRows(catalog, source, hebrew, recentMovies, recentSeries)
            // Genre names are a nicety: without them the meta line just has no genres.
            Load.Ready(rows, runCatching { catalog.genres() }.getOrDefault(emptyMap()))
        }.getOrElse { Load.Failed(it.message ?: it.toString()) }
    }

    when (val state = load) {
        Load.Loading -> Message(stringResource(R.string.loading), firstFocus)
        is Load.Failed -> Message(stringResource(R.string.load_failed, state.message), firstFocus, onRetry = { attempt++ })
        is Load.Ready -> {
            val home = source == BrowseSource.Home
            val w = watching
            val rows = remember(state.rows, w, home) {
                (if (home && w != null) listOfNotNull(continueRow(w, continueLabel, seasonEpisode)) else emptyList()) + state.rows
            }
            when {
                home && w == null -> Message(stringResource(R.string.loading), firstFocus)
                rows.isEmpty() -> Message(stringResource(R.string.nothing_here), firstFocus)
                else -> Rows(rows, state.genres, hebrew, firstFocus, up, tabsFocused, onMore, onOpen)
            }
        }
    }
}

/** Continue watching as a row: a series' card names its episode. Null when empty. */
private fun continueRow(items: List<ContinueItem>, label: String, seasonEpisode: String): BrowseRow? =
    items.takeIf { it.isNotEmpty() }?.let { list ->
        BrowseRow(
            label,
            category = null,
            titles = list.map { it.title },
            progress = list.associate { (t, p) ->
                val episode = if (p.isEpisode && !p.finished) seasonEpisode.format(p.season, p.episode) else null
                t.id to ((if (p.finished) null else p.fraction) to episode)
            },
        )
    }

private suspend fun loadRows(catalog: Catalog, source: BrowseSource, hebrew: Boolean, recentMovies: String, recentSeries: String): List<BrowseRow> =
    when (source) {
        BrowseSource.Home -> listOf(
            BrowseRow(recentMovies, null, catalog.latest(Kind.Movie)),
            BrowseRow(recentSeries, null, catalog.latest(Kind.Series)),
        ).filter { it.titles.isNotEmpty() }
        is BrowseSource.Section -> catalog.rows(source.kind).map { (c, titles) -> BrowseRow(c.label(hebrew), c, titles) }
    }

@Composable
private fun Rows(
    rows: List<BrowseRow>,
    genres: Map<Pair<Kind, Int>, Genre>,
    hebrew: Boolean,
    firstFocus: FocusRequester,
    up: FocusRequester,
    tabsFocused: Boolean,
    onMore: (Category) -> Unit,
    onOpen: (Title) -> Unit,
) {
    // Safe: empty rows are left out, and an empty page never gets here.
    // Kept when only Continue watching changes: the header stays on the focused card.
    var focused by remember { mutableStateOf(rows.first().titles.first()) }
    val list = rememberLazyListState()
    LaunchedEffect(tabsFocused) {
        if (tabsFocused) {
            list.scrollToItem(0)
            focused = rows.first().titles.first()
        }
    }
    Box(Modifier.fillMaxSize()) {
        Backdrop(focused.heroImage)
        Column(Modifier.padding(start = 88.dp, top = 76.dp)) {
            // Fixed height: rows do not jump when the synopsis length changes.
            Box(Modifier.height(220.dp)) {
                HeroText(
                    modifier = Modifier.width(560.dp),
                    titleMaxLines = 1,
                    title = focused.displayName(hebrew),
                    meta = { MetaRow(items = metaItems(focused, genres, hebrew), badges = listOfNotNull(focused.certification)) },
                    synopsis = focused.synopsis(hebrew),
                )
            }
            RowsAtTop {
                LazyColumn(
                    state = list,
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                    contentPadding = PaddingValues(top = 8.dp, bottom = 400.dp),
                ) {
                    // Two categories can share a label; their ids differ.
                    itemsIndexed(rows, key = { _, r -> r.category?.id ?: r.label }) { rowIndex, row ->
                        Column {
                            RowTitle(row.label)
                            // Up from the first row goes to the tabs; spatially the rail is nearer.
                            val rowModifier = if (rowIndex == 0) Modifier.focusProperties { this.up = up } else Modifier
                            Sideways {
                                LazyRow(
                                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                                    contentPadding = PaddingValues(end = 48.dp, top = 6.dp, bottom = 6.dp),
                                ) {
                                    itemsIndexed(row.titles, key = { _, t -> t.id }) { i, t ->
                                        val (watched, episode) = row.progress[t.id] ?: (null to null)
                                        LandscapeCard(
                                            imageUrl = t.cardImage,
                                            title = t.displayName(hebrew),
                                            label = episode,
                                            progress = watched,
                                            onClick = { onOpen(t) },
                                            onFocused = { focused = t },
                                            modifier = rowModifier.then(if (rowIndex == 0 && i == 0) Modifier.focusRequester(firstFocus) else Modifier),
                                        )
                                    }
                                    val category = row.category
                                    if (category != null) {
                                        item {
                                            LandscapeCard(imageUrl = null, title = stringResource(R.string.more), onClick = { onMore(category) }, modifier = rowModifier)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** "2026", "Crime • Drama": year and up to two genres. */
private fun metaItems(t: Title, genres: Map<Pair<Kind, Int>, Genre>, hebrew: Boolean): List<String> =
    listOfNotNull(
        t.year?.toString(),
        t.genreIds.mapNotNull { genres[t.kind to it]?.label(hebrew) }.take(2).joinToString(" • ").ifEmpty { null },
    )

/**
 * Loading, error or empty page. Focusable, so Down from the tabs lands
 * somewhere; with `onRetry`, a Retry button takes the focus instead.
 */
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
