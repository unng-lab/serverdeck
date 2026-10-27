import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/trusted_client_completion.dart';
import 'support/trusted_client_fixture.dart';

Future<void> pump() async {
  for (var n = 0; n < 12; n++) {
    await Future<void>.value();
  }
}

final class ControlledClock implements TrustedClientClock {
  @override
  Duration now = Duration.zero;
  final _timeouts = <void Function()>[];
  @override
  Future<T> wait<T>(Future<T> future, Duration remaining) {
    final deadline = now + remaining;
    final result = Completer<T>();
    final expire = () {
      if (!result.isCompleted && now >= deadline) {
        result.completeError(TimeoutException('CONTROLLED_DEADLINE'));
      }
    };
    _timeouts.add(expire);
    future.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future;
  }

  void advance(Duration duration) {
    now += duration;
    for (final expire in List.of(_timeouts)) {
      expire();
    }
  }
}

final class Child {
  final out = StreamController<List<int>>(sync: true);
  final err = StreamController<List<int>>(sync: true);
  final exit = Completer<int>();
  final clock = ControlledClock();
  final writes = <List<int>>[];
  final flush = Completer<void>();
  final close = Completer<void>();
  int flushes = 0, closes = 0;
  late final completion = TrustedClientCompletion(
    output: out.stream,
    errors: err.stream,
    exit: exit.future,
    write: (bytes) => writes.add(bytes),
    flush: () {
      flushes++;
      return flush.future;
    },
    close: () {
      closes++;
      return close.future;
    },
    clock: clock,
  );

  void ready([String text = trustedClientReady]) => out.add(ascii.encode(text));
  Future<void> finish([int code = 0]) async {
    if (!flush.isCompleted) flush.complete();
    if (!close.isCompleted) close.complete();
    if (!exit.isCompleted) exit.complete(code);
    await out.close();
    await err.close();
  }
}

