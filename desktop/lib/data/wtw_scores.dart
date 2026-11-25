import 'dart:async';

import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'semaphore.dart';
import 'session.dart';

/// WTW's own "% match" for the cards on screen, asked of WTW a few at a time
/// (Catalog.wtwScores) while WTW is connected. Answers fill in as they arrive
/// (listeners are told); cards already answered within the server's 12 hours
/// come with their titles (`Title.match`).
class WtwScores extends ChangeNotifier {
  WtwScores(this._catalog, this._wtw);

  final Catalog _catalog;
  final Session _wtw;
  final _known = <int, int?>{};
  final _asked = <int>{};
  final _calls = Semaphore(_parallelCalls);

  /// The WTW account the answers are for: another account's are dropped.
  String? _account;

  /// WTW's percent for this card once answered; null before, or when WTW does not score it.
  int? operator [](int id) => _known[id];

  /// What a title's card shows: WTW's own percent once answered, else the one that came with
  /// the title; null while WTW is not connected.
  int? matchOf(Title title) {
    final email = _wtw.email;
    if (email == null) return null;
    return (email == _account ? _known[title.id] : null) ?? title.match;
  }

  /// Asks for the titles that came without a percent.
  void requestFor(Iterable<Title> titles) => request([for (final t in titles) if (t.match == null) t.id]);

  /// Asks for the cards not asked yet, in order (the first rows first).
  void request(List<int> ids) {
    final email = _wtw.email;
    if (email == null) return;
    if (email != _account) {
      final had = _known.isNotEmpty;
      _known.clear();
      _asked.clear();
      _account = email;
      // Told after this call returns: it may be made while a page is being built.
      if (had) scheduleMicrotask(notifyListeners);
    }
    final fresh = ids.where(_asked.add).toList();
    for (var i = 0; i < fresh.length; i += _perCall) {
      final chunk = fresh.skip(i).take(_perCall).toList();
      unawaited(
        _calls.withPermit(() async {
          // Answers for an account switched away from meanwhile are dropped.
          if (_account != email) return;
          try {
            final answers = await _catalog.wtwScores(await _wtw.token(minSeconds: _tokenMinSeconds), chunk);
            if (_account == email) {
              _known.addAll(answers);
              notifyListeners();
            }
          } on Exception catch (e) {
            // A nicety: the cards stay without a number, and are asked again next time.
            if (_account == email) _asked.removeAll(chunk);
            debugPrint('WtwScores: Not answered: $e');
          }
        }),
      );
    }
  }
}

/// Titles per server call: WTW answers them at once, within the app's 20 s call timeout
/// when it is not slowed by the other calls; a call that times out is asked again later.
const _perCall = 6;
// Six at once: WTW takes about 10 s a title, and the owner asked for faster filling than the TV's two.
const _parallelCalls = 6;

/// The server refuses a WTW token about to expire: it must outlive the calls.
const _tokenMinSeconds = 300;
