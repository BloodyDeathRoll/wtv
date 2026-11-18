package com.wtv.app.data

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LiveTest {
    private fun ch(id: Long, vararg categories: Int) = Channel(id, id + 1000, "ch $id", id.toInt(), null, 0, false, categories.toList())
    private val israel = LiveCategory(1, "ישראל", "Israel", "ישראל")
    private val radio = LiveCategory(20, "רדיו", "Radio", null)
    private val sport = LiveCategory(30, "ספורט", "Sports", "ספורט")

    @Test fun `favourites first, then categories in order, empty groups left out`() {
        val channels = listOf(ch(1, 1), ch(2, 1), ch(3, 20), ch(4, 1, 20))
        val groups = liveGroups(channels, listOf(israel, sport, radio), setOf(3, 2), "Favourites", hebrew = false)
        assertEquals(listOf("Favourites", "Israel", "Radio"), groups.map { it.label })
        assertNull(groups[0].category)
        assertEquals(listOf(2L, 3L), groups[0].channels.map { it.id })
        assertEquals(listOf(1L, 2L, 4L), groups[1].channels.map { it.id })
        assertEquals(listOf(3L, 4L), groups[2].channels.map { it.id })
    }

    @Test fun `no favourites gives no Favourites group, and Hebrew labels fall back to the provider name`() {
        val groups = liveGroups(listOf(ch(3, 20)), listOf(radio), emptySet(), "Favourites", hebrew = true)
        assertEquals(listOf("רדיו"), groups.map { it.label })
    }

    @Test fun `a channel row parses, with no number, logo or categories`() {
        val full = channel(
            JSONObject().put("id", 5).put("ext_id", 123).put("name", "Kan 11").put("num", 11).put("logo_url", "https://l/k.png")
                .put("archive_days", 7).put("is_radio", false).put("category_ids", JSONArray(listOf(1, 20))),
        )
        assertEquals(Channel(5, 123, "Kan 11", 11, "https://l/k.png", 7, false, listOf(1, 20)), full)
        val bare = channel(JSONObject().put("id", 6).put("ext_id", 9).put("name", "X").put("num", JSONObject.NULL).put("logo_url", ""))
        assertEquals(Channel(6, 9, "X", null, null, 0, false, emptyList()), bare)
    }

    @Test fun `the favourite body names the channel and the flag only`() {
        assertEquals("""{"channel_id":5,"favorite":true}""", favoriteBody(5, true))
    }
}
