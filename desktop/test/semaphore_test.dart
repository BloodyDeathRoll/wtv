import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wtv/data/semaphore.dart';

void main() {
  test('no more than the permits run at once, in the order asked', () async {
    final two = Semaphore(2);
    var running = 0, most = 0;
    final order = <int>[];
    await Future.wait([
      for (var i = 0; i < 7; i++)
        two.withPermit(() async {
          most = max(most, ++running);
          order.add(i);
          await Future<void>.delayed(Duration.zero);
          running--;
        }),
    ]);
    expect(most, 2);
    expect(order, [0, 1, 2, 3, 4, 5, 6]);
  });

  test('a body that fails gives its permit back', () async {
    final one = Semaphore(1);
    await expectLater(one.withPermit<int>(() async => throw StateError('failed')), throwsStateError);
    expect(await one.withPermit(() async => 1), 1);
  });
}
