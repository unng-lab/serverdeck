import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'trusted_client_fixture.dart';

const trustedClientReady = 'TRUSTED_CLIENT_READY_TO_EXIT\n';
const trustedClientAck = 'TRUSTED_CLIENT_EXIT_ACK\n';

/// Injectable monotonic deadline driver for deterministic fixture unit tests.
abstract interface class TrustedClientClock {
  Duration get now;
  Future<T> wait<T>(Future<T> future, Duration remaining);
}

final class _MonotonicClock implements TrustedClientClock {
  final _watch = Stopwatch()..start();
  @override
  Duration get now => _watch.elapsed;
  @override
  Future<T> wait<T>(Future<T> future, Duration remaining) =>
      future.timeout(remaining);
}

/// Starts observing all child events immediately, before any protocol awaits.
final class TrustedClientCompletion {
  TrustedClientCompletion.attach(Process child)
    : this(
        output: child.stdout,
        errors: child.stderr,
        exit: child.exitCode,
        write: child.stdin.add,
        flush: child.stdin.flush,
        close: child.stdin.close,
      );

  TrustedClientCompletion({
    required Stream<List<int>> output,
    required Stream<List<int>> errors,
    required Future<int> exit,
    required void Function(List<int>) write,
    required Future<void> Function() flush,
    required Future<void> Function() close,
    TrustedClientClock? clock,
  }) : _write = write,
       _flush = flush,
       _close = close,
       _clock = clock ?? _MonotonicClock() {
    _capture(output, _out, true);
    _capture(errors, _err, false);
    exit.then((code) {
      _exit = code;
      _signal();
    }, onError: _fail);
  }

  final void Function(List<int>) _write;
  final Future<void> Function() _flush, _close;
  final TrustedClientClock _clock;
  final _out = <int>[], _err = <int>[];
  final _line = <int>[];
  Completer<void> _changed = Completer<void>();
  Object? _failure;
  StackTrace? _failureStack;
  bool _ready = false, _outDone = false, _errDone = false, _terminal = false;
  int? _exit;
  Duration? _deadline;
  Future<int>? _completion;
  Future<void>? _stdinClosed;
  Future<void>? _cleanup;

  String get output => utf8.decode(_out, allowMalformed: true);
  String get errors => utf8.decode(_err, allowMalformed: true);

  void _signal() {
    final previous = _changed;
    _changed = Completer<void>();
    previous.complete();
  }

  void _fail(Object error, StackTrace stack) {
    _failure ??= error;
    _failureStack ??= stack;
    _signal();
  }

  void _capture(Stream<List<int>> stream, List<int> target, bool stdout) {
    stream.listen(
      (chunk) {
        if (target.length + chunk.length > 16384) {
          _fail(StateError('TRUSTED_CLIENT_OUTPUT_LIMIT'), StackTrace.current);
          return;
        }
        target.addAll(chunk);
        if (stdout) {
          for (final byte in chunk) {
            _line.add(byte);
            if (byte == 10) {
              if (ascii.decode(_line, allowInvalid: true) ==
                  trustedClientReady) {
                _ready = true;
              }
              _line.clear();
            }
          }
        }
        _signal();
      },
      onError: _fail,
      onDone: () {
        if (stdout) {
          _outDone = true;
        } else {
          _errDone = true;
        }
        _signal();
      },
    );
  }

  void _guard() {
    if (_failure != null) {
      Error.throwWithStackTrace(_failure!, _failureStack!);
    }
    if (_terminal) throw StateError('TRUSTED_CLIENT_COMPLETION_TERMINAL');
    if (_clock.now >= _deadline!) throw TimeoutException('TRUSTED_CLIENT_EXIT');
  }

  Future<T> _within<T>(Future<T> future) async {
    _guard();
    final value = await _clock.wait(future, _deadline! - _clock.now);
    _guard();
    return value;
  }

  /// Non-async: every call returns the identical first completion, even 9→12s.
  Future<int> complete(Duration budget) {
    final previous = _completion;
    if (previous != null) return previous;
    final result = Completer<int>();
    _completion = result.future;
    _run(budget).then(result.complete, onError: result.completeError);
    return result.future;
  }

  /// Also reused by cleanup; no second close operation can replace its outcome.
  Future<void> closeStdin() {
    final previous = _stdinClosed;
    if (previous != null) return previous;
    final result = Completer<void>();
    _stdinClosed = result.future;
    Future<void>.sync(_close)
        .then(result.complete, onError: result.completeError);
    return result.future;
  }

