package com.wtv.app.player

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Base64

class EpgTest {
    private fun b64(s: String) = Base64.getEncoder().encodeToString(s.toByteArray())
    private fun listing(title: String, start: Long, end: Long, description: String? = null) =
        JSONObject().put("title", title).put("description", description ?: "").put("start_timestamp", start.toString()).put("stop_timestamp", end.toString())

    @Test fun `titles are decoded from base64, plain text kept, bad rows skipped, sorted by start`() {
        val json = JSONObject().put(
            "epg_listings",
            JSONArray()
                .put(listing(b64("מבזק חדשות"), 200, 300, b64("עדכון")))
                .put(listing("News", 100, 200))
                .put(JSONObject().put("title", b64("no times")))
                .put(listing("", 300, 400)),
        ).toString()
        val list = programmes(json)
        assertEquals(listOf("News", "מבזק חדשות"), list.map { it.title })
        assertEquals("עדכון", list[1].description)
        assertNull(list[0].description)
        assertEquals(100L, list[0].start)
    }

    @Test fun `no guide or a broken answer gives nothing`() {
        assertEquals(emptyList<Programme>(), programmes("""{"epg_listings":[]}"""))
        assertEquals(emptyList<Programme>(), programmes("[]"))
        assertEquals(emptyList<Programme>(), programmes("not json"))
    }

    @Test fun `now and next, also between programmes and after the last`() {
        val a = Programme("A", null, 100, 200)
        val b = Programme("B", null, 200, 300)
        val c = Programme("C", null, 400, 500)
        val list = listOf(a, b, c)
        assertEquals(a to b, nowAndNext(list, 150))
        assertEquals(b to c, nowAndNext(list, 200))
        assertEquals(null to c, nowAndNext(list, 350))
        assertEquals(null to null, nowAndNext(list, 600))
    }

    @Test fun `plain titles that look like base64 are kept, and empty programmes dropped`() {
        val json = JSONObject().put(
            "epg_listings",
            JSONArray()
                .put(listing("AAAA", 100, 200)) // decodes to control characters
                .put(listing("abc", 200, 300)) // unpadded
                .put(listing(b64("x"), 300, 300)), // no length
        ).toString()
        assertEquals(listOf("AAAA", "abc"), programmes(json).map { it.title })
    }

    @Test fun `the server address gets https when it has no scheme, and loses a trailing slash`() {
        assertEquals("https://tv.example:8080", serverBase(ProviderLogin("tv.example:8080/", "u", "p")))
        assertEquals("http://tv.example", serverBase(ProviderLogin(" http://tv.example ", "u", "p")))
    }
}
