package com.wtv.app.data

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CatalogTest {
    private fun row(vararg pairs: Pair<String, Any?>) = JSONObject().apply {
        put("id", 10); put("ext_id", 387982); put("kind", "movie"); put("name", "החיה")
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

    @Test fun `details take the TMDB runtime first and read group and rating, missing and null alike`() {
        val t = title(row("runtime_min" to 99, "tmdb_runtime_min" to 101, "tmdb_rating" to 6.4, "group_id" to 7, "container_ext" to "mkv"))
        assertEquals(101, t.runtimeMin)
        assertEquals(6.4, t.tmdbRating!!, 0.0001)
        assertEquals(7L, t.groupId)
        assertEquals(387982L, t.extId)
        assertEquals("mkv", t.containerExt)
        assertEquals(99, title(row("runtime_min" to 99, "tmdb_runtime_min" to null)).runtimeMin)
        assertNull(title(row("group_id" to null)).groupId)
        assertNull(title(row()).groupId)
    }

    @Test fun `copies list 4K first and at least the title itself`() {
        val t = title(row("container_ext" to "mp4"))
        fun copy(id: Long, cats: List<Int>) = JSONObject().put("id", id).put("ext_id", id * 10).put("container_ext", "mkv").put("category_ids", org.json.JSONArray(cats))
        val copies = copiesFrom(t, listOf(copy(1, listOf(449)), copy(2, listOf(99, 449))), fourK = setOf(99))
        assertEquals(listOf(2L, 1L), copies.map { it.id })
        assertEquals(listOf(true, false), copies.map { it.is4k })
        assertEquals(listOf(Copy(10, 387982, "mp4", false)), copiesFrom(t, emptyList(), setOf(99)))
    }

    @Test fun `copy labels number several HD copies only`() {
        val k = Copy(1, 1, null, true)
        val hd = Copy(2, 2, null, false)
        assertEquals(listOf("4K", "HD"), copyLabels(listOf(k, hd)))
        assertEquals(listOf("4K", "HD 1", "HD 2"), copyLabels(listOf(k, hd, hd.copy(id = 3))))
        assertEquals(listOf("HD"), copyLabels(listOf(hd)))
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
        // Date added is the newest copy's.
        assertEquals("group_added_at.desc.nullslast,id", Sort.Added.order(hebrew = false))
        assertEquals("sort_name_en.asc,id", Sort.Name.order(hebrew = false))
        assertEquals("sort_name_he.asc,id", Sort.Name.order(hebrew = true))
        for (s in Sort.entries) assertTrue(s.name, s.order(hebrew = false).endsWith(",id"))
    }

    @Test fun `a grid page asks for one category, available titles, the order, offset and limit`() {
        val path = pagePath(Category(185, Kind.Series, "Netflix", null, null), Sort.Rating, hebrew = false, offset = 120, limit = 60)
        assertTrue(path, path.startsWith("titles?select="))
        for (part in listOf("&kind=eq.series", "&available=is.true", "&is_primary=is.true", "&group_category_ids=cs.%7B185%7D", "&order=tmdb_rating.desc.nullslast,id", "&offset=120", "&limit=60")) {
            assertTrue(part, path.contains(part))
        }
    }

    @Test fun `rows ask for cards, newest copy first, in a category or all`() {
        val inCategory = latestPath(Kind.Movie, 99, 10)
        for (part in listOf("&kind=eq.movie", "&is_primary=is.true", "&group_category_ids=cs.%7B99%7D", "&order=group_added_at.desc.nullslast,id", "&limit=10")) {
            assertTrue(part, inCategory.contains(part))
        }
        assertFalse(latestPath(Kind.Series, null, 10).contains("category_ids"))
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
