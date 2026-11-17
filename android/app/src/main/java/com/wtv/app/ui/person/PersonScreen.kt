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
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.CastMember
import com.wtv.app.data.Title
import com.wtv.app.ui.browse.isHebrew
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
    val hebrew = isHebrew()
    val load by produceState<Load>(Load.Loading, person.personId) {
        value = try {
            Load.Ready(catalog.personTitles(person.personId))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Load.Failed(e.message ?: e.toString())
        }
    }

    Column(Modifier.fillMaxSize().padding(start = 88.dp, end = 48.dp, top = 48.dp)) {
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
                val state = load
                if (state is Load.Ready) {
                    Text(
                        pluralStringResource(R.plurals.person_titles, state.titles.size, state.titles.size),
                        style = MaterialTheme.typography.titleSmall,
                        color = WtvColors.TextSecondary,
                    )
                }
            }
        }
        Spacer(Modifier.height(24.dp))
        when (val state = load) {
            Load.Loading -> Message(stringResource(R.string.loading), firstFocus)
            is Load.Failed -> Message(stringResource(R.string.load_failed, state.message), firstFocus)
            is Load.Ready ->
                if (state.titles.isEmpty()) Message(stringResource(R.string.nothing_here), firstFocus)
                else {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(6),
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        verticalArrangement = Arrangement.spacedBy(18.dp),
                        contentPadding = PaddingValues(top = 6.dp, bottom = 48.dp),
                    ) {
                        itemsIndexed(state.titles, key = { _, t -> t.id }) { i, t ->
                            PosterCard(
                                imageUrl = t.posterImage,
                                title = t.displayName(hebrew),
                                onClick = { onOpen(t) },
                                modifier = if (i == 0) Modifier.focusRequester(firstFocus) else Modifier,
                            )
                        }
                    }
                    // The loading message held the focus; the first poster takes it.
                    LaunchedEffect(Unit) { runCatching { firstFocus.requestFocus() } }
                }
        }
    }
}

@Composable
private fun Message(text: String, focus: FocusRequester) {
    Box(Modifier.fillMaxSize().focusRequester(focus).focusable()) {
        Text(text, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextMuted)
    }
}
