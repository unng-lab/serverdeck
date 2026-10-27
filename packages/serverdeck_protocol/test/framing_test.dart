import 'dart:async';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/framing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'partial deadline counts from first bytes despite a slow drip',
    () async {
      var reads = 0;
      final deadlines = <Duration>[];
      final reader = FramedReader((deadline) async {
        deadlines.add(deadline);
        // Keep the frame incomplete: the old 5-byte payload could finish
        // within the deadline as its geometric delays approached zero.
        if (reads++ == 0) return [0, 16, 0, 0];
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return [0];
      }, partialDeadline: const Duration(milliseconds: 80));
      final timer = Stopwatch()..start();
      await expectLater(reader.readFrame(), throwsA(isA<TimeoutException>()));
      expect(timer.elapsedMilliseconds, lessThan(500));
      expect(deadlines.first, const Duration(seconds: 60));
      expect(
        deadlines.skip(1).every((d) => d <= const Duration(milliseconds: 80)),
        isTrue,
      );
      await expectLater(reader.readFrame(), throwsA(isA<StateError>()));
    },
  );
  test(
    'preserves coalesced complete frames and starts a new partial deadline',
    () async {
      final frames = frameBytes([1, 2, 3]);
      var reads = 0;
      final reader = FramedReader((deadline) async {
        return reads++ == 0 ? [...frames, ...frames, 3, 0] : [0, 0, 4, 5, 6];
      });
      expect(await reader.readFrame(), [1, 2, 3]);
      expect(await reader.readFrame(), [1, 2, 3]);
      expect(reads, 1);
      expect(await reader.readFrame(), [4, 5, 6]);
    },
  );
  test(
    'rejects overlapping reads, EOF and bounded chunk/frame failures',
    () async {
      final pending = Completer<List<int>>();
      final reader = FramedReader((_) => pending.future);
      final first = reader.readFrame();
      await expectLater(reader.readFrame(), throwsA(isA<StateError>()));
      final assertion = expectLater(first, throwsA(isA<StateError>()));
      pending.complete([]);
      await assertion;
      for (final bytes in [
        [0, 0, 0, 0],
        List.filled(65537, 1),
      ]) {
        final malformed = FramedReader((_) async => bytes);
        await expectLater(malformed.readFrame(), throwsFormatException);
        await expectLater(malformed.readFrame(), throwsA(isA<StateError>()));
      }
    },
  );
}
