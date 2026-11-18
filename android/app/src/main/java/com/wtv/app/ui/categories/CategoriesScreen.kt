package com.wtv.app.ui.categories

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
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
import com.wtv.app.data.Kind
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.theme.WtvColors

/**
 * Side bar → Categories, for movies or series: the provider's categories,
 * then the genres. A tag opens its full grid, as More does at a row's end.
 */
@OptIn(ExperimentalLayoutApi::class, ExperimentalTvMaterial3Api::class) // FlowRow, FilterChip
@Composable
fun CategoriesScreen(kind: Kind, firstFocus: FocusRequester, onOpen: (Category) -> Unit) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    // Null until loaded; a group that fails to load is left out.
    val groups by produceState<List<Pair<Int, List<Category>>>?>(null, kind, hebrew) {
        val providers = runCatching { catalog.categories(kind) }.getOrDefault(emptyList())
        val genres = runCatching { catalog.genreCategories(kind, hebrew) }.getOrDefault(emptyList())
        value = listOf(R.string.categories_providers to providers, R.string.categories_genres to genres).filter { it.second.isNotEmpty() }
    }
    Column(Modifier.fillMaxSize().padding(start = 88.dp, end = 48.dp, top = 48.dp).verticalScroll(rememberScrollState())) {
        Text(stringResource(R.string.rail_categories), style = MaterialTheme.typography.displayMedium, color = WtvColors.TextPrimary)
        val shown = groups ?: return@Column
        if (shown.isEmpty()) {
            Spacer(Modifier.height(24.dp))
            Text(stringResource(R.string.nothing_here), style = MaterialTheme.typography.titleMedium, color = WtvColors.TextMuted)
            return@Column
        }
        shown.forEachIndexed { g, (label, tags) ->
            Spacer(Modifier.height(28.dp))
            Text(stringResource(label), style = MaterialTheme.typography.titleMedium, color = WtvColors.TextSecondary)
            Spacer(Modifier.height(12.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                tags.forEachIndexed { i, c ->
                    FilterChip(
                        selected = false,
                        onClick = { onOpen(c) },
                        modifier = if (g == 0 && i == 0) Modifier.focusRequester(firstFocus) else Modifier,
                    ) { Text(c.label(hebrew)) }
                }
            }
        }
        Spacer(Modifier.height(48.dp))
        // The tags arrive after the page opened: the first one takes the focus then.
        LaunchedEffect(Unit) { runCatching { firstFocus.requestFocus() } }
    }
}
