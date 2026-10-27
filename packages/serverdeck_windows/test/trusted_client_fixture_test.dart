import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/trusted_client_fixture.dart';

Future<(Object, StackTrace)> failure(Future<void> future) async {
  try {
    await future;
  } catch (error, stack) {
    return (error, stack);
  }
  throw StateError('EXPECTED_FAILURE');
}

void main() {
  test('body settles before cleanup and caller awaits cleanup', () async {
    final body = Completer<void>(), cleanup = Completer<void>();
    var cleaning = false, finished = false;
    final result = runOwnedFixtureLifecycle(
      body: () => body.future,
      cleanup: () {
        cleaning = true;
        return cleanup.future;
      },
    ).then((_) => finished = true);
    await Future<void>.value();
    expect(cleaning, isFalse);
    body.complete();
    await Future<void>.value();
    expect(cleaning, isTrue);
    expect(finished, isFalse);
    cleanup.complete();
    await result;
    expect(finished, isTrue);
  });

  for (final bodyFails in [true, false]) {
    test('exact single error and stack: body=$bodyFails', () async {
      final error = StateError('private single');
      final stack = StackTrace.fromString('ORIGINAL_SINGLE_STACK');
      final observed = <Object>[];
      final outcome = await failure(
        runOwnedFixtureLifecycle(
          body: () async {
            if (bodyFails) Error.throwWithStackTrace(error, stack);
          },
          cleanup: () async {
            if (!bodyFails) Error.throwWithStackTrace(error, stack);
          },
          onFirstFailure: (error, stack) => observed.add(error),
        ),
      );
      expect(identical(outcome.$1, error), isTrue);
      expect(identical(outcome.$2, stack), isTrue);
      expect(outcome.$2.toString(), stack.toString());
      expect(observed, [same(error)]);
    });
  }

  test(
    'both failures preserve primary prefix, stack and secondary details',
    () async {
      final primary = StateError('PRIVATE_PRIMARY');
      final secondary = StateError('PRIVATE_SECONDARY');
      final firstStack = StackTrace.fromString('PRIMARY_STACK');
      final secondStack = StackTrace.fromString('SECONDARY_STACK');
      var observedBeforeCleanup = false;
      final outcome = await failure(
        runOwnedFixtureLifecycle(
          body: () async => Error.throwWithStackTrace(primary, firstStack),
          cleanup: () async {
            expect(observedBeforeCleanup, isTrue);
            Error.throwWithStackTrace(secondary, secondStack);
          },
          onFirstFailure: (error, stack) {
            expect(identical(error, primary), isTrue);
            observedBeforeCleanup = true;
            throw StateError('REFUSED_OBSERVER');
          },
        ),
      );
      final combined = outcome.$1 as OwnedFixtureFailure;
      expect(identical(combined.primary, primary), isTrue);
      expect(identical(combined.secondary, secondary), isTrue);
      expect(combined.primaryStack.toString(), firstStack.toString());
      expect(combined.secondaryStack.toString(), secondStack.toString());
      expect(combined.toString(), startsWith(primary.toString()));
      expect(
        combined.toString(),
        contains('\nOWNED_FIXTURE_CLEANUP_FAILURE:\n'),
      );
      expect(outcome.$2.toString(), firstStack.toString());
    },
  );

  test('cleanup-only observer refusal cannot mask exact outcome', () async {
    final error = StateError('CLEANUP_ONLY');
    final result = await failure(
      runOwnedFixtureLifecycle(
        body: () async {},
        cleanup: () async => throw error,
        onFirstFailure: (_, _) => throw StateError('OBSERVER_REFUSAL'),
      ),
    );
    expect(identical(result.$1, error), isTrue);
  });

  test('cleanup failure cannot replace an earlier body error', () async {
    final primary = StateError('BODY_FAILURE');
    final secondary = StateError('CLEANUP_FAILURE');
    final stack = StackTrace.fromString('ORIGINAL_BODY_STACK');
    final result = await failure(
      runOwnedFixtureLifecycle(
        body: () async => Error.throwWithStackTrace(primary, stack),
        cleanup: () async => throw secondary,
      ),
    );
    expect(result.$1, isA<OwnedFixtureFailure>());
    final aggregate = result.$1 as OwnedFixtureFailure;
    expect(identical(aggregate.primary, primary), isTrue);
    expect(identical(aggregate.secondary, secondary), isTrue);
    expect(result.$2.toString(), stack.toString());
  });

  group('bounded owned safe record', () {
    late Directory root;
    late File file;
    setUp(() {
      root = Directory.systemTemp.createTempSync('trusted-client-record-');
      file = File(p.join(root.path, trustedClientFailureBasename));
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('all seven phases and eight native codes plus null roundtrip', () {
      for (final phase in trustedClientFailurePhases) {
        for (final code in [...trustedClientFailureCodes, null]) {
          TrustedClientFailureRecorder(root.path)
              .record(phase, StateError(code ?? 'private'));
          final record = readTrustedClientFailure(root.path)!;
          expect(record.phase, phase);
          expect(record.code, code);
          expect(
            record.reasonMarker,
            'TRUSTED_CLIENT_FIXTURE_FAILURE:$phase:${code ?? '-'}',
          );
          expect(file.lengthSync(), lessThanOrEqualTo(128));
          expect(file.readAsStringSync(), '1|$phase|${code ?? '-'}\n');
        }
      }
    });

    test('classification never uses raw toString and timeout is exact', () {
      expect(trustedClientSafeCode(TimeoutException('PRIVATE')), 'TIMEOUT');
      expect(trustedClientSafeCode(StateError('UNAUTHORIZED suffix')), isNull);
      expect(trustedClientSafeCode(_NoString()), isNull);
      TrustedClientFailureRecorder(root.path).record('rpc-write', _NoString());
      expect(file.readAsStringSync(), '1|rpc-write|-\n');
    });

    test('secondary never overwrites first record; invalid phase refused', () {
      final recorder = TrustedClientFailureRecorder(root.path);
      recorder.record('rpc-read', StateError('TIMEOUT'));
      recorder.record('cleanup-worker', StateError('UNAUTHORIZED'));
      expect(file.readAsStringSync(), '1|rpc-read|TIMEOUT\n');
      file.deleteSync();
      TrustedClientFailureRecorder(root.path)
          .record('PRIVATE_PHASE', _NoString());
      expect(file.existsSync(), isFalse);
    });

    test(
      'missing unreadable malformed oversized and trailing records refused',
      () {
        expect(readTrustedClientFailure(root.path), isNull);
        for (final value in [
          '',
          '1|rpc-read|TIMEOUT',
          '1|rpc-read|TIMEOUT\r\n',
          '1|rpc-read|TIMEOUT\nextra',
          '1|rpc-read|TIMEOUT\n\n',
          '2|rpc-read|TIMEOUT\n',
          '1|unknown|TIMEOUT\n',
          '1|rpc-read|PRIVATE\n',
          '1|rpc-read|timeout\n',
          ' 1|rpc-read|TIMEOUT\n',
          'a' * 129,
          'a' * 128,
        ]) {
          file.writeAsStringSync(value);
          expect(readTrustedClientFailure(root.path), isNull, reason: value);
        }
        file.writeAsBytesSync([...ascii.encode('1|rpc-read|-\n'), 255]);
        expect(readTrustedClientFailure(root.path), isNull);
        file.deleteSync();
        Directory(file.path).createSync();
        expect(readTrustedClientFailure(root.path), isNull);
      },
    );

    test('writer refusal does not replace original fixture error', () async {
      final error = StateError('UNAUTHORIZED');
      Directory(file.path).createSync();
      final outcome = await failure(
        runOwnedFixtureLifecycle(
          body: () async => throw error,
          cleanup: () async {},
          onFirstFailure: (error, _) =>
              TrustedClientFailureRecorder(root.path)
                  .record('bootstrap', error),
        ),
      );
      expect(identical(outcome.$1, error), isTrue);
    });
  });
}

final class _NoString {
  @override
  String toString() => throw StateError('MUST_NOT_CLASSIFY_RAW_TEXT');
}
