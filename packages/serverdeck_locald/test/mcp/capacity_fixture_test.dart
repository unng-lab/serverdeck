import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/capacity_fixture.dart';

void main() {
  test(
    'prefill calls at most 20000 independent commits and reports buckets',
    () async {
      var calls = 0, classified = 0;
      final buckets = <int>[];
      final full = await prefillCapacityFixture(
        commitSync: () => calls++,
        isCapacityFailure: (_) {
          classified++;
          return false;
        },
        onBucket: buckets.add,
      );
      expect(full, isFalse);
      expect(calls, 20000);
      expect(classified, 0);
      expect(buckets, [
        for (var count = 0; count <= 20000; count += 1000) count,
      ]);
    },
  );

  test(
    'only a classified native failure marks full and stops commits',
    () async {
      final nativeFailure = Object();
      var calls = 0, classified = 0;
      final full = await prefillCapacityFixture(
        commitSync: () {
          calls++;
          if (calls == 3) throw nativeFailure;
        },
        isCapacityFailure: (error) {
          expect(error, same(nativeFailure));
          classified++;
          return true;
        },
      );
      expect(full, isTrue);
      expect(calls, 3);
      expect(classified, 1);
    },
  );

  test(
    'unclassified failure retains its identity and original stack',
    () async {
      final failure = StateError('synthetic noncapacity failure');
      final originalStack = StackTrace.fromString('original commit stack');
      var calls = 0, classified = 0;
      try {
        await prefillCapacityFixture(
          commitSync: () {
            calls++;
            Error.throwWithStackTrace(failure, originalStack);
          },
          isCapacityFailure: (error) {
            expect(error, same(failure));
            classified++;
            return false;
          },
        );
        fail('the original commit error must propagate');
      } catch (error, stack) {
        expect(error, same(failure));
        expect(stack.toString(), originalStack.toString());
      }
      expect(calls, 1);
      expect(classified, 1);
    },
  );

  test('each 16 successful commits gives timers an event queue turn', () async {
    final nativeFailure = Object();
    final timerTurns = <int>[];
    var calls = 0;
    final full = await prefillCapacityFixture(
      commitSync: () {
        calls++;
        if (calls == 65) throw nativeFailure;
        if ((calls - 1) % 16 == 0) Timer.run(() => timerTurns.add(calls));
      },
      isCapacityFailure: (error) => identical(error, nativeFailure),
    );
    expect(full, isTrue);
    expect(calls, 65);
    expect(timerTurns, [16, 32, 48, 64]);
  });

  test('observer failure cannot mask a commit outcome', () async {
    final nativeFailure = Object();
    final full = await prefillCapacityFixture(
      commitSync: () => throw nativeFailure,
      isCapacityFailure: (error) => identical(error, nativeFailure),
      onBucket: (_) => throw StateError('synthetic observer failure'),
    );
    expect(full, isTrue);
  });

  group('checked capacity phase file', () {
    late Directory root;
    File phaseFile() => File(
      '${root.path}${Platform.pathSeparator}$capacityFixturePhaseFileName',
    );

    setUp(() {
      root = Directory.systemTemp.createTempSync('serverdeck-capacity-phase-');
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('all 31 fixed phases round trip within the ASCII byte bound', () {
      expect(capacityFixturePhaseTokens, {
        'capacity-start',
        'capacity-reader-ready',
        for (var count = 0; count <= 20000; count += 1000)
          'capacity-prefill-$count',
        'capacity-full',
        'capacity-confirm-refused',
        'capacity-reader-released',
        'capacity-recovery-confirm',
        'capacity-recovered',
        'capacity-replay-verified',
        'capacity-revoke-verified',
        'capacity-complete',
      });
      for (final phase in capacityFixturePhaseTokens) {
        writeCapacityFixturePhase(root.path, phase);
        final bytes = phaseFile().readAsBytesSync();
        expect(bytes.length, lessThanOrEqualTo(64));
        expect(bytes.every((value) => value <= 127), isTrue);
        expect(ascii.decode(bytes), '$phase\n');
        expect(readCapacityFixturePhase(root.path), phase);
      }
    });

    test('missing and unreadable observations become unknown', () {
      expect(readCapacityFixturePhase(root.path), capacityFixtureUnknownPhase);
      Directory(phaseFile().path).createSync();
      expect(readCapacityFixturePhase(root.path), capacityFixtureUnknownPhase);
    });

    test('partial, invalid, non-ASCII and oversized values become unknown', () {
      final invalid = <List<int>>[
        [],
        ascii.encode('capacity-start'),
        ascii.encode('capacity-prefill-1000'),
        ascii.encode('capacity-start\r\n'),
        ascii.encode('capacity-start\n\n'),
        ascii.encode(' capacity-start\n'),
        ascii.encode('capacity-start \n'),
        ascii.encode('capacity-prefill-999\n'),
        ascii.encode('capacity-prefill--1000\n'),
        ascii.encode('capacity-prefill-20001\n'),
        ascii.encode('capacity-prefill-21000\n'),
        ascii.encode('foreign-private-value\n'),
        [255, 10],
        [...List<int>.filled(64, 97), 10],
      ];
      for (final bytes in invalid) {
        phaseFile().writeAsBytesSync(bytes, flush: true);
        expect(
          readCapacityFixturePhase(root.path),
          capacityFixtureUnknownPhase,
        );
      }
    });

    test('invalid writer input replaces an earlier phase with unknown', () {
      writeCapacityFixturePhase(root.path, 'capacity-start');
      writeCapacityFixturePhase(root.path, 'private-invalid-token');
      expect(readCapacityFixturePhase(root.path), capacityFixtureUnknownPhase);
      expect(phaseFile().readAsStringSync(), 'unknown\n');
    });

    test('writer filesystem failure remains observational', () {
      final rootFile = File(
        '${root.path}${Platform.pathSeparator}not-a-directory',
      )..writeAsStringSync('fixture');
      expect(
        () => writeCapacityFixturePhase(rootFile.path, 'capacity-start'),
        returnsNormally,
      );
      expect(
        readCapacityFixturePhase(rootFile.path),
        capacityFixtureUnknownPhase,
      );
    });
  });
}