void main() {
  test(
    'body failure remains primary when bounded child cleanup fails',
    () async {
      final child = Child();
      final primary = StateError('ORIGINAL_BODY_FAILURE');
      final stack = StackTrace.fromString('ORIGINAL_BODY_STACK');
      var killed = false;
      Object? observed;
      final lifecycle = runOwnedFixtureLifecycle(
        body: () async => Error.throwWithStackTrace(primary, stack),
        cleanup: () => child.completion.cleanup(
          kill: () {
            killed = true;
          },
          exit: child.exit.future,
        ),
        onFirstFailure: (error, _) => observed = error,
      );
      final check = expectLater(
        lifecycle,
        throwsA(
          isA<OwnedFixtureFailure>()
              .having((e) => e.primary, 'primary', same(primary))
              .having((e) => e.secondary, 'cleanup', isA<TimeoutException>()),
        ),
      );
      await pump();
      expect(observed, same(primary));
      expect(killed, isTrue);
      child.exit.complete(0);
      await pump();
      child.clock.advance(const Duration(seconds: 5));
      await check;
      await child.finish();
    },
  );

  test(
    'pending close never postpones kill; join observed and shared5s fails',
    () async {
      final child = Child();
      var killed = false, joined = false;
      final joining = child.exit.future.then((code) {
        joined = true;
        return code;
      });
      final cleanup = child.completion.cleanup(
        kill: () {
          killed = true;
        },
        exit: joining,
      );
      expect(killed, isTrue);
      expect(child.closes, 1);
      child.exit.complete(0);
      await pump();
      expect(joined, isTrue);
      final check = expectLater(cleanup, throwsA(isA<TimeoutException>()));
      child.clock.advance(const Duration(seconds: 5));
      await check;
      expect(
        identical(
          cleanup,
          child.completion.cleanup(
            kill: () => fail('SECOND_KILL'),
            exit: child.exit.future,
          ),
        ),
        isTrue,
      );
      child.ready();
      await pump();
      expect(child.writes, isEmpty);
      await child.finish();
    },
  );

  test(
    'cleanup close and join have one5s budget; late READY cannot ACK',
    () async {
      final child = Child();
      final completion = child.completion.complete(const Duration(seconds: 12));
      final completeCheck = expectLater(completion, throwsStateError);
      final cleanup = child.completion.cleanup(
        kill: () {},
        exit: child.exit.future,
      );
      final check = expectLater(cleanup, throwsA(isA<TimeoutException>()));
      await completeCheck;
      child.clock.advance(const Duration(seconds: 3));
      child.close.complete();
      await pump();
      child.clock.advance(const Duration(seconds: 2));
      await check;
      child.ready();
      await pump();
      expect(child.writes, isEmpty);
      await child.finish();
    },
  );

  test(
    'cleanup preserves broad prior IOException policy and other failures',
    () async {
      for (final error in [
        const FileSystemException('OWNED_CLOSED'),
        StateError('CLOSE_FAILURE'),
      ]) {
        final child = Child();
        final cleanup = child.completion.cleanup(
          kill: () {},
          exit: child.exit.future,
        );
        final check = error is IOException
            ? expectLater(cleanup, completes)
            : expectLater(cleanup, throwsA(same(error)));
        child.close.completeError(error);
        child.exit.complete(0);
        await check;
        await child.finish();
      }
    },
  );

  test('exit errors are observed before completion starts', () async {
    final child = Child();
    final completion = child.completion;
    final error = StateError('EARLY_EXIT_ERROR');
    child.exit.completeError(error);
    await pump();
    await expectLater(
      completion.complete(const Duration(seconds: 12)),
      throwsA(same(error)),
    );
    await child.finish();
  });

  test('expired continuation after ACK write cannot flush or close', () async {
    final out = StreamController<List<int>>(sync: true);
    final err = StreamController<List<int>>(sync: true);
    final clock = ControlledClock();
    var flushed = false, closed = false;
    final completion = TrustedClientCompletion(
      output: out.stream,
      errors: err.stream,
      exit: Future.value(0),
      write: (_) => clock.advance(const Duration(seconds: 12)),
      flush: () async {
        flushed = true;
      },
      close: () async {
        closed = true;
      },
      clock: clock,
    );
    out.add(ascii.encode(trustedClientReady));
    await expectLater(
      completion.complete(const Duration(seconds: 12)),
      throwsA(isA<TimeoutException>()),
    );
    expect(flushed, isFalse);
    expect(closed, isFalse);
    await out.close();
    await err.close();
  });

  test(
    'cached completion is published before a reentrant ACK writer',
    () async {
      final out = StreamController<List<int>>(sync: true);
      final err = StreamController<List<int>>(sync: true);
      late TrustedClientCompletion completion;
      Future<int>? reentrant;
      completion = TrustedClientCompletion(
        output: out.stream,
        errors: err.stream,
        exit: Future.value(0),
        write: (_) =>
            reentrant = completion.complete(const Duration(seconds: 12)),
        flush: () async {},
        close: () async {},
      );
      out.add(ascii.encode(trustedClientReady));
      final first = completion.complete(const Duration(seconds: 9));
      expect(identical(first, reentrant), isTrue);
      await out.close();
      await err.close();
      expect(await first, 0);
    },
  );

  test(
    'synchronous write and asynchronous flush failures retain their errors',
    () async {
      for (final writeFails in [true, false]) {
        final out = StreamController<List<int>>(sync: true);
        final err = StreamController<List<int>>(sync: true);
        final error = StateError('ACK_WRITE_OR_FLUSH_FAILED');
        final completion = TrustedClientCompletion(
          output: out.stream,
          errors: err.stream,
          exit: Future.value(0),
          write: (_) {
            if (writeFails) throw error;
          },
          flush: () async => throw error,
          close: () async {},
        );
        out.add(ascii.encode(trustedClientReady));
        await expectLater(
          completion.complete(const Duration(seconds: 12)),
          throwsA(same(error)),
        );
        await out.close();
        await err.close();
      }
    },
  );

  test(
    'fragmented READY while stdout open; ACK flush close precede exit',
    () async {
      final child = Child();
      final completion = child.completion;
      final future = completion.complete(const Duration(seconds: 12));
      child.ready('CLIENT_PASS\nTRUSTED_CLIENT_READY_');
      await pump();
      expect(child.writes, isEmpty);
      child.ready('TO_EXIT\n');
      await pump();
      expect(ascii.decode(child.writes.single), trustedClientAck);
      expect(child.flushes, 1);
      expect(child.closes, 0);
      child.flush.complete();
      await pump();
      expect(child.closes, 1);
      child.close.complete();
      await child.finish();
      expect(await future, 0);
      expect(completion.output, 'CLIENT_PASS\n$trustedClientReady');
      expect(completion.errors, isEmpty);
    },
  );

  test(
    'exact READY line only; prefix suffix CRLF and substring refused',
    () async {
      for (final invalid in [
        'prefix$trustedClientReady',
        'TRUSTED_CLIENT_READY_TO_EXIT suffix\n',
        'TRUSTED_CLIENT_READY_TO_EXIT\r\n',
        'TRUSTED_CLIENT_READY_TO_EXIT',
      ]) {
        final child = Child();
        final result = child.completion.complete(const Duration(seconds: 12));
        final check = expectLater(result, throwsStateError);
        child.ready(invalid);
        await child.finish();
        await check;
        expect(child.writes, isEmpty);
      }
    },
  );

  test('identical cached 9→12 future and failure cannot restart', () async {
    final child = Child();
    final first = child.completion.complete(const Duration(seconds: 9));
    expect(
      identical(first, child.completion.complete(const Duration(seconds: 12))),
      isTrue,
    );
    final check = expectLater(first, throwsA(isA<TimeoutException>()));
    child.clock.advance(const Duration(seconds: 9));
    await check;
    child.ready();
    await pump();
    expect(child.writes, isEmpty);
    expect(
      identical(first, child.completion.complete(const Duration(seconds: 12))),
      isTrue,
    );
    await child.finish();
  });

  test('one absolute budget includes flush close exit and drain', () async {
    for (final stage in ['flush', 'close', 'exit', 'drain']) {
      final child = Child();
      final future = child.completion.complete(const Duration(seconds: 12));
      final check = expectLater(future, throwsA(isA<TimeoutException>()));
      child.clock.advance(const Duration(seconds: 8));
      child.ready();
      await pump();
      if (stage != 'flush') {
        child.flush.complete();
        await pump();
      }
      if (stage == 'exit' || stage == 'drain') {
        child.close.complete();
        await pump();
      }
      if (stage == 'drain') {
        child.exit.complete(0);
        await pump();
      }
      child.clock.advance(const Duration(seconds: 4));
      await check;
      await child.finish();
      expect(child.writes.length, 1);
    }
  });

  test('early exit permits buffered READY drain in the same budget', () async {
    final child = Child();
    final future = child.completion.complete(const Duration(seconds: 12));
    child.exit.complete(0);
    await pump();
    expect(child.writes, isEmpty);
    child.ready('CLIENT_PASS\n$trustedClientReady');
    await child.finish();
    expect(await future, 0);
  });

  test('early exit without READY fails after bounded stdout drain', () async {
    final child = Child();
    final future = child.completion.complete(const Duration(seconds: 12));
    final check = expectLater(future, throwsStateError);
    child.exit.complete(1);
    await child.finish(1);
    await check;
    expect(child.writes, isEmpty);
  });

  for (final stdout in [true, false]) {
    test(
      '16KiB stream bound and early observed errors stdout=$stdout',
      () async {
        final child = Child();
        final completion = child.completion;
        (stdout ? child.out : child.err).add(List.filled(16385, 97));
        final result = completion.complete(const Duration(seconds: 12));
        await expectLater(result, throwsStateError);
        expect(completion.output.length, lessThanOrEqualTo(16384));
        expect(completion.errors.length, lessThanOrEqualTo(16384));
        await child.finish();

        final errorChild = Child();
        final observed = errorChild.completion;
        final error = StateError('EARLY_STREAM_ERROR');
        (stdout ? errorChild.out : errorChild.err).addError(error);
        await expectLater(
          observed.complete(const Duration(seconds: 12)),
          throwsA(same(error)),
        );
        await errorChild.finish();
      },
    );
  }

  test(
    'stdin close is one cached operation including cleanup after failure',
    () async {
      final child = Child();
      final future = child.completion.complete(const Duration(seconds: 12));
      child.ready();
      child.flush.complete();
      await pump();
      final close = child.completion.closeStdin();
      expect(identical(close, child.completion.closeStdin()), isTrue);
      final check = expectLater(future, throwsStateError);
      final closeCheck = expectLater(close, throwsStateError);
      child.close.completeError(StateError('CLOSE_FAILURE'));
      await check;
      await closeCheck;
      expect(child.closes, 1);
      await child.finish();
    },
  );

  test('ACK accepts arbitrary fragmentation only with final EOF', () async {
    final input = StreamController<List<int>>(sync: true);
    final clock = ControlledClock();
    final ready = <String>[];
    var completed = false;
    final future = finishTrustedClient(
      input: input.stream,
      writeReady: ready.add,
      flushReady: () async {},
      clock: clock,
    ).then((_) => completed = true);
    for (final byte in ascii.encode(trustedClientAck)) {
      input.add([byte]);
    }
    await pump();
    expect(ready, [trustedClientReady]);
    expect(completed, isFalse);
    await input.close();
    await future;
    expect(completed, isTrue);
  });

  test(
    'ACK rejects incomplete EOF trailing CRLF nonASCII >64 and stream error',
    () async {
      for (final bytes in [
        <int>[],
        ascii.encode('TRUSTED_CLIENT_EXIT_ACK'),
        ascii.encode('$trustedClientAck '),
        ascii.encode('TRUSTED_CLIENT_EXIT_ACK\r\n'),
        [...ascii.encode(trustedClientAck), 255],
        List.filled(65, 65),
      ]) {
        final input = StreamController<List<int>>(sync: true);
        final result = finishTrustedClient(
          input: input.stream,
          writeReady: (_) {},
          flushReady: () async {},
        );
        final check = expectLater(result, throwsStateError);
        input.add(bytes);
        await input.close();
        await check;
      }
      final input = StreamController<List<int>>(sync: true);
      final error = StateError('ACK_STREAM_ERROR');
      final result = finishTrustedClient(
        input: input.stream,
        writeReady: (_) {},
        flushReady: () async {},
      );
      final check = expectLater(result, throwsA(same(error)));
      input.addError(error);
      await input.close();
      await check;
    },
  );

  test(
    'client single 12s budget includes READY flush and missing ACK EOF',
    () async {
      final input = StreamController<List<int>>(sync: true);
      final clock = ControlledClock(), flush = Completer<void>();
      final result = finishTrustedClient(
        input: input.stream,
        writeReady: (_) {},
        flushReady: () => flush.future,
        clock: clock,
      );
      final check = expectLater(result, throwsA(isA<TimeoutException>()));
      clock.advance(const Duration(seconds: 8));
      flush.complete();
      await pump();
      input.add(ascii.encode(trustedClientAck));
      await pump();
      clock.advance(const Duration(seconds: 4));
      await check;
      await input.close();
    },
  );
}
