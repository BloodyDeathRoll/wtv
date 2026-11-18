package com.wtv.app.data

import org.json.JSONObject

/**
 * Where playback of a movie or one episode stopped. Episodes are known by
 * season and number, not id: a series' copies each have their own episode rows.
 */
data class Progress(val titleId: Long, val season: Int?, val episode: Int?, val positionSecs: Int, val durationSecs: Int?) {
    val isEpisode: Boolean get() = season != null && episode != null

    /** Watched to the credits: not resumed, and a movie leaves Continue watching. */
    val finished: Boolean get() = durationSecs != null && durationSecs > 0 && positionSecs >= durationSecs * FINISHED_AT

    /** Where Play starts: the saved position, unless it is at the very start or finished. */
    val resumeSecs: Int get() = if (finished || positionSecs < MIN_RESUME_SECS) 0 else positionSecs

    /** Share watched, for the bar on a card; null when the length is unknown. */
    val fraction: Float? get() = durationSecs?.takeIf { it > 0 }?.let { (positionSecs.toFloat() / it).coerceIn(0f, 1f) }
}

internal const val FINISHED_AT = 0.95
internal const val MIN_RESUME_SECS = 30

/** What Play does on a series page: this episode, from this second. */
data class EpisodePlay(val episode: Episode, val startSecs: Int)

/**
 * Play on a series: the last episode watched if it is unfinished, else the
 * one after it; the first episode when nothing was watched, the last one
 * watched is gone, or it was the series' last.
 * `progress` is newest first; `episodes` in order.
 */
fun nextEpisode(episodes: List<Episode>, progress: List<Progress>): EpisodePlay? {
    val first = episodes.firstOrNull() ?: return null
    val last = progress.firstOrNull { it.isEpisode } ?: return EpisodePlay(first, 0)
    val i = episodes.indexOfFirst { it.season == last.season && it.number == last.episode }
    return when {
        i < 0 -> EpisodePlay(first, 0)
        !last.finished -> EpisodePlay(episodes[i], last.resumeSecs)
        else -> EpisodePlay(episodes.getOrNull(i + 1) ?: first, 0)
    }
}

/** The episode after `episodeId` in `episodes` (in order); null after the last, or when it is not there. */
fun episodeAfter(episodes: List<Episode>, episodeId: Long?): Episode? =
    episodes.indexOfFirst { it.id == episodeId }.takeIf { it >= 0 }?.let { episodes.getOrNull(it + 1) }

/** A card in the Continue watching row. */
data class ContinueItem(val title: Title, val progress: Progress)

/**
 * Continue watching from progress rows (newest first, each with its title):
 * one card per title (its copies count as one), from its newest row. A
 * finished movie leaves the row; a series stays, for its next episode.
 */
internal fun continueItems(rows: List<JSONObject>): List<ContinueItem> =
    rows.mapNotNull { o -> o.optJSONObject("titles")?.let { ContinueItem(title(it), progress(o)) } }
        .distinctBy { it.title.groupId ?: it.title.id }
        .filterNot { !it.progress.isEpisode && it.progress.finished }

internal const val PROGRESS_COLUMNS = "title_id,position_secs,duration_secs,episodes(season,episode)"

/** A progress row from the REST API, with its episode's season and number embedded. */
internal fun progress(o: JSONObject): Progress {
    val e = o.optJSONObject("episodes")
    return Progress(
        titleId = o.getLong("title_id"),
        season = e?.getInt("season"),
        episode = e?.getInt("episode"),
        positionSecs = o.getInt("position_secs"),
        durationSecs = if (o.isNull("duration_secs") || !o.has("duration_secs")) null else o.getInt("duration_secs"),
    )
}

/** The JSON body that saves a position. The user is the database's: the signed-in one. */
internal fun progressBody(titleId: Long, episodeId: Long?, positionSecs: Int, durationSecs: Int?): String =
    JSONObject()
        .put("title_id", titleId)
        .put("episode_id", episodeId ?: JSONObject.NULL)
        .put("position_secs", positionSecs)
        .put("duration_secs", durationSecs ?: JSONObject.NULL)
        .toString()
