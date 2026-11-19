package com.wtv.app.ui.title

import android.util.Log
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material.icons.outlined.Replay
import androidx.compose.material.icons.outlined.ThumbDown
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.tv.material3.Button
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.FilterChip
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.CastMember
import com.wtv.app.data.Copy
import com.wtv.app.data.Episode
import com.wtv.app.data.Genre
import com.wtv.app.data.Kind
import com.wtv.app.data.Marks
import com.wtv.app.data.Progress
import com.wtv.app.data.Rating
import com.wtv.app.data.Title
import com.wtv.app.data.asCopy
import com.wtv.app.data.copyLabels
import com.wtv.app.data.nextEpisode
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.components.LocalTitleMenu
import com.wtv.app.ui.components.ActionDivider
import com.wtv.app.ui.components.ActionIcon
import com.wtv.app.ui.components.Backdrop
import com.wtv.app.ui.components.HeaderHeight
import com.wtv.app.ui.components.HeaderTop
import com.wtv.app.ui.components.HeroText
import com.wtv.app.ui.components.MatchBadge
import com.wtv.app.ui.components.LandscapeCard
import com.wtv.app.ui.components.MetaRow
import com.wtv.app.ui.components.PersonCard
import com.wtv.app.ui.components.PlayButton
import com.wtv.app.ui.components.RowTitle
import com.wtv.app.ui.components.RowsAtTop
import com.wtv.app.ui.components.Sideways
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

private data class Extras(
    val cast: List<CastMember>,
    val copies: List<Copy>,
    val genres: Map<Pair<Kind, Int>, Genre>,
    val loaded: Boolean,
    val alsoLiked: List<Title> = emptyList(),
)

/**
 * A title's page: the header with Play and the title's actions; for a series
 * its seasons and episodes, the header following the focused episode; then the
 * cast. "Customers also liked" comes with P4-5.
 *
 * Play resumes: a movie where it stopped, a series at its next episode. The
 * saved positions reload when `progressVersion` changes (a player closed).
 * `onPlay` and `onPlayEpisode` take the second to start at.
 */
