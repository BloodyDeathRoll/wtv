package com.wtv.app.ui

/**
 * TMDB image sizes the app uses. TMDB serves backdrops only at w300, w780
 * and w1280: w300 is too soft for a 400 px card, so cards use w780.
 */
enum class TmdbSize(val path: String) {
    Poster("w342"),
    Card("w780"),
    Backdrop("w1280"),
    Profile("w185"),
}

/** A TMDB image path ("/abc.jpg") as a URL, or null. */
fun tmdbImage(path: String?, size: TmdbSize): String? =
    path?.let { "https://image.tmdb.org/t/p/${size.path}$it" }
