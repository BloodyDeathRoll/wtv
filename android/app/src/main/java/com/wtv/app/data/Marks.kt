package com.wtv.app.data

import org.json.JSONObject

/** Love / Like / Dislike, as WTW has them. */
enum class Rating(val db: String) { Love("love"), Like("like"), Dislike("dislike") }

/** The user's rating and watchlist entry for a card. */
data class Marks(val rating: Rating? = null, val onWatchlist: Boolean = false)

/** Ratings and the watchlist belong to the card: one title over all its copies. */
internal val Title.cardId: Long get() = groupId ?: id

internal fun rating(db: String?): Rating? = Rating.entries.firstOrNull { it.db == db }

/** WTW's reaction (loved, liked, disliked) as a rating. */
internal fun fromWtw(reaction: String?): Rating? = when (reaction) {
    "loved" -> Rating.Love
    "liked" -> Rating.Like
    "disliked" -> Rating.Dislike
    else -> null
}

internal fun ratingBody(titleId: Long, rating: Rating): String = JSONObject().put("title_id", titleId).put("rating", rating.db).toString()
