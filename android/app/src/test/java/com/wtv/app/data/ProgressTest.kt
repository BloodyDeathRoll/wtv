package com.wtv.app.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProgressTest {
    private fun movie(pos: Int, dur: Int?) = Progress(1, null, null, pos, dur)
    private fun ep(season: Int, number: Int, pos: Int, dur: Int? = 2400) = Progress(1, season, number, pos, dur)
    private fun episode(season: Int, number: Int) =
        Episode(season * 100L + number, 1, "mp4", season, number, null, null, null, null, null, 2400, null, null)

    @Test fun `finished at 95 percent, resume skips the first 30 seconds and finished titles`() {
        assertFalse(movie(5699, 6000).finished)
        assertTrue(movie(5700, 6000).finished)
        assertFalse(movie(5000, null).finished)
        assertEquals(0, movie(29, 6000).resumeSecs)
        assertEquals(30, movie(30, 6000).resumeSecs)
        assertEquals(0, movie(5800, 6000).resumeSecs)
        assertEquals(5000, movie(5000, null).resumeSecs)
        assertEquals(0.5f, movie(3000, 6000).fraction!!, 0.0001f)
        assertNull(movie(3000, 0).fraction)
    }

    @Test fun `series Play - first episode, the unfinished one, the next, or back to the first`() {
        val eps = listOf(episode(1, 1), episode(1, 2), episode(2, 1))
        assertNull(nextEpisode(emptyList(), emptyList()))
        assertEquals(EpisodePlay(eps[0], 0), nextEpisode(eps, emptyList()))
        // Newest first: the unfinished S1E2 wins over the older S1E1.
        assertEquals(EpisodePlay(eps[1], 600), nextEpisode(eps, listOf(ep(1, 2, 600), ep(1, 1, 2400))))
        // Finished S1E2: the next is S2E1 (across the season).
        assertEquals(EpisodePlay(eps[2], 0), nextEpisode(eps, listOf(ep(1, 2, 2350))))
        // The series' last episode finished, or the watched one is gone: from the start.
        assertEquals(EpisodePlay(eps[0], 0), nextEpisode(eps, listOf(ep(2, 1, 2390))))
        assertEquals(EpisodePlay(eps[0], 0), nextEpisode(eps, listOf(ep(3, 7, 100))))
        // A movie position on the series is ignored.
        assertEquals(EpisodePlay(eps[0], 0), nextEpisode(eps, listOf(movie(100, 200))))
    }

    private fun row(titleId: Long, groupId: Long?, pos: Int, dur: Int?, season: Int? = null, number: Int? = null, kind: String = "movie") =
        JSONObject().apply {
            put("title_id", titleId); put("position_secs", pos); put("duration_secs", dur ?: JSONObject.NULL)
            put("episodes", if (season == null) JSONObject.NULL else JSONObject().put("season", season).put("episode", number))
            put("titles", JSONObject().put("id", titleId).put("ext_id", 9).put("kind", kind).put("name", "t$titleId").put("group_id", groupId ?: JSONObject.NULL))
        }

    @Test fun `a progress row parses, with and without an episode`() {
        val m = progress(row(5, 5, 120, null))
        assertEquals(Progress(5, null, null, 120, null), m)
        assertFalse(m.isEpisode)
        val e = progress(row(6, 6, 300, 2400, season = 2, number = 3, kind = "series"))
        assertEquals(Progress(6, 2, 3, 300, 2400), e)
        assertTrue(e.isEpisode)
    }

    @Test fun `continue watching - one card per title group from its newest row, finished movies out, series kept`() {
        val items = continueItems(
            listOf(
                row(1, 1, 600, 6000), // newest: movie group 1, copy 1
                row(2, 1, 5000, 6000), // older row of the same movie, another copy
                row(3, 3, 5900, 6000), // finished movie: out
                row(4, 4, 2390, 2400, season = 1, number = 8, kind = "series"), // finished episode: series stays
                row(5, null, 100, null), // never regrouped: its own card
                JSONObject().put("title_id", 6).put("position_secs", 1).put("duration_secs", 2), // title not readable: skipped
            ),
        )
        assertEquals(listOf(1L, 4L, 5L), items.map { it.title.id })
        assertEquals(600, items[0].progress.positionSecs)
    }

    @Test fun `the save body names title, episode, position and length, with nulls`() {
        val movie = JSONObject(progressBody(7, null, 90, null))
        assertEquals(7L, movie.getLong("title_id"))
        assertTrue(movie.isNull("episode_id"))
        assertEquals(90, movie.getInt("position_secs"))
        assertTrue(movie.isNull("duration_secs"))
        assertFalse(movie.has("user_id"))
        val episode = JSONObject(progressBody(7, 44, 90, 2400))
        assertEquals(44L, episode.getLong("episode_id"))
        assertEquals(2400, episode.getInt("duration_secs"))
    }

    @Test fun `one episode per number - the one named after the series, then the newest`() {
        fun e(season: Int, number: Int, extId: Long, name: String?) =
            Episode(extId, extId, "mp4", season, number, null, null, null, null, null, null, null, null, name)
        val series = "007: הדרך למיליון"
        val picked = oneEach(
            listOf(
                e(1, 1, 179838, "$series - S01E01 - פרק 1"),
                e(1, 1, 229332, "הבר מצווה - S01E01 - פרק 1"),
                e(1, 1, 285382, "$series - S01E01 - פרק 1"),
                e(1, 1, 292447, "אוז - S01E01 - השיגרה"),
                e(1, 2, 10, null),
                e(1, 2, 11, null),
                e(2, 1, 5, "other"),
            ),
            series,
        )
        assertEquals(listOf(285382L, 11L, 5L), picked.map { it.extId })
    }
}
