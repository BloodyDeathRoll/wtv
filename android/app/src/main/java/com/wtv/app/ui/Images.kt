package com.wtv.app.ui

/** TMDB image sizes the app uses. */
enum class TmdbSize(val path: String) {
    Poster("w342"),
    Card("w780"),
    Backdrop("w1280"),
    Profile("w185"),
}

/** A TMDB image path ("/abc.jpg") as a URL, or null. */
fun tmdbImage(path: String?, size: TmdbSize): String? =
    path?.let { "https://image.tmdb.org/t/p/${size.path}$it" }
