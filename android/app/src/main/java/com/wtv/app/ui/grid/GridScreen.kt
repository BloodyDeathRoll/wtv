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
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
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
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.FilterChip
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.Category
import com.wtv.app.data.Sort
import com.wtv.app.data.Title
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.components.Backdrop
import com.wtv.app.ui.components.PosterCard
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.launch

private const val PAGE = 60
private const val COLUMNS = 6

/** Load the next page when the focus gets this close to the end. */
private const val PRELOAD = 2 * COLUMNS

/**
 * A whole category as a poster grid, with a choice of order. The focused
 * title's name and backdrop show above the grid.
 */
@OptIn(ExperimentalTvMaterial3Api::class) // FilterChip
@Composable
fun GridScreen(category: Category, firstFocus: FocusRequester, onOpen: (Title) -> Unit) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    val scope = rememberCoroutineScope()

    var sort by rememberSaveable { mutableStateOf(Sort.Added) }
    val titles = remember(sort, hebrew) { mutableStateListOf<Title>() }
    var end by remember(sort, hebrew) { mutableStateOf(false) }
    var loading by remember(sort, hebrew) { mutableStateOf(false) }
    var error by remember(sort, hebrew) { mutableStateOf<String?>(null) }
    var focused by remember(sort, hebrew) { mutableStateOf<Title?>(null) }
    val chips = remember { FocusRequester() }

    fun loadMore() {
        if (loading || end) return
        loading = true
        scope.launch {
            runCatching { catalog.page(category, sort, hebrew, titles.size, PAGE) }
                .onSuccess {
                    titles.addAll(it)
                    if (it.size < PAGE) end = true
                    if (focused == null) focused = it.firstOrNull()
                    error = null
                }
                .onFailure { error = it.message ?: it.toString() }
            loading = false
        }
    }
    LaunchedEffect(sort, hebrew) { loadMore() }

    // The loading message held the focus; when the first page arrives, the first
    // poster takes it. Only on opening: after a sort change the focus stays on the chips.
    var placed by remember { mutableStateOf(false) }
    LaunchedEffect(titles.isNotEmpty()) {
        if (titles.isNotEmpty() && !placed) {
            placed = true
            firstFocus.requestFocus()
        }
    }

    Box(Modifier.fillMaxSize()) {
        Backdrop(focused?.heroImage)
        Column(Modifier.padding(start = 88.dp, end = 48.dp, top = 40.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(category.label(hebrew), style = MaterialTheme.typography.headlineMedium, color = WtvColors.TextPrimary)
                Spacer(Modifier.padding(start = 24.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Sort.entries.forEachIndexed { i, s ->
                        FilterChip(
                            selected = s == sort,
                            onClick = { sort = s },
                            modifier = if (i == 0) Modifier.focusRequester(chips) else Modifier,
                        ) { Text(stringResource(s.label)) }
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            // The focused title, in one line: the grid has no room for a full header.
            Text(
                focused?.let { t -> listOfNotNull(t.displayName(hebrew), t.year?.toString(), t.certification).joinToString("   ") } ?: " ",
                style = MaterialTheme.typography.titleSmall,
                color = WtvColors.TextSecondary,
                maxLines = 1,
            )
            Spacer(Modifier.height(12.dp))
            when {
                titles.isEmpty() && error != null -> Message(stringResource(R.string.load_failed, error!!), firstFocus)
                titles.isEmpty() && end -> Message(stringResource(R.string.nothing_here), firstFocus)
                titles.isEmpty() -> Message(stringResource(R.string.loading), firstFocus)
                else -> LazyVerticalGrid(
                    columns = GridCells.Fixed(COLUMNS),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                    contentPadding = PaddingValues(top = 6.dp, bottom = 48.dp),
                ) {
                    itemsIndexed(titles, key = { _, t -> t.id }) { i, t ->
                        PosterCard(
                            imageUrl = t.posterImage,
                            title = t.displayName(hebrew),
                            onClick = { onOpen(t) },
                            onFocused = {
                                focused = t
                                if (i >= titles.size - PRELOAD) loadMore()
                            },
                            modifier = Modifier
                                .then(if (i == 0) Modifier.focusRequester(firstFocus) else Modifier)
                                // Up from the first row goes to the sort chips.
                                .then(if (i < COLUMNS) Modifier.focusProperties { up = chips } else Modifier),
                        )
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

@Composable
private fun Message(text: String, focus: FocusRequester) {
    Box(Modifier.fillMaxSize().focusRequester(focus).focusable(), contentAlignment = Alignment.TopStart) {
        Text(text, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextMuted)
    }
}
