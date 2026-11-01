import 'package:serverdeck_engine/hosting/in_process_gateway.dart';
import 'package:serverdeck_engine/hosting/worker_power.dart';
import 'package:test/test.dart';

void main() {
  test(
    'private power intent has exact fields and bounded positive epoch/deadline',
    () {
      final value = WorkerPowerIntent(1, true, 30000000);
      final copy = WorkerPowerIntent.fromFrame(value.toFrame());
      expect(copy.epoch, 1);
      expect(copy.suspended, isTrue);
      for (final frame in [
        {...value.toFrame(), 'role': 'owner'},
        {...value.toFrame(), 'epoch': 0},
        {...value.toFrame(), 'suspended': 1},
        {...value.toFrame(), 'expiresAt': 0},
      ]) {
        expect(
          () => WorkerPowerIntent.fromFrame(frame),
          throwsA(anyOf(isA<EngineCallFailure>(), isA<FormatException>())),
        );
      }
    },
  );
  test(
    'startup queue coalesces power ahead of begin and preserves ordinary quota',
    () {
      final queue = WorkerStartupQueue();
      for (var i = 1; i <= 26; i++) {
        queue.add({'kind': 'readiness', 'sequence': i});
      }
      expect(
        () => queue.add({'kind': 'readiness', 'sequence': 27}),
        throwsA(isA<EngineCallFailure>()),
      );
      for (var i = 1; i <= 1000; i++) {
        queue.add(WorkerPowerIntent(i, i.isOdd, 30000000).toFrame());
      }
      queue.add(WorkerPowerIntent(1, true, 30000000).toFrame());
      final frames = queue.takeForStart();
      expect(frames.length, 28);
      expect(frames.first['epoch'], 1000);
      expect(frames.first['suspended'], isFalse);
      expect(frames[1], {'kind': 'begin'});
      expect(
        frames.skip(2).map((f) => f['sequence']),
        List.generate(26, (i) => i + 1),
      );
      expect(queue.takeForStart(), [
        {'kind': 'begin'},
      ]);
    },
  );
}
