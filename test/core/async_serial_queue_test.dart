import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luna_cycle/core/async_serial_queue.dart';

void main() {
  test(
    'serializes operations and continues after a failed operation',
    () async {
      final queue = AsyncSerialQueue();
      final firstGate = Completer<void>();
      var running = 0;
      var maxRunning = 0;

      Future<void> operation() async {
        running++;
        if (running > maxRunning) maxRunning = running;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
      }

      final first = queue.run(() async {
        await firstGate.future;
        await operation();
        return 'first';
      });
      final failed = queue.run<void>(() async {
        throw StateError('expected failure');
      });
      final last = queue.run(operation);
      firstGate.complete();

      expect(await first, 'first');
      await expectLater(failed, throwsA(isA<StateError>()));
      await last;
      expect(maxRunning, 1);
      expect(running, 0);
    },
  );
}
