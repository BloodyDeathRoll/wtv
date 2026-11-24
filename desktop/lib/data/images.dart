/// TMDB image sizes the app uses. TMDB serves backdrops only at w300, w780
/// and w1280: w300 is too soft for a 400 px card, so cards use w780.
enum TmdbSize {
  poster('w342'),
  card('w780'),
  backdrop('w1280'),
  profile('w185'),

  /// Episode stills: TMDB serves them at w92, w185, w300 and original only.
  still('w300');

  const TmdbSize(this.path);

  final String path;
}

/// A TMDB image path ("/abc.jpg") as a URL, or null.
String? tmdbImage(String? path, TmdbSize size) => path == null ? null : 'https://image.tmdb.org/t/p/${size.path}$path';
