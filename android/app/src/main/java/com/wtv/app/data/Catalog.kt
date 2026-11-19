package com.wtv.app.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
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

/**
 * A provider category, or with `genre` a TMDB genre, or with `all` every title
 * of the kind (side bar → Categories): all open the same grid. `count`, when
 * known, is how many titles it has.
 */
data class Category(
    val id: Int,
    val kind: Kind,
    val name: String,
    val nameEn: String?,
    val nameHe: String?,
    val genre: Boolean = false,
    val all: Boolean = false,
    val count: Int? = null,
) {
    fun label(hebrew: Boolean): String = (if (hebrew) nameHe else nameEn) ?: name
}

/**
 * A movie or series as the app shows it. TMDB text first, in the app's
 * language; the provider's own (mostly Hebrew) text when TMDB has none.
 */
data class Title(
    val id: Long,
    /** The provider's id of this copy; with `containerExt`, what playback needs. */
    val extId: Long,
    val containerExt: String?,
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
    /** WTW's "% match" from the user's ranking; null without one. Shown only while WTW is connected. */
    val match: Int? = null,
) {
    fun displayName(hebrew: Boolean): String = (if (hebrew) nameHe else nameEn) ?: name
    fun synopsis(hebrew: Boolean): String? = if (hebrew) overviewHe ?: plot ?: overviewEn else overviewEn ?: plot ?: overviewHe
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

/** An episode of a series. Names and synopses as for titles: TMDB first, then the provider's. */
data class Episode(
    val id: Long,
    val extId: Long,
    val containerExt: String?,
    val season: Int,
    val number: Int,
    val nameEn: String?,
    val nameHe: String?,
    val overviewEn: String?,
    val overviewHe: String?,
    val plot: String?,
    val durationSecs: Int?,
    val tmdbStill: String?,
    val providerImage: String?,
    /** The provider's own name, "Series - S01E01 - …"; tells this series' episodes from others filed under it. */
    val providerName: String? = null,
) {
    /**
     * Null when there is no real name: the page writes "Episode 3" in the
     * app's language. TMDB's own stand-ins ("Episode 3") are stored empty by
     * the enrichment job.
     */
    fun displayName(hebrew: Boolean): String? = if (hebrew) nameHe ?: nameEn else nameEn

    /**
     * As for titles: in Hebrew the provider's (Hebrew) plot comes before TMDB's English.
     * English ends on the Hebrew overview because the database drops the plot when one exists.
     */
    fun synopsis(hebrew: Boolean): String? = if (hebrew) overviewHe ?: plot ?: overviewEn else overviewEn ?: plot ?: overviewHe
    val image: String? get() = tmdbImage(tmdbStill, TmdbSize.Still) ?: providerImage
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

    /** A kind's genres as categories, by name: the side bar's second group of tags. */
    suspend fun genreCategories(kind: Kind, hebrew: Boolean): List<Category> =
        genres().filterKeys { it.first == kind }
            .map { (key, g) -> Category(key.second, kind, g.nameEn, g.nameEn, g.nameHe, genre = true) }
            .sortedBy { it.label(hebrew) }

    suspend fun genres(): Map<Pair<Kind, Int>, Genre> = genresLock.withLock {
        genres ?: api.get("genres?select=kind,id,name_en,name_he").objects()
            .associate { (kindOf(it.getString("kind")) to it.getInt("id")) to Genre(it.getString("name_en"), it.text("name_he")) }
            .also { genres = it }
    }

    /** The newest titles the provider has, in one category or all. */
    suspend fun latest(kind: Kind, category: Int? = null, limit: Int = 10, genre: Boolean = false): List<Title> =
        api.get(latestPath(kind, category, limit, genre)).objects().map(::title)

    /** One page of a category, best first by the user's WTW ranking; newest first without one. */
    suspend fun recommendedPage(category: Category, offset: Int, limit: Int): List<Title> =
        api.get(recommendedPath(category, offset, limit)).objects().map(::title)

    /** Home: the best ranked titles the user has not rated in WTW. */
    suspend fun topPicks(limit: Int = 20): List<Title> = api.get("rpc/top_picks?select=$TITLE_COLUMNS&p_limit=$limit").objects().map(::title)

    /** "Recommended for You": the ranking's best, unrated, in one kind or both; a page at a time. */
    suspend fun topPicksPage(kind: Kind?, offset: Int, limit: Int): List<Title> =
        api.get("rpc/top_picks_page?select=$TITLE_COLUMNS&p_offset=$offset&p_limit=$limit" + (kind?.let { "&p_kind=${it.db}" } ?: "")).objects().map(::title)

    /** "Watch it again" without WTW: the titles the user finished, last finished first. */
    suspend fun finishedTitles(limit: Int = 20, kind: Kind? = null): List<Title> =
        api.get("rpc/finished_titles?select=$TITLE_COLUMNS&p_limit=$limit" + (kind?.let { "&p_kind=${it.db}" } ?: "")).objects().map(::title)

    /** Home: of the newest titles, the ranking's best, unrated. */
    suspend fun newForYou(limit: Int = 20): List<Title> = api.get("rpc/new_for_you?select=$TITLE_COLUMNS&p_limit=$limit").objects().map(::title)

    /** "Customers also liked": the cards nearest in WTW's taste space, the user's best first. */
    suspend fun alsoLiked(title: Title, limit: Int = 20): List<Title> =
        api.get("rpc/also_liked?select=$TITLE_COLUMNS&p_title=${title.id}&p_limit=$limit").objects().map(::title)

    /** Home: titles loved or liked in WTW. */
    suspend fun watchAgain(limit: Int = 20, kind: Kind? = null): List<Title> =
        api.get("rpc/watch_again?select=$TITLE_COLUMNS&p_limit=$limit" + (kind?.let { "&p_kind=${it.db}" } ?: "")).objects().map(::title)

    /**
     * Asks the server to rank the catalog from the user's WTW data (`wtwToken`
     * is their WTW session). Cheap when a recent ranking exists: the server
     * keeps it. True when a new ranking was made.
     */
    suspend fun refreshRanking(wtwToken: String): Boolean =
        !JSONObject(api.function("rank", JSONObject().put("wtw_token", wtwToken).toString())).optBoolean("fresh")

    /**
     * WTW's own "% match" for these cards, asked of WTW by the server (`wtw-scores`):
     * card id to the percent WTW shows, null when WTW does not score the title.
     * Cards WTW could not be asked about this time are left out.
     */
    suspend fun wtwScores(wtwToken: String, ids: List<Long>): Map<Long, Int?> {
        val body = JSONObject().put("wtw_token", wtwToken).put("title_ids", JSONArray(ids))
        val scores = JSONObject(api.function("wtw-scores", body.toString())).optJSONObject("scores") ?: return emptyMap()
        return scores.keys().asSequence().associate { it.toLong() to if (scores.isNull(it)) null else scores.getInt(it) }
    }

    /** One page of a category in the given order. */
    suspend fun page(category: Category, sort: Sort, hebrew: Boolean, offset: Int, limit: Int): List<Title> =
        api.get(pagePath(category, sort, hebrew, offset, limit)).objects().map(::title)

    /**
     * A series' episodes in order, one per season and number (see [oneEach]).
     * Read 1,000 at a time: the REST API returns no more per call, and daily
     * shows have up to 1,500.
     */
    suspend fun episodes(series: Title): List<Episode> {
        val all = mutableListOf<Episode>()
        while (true) {
            val page = api.get(episodesPath(series.id, offset = all.size)).objects().map(::episode)
            all += page
            if (page.size < EPISODES_PAGE) return oneEach(all, series.name)
        }
    }

    /**
     * The provider's titles a person is billed in (top 15 billing, from TMDB),
     * as cards, newest first. Read from the cast side: the person's index makes
     * it fast, where filtering titles by cast is not.
     */
    suspend fun personTitles(personId: Int): List<Title> {
        val rows = api.get("title_cast?select=titles($TITLE_COLUMNS,is_primary,available)&person_id=eq.$personId").objects()
            .mapNotNull { it.optJSONObject("titles") }
        // Cast is stored for every copy, so the card is normally among the rows.
        // A copy whose card is not (its enrichment still pending) is resolved to it.
        val missing = cardsMissingFor(rows)
        val cards = if (missing.isEmpty()) emptyList()
        else api.get("titles?select=$TITLE_COLUMNS,is_primary,available&id=in.(${missing.joinToString(",")})").objects()
        return personCards(rows + cards)
    }

    /**
     * Cards whose name contains `query`, in English, Hebrew or the provider's
     * own; names starting with it first. Of one kind, or both.
     */
    suspend fun search(query: String, hebrew: Boolean, kind: Kind? = null): List<Title> {
        val q = query.replace("*", "").trim()
        if (q.isEmpty()) return emptyList()
        return coroutineScope {
            val startsWith = async { api.get(searchPath(q, hebrew, prefix = true, kind)).objects().map(::title) }
            val contains = async { api.get(searchPath(q, hebrew, prefix = false, kind)).objects().map(::title) }
            mergeSearch(startsWith.await(), contains.await())
        }
    }

    /** Actors whose name contains `query` and who are in an available title (of `kind`): the best known first. */
    suspend fun searchPeople(query: String, kind: Kind? = null): List<CastMember> {
        val q = query.trim()
        if (q.length < 2) return emptyList()
        return api.get(peopleSearchPath(q, kind)).objects().map { CastMember(it.getInt("tmdb_id"), it.getString("name"), null, it.text("profile")) }
    }

    /** Billed cast of a title, in order. */
    suspend fun cast(titleId: Long): List<CastMember> =
        api.get("title_cast?select=position,character,people(tmdb_id,name,profile)&title_id=eq.$titleId&order=position").objects().map {
            val p = it.getJSONObject("people")
            CastMember(p.getInt("tmdb_id"), p.getString("name"), it.text("character"), p.text("profile"))
        }

    /** The available copies of a title, the 4K ones first; at least the title itself. */
    suspend fun copies(title: Title): List<Copy> {
        val fourK = categories(title.kind).filter { it.name.contains("4K", ignoreCase = true) }.map { it.id }.toSet()
        val rows = api.get("titles?select=id,ext_id,container_ext,category_ids&group_id=eq.${title.groupId ?: title.id}&available=is.true&order=id").objects()
        return copiesFrom(title, rows, fourK)
    }

    /** Saves where playback stopped: one row per movie, or per episode, and user. */
    suspend fun saveProgress(titleId: Long, episodeId: Long?, positionSecs: Int, durationSecs: Int?) =
        api.post(
            "progress?on_conflict=user_id,title_id,episode_id",
            progressBody(titleId, episodeId, positionSecs, durationSecs),
            prefer = "resolution=merge-duplicates,return=minimal",
        )

    /** A title's saved positions over all its copies, newest first. */
    suspend fun progress(title: Title): List<Progress> =
        api.get("progress?select=$PROGRESS_COLUMNS,titles!inner(group_id)&titles.group_id=eq.${title.groupId ?: title.id}&order=updated_at.desc")
            .objects().map(::progress)

    /** Forgets the saved positions on these copies: the title leaves Continue watching and plays from the start. */
    suspend fun clearProgress(titleIds: Collection<Long>) {
        if (titleIds.isNotEmpty()) api.delete("progress?title_id=in.(${titleIds.joinToString(",")})")
    }

    /** The Continue watching row: titles with a saved position, last watched first. */
    suspend fun continueWatching(): List<ContinueItem> =
        continueItems(
            api.get("progress?select=$PROGRESS_COLUMNS,titles!inner($TITLE_COLUMNS)&titles.available=is.true&order=updated_at.desc&limit=$CONTINUE_ROWS")
                .objects(),
        ).take(CONTINUE_CARDS)

    /** The live categories, in the provider's order. */
    suspend fun liveCategories(): List<LiveCategory> =
        api.get("categories?select=ext_id,name,name_en,name_he&kind=eq.live&order=position").objects()
            .map { LiveCategory(it.getInt("ext_id"), it.getString("name"), it.text("name_en"), it.text("name_he")) }

    /** The available channels by number. shortcut: one call, the API's 1,000-row cap (583 today); page it if the provider passes 1,000. */
    suspend fun channels(): List<Channel> =
        api.get("channels?select=$CHANNEL_COLUMNS&available=is.true&order=num.nullslast,id&limit=1000").objects().map(::channel)

    /** The ids of the user's favourite channels. */
    suspend fun favoriteChannels(): Set<Long> =
        api.get("channel_prefs?select=channel_id&favorite=is.true").objects().mapTo(HashSet()) { it.getLong("channel_id") }

    suspend fun setFavorite(channelId: Long, favorite: Boolean) =
        api.post("channel_prefs?on_conflict=user_id,channel_id", favoriteBody(channelId, favorite), prefer = UPSERT)

    /** Bumped on every watchlist change, so the Watchlist page reads it again. */
    var watchlistVersion by mutableIntStateOf(0)
        private set

    /** The user's rating and watchlist entry for a title's card. */
    suspend fun marks(title: Title): Marks = coroutineScope {
        val rating = async { api.get("ratings?select=rating&title_id=eq.${title.cardId}").objects().firstOrNull()?.text("rating") }
        val listed = async { api.get("watchlist?select=title_id&title_id=eq.${title.cardId}").objects().isNotEmpty() }
        // Pre-filled from WTW (P4-6): the user's WTW rating shows until they rate here.
        // It cannot be cleared from the TV: clearing removes only the WTV rating.
        // `title.id` is the card's copy; `rank` writes a row for every copy of a title.
        val wtw = async { runCatching { api.get("rankings?select=wtw_reaction&title_id=eq.${title.id}").objects().firstOrNull()?.text("wtw_reaction") }.getOrNull() }
        Marks(rating(rating.await()) ?: fromWtw(wtw.await()), listed.await())
    }

    /** Rated titles count as seen: a change reloads Home's and the sections' rows. */
    var ratingsVersion by mutableIntStateOf(0)
        private set

    /** Rates a title's card, or clears its rating with null. */
    suspend fun setRating(title: Title, rating: Rating?) {
        if (rating == null) api.delete("ratings?title_id=eq.${title.cardId}")
        else api.post("ratings?on_conflict=user_id,title_id", ratingBody(title.cardId, rating), prefer = UPSERT)
        ratingsVersion++
    }

    /** How many titles the kind has in all, per provider category and per genre: (tag, id) to count. */
    suspend fun categoryCounts(kind: Kind): Map<Pair<String, Int>, Int> =
        api.get("rpc/category_counts?p_kind=${kind.db}").objects().associate { (it.getString("tag") to it.getInt("id")) to it.getInt("n") }

    suspend fun setWatchlist(title: Title, on: Boolean) {
        if (on) api.post("watchlist?on_conflict=user_id,title_id", JSONObject().put("title_id", title.cardId).toString(), prefer = "resolution=ignore-duplicates,return=minimal")
        else api.delete("watchlist?title_id=eq.${title.cardId}")
        watchlistVersion++
    }

    /**
     * The watchlist, last added first; titles the provider no longer has are left out.
     * shortcut: entries (and ratings) point at the card's copy at the time. If the provider drops
     * that copy, the regroup makes another copy the card and the entry no longer shows, though the
     * title is still there; key them by TMDB id if that happens often.
     */
    suspend fun watchlist(): List<Title> =
        api.get("watchlist?select=added_at,titles!inner($TITLE_COLUMNS)&titles.available=is.true&order=added_at.desc").objects()
            .mapNotNull { it.optJSONObject("titles") }.map(::title)

    /** What the user hid on the Live TV page. */
    suspend fun liveFilters(): LiveFilters = coroutineScope {
        val channels = async { api.get("channel_prefs?select=channel_id&hidden=is.true").objects().mapTo(HashSet()) { it.getLong("channel_id") } }
        val groups = async { api.get("live_group_prefs?select=category_id&hidden=is.true").objects().mapTo(HashSet()) { it.getInt("category_id") } }
        val radio = async { api.get("user_settings?select=show_radio").objects().firstOrNull()?.optBoolean("show_radio", true) ?: true }
        LiveFilters(channels.await(), groups.await(), radio.await())
    }

    suspend fun setChannelHidden(channelId: Long, hidden: Boolean) =
        api.post("channel_prefs?on_conflict=user_id,channel_id", hiddenBody(channelId, hidden), prefer = UPSERT)

    suspend fun setGroupHidden(categoryId: Int, hidden: Boolean) =
        api.post("live_group_prefs?on_conflict=user_id,category_id", groupBody(categoryId, hidden), prefer = UPSERT)

    suspend fun setShowRadio(show: Boolean) =
        api.post("user_settings?on_conflict=user_id", JSONObject().put("show_radio", show).toString(), prefer = UPSERT)

    /** A section's rows: its provider categories, then `extra` (genres), newest first; empty ones left out. */
    suspend fun rows(kind: Kind, perRow: Int = 10, extra: List<Category> = emptyList()): List<Pair<Category, List<Title>>> = coroutineScope {
        (categories(kind) + extra).map { c -> async { rowRequests.withPermit { c to latest(kind, c.id, perRow, c.genre) } } }
            .awaitAll()
            .filter { it.second.isNotEmpty() }
    }
}

/**
 * Rows and grids show cards: one title per group of copies (#56). A card's
 * categories and date are those of all its copies.
 */
private fun cards(kind: Kind, category: Int?, genre: Boolean = false): String =
    "titles?select=$TITLE_COLUMNS&kind=eq.${kind.db}&available=is.true&is_primary=is.true" +
        (category?.let { if (genre) "&tmdb_genre_ids=cs.%7B$it%7D" else "&group_category_ids=cs.%7B$it%7D" } ?: "")

internal fun latestPath(kind: Kind, category: Int?, limit: Int, genre: Boolean = false): String =
    cards(kind, category, genre) + "&order=${Sort.Added.order(hebrew = false)}&limit=$limit"

internal fun recommendedPath(category: Category, offset: Int, limit: Int): String =
    "rpc/recommended_page?select=$TITLE_COLUMNS&p_kind=${category.kind.db}" +
        (if (category.all) "" else "&${if (category.genre) "p_genre" else "p_category"}=${category.id}") +
        "&p_offset=$offset&p_limit=$limit"

internal fun pagePath(category: Category, sort: Sort, hebrew: Boolean, offset: Int, limit: Int): String =
    cards(category.kind, category.id.takeUnless { category.all }, category.genre) + "&order=${sort.order(hebrew)}&offset=$offset&limit=$limit"

private const val TITLE_COLUMNS = "id,ext_id,container_ext,kind,name,title_en,title_he,year,plot,overview_en,overview_he,tmdb_genre_ids,certification," +
    "tmdb_backdrop,tmdb_poster,backdrop_url,poster_url,runtime_min,tmdb_runtime_min,director,cast_names,tmdb_rating,original_language,group_id,wtw_match"

private fun kindOf(db: String): Kind = Kind.entries.firstOrNull { it.db == db } ?: throw ApiException("Unknown kind: $db")

/** A title row from the REST API. */
internal fun title(o: JSONObject) = Title(
    id = o.getLong("id"),
    extId = o.getLong("ext_id"),
    containerExt = o.text("container_ext"),
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
    match = o.int("wtw_match"),
)

/** Ids of the cards of copies in `rows` whose card is not in `rows` itself. */
internal fun cardsMissingFor(rows: List<JSONObject>): Set<Long> {
    val present = rows.filter { it.optBoolean("is_primary") }.map { it.getLong("id") }.toSet()
    return rows.filter { !it.optBoolean("is_primary") && !it.isNull("group_id") }
        .map { it.getLong("group_id") }
        .filterNot { it in present }
        .toSet()
}

/** Cards from a person's title rows: available cards only, newest first, each once. */
internal fun personCards(rows: List<JSONObject>): List<Title> =
    rows.filter { it.optBoolean("is_primary") && it.optBoolean("available") }
        .map(::title)
        .distinctBy { it.id }
        .sortedWith(compareByDescending<Title> { it.year ?: Int.MIN_VALUE }.thenBy { it.id })

/**
 * Cards whose names start with (`prefix`) or contain `query`, over the three
 * names. The value is quoted for PostgREST's `or=(…)` syntax (commas,
 * parentheses and quotes are text) and URL-encoded. `*` is PostgREST's ilike
 * wildcard; `%` and `_` in the query are escaped so they match themselves.
 */
internal fun searchPath(query: String, hebrew: Boolean, prefix: Boolean, kind: Kind? = null): String {
    val literal = query
        .replace("*", "")
        .replace("\\", "\\\\")
        .replace("%", "\\%")
        .replace("_", "\\_")
    // Inside a quoted PostgREST value, backslashes and quotes are escaped once more.
    val quotedBody = literal.replace("\\", "\\\\").replace("\"", "\\\"")
    val pattern = "\"" + (if (prefix) "" else "*") + quotedBody + "*\""
    val or = "(sort_name_en.ilike.$pattern,sort_name_he.ilike.$pattern,name.ilike.$pattern)"
    return "titles?select=$TITLE_COLUMNS&is_primary=is.true&available=is.true" + (kind?.let { "&kind=eq.${it.db}" } ?: "") +
        "&or=${java.net.URLEncoder.encode(or, "UTF-8").replace("+", "%20")}" +
        "&order=${Sort.Name.order(hebrew)}&limit=$SEARCH_LIMIT"
}

internal const val SEARCH_LIMIT = 60

/** The actors search, the query URL-encoded. */
internal fun peopleSearchPath(query: String, kind: Kind?): String =
    "rpc/search_people?p_query=" + java.net.URLEncoder.encode(query, "UTF-8").replace("+", "%20") + (kind?.let { "&p_kind=${it.db}" } ?: "")

/** Rows read for Continue watching: a series has a row per episode watched. */
private const val CONTINUE_ROWS = 200
private const val CONTINUE_CARDS = 20

/** Names that start with the query first (each fetched on its own, so the limit cannot cut them), then the rest. */
internal fun mergeSearch(startsWith: List<Title>, contains: List<Title>): List<Title> =
    (startsWith + contains).distinctBy { it.id }.take(SEARCH_LIMIT)

internal const val EPISODES_PAGE = 1000

internal fun episodesPath(seriesId: Long, offset: Int): String =
    "episodes?select=id,ext_id,container_ext,season,episode,name,name_en,name_he,overview_en,overview_he,plot,duration_secs,tmdb_still,image_url" +
        "&title_id=eq.$seriesId&available=is.true&order=season,episode,id&offset=$offset&limit=$EPISODES_PAGE"

internal fun episode(o: JSONObject) = Episode(
    id = o.getLong("id"),
    extId = o.getLong("ext_id"),
    containerExt = o.text("container_ext"),
    season = o.getInt("season"),
    number = o.getInt("episode"),
    nameEn = o.text("name_en"),
    nameHe = o.text("name_he"),
    overviewEn = o.text("overview_en"),
    overviewHe = o.text("overview_he"),
    plot = o.text("plot"),
    durationSecs = o.int("duration_secs"),
    tmdbStill = o.text("tmdb_still"),
    providerImage = o.text("image_url"),
    providerName = o.text("name"),
)

/**
 * One episode per season and number, in order. The provider lists some
 * several times: an older upload of the same file, or another series'
 * episode filed under this one. The copy named after the series wins, then
 * the newest (the provider's ids grow).
 */
internal fun oneEach(episodes: List<Episode>, seriesName: String): List<Episode> =
    episodes.groupBy { it.season to it.number }.values.map { copies ->
        copies.maxWith(compareBy<Episode>({ it.providerName?.startsWith(seriesName) == true }, { it.extId }))
    }

/**
 * A title as its only copy: what Play uses when the copies are not known.
 * For a grouped title whose copies all went unavailable this copy may not
 * play either; playback (P3-1) must show a failed stream as an error.
 */
fun Title.asCopy(): Copy = Copy(id, extId, containerExt, is4k = false)

/** Copies from rows of `titles`; a copy is 4K when it is in one of `fourK` (categories named with "4K"). */
internal fun copiesFrom(title: Title, rows: List<JSONObject>, fourK: Set<Int>): List<Copy> =
    rows.map { o ->
        val cats = o.optJSONArray("category_ids")?.let { a -> List(a.length()) { a.getInt(it) } } ?: emptyList()
        Copy(o.getLong("id"), o.getLong("ext_id"), o.text("container_ext"), cats.any { it in fourK })
    }
        .ifEmpty { listOf(title.asCopy()) }
        .sortedByDescending { it.is4k }

/** Button labels for the copies: "4K", "HD", and "HD 1", "HD 2" when there are several HD copies. */
fun copyLabels(copies: List<Copy>): List<String> {
    val numberHd = copies.count { !it.is4k } > 1
    var hd = 0
    return copies.map { if (it.is4k) "4K" else if (numberHd) "HD ${++hd}" else "HD" }
}

private fun JSONObject.int(key: String): Int? = if (isNull(key) || !has(key)) null else getInt(key)

internal fun JSONArray.objects(): List<JSONObject> = List(length()) { getJSONObject(it) }

/** The string at `key`, or null for a missing, null or blank value. */
internal fun JSONObject.text(key: String): String? = if (isNull(key)) null else optString(key).takeIf { it.isNotBlank() }

private const val UPSERT = "resolution=merge-duplicates,return=minimal"