  /// Keep the old owned-input IOException policy, but never let an unfinished
  /// close postpone kill. Close and join share the original 5s cleanup budget.
  Future<void> cleanup({
    required void Function() kill,
    required Future<int> exit,
    void Function(Object error, StackTrace stack)? onFirstFailure,
  }) {
    final previous = _cleanup;
    if (previous != null) return previous;
    final result = Completer<void>();
    _cleanup = result.future;
    _runCleanup(
      kill: kill,
      exit: exit,
      onFirstFailure: onFirstFailure,
    ).then(result.complete, onError: result.completeError);
    return result.future;
  }

  Future<void> _runCleanup({
    required void Function() kill,
    required Future<int> exit,
    void Function(Object error, StackTrace stack)? onFirstFailure,
  }) async {
    _terminal = true;
    _signal();
    final deadline = _clock.now + const Duration(seconds: 5);
    var closeSettled = false, joinSettled = false;
    final closing = () async {
      try {
        await closeStdin();
      } on IOException {
        // Existing policy: owned input may already have closed with the child.
      }
    }().whenComplete(() => closeSettled = true);
    final joining = exit
        .then<void>((_) {})
        .whenComplete(() => joinSettled = true);
    closing.ignore();
    joining.ignore();
    Future<void> bounded(Future<void> future, bool Function() settled) async {
      if (settled()) {
        await future;
        return;
      }
      final remaining = deadline - _clock.now;
      if (remaining <= Duration.zero) {
        throw TimeoutException('TRUSTED_CLIENT_CLEANUP');
      }
      await _clock.wait(future, remaining);
      if (_clock.now >= deadline) {
        throw TimeoutException('TRUSTED_CLIENT_CLEANUP');
      }
    }

    await runOwnedFixtureLifecycle(
      body: () async => kill(),
      cleanup: () => runOwnedFixtureLifecycle(
        body: () => bounded(closing, () => closeSettled),
        cleanup: () => bounded(joining, () => joinSettled),
        onFirstFailure: onFirstFailure,
      ),
      onFirstFailure: onFirstFailure,
    );
  }

  Future<int> _run(Duration budget) async {
    _deadline = _clock.now + budget;
    try {
      _guard();
      while (!_ready) {
        if (_outDone) throw StateError('TRUSTED_CLIENT_READY_MISSING');
        await _within(_changed.future);
      }
      _guard();
      _write(ascii.encode(trustedClientAck));
      _guard();
      await _within(Future<void>.sync(_flush));
      _guard();
      await _within(closeStdin());
      while (_exit == null || !_outDone || !_errDone) {
        await _within(_changed.future);
      }
      _guard();
      return _exit!;
    } finally {
      _terminal = true;
    }
  }
}

/// Called only after the client's body and physical cleanup returned normally.
Future<void> finishTrustedClient({
  required Stream<List<int>> input,
  required void Function(String) writeReady,
  required Future<void> Function() flushReady,
  TrustedClientClock? clock,
}) async {
  final timer = clock ?? _MonotonicClock();
  final deadline = timer.now + const Duration(seconds: 12);
  void guard() {
    if (timer.now >= deadline) throw TimeoutException('TRUSTED_CLIENT_ACK');
  }

  Future<T> within<T>(Future<T> future) async {
    guard();
    final value = await timer.wait(future, deadline - timer.now);
    guard();
    return value;
  }

  final received = Completer<void>();
  final bytes = <int>[];
  final subscription = input.listen(
    (chunk) {
      if (received.isCompleted) return;
      if (bytes.length + chunk.length > 64 || chunk.any((byte) => byte > 127)) {
        received.completeError(StateError('TRUSTED_CLIENT_ACK_INVALID'));
        return;
      }
      bytes.addAll(chunk);
      final expected = ascii.encode(trustedClientAck);
      if (bytes.length > expected.length ||
          !List.generate(
            bytes.length,
            (i) => bytes[i] == expected[i],
          ).every((v) => v)) {
        received.completeError(StateError('TRUSTED_CLIENT_ACK_INVALID'));
      }
    },
    onError: (Object error, StackTrace stack) {
      if (!received.isCompleted) received.completeError(error, stack);
    },
    onDone: () {
      if (received.isCompleted) return;
      if (ascii.decode(bytes) == trustedClientAck) {
        received.complete();
      } else {
        received.completeError(StateError('TRUSTED_CLIENT_ACK_INVALID'));
      }
    },
  );
  // Input can fail while READY flush is still pending; observe it immediately.
  received.future.ignore();
  try {
    guard();
    writeReady(trustedClientReady);
    await within(Future<void>.sync(flushReady));
    await within(received.future);
  } finally {
    await subscription.cancel();
  }
}

Future<void> finishTrustedClientProcess() => finishTrustedClient(
  input: stdin,
  writeReady: stdout.write,
  flushReady: stdout.flush,
);
