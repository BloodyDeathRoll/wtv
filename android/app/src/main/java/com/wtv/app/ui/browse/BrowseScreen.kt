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
import com.wtv.app.ui.components.LocalTitleMenu
import com.wtv.app.ui.components.Backdrop
import com.wtv.app.ui.components.HeroText
import com.wtv.app.ui.components.LandscapeCard
import com.wtv.app.ui.components.MetaRow
import com.wtv.app.ui.components.RowTitle
import com.wtv.app.ui.components.RowsAtTop
import com.wtv.app.ui.components.Sideways
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull

/** What a browse page shows: one section's category rows, or Home's latest rows. */
sealed interface BrowseSource {
    data object Home : BrowseSource
    data class Section(val kind: Kind) : BrowseSource
}

/**
 * A row on the page. Its "More" card opens `category`'s grid, or with
 * `forYou` the recommendations page (of `forYouKind`, or both kinds).
 * `progress` (Continue watching) gives a card its watched bar and label, by title id.
 */
data class BrowseRow(
    val label: String,
    val category: Category?,
    val titles: List<Title>,
    val progress: Map<Long, Pair<Float?, String?>> = emptyMap(),
    val forYou: Boolean = false,
    val forYouKind: Kind? = null,
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
    /** The connected WTW account; a change reloads the rows (Top picks, Watch it again). */
    wtwEmail: String?,
    tabsFocused: Boolean,
    onMore: (Category) -> Unit,
    onOpen: (Title) -> Unit,
    /** More on a recommendations row: the recommendations page, of one kind or (null) both. */
    onForYou: (Kind?) -> Unit,
) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    val continueLabel = stringResource(R.string.row_continue)
    val seasonEpisode = stringResource(R.string.season_episode)
    // Null until loaded: Home shows its rows once this is in too, so the row does not
    // appear above the rows after the user has started moving. A nicety: when it
    // fails, Home just has no Continue watching row.
    // Bounded: Home waits for it, and it is not worth a long wait.
    val watching by produceState<List<ContinueItem>?>(null, progressVersion) {
        value = runCatching { withTimeoutOrNull(CONTINUE_WAIT_MS) { catalog.continueWatching() } }.getOrNull() ?: value.orEmpty()
    }
    val app = LocalContext.current.applicationContext as WtvApplication
    val recentMovies = stringResource(R.string.row_recent_movies)
    val recentSeries = stringResource(R.string.row_recent_series)
    val forYou = HomeLabels(
        stringResource(R.string.row_top_picks),
        stringResource(R.string.row_new_for_you),
        stringResource(R.string.row_watch_again),
        stringResource(R.string.row_recommended),
    )
    var attempt by remember { mutableIntStateOf(0) }
    // A reload for a new ranking, or after a rating (rated titles leave the picks), keeps
    // the rows on screen until the new ones are in.
    var quiet by remember { mutableStateOf(false) }
    val ratings = catalog.ratingsVersion
    var ratingsSeen by remember { mutableIntStateOf(ratings) }
    val load by produceState<Load>(Load.Loading, source, hebrew, attempt, wtwEmail, ratings) {
        val keep = (quiet || ratings != ratingsSeen) && value is Load.Ready
        quiet = false
        ratingsSeen = ratings
        if (!keep) value = Load.Loading
        val next = runCatching {
            val rows = loadRows(catalog, source, hebrew, recentMovies, recentSeries, forYou, wtw = wtwEmail != null)
            // Genre names are a nicety: without them the meta line just has no genres.
            Load.Ready(rows, runCatching { catalog.genres() }.getOrDefault(emptyMap()))
        }.getOrElse { Load.Failed(it.message ?: it.toString()) }
        // A failed quiet reload leaves what is shown.
        if (!(keep && next is Load.Failed)) value = next
    }

    // Home shows its rows at once; with WTW connected it then has the server rank,
    // and reloads only when a new ranking was made (the server keeps one for an hour).
    if (source == BrowseSource.Home) {
        LaunchedEffect(Unit) {
            if (refreshRanking(app)) {
                quiet = true
                attempt++
            }
        }
    }

    when (val state = load) {
        Load.Loading -> Message(stringResource(R.string.loading), firstFocus, up)
        is Load.Failed -> Message(stringResource(R.string.load_failed, state.message), firstFocus, up, onRetry = { attempt++ })
        is Load.Ready -> {
            val home = source == BrowseSource.Home
            val w = watching
            val rows = remember(state.rows, w, home) {
                (if (home && w != null) listOfNotNull(continueRow(w, continueLabel, seasonEpisode)) else emptyList()) + state.rows
            }
            when {
                home && w == null -> Message(stringResource(R.string.loading), firstFocus, up)
                rows.isEmpty() -> Message(stringResource(R.string.nothing_here), firstFocus, up)
                else -> Rows(rows, state.genres, hebrew, firstFocus, up, tabsFocused, onMore, onOpen, onForYou)
            }
        }
    }
}

