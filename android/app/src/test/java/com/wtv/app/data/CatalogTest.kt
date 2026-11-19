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

    @Test fun `an episode parses, and its name and synopsis fall back like a title's`() {
        val o = JSONObject().put("id", 5).put("ext_id", 369702).put("season", 1).put("episode", 3)
            .put("name_en", "Pilot").put("name_he", JSONObject.NULL).put("overview_en", "EN").put("plot", "PROVIDER")
            .put("duration_secs", 2555).put("tmdb_still", "/s.jpg").put("image_url", "https://p/e.jpg")
        val e = episode(o)
        assertEquals(1, e.season)
        assertEquals(3, e.number)
        assertEquals(2555, e.durationSecs)
        assertEquals("Pilot", e.displayName(hebrew = false))
        assertEquals("Pilot", e.displayName(hebrew = true))
        assertEquals("EN", e.synopsis(hebrew = false))
        assertEquals("PROVIDER", e.synopsis(hebrew = true))
        val onlyHebrew = episode(JSONObject().put("id", 7).put("ext_id", 2).put("season", 1).put("episode", 5).put("overview_he", "HE"))
        assertEquals("HE", onlyHebrew.synopsis(hebrew = false))
        assertEquals("https://image.tmdb.org/t/p/w300/s.jpg", e.image)
        assertNull(episode(JSONObject().put("id", 6).put("ext_id", 1).put("season", 1).put("episode", 4)).displayName(hebrew = false))
    }

    @Test fun `episodes are read in pages of 1000 in a stable order`() {
        val path = episodesPath(15791, offset = 1000)
        for (part in listOf("&title_id=eq.15791", "&available=is.true", "&order=season,episode,id", "&offset=1000", "&limit=1000")) assertTrue(part, path.contains(part))
    }

    @Test fun `a person's titles are available cards only, each once, newest first`() {
        fun t(id: Int, year: Int?, primary: Boolean = true, available: Boolean = true) =
            row("year" to year, "is_primary" to primary, "available" to available).put("id", id)
        val cards = personCards(listOf(t(1, 2019), t(2, 2025), t(3, 2025, primary = false), t(4, 2020, available = false), t(2, 2025), t(5, null)))
        assertEquals(listOf(2L, 1L, 5L), cards.map { it.id })
    }

    @Test fun `a copy whose card is missing is resolved to its card`() {
        fun t(id: Int, primary: Boolean, group: Int?) = row("is_primary" to primary, "group_id" to group, "available" to true).put("id", id)
        assertEquals(setOf(9L), cardsMissingFor(listOf(t(1, true, 1), t(2, false, 1), t(3, false, 9), t(4, false, null))))
    }

    private fun decodedOr(path: String) = java.net.URLDecoder.decode(path.substringAfter("&or=").substringBefore("&"), "UTF-8")

    @Test fun `search quotes the query for the or filter and encodes it`() {
        val or = decodedOr(searchPath("bad, (boys) \"x\"", hebrew = false, prefix = false))
        val p = "\"*bad, (boys) \\\"x\\\"*\""
        assertEquals("(sort_name_en.ilike.$p,sort_name_he.ilike.$p,name.ilike.$p)", or)
        val path = searchPath("x", hebrew = false, prefix = false)
        assertTrue(path.contains("&is_primary=is.true"))
        assertTrue(path.contains("&order=sort_name_en.asc,id"))
        assertTrue(searchPath("שוטר", hebrew = true, prefix = false).contains("&order=sort_name_he.asc,id"))
    }

    @Test fun `a section search keeps to its kind and actors are searched by an encoded name`() {
        assertTrue(searchPath("x", hebrew = false, prefix = false, kind = Kind.Movie).contains("&kind=eq.movie&"))
        assertFalse(searchPath("x", hebrew = false, prefix = false).contains("&kind="))
        assertEquals("rpc/search_people?p_query=tom%20h%26a&p_kind=series", peopleSearchPath("tom h&a", Kind.Series))
        assertEquals("rpc/search_people?p_query=brad", peopleSearchPath("brad", null))
    }

    @Test fun `a prefix search has no leading wildcard`() {
        assertTrue(decodedOr(searchPath("bad", hebrew = false, prefix = true)).startsWith("(sort_name_en.ilike.\"bad*\","))
    }

    @Test fun `percent, underscore and backslash in a query match themselves`() {
        // SQL LIKE escapes are \% \_ \; inside a quoted PostgREST value each backslash is doubled.
        val or = decodedOr(searchPath("100%_a\\b", hebrew = false, prefix = false))
        assertTrue(or, or.startsWith("(sort_name_en.ilike.\"*100\\\\%\\\\_a\\\\\\\\b*\","))
    }

    @Test fun `names starting with the query come first, each once, within the limit`() {
        fun t(id: Int) = title(row().put("id", id))
        assertEquals(listOf(3L, 4L, 1L, 2L), mergeSearch(listOf(t(3), t(4)), listOf(t(1), t(3), t(2), t(4))).map { it.id })
        assertEquals(SEARCH_LIMIT, mergeSearch(List(50) { t(it) }, List(50) { t(100 + it) }).size)
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
        // The database drops the provider's plot when TMDB has a Hebrew overview.
        val onlyHebrew = title(row("overview_he" to "HE"))
        assertEquals("HE", onlyHebrew.synopsis(hebrew = false))
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

    @Test fun `a recommended page asks the server function for one category, offset and limit`() {
        val path = recommendedPath(Category(7, Kind.Movie, "Kids", null, null), offset = 60, limit = 60)
        assertTrue(path, path.startsWith("rpc/recommended_page?select="))
        for (part in listOf("&p_kind=movie", "&p_category=7", "&p_offset=60", "&p_limit=60")) assertTrue(part, path.contains(part))
    }

    @Test fun `a genre's page filters by TMDB genre, in both orders`() {
        val drama = Category(18, Kind.Movie, "Drama", "Drama", null, genre = true)
        val page = pagePath(drama, Sort.Year, hebrew = false, offset = 0, limit = 60)
        assertTrue(page, page.contains("&tmdb_genre_ids=cs.%7B18%7D"))
        assertFalse(page, page.contains("category_ids"))
        val recommended = recommendedPath(drama, offset = 0, limit = 60)
        assertTrue(recommended, recommended.contains("&p_genre=18"))
        assertFalse(recommended, recommended.contains("p_category"))
    }

    @Test fun `All movies is the whole kind, in both orders`() {
        val all = Category(0, Kind.Movie, "All movies", null, null, all = true)
        val page = pagePath(all, Sort.Name, hebrew = false, offset = 0, limit = 60)
        assertTrue(page, page.contains("&kind=eq.movie"))
        assertFalse(page, page.contains("_ids=cs."))
        val recommended = recommendedPath(all, offset = 0, limit = 60)
        assertFalse(recommended, recommended.contains("p_category") || recommended.contains("p_genre"))
    }
}
