package com.wtv.app.data

import org.json.JSONObject

/** A live channel. `num` is the provider's channel number; `archiveDays` > 0 has catch-up. */
data class Channel(
    val id: Long,
    val extId: Long,
    val name: String,
    val num: Int?,
    val logo: String?,
    val archiveDays: Int,
    val isRadio: Boolean,
    val categoryIds: List<Int>,
)

data class LiveCategory(val id: Int, val name: String, val nameEn: String?, val nameHe: String?) {
    fun label(hebrew: Boolean): String = (if (hebrew) nameHe else nameEn) ?: name
}

/** A group of channels on the Live TV page: Favourites (`category` null) or a provider category. */
data class LiveGroup(val category: LiveCategory?, val label: String, val channels: List<Channel>)

internal const val CHANNEL_COLUMNS = "id,ext_id,name,num,logo_url,archive_days,is_radio,category_ids"

internal fun channel(o: JSONObject): Channel {
    val ids = o.optJSONArray("category_ids")
    return Channel(
        id = o.getLong("id"),
        extId = o.getLong("ext_id"),
        name = o.getString("name"),
        num = if (o.isNull("num")) null else o.getInt("num"),
        logo = o.text("logo_url"),
        archiveDays = o.optInt("archive_days"),
        isRadio = o.optBoolean("is_radio"),
        categoryIds = if (ids == null) emptyList() else List(ids.length()) { ids.getInt(it) },
    )
}

/**
 * The page's groups: Favourites first when there are any, then each category
 * in the provider's order. Channels keep the given order; empty groups are left out.
 */
fun liveGroups(channels: List<Channel>, categories: List<LiveCategory>, favorites: Set<Long>, favoritesLabel: String, hebrew: Boolean): List<LiveGroup> {
    val favorite = LiveGroup(null, favoritesLabel, channels.filter { it.id in favorites })
    val byCategory = categories.map { c -> LiveGroup(c, c.label(hebrew), channels.filter { c.id in it.categoryIds }) }
    return (listOf(favorite) + byCategory).filter { it.channels.isNotEmpty() }
}

/** The JSON body that sets a channel's favourite flag. The user is the database's: the signed-in one. */
internal fun favoriteBody(channelId: Long, favorite: Boolean): String =
    JSONObject().put("channel_id", channelId).put("favorite", favorite).toString()
