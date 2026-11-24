import 'dart:convert';

import 'catalog.dart';

/// Love / Like / Dislike, as WTW has them.
enum Rating {
  love('love'),
  like('like'),
  dislike('dislike');

  const Rating(this.db);

  final String db;
}

/// The user's rating and watchlist entry for a card.
class Marks {
  const Marks({this.rating, this.onWatchlist = false});

  final Rating? rating;
  final bool onWatchlist;

  /// `rating` is a function, so that it can also give null: no rating.
  Marks copyWith({Rating? Function()? rating, bool? onWatchlist}) =>
      Marks(rating: rating == null ? this.rating : rating(), onWatchlist: onWatchlist ?? this.onWatchlist);
}

extension TitleCard on Title {
  /// Ratings and the watchlist belong to the card: one title over all its copies.
  int get cardId => groupId ?? id;
}

Rating? rating(String? db) => Rating.values.where((r) => r.db == db).firstOrNull;

/// WTW's reaction (loved, liked, disliked) as a rating.
Rating? fromWtw(String? reaction) => switch (reaction) {
  'loved' => Rating.love,
  'liked' => Rating.like,
  'disliked' => Rating.dislike,
  _ => null,
};

String ratingBody(int titleId, Rating rating) => jsonEncode({'title_id': titleId, 'rating': rating.db});
