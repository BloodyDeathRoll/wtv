import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wtv/data/marks.dart';

void main() {
  test('ratings read from the database words, and unknown ones are none', () {
    expect(rating('love'), Rating.love);
    expect(rating('dislike'), Rating.dislike);
    expect(rating('meh'), isNull);
    expect(rating(null), isNull);
  });

  test('the rating body names the card and the word', () {
    expect(jsonDecode(ratingBody(42, Rating.like)), {'title_id': 42, 'rating': 'like'});
  });

  test('WTW reactions become ratings, anything else none', () {
    expect(fromWtw('loved'), Rating.love);
    expect(fromWtw('liked'), Rating.like);
    expect(fromWtw('disliked'), Rating.dislike);
    expect(fromWtw('mixed'), isNull);
    expect(fromWtw(null), isNull);
  });
}
