package com.wtv.app.ui.title

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.ThumbDown
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.platform.LocalContext
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
import com.wtv.app.data.Title
import com.wtv.app.data.asCopy
import com.wtv.app.data.copyLabels
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.components.ActionIcon
import com.wtv.app.ui.components.Backdrop
import com.wtv.app.ui.components.HeroText
import com.wtv.app.ui.components.LandscapeCard
import com.wtv.app.ui.components.MetaRow
import com.wtv.app.ui.components.PersonCard
import com.wtv.app.ui.components.PlayButton
import com.wtv.app.ui.components.RowTitle
import com.wtv.app.ui.components.RowsAtTop
import com.wtv.app.ui.components.Sideways
import com.wtv.app.ui.theme.WtvColors

private data class Extras(val cast: List<CastMember>, val copies: List<Copy>, val genres: Map<Pair<Kind, Int>, Genre>, val loaded: Boolean)

/**
 * A title's page: the header with Play and the title's actions; for a series
 * its seasons and episodes, the header following the focused episode; then the
 * cast. "Customers also liked" comes with P4-5.
 */
@Composable
fun TitleScreen(
    title: Title,
    play: FocusRequester,
    onPlay: (Copy) -> Unit,
    onPlayEpisode: (Episode) -> Unit,
    onPerson: (CastMember) -> Unit,
) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    // Cast, copies and genres are extras: the page shows without them.
    val extras by produceState(Extras(emptyList(), emptyList(), emptyMap(), loaded = false), title.id) {
        value = coroutineScope {
            val cast = async { orDefault(emptyList()) { catalog.cast(title.id) } }
            val copies = async { orDefault(emptyList()) { catalog.copies(title) } }
            val genres = async { orDefault(emptyMap()) { catalog.genres() } }
            Extras(cast.await(), copies.await(), genres.await(), loaded = true)
        }
    }
    var choosing by remember { mutableStateOf(false) }
    // Play pressed before the copies arrived: answered once they do, so a 4K copy is not skipped.
    var playPending by remember(title.id) { mutableStateOf(false) }
    fun play() {
        // Copies failed to load: play this copy.
        if (extras.copies.size > 1) choosing = true else onPlay(extras.copies.firstOrNull() ?: title.asCopy())
    }
    LaunchedEffect(extras.loaded, playPending) {
        if (extras.loaded && playPending) {
            playPending = false
            play()
        }
    }
    var info by remember { mutableStateOf(false) }
    LaunchedEffect(title.id) { play.requestFocus() }

    // Series: the episodes, a season at a time; the header shows the focused episode.
    // Null until loaded.
    val episodes by produceState<List<Episode>?>(if (title.kind == Kind.Series) null else emptyList(), title.id) {
        if (title.kind == Kind.Series) value = orDefault(emptyList()) { catalog.episodes(title.id) }
    }
    val allEpisodes = episodes.orEmpty()
    val seasons = remember(allEpisodes) { allEpisodes.map { it.season }.distinct() }
    var season by remember(title.id) { mutableStateOf<Int?>(null) }
    val shownSeason = season ?: seasons.firstOrNull()
    val seasonEpisodes = remember(allEpisodes, shownSeason) { allEpisodes.filter { it.season == shownSeason } }
    // Play on a series pressed before the episodes arrived: answered once they do.
    var episodePending by remember(title.id) { mutableStateOf(false) }
    LaunchedEffect(episodes, episodePending) {
        if (episodes != null && episodePending) {
            episodePending = false
            seasonEpisodes.firstOrNull()?.let(onPlayEpisode)
        }
    }
    var episode by remember(title.id) { mutableStateOf<Episode?>(null) }
    // Focus outside the episodes row: the header is the title's again.
    val showsTitle = Modifier.onFocusChanged { if (it.hasFocus) episode = null }

    Box(Modifier.fillMaxSize()) {
        Backdrop(title.heroImage)
        Column(Modifier.padding(start = 88.dp, top = 64.dp)) {
            // Fixed height: the rows do not jump when the header text changes.
            Box(Modifier.height(300.dp)) {
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
                                stringResource(R.string.play),
                                onClick = {
                                    // TODO(P3-2): series resume at the next episode to watch.
                                    when {
                                        title.kind != Kind.Series -> if (extras.loaded) play() else playPending = true
                                        episodes == null -> episodePending = true
                                        else -> seasonEpisodes.firstOrNull()?.let(onPlayEpisode)
                                    }
                                },
                                modifier = Modifier.focusRequester(play),
                            )
                            Spacer(Modifier.width(12.dp))
                            // TODO(P4-2): watchlist and ratings are stored with the ratings work.
                            ActionIcon(Icons.Outlined.Add, stringResource(R.string.add_to_watchlist), onClick = {})
                            ActionIcon(Icons.Outlined.FavoriteBorder, stringResource(R.string.rate_love), onClick = {})
                            ActionIcon(Icons.Outlined.ThumbUp, stringResource(R.string.rate_like), onClick = {})
                            ActionIcon(Icons.Outlined.ThumbDown, stringResource(R.string.rate_dislike), onClick = {})
                            ActionIcon(Icons.Outlined.Info, stringResource(R.string.more_info), onClick = { info = true })
                        }
                    },
                )
            }
            // The episodes row's title line holds the season chips: more room above its cards.
            RowsAtTop(titleSpaceDp = 58.dp) {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                    contentPadding = PaddingValues(top = 8.dp, bottom = 400.dp),
                ) {
                    if (seasonEpisodes.isNotEmpty()) {
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
                                                LandscapeCard(
                                                    imageUrl = e.image ?: title.cardImage,
                                                    title = e.displayName(hebrew) ?: stringResource(R.string.episode_number, e.number),
                                                    label = stringResource(R.string.episode_number, e.number),
                                                    onClick = { onPlayEpisode(e) },
                                                    onFocused = { episode = e },
                                                )
                                        }
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
                                            PersonCard(imageUrl = c.photo, name = c.name, onClick = { onPerson(c) })
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
        CopyChooser(extras.copies, onChoose = { choosing = false; onPlay(it) }, onDismiss = { choosing = false })
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
