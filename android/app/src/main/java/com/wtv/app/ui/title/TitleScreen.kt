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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.tv.material3.Button
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.CastMember
import com.wtv.app.data.Copy
import com.wtv.app.data.Genre
import com.wtv.app.data.Kind
import com.wtv.app.data.Title
import com.wtv.app.data.asCopy
import com.wtv.app.data.copyLabels
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.components.ActionIcon
import com.wtv.app.ui.components.Backdrop
import com.wtv.app.ui.components.HeroText
import com.wtv.app.ui.components.MetaRow
import com.wtv.app.ui.components.PersonCard
import com.wtv.app.ui.components.PlayButton
import com.wtv.app.ui.components.RowTitle
import com.wtv.app.ui.theme.WtvColors

private data class Extras(val cast: List<CastMember>, val copies: List<Copy>, val genres: Map<Pair<Kind, Int>, Genre>)

/**
 * A title's page: the header with Play and the title's actions, then its cast.
 * Episodes (series) and "Customers also liked" come with P2-7 and P4-5.
 */
@Composable
fun TitleScreen(title: Title, play: FocusRequester, onPlay: (Copy) -> Unit, onPerson: (CastMember) -> Unit) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    // Cast, copies and genres are extras: the page shows without them.
    val extras by produceState(Extras(emptyList(), emptyList(), emptyMap()), title.id) {
        value = coroutineScope {
            val cast = async { runCatching { catalog.cast(title.id) }.getOrDefault(emptyList()) }
            val copies = async { runCatching { catalog.copies(title) }.getOrDefault(emptyList()) }
            val genres = async { runCatching { catalog.genres() }.getOrDefault(emptyMap()) }
            Extras(cast.await(), copies.await(), genres.await())
        }
    }
    var choosing by remember { mutableStateOf(false) }
    var info by remember { mutableStateOf(false) }
    LaunchedEffect(title.id) { play.requestFocus() }

    Box(Modifier.fillMaxSize()) {
        Backdrop(title.heroImage)
        Column(Modifier.padding(start = 88.dp, top = 76.dp)) {
            HeroText(
                modifier = Modifier.width(560.dp),
                title = title.displayName(hebrew),
                meta = {
                    MetaRow(
                        items = listOfNotNull(
                            title.year?.toString(),
                            title.runtimeMin?.let { runtimeLabel(it) },
                            title.genreIds.mapNotNull { extras.genres[title.kind to it]?.label(hebrew) }.take(2).joinToString(" • ").ifEmpty { null },
                        ),
                        badges = listOfNotNull(title.certification, if (extras.copies.any { it.is4k }) "4K" else null),
                    )
                },
                synopsis = title.synopsis(hebrew),
                actions = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        PlayButton(
                            stringResource(R.string.play),
                            onClick = {
                                // Copies not loaded (yet, or the call failed): play this copy.
                                if (extras.copies.size > 1) choosing = true else onPlay(extras.copies.firstOrNull() ?: title.asCopy())
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
            if (extras.cast.isNotEmpty()) {
                Spacer(Modifier.height(32.dp))
                RowTitle(stringResource(R.string.row_cast))
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
