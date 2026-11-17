package com.wtv.app.ui.showcase

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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.ThumbDown
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.wtv.app.R
import com.wtv.app.ui.TmdbSize
import com.wtv.app.ui.components.ActionIcon
import com.wtv.app.ui.components.Backdrop
import com.wtv.app.ui.components.HeroText
import com.wtv.app.ui.components.LandscapeCard
import com.wtv.app.ui.components.MetaRow
import com.wtv.app.ui.components.PlayButton
import com.wtv.app.ui.components.RowTitle
import com.wtv.app.ui.tmdbImage

/** Sample titles from the provider catalog (TMDB data, 2026-11-17). Replaced by real data in P2-4. */
private data class Sample(val title: String, val year: Int, val genres: String, val cert: String, val backdrop: String, val synopsis: String)

private val Samples = listOf(
    Sample("Chicago Fire", 2012, "Drama", "TV-14", "/otaBZzLIqrKdXcovbAvVONJCnb4.jpg", "An edge-of-your-seat view into the lives of everyday heroes committed to one of America's noblest professions."),
    Sample("Doctor X: Mafia in White", 2026, "Mystery • Drama", "TV-MA", "/mDYIV71RL3mkaW8IfSGNthuVB7l.jpg", "In a hospital dominated by ego and corruption, an enigmatic but brilliant surgeon arrives, taking on seemingly impossible cases."),
    Sample("Elsbeth", 2024, "Crime • Drama", "TV-14", "/5PqkJBZdzkZnfg0LCuKcrHlspco.jpg", "After her successful career in Chicago, Elsbeth Tascioni, an astute but unconventional attorney, makes unique observations."),
    Sample("The Gilded Age", 2022, "Drama", "TV-MA", "/afUVsProh46h31w2EvL7qyHXrqj.jpg", "It's 1882 and the Gilded Age is in full swing when Marian Brook moves in with her rigidly conventional aunts in New York City."),
    Sample("Crystal Lake", 2026, "Drama • Mystery", "TV-MA", "/wxiBsKFEOOFK8eQStWOykNORlXY.jpg", "Single mother Pam Voorhees has been unable to shake her grief after her young son drowned in the town lake."),
    Sample("Marshals", 2026, "Drama • Crime", "TV-14", "/yGJGwt7DdIWTUXuahLfhcH1gi7G.jpg", "With the Yellowstone Ranch behind him, Kayce Dutton joins an elite unit of U.S. Marshals."),
    Sample("Girl Taken", 2026, "Drama • Crime", "TV-MA", "/pPA3PDOZgq55QXTSj5FlFC6KTpJ.jpg", "Twin sisters Lily and Abby's lives are shattered when Lily is abducted from their quiet rural English town."),
)

/** The design system on one screen: header, actions, a row that drives the header. Home's content until P2-4. */
@Composable
fun Showcase(firstFocus: FocusRequester, up: FocusRequester, modifier: Modifier = Modifier) {
    // Up from the top row goes to the tabs; spatially the rail is nearer.
    val toTabs = Modifier.focusProperties { this.up = up }
    var focused by remember { mutableStateOf(Samples.first()) }
    Box(modifier.fillMaxSize()) {
        Backdrop(tmdbImage(focused.backdrop, TmdbSize.Backdrop))
        Row(Modifier.fillMaxSize()) {
            Column(Modifier.padding(start = 88.dp, top = 76.dp)) {
                HeroText(
                    modifier = Modifier.width(520.dp),
                    title = focused.title,
                    highlight = stringResource(R.string.recommended_by_wtw),
                    meta = { MetaRow(items = listOf(focused.year.toString(), focused.genres), badges = listOf(focused.cert, "HD")) },
                    synopsis = focused.synopsis,
                    actions = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            PlayButton(stringResource(R.string.play), onClick = {}, modifier = toTabs.focusRequester(firstFocus))
                            Spacer(Modifier.padding(start = 12.dp))
                            ActionIcon(Icons.Outlined.Add, stringResource(R.string.add_to_watchlist), onClick = {}, modifier = toTabs)
                            ActionIcon(Icons.Outlined.FavoriteBorder, stringResource(R.string.rate_love), onClick = {}, modifier = toTabs)
                            ActionIcon(Icons.Outlined.ThumbUp, stringResource(R.string.rate_like), onClick = {}, modifier = toTabs, selected = true)
                            ActionIcon(Icons.Outlined.ThumbDown, stringResource(R.string.rate_dislike), onClick = {}, modifier = toTabs)
                            ActionIcon(Icons.Outlined.Info, stringResource(R.string.more_info), onClick = {}, modifier = toTabs)
                        }
                    },
                )
                Spacer(Modifier.height(28.dp))
                RowTitle(stringResource(R.string.row_also_liked))
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    contentPadding = PaddingValues(end = 48.dp, top = 6.dp, bottom = 6.dp),
                ) {
                    items(Samples) { s ->
                        LandscapeCard(
                            imageUrl = tmdbImage(s.backdrop, TmdbSize.Card),
                            title = s.title,
                            onClick = {},
                            onFocused = { focused = s },
                        )
                    }
                }
            }
        }
    }
}
