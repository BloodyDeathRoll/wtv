package com.wtv.app.data

import com.wtv.app.ui.TmdbSize
import com.wtv.app.ui.tmdbImage
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import org.json.JSONArray
import org.json.JSONObject

enum class Kind(val db: String) { Movie("movie"), Series("series") }

data class Category(val id: Int, val kind: Kind, val name: String, val nameEn: String?, val nameHe: String?) {
    fun label(hebrew: Boolean): String = (if (hebrew) nameHe else nameEn) ?: name
}

/**
 * A movie or series as the app shows it. TMDB text first, in the app's
 * language; the provider's own (mostly Hebrew) text when TMDB has none.
 */
data class Title(
    val id: Long,
    val kind: Kind,
    val name: String,
    val nameEn: String?,
    val nameHe: String?,
    val year: Int?,
    val plot: String?,
    val overviewEn: String?,
    val overviewHe: String?,
    val genreIds: List<Int>,
    val certification: String?,
    val tmdbBackdrop: String?,
    val tmdbPoster: String?,
    val providerBackdrop: String?,
    val providerPoster: String?,
) {
    fun displayName(hebrew: Boolean): String = (if (hebrew) nameHe else nameEn) ?: name
    fun synopsis(hebrew: Boolean): String? = if (hebrew) overviewHe ?: plot ?: overviewEn else overviewEn ?: plot
    val cardImage: String? get() = tmdbImage(tmdbBackdrop, TmdbSize.Card) ?: providerBackdrop ?: tmdbImage(tmdbPoster, TmdbSize.Card) ?: providerPoster
    val heroImage: String? get() = tmdbImage(tmdbBackdrop, TmdbSize.Backdrop) ?: providerBackdrop
}

data class Genre(val nameEn: String, val nameHe: String?) {
    fun label(hebrew: Boolean): String = (if (hebrew) nameHe else null) ?: nameEn
}

/** Catalog reads, cached for the app's lifetime (the catalog changes every few hours at most). */
class Catalog(private val api: Api) {
    private val categories = mutableMapOf<Kind, List<Category>>()
    private var genres: Map<Pair<Kind, Int>, Genre>? = null

    suspend fun categories(kind: Kind): List<Category> = categories.getOrPut(kind) {
        api.get("categories?select=ext_id,name,name_en,name_he&kind=eq.${kind.db}&order=position").objects().map {
            Category(it.getInt("ext_id"), kind, it.getString("name"), it.text("name_en"), it.text("name_he"))
        }
    }

    suspend fun genres(): Map<Pair<Kind, Int>, Genre> = genres ?: api.get("genres?select=kind,id,name_en,name_he").objects()
        .associate { (Kind.entries.first { k -> k.db == it.getString("kind") } to it.getInt("id")) to Genre(it.getString("name_en"), it.text("name_he")) }
        .also { genres = it }

    /** The newest titles the provider has, in one category or all. */
    suspend fun latest(kind: Kind, category: Int? = null, limit: Int = 10): List<Title> {
        val inCategory = category?.let { "&category_ids=cs.%7B$it%7D" } ?: ""
        return api.get("titles?select=$TITLE_COLUMNS&kind=eq.${kind.db}&available=is.true$inCategory&order=added_at.desc.nullslast,id&limit=$limit")
            .objects().map(::title)
    }

    /** One row per provider category, newest first; empty categories left out. */
    suspend fun rows(kind: Kind, perRow: Int = 10): List<Pair<Category, List<Title>>> = coroutineScope {
        categories(kind).map { c -> async { c to latest(kind, c.id, perRow) } }.awaitAll().filter { it.second.isNotEmpty() }
    }

    private fun title(o: JSONObject) = Title(
        id = o.getLong("id"),
        kind = Kind.entries.first { it.db == o.getString("kind") },
        name = o.getString("name"),
        nameEn = o.text("title_en"),
        nameHe = o.text("title_he"),
        year = if (o.isNull("year")) null else o.getInt("year"),
        plot = o.text("plot"),
        overviewEn = o.text("overview_en"),
        overviewHe = o.text("overview_he"),
        genreIds = o.optJSONArray("tmdb_genre_ids")?.let { a -> List(a.length()) { a.getInt(it) } } ?: emptyList(),
        certification = o.text("certification"),
        tmdbBackdrop = o.text("tmdb_backdrop"),
        tmdbPoster = o.text("tmdb_poster"),
        providerBackdrop = o.text("backdrop_url"),
        providerPoster = o.text("poster_url"),
    )

    private companion object {
        const val TITLE_COLUMNS = "id,kind,name,title_en,title_he,year,plot,overview_en,overview_he,tmdb_genre_ids,certification,tmdb_backdrop,tmdb_poster,backdrop_url,poster_url"
    }
}

private fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }

/** The string at `key`, or null for a missing, null or blank value. */
private fun JSONObject.text(key: String): String? = if (isNull(key)) null else optString(key).takeIf { it.isNotBlank() }
