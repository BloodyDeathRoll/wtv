import 'dart:async';
import 'dart:collection';

/// At most `permits` bodies run at once; the others wait their turn, first come first.
class Semaphore {
  Semaphore(int permits) : _free = permits;

  int _free;
  final _waiting = Queue<Completer<void>>();

  Future<T> withPermit<T>(Future<T> Function() body) async {
    if (_free > 0) {
      _free--;
    } else {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    try {
      return await body();
    } finally {
      // The next one waiting takes this permit over; it is never free in between.
      if (_waiting.isEmpty) {
        _free++;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }
}
