package com.wtv.app.ui.search

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
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
import androidx.compose.ui.unit.dp
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.R
import com.wtv.app.WtvApplication
import com.wtv.app.data.Title
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.components.PosterCard
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

/** Wait this long after the last key before searching. */
private const val TYPING_PAUSE_MS = 350L

private sealed interface Results {
    data object Idle : Results
    data object Searching : Results
    /** `query` is the one searched, which the field may have moved on from. */
    data class Found(val query: String, val titles: List<Title>) : Results
    data class Failed(val message: String) : Results
}

/**
 * Text search over the provider's titles, in English or Hebrew. The field
 * opens the TV's keyboard; results show as posters below it.
 */
@Composable
fun SearchScreen(field: FocusRequester, onOpen: (Title) -> Unit) {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    var query by rememberSaveable { mutableStateOf("") }
    var results by remember { mutableStateOf<Results>(Results.Idle) }
    var fieldFocused by remember { mutableStateOf(false) }
    val firstResult = remember { FocusRequester() }
    // The keyboard's Search key: search now, without the typing pause, and move to the results when they arrive.
    var searchNow by remember { mutableIntStateOf(0) }
    var seenSearchNow by remember { mutableIntStateOf(0) }
    var focusResults by remember { mutableStateOf(false) }

    // A new query cancels the search of the previous one.
    LaunchedEffect(query, hebrew, searchNow) {
        if (query.isBlank()) {
            results = Results.Idle
            return@LaunchedEffect
        }
        if (searchNow == seenSearchNow) delay(TYPING_PAUSE_MS)
        seenSearchNow = searchNow
        // Earlier results stay on screen until the new ones arrive: no flicker while typing.
        if (results !is Results.Found) results = Results.Searching
        results = try {
            Results.Found(query.trim(), catalog.search(query, hebrew))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Results.Failed(e.message ?: e.toString())
        }
    }

    LaunchedEffect(results) {
        val r = results
        if (focusResults && r is Results.Found) {
            focusResults = false
            if (r.titles.isNotEmpty()) runCatching { firstResult.requestFocus() }
        }
    }

    Column(Modifier.fillMaxSize().padding(start = 88.dp, end = 48.dp, top = 48.dp)) {
        BasicTextField(
            value = query,
            onValueChange = { query = it },
            singleLine = true,
            textStyle = MaterialTheme.typography.headlineMedium.copy(color = WtvColors.TextPrimary),
            cursorBrush = SolidColor(WtvColors.TextPrimary),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            // The keyboard's Search key moves on to the results.
            keyboardActions = KeyboardActions(onSearch = {
                val shown = results
                if (shown is Results.Found && shown.query == query.trim() && shown.titles.isNotEmpty()) {
                    runCatching { firstResult.requestFocus() }
                } else {
                    focusResults = true
                    searchNow++
                }
            }),
            modifier = Modifier
                .width(640.dp)
                .focusRequester(field)
                // A text field keeps Down for its cursor; on a TV Down means "to the results".
                .onPreviewKeyEvent {
                    if (it.type == KeyEventType.KeyDown && it.key == Key.DirectionDown) {
                        runCatching { firstResult.requestFocus() }.getOrDefault(false)
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
                    if (query.isEmpty()) {
                        Text(stringResource(R.string.search_hint), style = MaterialTheme.typography.headlineMedium, color = WtvColors.TextMuted)
                    }
                    inner()
                }
            },
        )
        Spacer(Modifier.height(24.dp))
        when (val r = results) {
            Results.Idle -> Unit
            Results.Searching -> Note(stringResource(R.string.searching))
            is Results.Failed -> Note(stringResource(R.string.load_failed, r.message))
            is Results.Found ->
                if (r.titles.isEmpty()) Note(stringResource(R.string.no_results, r.query))
                else LazyVerticalGrid(
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
                            modifier = Modifier
                                .then(if (i == 0) Modifier.focusRequester(firstResult) else Modifier)
                                // Up from the first row goes back to the field.
                                .then(if (i < 6) Modifier.focusProperties { up = field } else Modifier),
                        )
                    }
                }
        }
    }
}

@Composable
private fun Note(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, color = WtvColors.TextMuted)
}
