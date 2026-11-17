package com.wtv.app.data

import com.wtv.app.ui.TmdbSize
import com.wtv.app.ui.tmdbImage
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
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
    val runtimeMin: Int?,
    val director: String?,
    val castNames: String?,
    val tmdbRating: Double?,
    val originalLanguage: String?,
    /** The card of this title's copies; null before the first regroup (then the title is its own card). */
    val groupId: Long?,
) {
    fun displayName(hebrew: Boolean): String = (if (hebrew) nameHe else nameEn) ?: name
    fun synopsis(hebrew: Boolean): String? = if (hebrew) overviewHe ?: plot ?: overviewEn else overviewEn ?: plot
    val cardImage: String? get() = tmdbImage(tmdbBackdrop, TmdbSize.Card) ?: providerBackdrop ?: tmdbImage(tmdbPoster, TmdbSize.Card) ?: providerPoster
    val heroImage: String? get() = tmdbImage(tmdbBackdrop, TmdbSize.Backdrop) ?: providerBackdrop
    val posterImage: String? get() = tmdbImage(tmdbPoster, TmdbSize.Poster) ?: providerPoster
}

/** Orders of a category grid. Name follows the app's language. */
enum class Sort { Added, Year, Name, Rating }

/** The REST `order` value for a sort; every order ends on `id`, so paging is stable. */
internal fun Sort.order(hebrew: Boolean): String = when (this) {
    Sort.Added -> "group_added_at.desc.nullslast,id"
    Sort.Year -> "year.desc.nullslast,id"
    Sort.Name -> "${if (hebrew) "sort_name_he" else "sort_name_en"}.asc,id"
    Sort.Rating -> "tmdb_rating.desc.nullslast,id"
}

/** A cast member as the title page shows them. */
data class CastMember(val personId: Int, val name: String, val character: String?, val profile: String?) {
    val photo: String? get() = tmdbImage(profile, TmdbSize.Profile)
}

/** One provider copy of a title; Play chooses among them. */
data class Copy(val id: Long, val extId: Long, val containerExt: String?, val is4k: Boolean)

data class Genre(val nameEn: String, val nameHe: String?) {
    fun label(hebrew: Boolean): String = (if (hebrew) nameHe else null) ?: nameEn
}

/** Catalog reads, cached for the app's lifetime (the catalog changes every few hours at most). */
class Catalog(private val api: Api) {
    // A lock per cache: a quick tab switch must not fetch twice or race, and
    // the two fetches do not wait for each other.
    private val categoriesLock = Mutex()
    private val genresLock = Mutex()
    private val categories = mutableMapOf<Kind, List<Category>>()
    private var genres: Map<Pair<Kind, Int>, Genre>? = null

    /** Parallel row requests. ~25 categories at once is a lot for a TV's Wi-Fi. */
    private val rowRequests = Semaphore(6)

    suspend fun categories(kind: Kind): List<Category> = categoriesLock.withLock {
        categories[kind] ?: api.get("categories?select=ext_id,name,name_en,name_he&kind=eq.${kind.db}&order=position").objects()
            .map { Category(it.getInt("ext_id"), kind, it.getString("name"), it.text("name_en"), it.text("name_he")) }
            .also { categories[kind] = it }
    }

    suspend fun genres(): Map<Pair<Kind, Int>, Genre> = genresLock.withLock {
        genres ?: api.get("genres?select=kind,id,name_en,name_he").objects()
            .associate { (kindOf(it.getString("kind")) to it.getInt("id")) to Genre(it.getString("name_en"), it.text("name_he")) }
            .also { genres = it }
    }

    /** The newest titles the provider has, in one category or all. */
    suspend fun latest(kind: Kind, category: Int? = null, limit: Int = 10): List<Title> =
        api.get(latestPath(kind, category, limit)).objects().map(::title)

    /** One page of a category in the given order. */
    suspend fun page(category: Category, sort: Sort, hebrew: Boolean, offset: Int, limit: Int): List<Title> =
        api.get(pagePath(category, sort, hebrew, offset, limit)).objects().map(::title)

    /** Billed cast of a title, in order. */
    suspend fun cast(titleId: Long): List<CastMember> =
        api.get("title_cast?select=position,character,people(tmdb_id,name,profile)&title_id=eq.$titleId&order=position").objects().map {
            val p = it.getJSONObject("people")
            CastMember(p.getInt("tmdb_id"), p.getString("name"), it.text("character"), p.text("profile"))
        }