private const val CONTINUE_WAIT_MS = 5_000L
/** A first ranking takes about 10 s; after that the server answers at once. */
private const val RANKING_WAIT_MS = 30_000L

private class HomeLabels(val topPicks: String, val newForYou: String, val watchAgain: String, val recommended: String)

/**
 * With WTW connected, has the server rank the catalog; true when a new
 * ranking was made. A nicety: on failure or timeout Home keeps what it shows.
 */
private suspend fun refreshRanking(app: WtvApplication): Boolean {
    if (app.wtw.email == null) return false
    return withTimeoutOrNull(RANKING_WAIT_MS) {
        try {
            app.catalog.refreshRanking(app.wtw.token())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            false
        }
    } ?: false
}

/**
 * Continue watching as a row: a series' card names the episode to resume.
 * After a finished episode the card shows neither label nor bar: the next
 * episode is known only on the series page. Null when empty.
 */
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

/**
 * The page's rows. With WTW connected: Top picks and New for you on Home,
 * "Recommended for You" first on Movies and Series, and Watch it again from
 * the titles Loved or Liked in WTW. Without WTW, Watch it again holds what
 * the user finished. Empty rows are left out.
 */
private suspend fun loadRows(
    catalog: Catalog,
    source: BrowseSource,
    hebrew: Boolean,
    recentMovies: String,
    recentSeries: String,
    forYou: HomeLabels,
    wtw: Boolean,
): List<BrowseRow> =
    when (source) {
        BrowseSource.Home -> coroutineScope {
            val picks = async { if (wtw) catalog.topPicks() else emptyList() }
            val fresh = async { if (wtw) catalog.newForYou() else emptyList() }
            val movies = async { catalog.latest(Kind.Movie) }
            val series = async { catalog.latest(Kind.Series) }
            val again = async { if (wtw) catalog.watchAgain() else catalog.finishedTitles() }
            listOf(
                BrowseRow(forYou.topPicks, null, picks.await(), forYou = true),
                BrowseRow(forYou.newForYou, null, fresh.await()),
                BrowseRow(recentMovies, null, movies.await()),
                BrowseRow(recentSeries, null, series.await()),
                BrowseRow(forYou.watchAgain, null, again.await()),
            ).filter { it.titles.isNotEmpty() }
        }
        is BrowseSource.Section -> coroutineScope {
            // A nicety: when it fails, the section just has no Recommended row.
            val recommended = async { if (wtw) runCatching { catalog.topPicksPage(source.kind, 0, SECTION_PICKS) }.getOrDefault(emptyList()) else emptyList() }
            val rows = catalog.rows(source.kind).map { (c, titles) -> BrowseRow(c.label(hebrew), c, titles) }
            listOf(BrowseRow(forYou.recommended, null, recommended.await(), forYou = true, forYouKind = source.kind))
                .filter { it.titles.isNotEmpty() } + rows
        }
    }

/** Titles in a section's "Recommended for You" row, before its More card. */
private const val SECTION_PICKS = 10

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
    onForYou: (Kind?) -> Unit,
) {
    // Safe: empty rows are left out, and an empty page never gets here.
    // Kept when only Continue watching changes: the header stays on the focused card.
    var focused by remember { mutableStateOf(rows.first().titles.first()) }
    // A reload (retry, language) brings new title objects: the header moves to the first card.
    LaunchedEffect(rows) {
        if (rows.none { r -> r.titles.any { it.id == focused.id } }) focused = rows.first().titles.first()
    }
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
                                            onLongClick = LocalTitleMenu.current.let { menu -> { menu(t) } },
                                            onFocused = { focused = t },
                                            modifier = rowModifier.then(if (rowIndex == 0 && i == 0) Modifier.focusRequester(firstFocus) else Modifier),
                                        )
                                    }
                                    val category = row.category
                                    if (category != null || row.forYou) {
                                        item {
                                            LandscapeCard(
                                                imageUrl = null,
                                                title = stringResource(R.string.more),
                                                onClick = { if (category != null) onMore(category) else onForYou(row.forYouKind) },
                                                modifier = rowModifier,
                                            )
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