@Composable
fun TitleScreen(
    title: Title,
    /** Press Play as soon as the page opens (Play from a card's menu). */
    autoPlay: Boolean = false,
    play: FocusRequester,
    progressVersion: Int,
    onPlay: (Copy, Int) -> Unit,
    /** The episode, the second to start at, and the series' episodes in order (for the next one). */
    onPlayEpisode: (Episode, Int, List<Episode>) -> Unit,
    onPerson: (CastMember) -> Unit,
    onOpen: (Title) -> Unit,
    /** Saved positions were removed: the pages showing them reload. */
    onProgressCleared: () -> Unit,
) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    // Cast, copies and genres are extras: the page shows without them.
    val extras by produceState(Extras(emptyList(), emptyList(), emptyMap(), loaded = false), title.id) {
        value = coroutineScope {
            val cast = async { orDefault(emptyList()) { catalog.cast(title.id) } }
            val copies = async { orDefault(emptyList()) { catalog.copies(title) } }
            val genres = async { orDefault(emptyMap()) { catalog.genres() } }
            val alsoLiked = async { orDefault(emptyList()) { catalog.alsoLiked(title) } }
            Extras(cast.await(), copies.await(), genres.await(), loaded = true, alsoLiked = alsoLiked.await())
        }
    }
    // Saved positions, newest first; null until first loaded. A failed load counts as none.
    val progress by produceState<List<Progress>?>(null, title.id, progressVersion) {
        value = orDefault(emptyList()) { catalog.progress(title) }
    }
    val movieStart = progress.orEmpty().firstOrNull { !it.isEpisode }?.resumeSecs ?: 0
    // The second Play starts at: chosen with Play or Start over, used by the copy chooser.
    var start by remember { mutableStateOf(0) }
    var choosing by remember { mutableStateOf(false) }
    // Play pressed before the copies (or positions) arrived: answered once they do, so a 4K copy is not skipped.
    var playPending by remember(title.id) { mutableStateOf<Int?>(null) }
    fun play(from: Int) {
        start = from
        // Copies failed to load: play this copy.
        if (extras.copies.size > 1) choosing = true else onPlay(extras.copies.firstOrNull() ?: title.asCopy(), from)
    }
    LaunchedEffect(extras.loaded, progress, playPending) {
        val pending = playPending
        if (extras.loaded && progress != null && pending != null) {
            playPending = null
            // -1: Play pressed, start where the movie stopped.
            play(if (pending < 0) movieStart else pending)
        }
    }
    var info by remember { mutableStateOf(false) }
    LaunchedEffect(title.id) { play.requestFocus() }

    // Rating and watchlist: shown at once, saved one at a time in the order pressed,
    // and put back to what it was if the save fails (unless a later press changed it).
    // A rating pressed again is cleared.
    val scope = rememberCoroutineScope()
    val saving = remember { Mutex() }
    var marks by remember(title.id) { mutableStateOf(Marks()) }
    var touched by remember(title.id) { mutableStateOf(false) }
    LaunchedEffect(title.id) {
        // A press before the load came in wins over the loaded value.
        runCatching { catalog.marks(title) }.onSuccess { if (!touched) marks = it }
    }
    fun rate(r: Rating) {
        touched = true
        val before = marks.rating
        val to = if (before == r) null else r
        marks = marks.copy(rating = to)
        scope.launch {
            saving.withLock {
                runCatching { catalog.setRating(title, to) }.onFailure { if (marks.rating == to) marks = marks.copy(rating = before) }
            }
        }
    }
    fun toggleWatchlist() {
        touched = true
        val to = !marks.onWatchlist
        marks = marks.copy(onWatchlist = to)
        scope.launch {
            saving.withLock {
                runCatching { catalog.setWatchlist(title, to) }.onFailure { if (marks.onWatchlist == to) marks = marks.copy(onWatchlist = !to) }
            }
        }
    }

    // Series: the episodes, a season at a time; the header shows the focused episode.
    // Null until loaded.
    val episodes by produceState<List<Episode>?>(if (title.kind == Kind.Series) null else emptyList(), title.id) {
        if (title.kind == Kind.Series) value = orDefault(emptyList()) { catalog.episodes(title) }
    }
    val allEpisodes = episodes.orEmpty()
    val seasons = remember(allEpisodes) { allEpisodes.map { it.season }.distinct() }
    var season by remember(title.id) { mutableStateOf<Int?>(null) }
    val shownSeason = season ?: seasons.firstOrNull()
    val seasonEpisodes = remember(allEpisodes, shownSeason) { allEpisodes.filter { it.season == shownSeason } }
    val next = remember(allEpisodes, progress) { nextEpisode(allEpisodes, progress.orEmpty()) }
    // Episode positions by season and number: the bar on each card, and where it starts.
    val watched = remember(progress) { progress.orEmpty().filter { it.isEpisode }.distinctBy { it.season to it.episode }.associateBy { it.season to it.episode } }
    // Play on a series pressed before the episodes (or positions) arrived: answered once they do.
    var episodePending by remember(title.id) { mutableStateOf(false) }
    LaunchedEffect(episodes, progress, episodePending) {
        if (episodes != null && progress != null && episodePending) {
            episodePending = false
            next?.let { onPlayEpisode(it.episode, it.startSecs, allEpisodes) }
        }
    }
    // What the Play button says: Resume, "Play S1 E4" for the next episode, or Play.
    val resuming = if (title.kind == Kind.Series) (next?.startSecs ?: 0) > 0 else movieStart > 0
    val playLabel = when {
        resuming -> stringResource(R.string.resume)
        next != null && next.episode != allEpisodes.firstOrNull() ->
            stringResource(R.string.play_episode, stringResource(R.string.season_episode, next.episode.season, next.episode.number))
        else -> stringResource(R.string.play)
    }
    // Play: what is not loaded yet is waited for (the pending flags), then played.
    fun pressPlay() {
        when {
            title.kind != Kind.Series -> if (extras.loaded && progress != null) play(movieStart) else playPending = -1
            episodes == null || progress == null -> episodePending = true
            else -> next?.let { onPlayEpisode(it.episode, it.startSecs, allEpisodes) }
        }
    }
    LaunchedEffect(title.id) { if (autoPlay) pressPlay() }
    var episode by remember(title.id) { mutableStateOf<Episode?>(null) }
    // Focus outside the episodes row: the header is the title's again.
    val showsTitle = Modifier.onFocusChanged { if (it.hasFocus) episode = null }

    Box(Modifier.fillMaxSize()) {
        Backdrop(title.heroImage)
        Column(Modifier.padding(start = 88.dp, top = HeaderTop)) {
            // Fixed height: the rows do not jump when the header text changes. Below the
            // browse header's text: the actions, and the focused action's name under them.
            Box(Modifier.fillMaxWidth().padding(end = 64.dp).height(HeaderHeight + 92.dp)) {
                wtwMatch(title)?.let { MatchBadge(it, Modifier.align(AbsoluteAlignment.TopRight)) }
                val e = episode
                HeroText(
                    modifier = Modifier.width(560.dp),
                    titleMaxLines = 1,
                    title = e?.let { it.displayName(hebrew) ?: stringResource(R.string.episode_number, it.number) } ?: title.displayName(hebrew),
                    meta = {
                        MetaRow(
                            items = if (e != null) {
                                listOfNotNull(
                                    stringResource(R.string.season_episode, e.season, e.number),
                                    e.durationSecs?.let { runtimeLabel(it / 60) },
                                    title.year?.toString(),
                                )
                            } else {
                                listOfNotNull(
                                    seasons.size.takeIf { it > 1 }?.let { pluralStringResource(R.plurals.seasons, it, it) },
                                    title.year?.toString(),
                                    title.runtimeMin?.let { runtimeLabel(it) }.takeIf { title.kind == Kind.Movie },
                                    title.genreIds.mapNotNull { extras.genres[title.kind to it]?.label(hebrew) }.take(2).joinToString(" • ").ifEmpty { null },
                                )
                            },
                            badges = listOfNotNull(title.certification, if (extras.copies.any { it.is4k }) "4K" else null),
                        )
                    },
                    synopsis = e?.synopsis(hebrew) ?: title.synopsis(hebrew),
                    actions = {
                        Row(showsTitle, verticalAlignment = Alignment.CenterVertically) {
                            PlayButton(
                                playLabel,
                                onClick = ::pressPlay,
                                modifier = Modifier.focusRequester(play),
                            )
                            Spacer(Modifier.width(12.dp))
                            if (resuming) {
                                ActionIcon(
                                    Icons.Outlined.Replay,
                                    stringResource(R.string.start_over),
                                    onClick = {
                                        if (title.kind == Kind.Series) next?.let { onPlayEpisode(it.episode, 0, allEpisodes) }
                                        else if (extras.loaded) play(0) else playPending = 0
                                    },
                                )
                            }
                            ActionIcon(
                                if (marks.onWatchlist) Icons.Outlined.Check else Icons.Outlined.Add,
                                stringResource(if (marks.onWatchlist) R.string.remove_from_watchlist else R.string.add_to_watchlist),
                                onClick = ::toggleWatchlist,
                                selected = marks.onWatchlist,
                            )
                            if (progress.orEmpty().isNotEmpty()) {
                                ActionIcon(
                                    Icons.Outlined.RemoveCircleOutline,
                                    stringResource(R.string.remove_from_continue),
                                    onClick = {
                                        // The button goes away: the focus moves to Play first, not to the tabs.
                                        play.requestFocus()
                                        val ids = progress.orEmpty().map { it.titleId }.toSet()
                                        scope.launch {
                                            runCatching { catalog.clearProgress(ids) }
                                                .onSuccess { onProgressCleared() }
                                                .onFailure { Log.w("WtvProgress", "Removing the positions failed: ${it.message}") }
                                        }
                                    },
                                )
                            }
                            ActionIcon(Icons.Outlined.Info, stringResource(R.string.more_info), onClick = { info = true })
                            // The ratings stand apart from the title's actions.
                            ActionDivider()
                            ActionIcon(
                                if (marks.rating == Rating.Love) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                                stringResource(R.string.rate_love),
                                onClick = { rate(Rating.Love) },
                                selected = marks.rating == Rating.Love,
                            )
                            ActionIcon(
                                if (marks.rating == Rating.Like) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp,
                                stringResource(R.string.rate_like),
                                onClick = { rate(Rating.Like) },
                                selected = marks.rating == Rating.Like,
                            )
                            ActionIcon(
                                if (marks.rating == Rating.Dislike) Icons.Filled.ThumbDown else Icons.Outlined.ThumbDown,
                                stringResource(R.string.rate_dislike),
                                onClick = { rate(Rating.Dislike) },
                                selected = marks.rating == Rating.Dislike,
                            )
                        }
                    },
                )
            }
            // The episodes row's title line holds the season chips: more room above its cards.
            RowsAtTop(titleSpaceDp = 58.dp) {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    contentPadding = PaddingValues(top = 8.dp, bottom = 400.dp),
                ) {
                    // A series' row is there from the start, empty while loading: the list keeps
                    // its place by the first item, so a row inserted later above the cast
                    // would land off screen.
                    if (seasonEpisodes.isNotEmpty() || (title.kind == Kind.Series && episodes == null)) {
                        item(key = "episodes") {
                            Column {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    RowTitle(stringResource(R.string.row_episodes))
                                    if (seasons.size > 1) {
                                        Spacer(Modifier.width(20.dp))
                                        // On the chips the header is the series' again.
                                        Box(showsTitle) { SeasonChips(seasons, shownSeason, onSeason = { season = it }) }
                                    }
                                }
                                // A new row per season: it starts at episode 1, not at the old scroll position.
                                key(shownSeason) {
                                    Sideways {
                                        LazyRow(
                                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                                            contentPadding = PaddingValues(end = 48.dp, top = 6.dp, bottom = 6.dp),
                                        ) {
                                            items(seasonEpisodes, key = { it.id }) { e ->
                                                val saved = watched[e.season to e.number]
                                                LandscapeCard(
                                                    imageUrl = e.image ?: title.cardImage,
                                                    title = e.displayName(hebrew) ?: stringResource(R.string.episode_number, e.number),
                                                    label = stringResource(R.string.episode_number, e.number),
                                                    progress = saved?.fraction,
                                                    onClick = { onPlayEpisode(e, saved?.resumeSecs ?: 0, allEpisodes) },
                                                    onFocused = { episode = e },
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // Loaded with the cast, so it never lands above a row already on screen.
                    if (extras.alsoLiked.isNotEmpty()) {
                        item(key = "alsoLiked") {
                            Column(showsTitle) {
                                RowTitle(stringResource(R.string.row_also_liked))
                                Sideways {
                                    LazyRow(
                                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                                        contentPadding = PaddingValues(end = 48.dp, top = 6.dp, bottom = 6.dp),
                                    ) {
                                        items(extras.alsoLiked, key = { it.id }) { t ->
                                            // The name on the image: the picture alone does not tell titles apart.
                                            LandscapeCard(imageUrl = t.cardImage, title = t.displayName(hebrew), onClick = { onOpen(t) }, label = t.displayName(hebrew), onLongClick = LocalTitleMenu.current.let { menu -> { menu(t) } })
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if (extras.cast.isNotEmpty()) {
                        item(key = "cast") {
                            Column(showsTitle) {
                                RowTitle(stringResource(R.string.row_cast))
                                Sideways {
                                    LazyRow(
                                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                                        contentPadding = PaddingValues(end = 48.dp, top = 6.dp, bottom = 6.dp),
                                    ) {
                                        items(extras.cast, key = { it.personId }) { c ->
                                            PersonCard(imageUrl = c.photo, name = c.name, onClick = { onPerson(c) }, label = c.name)
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

    if (choosing) {
        CopyChooser(extras.copies, onChoose = { choosing = false; onPlay(it, start) }, onDismiss = { choosing = false })
    }
    if (info) {
        MoreInfo(title, extras.cast, hebrew, onDismiss = { info = false })
    }
}

@Composable
private fun runtimeLabel(minutes: Int): String =
    if (minutes >= 60) stringResource(R.string.runtime_hours, minutes / 60, minutes % 60) else stringResource(R.string.runtime_minutes, minutes)

/** "Play in 4K / HD": one button per copy, the first (4K if any) focused. */
@Composable
private fun CopyChooser(copies: List<Copy>, onChoose: (Copy) -> Unit, onDismiss: () -> Unit) {
    val first = remember { FocusRequester() }
    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier.background(WtvColors.Surface, RoundedCornerShape(12.dp)).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(stringResource(R.string.choose_copy), style = MaterialTheme.typography.titleMedium, color = WtvColors.TextPrimary)
            copies.zip(copyLabels(copies)).forEachIndexed { i, (c, label) ->
                Button(onClick = { onChoose(c) }, modifier = if (i == 0) Modifier.focusRequester(first) else Modifier) { Text(label) }
            }
        }
    }
    LaunchedEffect(Unit) { first.requestFocus() }
}

/** Full synopsis and credits. */
@Composable
private fun MoreInfo(title: Title, cast: List<CastMember>, hebrew: Boolean, onDismiss: () -> Unit) {
    val close = remember { FocusRequester() }
    Dialog(onDismissRequest = onDismiss) {
        Column(
            Modifier.width(620.dp).background(WtvColors.Surface, RoundedCornerShape(12.dp)).padding(28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(title.displayName(hebrew), style = MaterialTheme.typography.headlineMedium, color = WtvColors.TextPrimary)
            title.synopsis(hebrew)?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = WtvColors.TextSecondary) }
            val castLine = cast.take(8).joinToString(", ") { it.name }.ifEmpty { title.castNames.orEmpty() }
            listOfNotNull(
                title.director?.let { stringResource(R.string.info_director) to it },
                castLine.takeIf { it.isNotEmpty() }?.let { stringResource(R.string.info_cast) to it },
                title.originalLanguage?.let { stringResource(R.string.info_language) to it.uppercase() },
                title.tmdbRating?.let { stringResource(R.string.info_rating) to stringResource(R.string.info_rating_value, it) },
            ).forEach { (label, value) ->
                Text("$label: $value", style = MaterialTheme.typography.bodyMedium, color = WtvColors.TextSecondary)
            }
            Button(onClick = onDismiss, modifier = Modifier.focusRequester(close)) { Text(stringResource(R.string.close)) }
        }
    }
    LaunchedEffect(Unit) { close.requestFocus() }
}

/** Season choices next to the episodes row title. Moving onto one shows that season. */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun SeasonChips(seasons: List<Int>, shown: Int?, onSeason: (Int) -> Unit) {
    Sideways {
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(bottom = 10.dp)) {
            items(seasons, key = { it }) { n ->
                FilterChip(
                    selected = n == shown,
                    onClick = { onSeason(n) },
                    modifier = Modifier.onFocusChanged { if (it.isFocused && n != shown) onSeason(n) },
                ) { Text(stringResource(R.string.season_number, n)) }
            }
        }
    }
}

/** The value of `block`, or `default` if it fails; cancellation is not a failure. */
private suspend fun <T> orDefault(default: T, block: suspend () -> T): T =
    try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        default
    }

/** WTW's own "% match" for the title while WTW is connected on this device; asked for when not known yet. */
@Composable
private fun wtwMatch(title: Title): Int? {
    val app = LocalContext.current.applicationContext as WtvApplication
    val connected = remember { app.wtw.email != null }
    LaunchedEffect(title.id, connected) { if (connected && title.match == null) app.wtwScores.request(listOf(title.id)) }
    return if (connected) app.wtwScores[title.id] ?: title.match else null
}