    /**
     * The available copies of a title, the 4K ones first. A copy is 4K when it
     * is in a provider category named with "4K".
     */
    suspend fun copies(title: Title): List<Copy> {
        val fourK = categories(title.kind).filter { it.name.contains("4K", ignoreCase = true) }.map { it.id }.toSet()
        return api.get("titles?select=id,ext_id,container_ext,category_ids&group_id=eq.${title.groupId ?: title.id}&available=is.true&order=id")
            .objects()
            .map { o ->
                val cats = o.optJSONArray("category_ids")?.let { a -> List(a.length()) { a.getInt(it) } } ?: emptyList()
                Copy(o.getLong("id"), o.getLong("ext_id"), o.text("container_ext"), cats.any { it in fourK })
            }
            .ifEmpty { listOf(Copy(title.id, -1, null, false)) }
            .sortedByDescending { it.is4k }
    }

    /** One row per provider category, newest first; empty categories left out. */
    suspend fun rows(kind: Kind, perRow: Int = 10): List<Pair<Category, List<Title>>> = coroutineScope {
        categories(kind).map { c -> async { rowRequests.withPermit { c to latest(kind, c.id, perRow) } } }
            .awaitAll()
            .filter { it.second.isNotEmpty() }
    }
}

/**
 * Rows and grids show cards: one title per group of copies (#56). A card's
 * categories and date are those of all its copies.
 */
private fun cards(kind: Kind, category: Int?): String =
    "titles?select=$TITLE_COLUMNS&kind=eq.${kind.db}&available=is.true&is_primary=is.true" +
        (category?.let { "&group_category_ids=cs.%7B$it%7D" } ?: "")

internal fun latestPath(kind: Kind, category: Int?, limit: Int): String =
    cards(kind, category) + "&order=${Sort.Added.order(hebrew = false)}&limit=$limit"

internal fun pagePath(category: Category, sort: Sort, hebrew: Boolean, offset: Int, limit: Int): String =
    cards(category.kind, category.id) + "&order=${sort.order(hebrew)}&offset=$offset&limit=$limit"

private const val TITLE_COLUMNS = "id,kind,name,title_en,title_he,year,plot,overview_en,overview_he,tmdb_genre_ids,certification," +
    "tmdb_backdrop,tmdb_poster,backdrop_url,poster_url,runtime_min,tmdb_runtime_min,director,cast_names,tmdb_rating,original_language,group_id"

private fun kindOf(db: String): Kind = Kind.entries.firstOrNull { it.db == db } ?: throw ApiException("Unknown kind: $db")

/** A title row from the REST API. */
internal fun title(o: JSONObject) = Title(
    id = o.getLong("id"),
    kind = kindOf(o.getString("kind")),
    name = o.getString("name"),
    nameEn = o.text("title_en"),
    nameHe = o.text("title_he"),
    year = o.int("year"),
    plot = o.text("plot"),
    overviewEn = o.text("overview_en"),
    overviewHe = o.text("overview_he"),
    genreIds = o.optJSONArray("tmdb_genre_ids")?.let { a -> List(a.length()) { a.getInt(it) } } ?: emptyList(),
    certification = o.text("certification"),
    tmdbBackdrop = o.text("tmdb_backdrop"),
    tmdbPoster = o.text("tmdb_poster"),
    providerBackdrop = o.text("backdrop_url"),
    providerPoster = o.text("poster_url"),
    runtimeMin = o.int("tmdb_runtime_min") ?: o.int("runtime_min"),
    director = o.text("director"),
    castNames = o.text("cast_names"),
    tmdbRating = if (o.isNull("tmdb_rating") || !o.has("tmdb_rating")) null else o.getDouble("tmdb_rating"),
    originalLanguage = o.text("original_language"),
    groupId = if (o.isNull("group_id") || !o.has("group_id")) null else o.getLong("group_id"),
)

private fun JSONObject.int(key: String): Int? = if (isNull(key) || !has(key)) null else getInt(key)

private fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }

/** The string at `key`, or null for a missing, null or blank value. */
internal fun JSONObject.text(key: String): String? = if (isNull(key)) null else optString(key).takeIf { it.isNotBlank() }
