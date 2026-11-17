package com.wtv.app.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CatalogTest {
    private fun row(vararg pairs: Pair<String, Any?>) = JSONObject().apply {
        put("id", 10); put("kind", "movie"); put("name", "החיה")
        for ((k, v) in pairs) put(k, v ?: JSONObject.NULL)
    }

    @Test fun `a full row parses, nulls and blanks become null`() {
        val t = title(row("title_en" to "The Beast", "title_he" to " ", "year" to 2026, "plot" to null, "tmdb_genre_ids" to org.json.JSONArray(listOf(28, 53)), "certification" to "R"))
        assertEquals(10L, t.id)
        assertEquals(Kind.Movie, t.kind)
        assertEquals("The Beast", t.nameEn)
        assertNull(t.nameHe)
        assertEquals(2026, t.year)
        assertNull(t.plot)
        assertEquals(listOf(28, 53), t.genreIds)
        assertEquals("R", t.certification)
    }

    @Test fun `missing optional columns do not fail`() {
        val t = title(row())
        assertNull(t.nameEn)
        assertNull(t.year)
        assertEquals(emptyList<Int>(), t.genreIds)
    }

    @Test fun `names come from TMDB in the app language, else from the provider`() {
        val t = title(row("title_en" to "The Beast", "title_he" to "החיה (TMDB)"))
        assertEquals("The Beast", t.displayName(hebrew = false))
        assertEquals("החיה (TMDB)", t.displayName(hebrew = true))
        assertEquals("החיה", title(row()).displayName(hebrew = false))
    }

    @Test fun `synopsis falls back from English to the provider, and from Hebrew to the provider then English`() {
        val all = title(row("overview_en" to "EN", "overview_he" to "HE", "plot" to "PROVIDER"))
        assertEquals("EN", all.synopsis(hebrew = false))
        assertEquals("HE", all.synopsis(hebrew = true))
        val onlyProvider = title(row("plot" to "PROVIDER"))
        assertEquals("PROVIDER", onlyProvider.synopsis(hebrew = false))
        assertEquals("PROVIDER", onlyProvider.synopsis(hebrew = true))
        val onlyEnglish = title(row("overview_en" to "EN"))
        assertEquals("EN", onlyEnglish.synopsis(hebrew = true))
    }

    @Test fun `images use the TMDB backdrop first and provider images after`() {
        val tmdb = title(row("tmdb_backdrop" to "/b.jpg", "backdrop_url" to "https://p/b.jpg"))
        assertEquals("https://image.tmdb.org/t/p/w780/b.jpg", tmdb.cardImage)
        assertEquals("https://image.tmdb.org/t/p/w1280/b.jpg", tmdb.heroImage)
        val provider = title(row("backdrop_url" to "https://p/b.jpg", "poster_url" to "https://p/p.jpg"))
        assertEquals("https://p/b.jpg", provider.cardImage)
        assertEquals("https://p/p.jpg", title(row("poster_url" to "https://p/p.jpg")).cardImage)
        assertNull(title(row("poster_url" to "https://p/p.jpg")).heroImage)
    }

    @Test fun `category and genre labels fall back to what exists`() {
        assertEquals("Netflix", Category(1, Kind.Movie, "Netflix - נטפליקס", "Netflix", "נטפליקס").label(hebrew = false))
        assertEquals("נטפליקס", Category(1, Kind.Movie, "Netflix - נטפליקס", "Netflix", "נטפליקס").label(hebrew = true))
        assertEquals("קטגוריה", Category(1, Kind.Movie, "קטגוריה", null, null).label(hebrew = false))
        assertEquals("Drama", Genre("Drama", null).label(hebrew = true))
    }

    @Test fun `sort orders end on id and name follows the language`() {
        assertEquals("added_at.desc.nullslast,id", Sort.Added.order(hebrew = false))
        assertEquals("sort_name_en.asc,id", Sort.Name.order(hebrew = false))
        assertEquals("sort_name_he.asc,id", Sort.Name.order(hebrew = true))
        for (s in Sort.entries) assertTrue(s.name, s.order(hebrew = false).endsWith(",id"))
    }

    @Test fun `poster prefers TMDB, then the provider's`() {
        assertEquals("https://image.tmdb.org/t/p/w342/p.jpg", title(row("tmdb_poster" to "/p.jpg", "poster_url" to "https://p/p.jpg")).posterImage)
        assertEquals("https://p/p.jpg", title(row("poster_url" to "https://p/p.jpg")).posterImage)
    }

    @Test fun `only a real rejection of the refresh token counts, never a rate limit or a server error`() {
        for (code in listOf(400, 401, 403, 404, 422)) assertTrue("$code", isRejection(code))
        for (code in listOf(408, 429, 500, 502, 503)) assertFalse("$code", isRejection(code))
    }

    @Test fun `an access token is used until a minute before it expires`() {
        assertTrue(isFresh(expiresAtSeconds = 1000, nowSeconds = 939))
        assertFalse(isFresh(expiresAtSeconds = 1000, nowSeconds = 940))
        assertFalse(isFresh(expiresAtSeconds = 0, nowSeconds = 1))
    }
}
